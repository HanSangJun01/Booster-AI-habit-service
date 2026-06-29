import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

const errorRate      = new Rate('errors');
const edgeCaseCorrect = new Rate('edge_case_correct'); // 잘못된 요청 → 4xx 정상 반환 확인

const challengeListDuration   = new Trend('challenge_list_duration');
const challengeDetailDuration = new Trend('challenge_detail_duration');
const checkInWriteDuration    = new Trend('checkin_write_duration');
const checkInReadDuration     = new Trend('checkin_read_duration');

const BASE_URL               = __ENV.BASE_URL               || 'http://localhost:8080';
const CHALLENGE_ID           = __ENV.CHALLENGE_ID           || '1';
const ENDED_CHALLENGE_ID     = __ENV.ENDED_CHALLENGE_ID     || '999';
const FORMATION_CHALLENGE_ID = __ENV.FORMATION_CHALLENGE_ID || '0';
const soakEnabled            = __ENV.SOAK_DURATION && __ENV.SOAK_DURATION !== '0s';
const formationEnabled       = FORMATION_CHALLENGE_ID !== '0';

export const options = {
  scenarios: {
    // 1. 정상 부하 (5→20→50 VU 램프업)
    normal_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 5  },  // 워밍업
        { duration: '1m',  target: 20 },  // 기본 부하
        { duration: '30s', target: 50 },  // 피크
        { duration: '20s', target: 0  },  // 쿨다운
      ],
      exec: 'normalFlow',
    },

    // 2. 동시 같은 유저 (10 VU 모두 userId=1로 체크인 — 멱등성·경쟁조건 확인)
    concurrent_same_user: {
      executor: 'constant-vus',
      vus: 10,
      duration: '20s',
      startTime: '1m30s',  // 피크 구간 중 실행
      exec: 'sameUserFlow',
    },

    // 3. 엣지케이스 (부하 끝난 후 비정상 요청 → 4xx 반환 확인)
    edge_cases: {
      executor: 'per-vu-iterations',
      vus: 1,
      iterations: 5,
      startTime: '2m20s',
      exec: 'edgeCaseFlow',
    },

    // 4. 팀 구성 동시성 (10 VU가 동시에 같은 챌린지에 참여 신청 — race condition 검증)
    ...(formationEnabled ? {
      team_formation_concurrency: {
        executor: 'constant-vus',
        vus: 10,
        duration: '10s',
        startTime: '2m30s',
        exec: 'teamFormationFlow',
      },
    } : {}),

    // 5. Soak (메모리 누수 확인 — SOAK_DURATION 환경변수로 opt-in)
    ...(soakEnabled ? {
      soak: {
        executor: 'constant-vus',
        vus: 5,
        duration: __ENV.SOAK_DURATION,
        startTime: '2m40s',
        exec: 'normalFlow',
      },
    } : {}),
  },

  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(50)', 'p(90)', 'p(95)', 'p(99)'],

  thresholds: {
    http_req_duration:         ['p(99)<500'],   // 전체 p99 < 500ms
    challenge_list_duration:   ['p(95)<200'],   // 목록 조회 p95 < 200ms
    challenge_detail_duration: ['p(95)<150'],   // 상세 조회 p95 < 150ms
    checkin_write_duration:    ['p(95)<300'],   // 체크인 쓰기 p95 < 300ms
    errors:                    ['rate<0.01'],   // 에러율 1% 미만
    edge_case_correct:         ['rate>0.95'],   // 엣지케이스 4xx 정상 반환 95% 이상
  },
};

export function handleSummary(data) {
  return {
    '/tmp/k6-summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}

// ── 시나리오 1: 정상 흐름 ────────────────────────────────────────────────
export function normalFlow() {
  const userId = (__VU % 5) + 1;
  const authHeaders = {
    'Content-Type': 'application/json',
    'X-User-Id': String(userId),
  };
  const today = new Date().toISOString().slice(0, 10).replace(/-/g, '');

  const listRes = http.get(`${BASE_URL}/api/challenges`);
  challengeListDuration.add(listRes.timings.duration);
  check(listRes, { 'list 200': (r) => r.status === 200 });
  errorRate.add(listRes.status >= 400);
  if (listRes.status >= 400) {
    console.error(`[VU${__VU}] list failed: ${listRes.status} ${listRes.body}`);
  }
  sleep(0.3);

  const detailRes = http.get(`${BASE_URL}/api/challenges/${CHALLENGE_ID}`, { headers: authHeaders });
  challengeDetailDuration.add(detailRes.timings.duration);
  check(detailRes, { 'detail 200': (r) => r.status === 200 });
  errorRate.add(detailRes.status >= 400);
  if (detailRes.status >= 400) {
    console.error(`[VU${__VU}] detail failed: ${detailRes.status} ${detailRes.body}`);
  }
  sleep(0.3);

  const checkInWriteRes = http.post(
    `${BASE_URL}/api/challenges/${CHALLENGE_ID}/check-ins`,
    JSON.stringify({ currentLat: 37.5665, currentLng: 126.9780 }),
    { headers: authHeaders }
  );
  checkInWriteDuration.add(checkInWriteRes.timings.duration);
  check(checkInWriteRes, { 'checkin write 2xx': (r) => r.status === 200 || r.status === 201 });
  errorRate.add(checkInWriteRes.status >= 400);
  if (checkInWriteRes.status >= 400) {
    console.error(`[VU${__VU}] checkin write failed: ${checkInWriteRes.status} ${checkInWriteRes.body}`);
  }
  sleep(0.3);

  const checkInReadRes = http.get(
    `${BASE_URL}/api/challenges/${CHALLENGE_ID}/check-ins?date=${today}`,
    { headers: authHeaders }
  );
  checkInReadDuration.add(checkInReadRes.timings.duration);
  check(checkInReadRes, { 'checkin read 200': (r) => r.status === 200 });
  errorRate.add(checkInReadRes.status >= 400);
  if (checkInReadRes.status >= 400) {
    console.error(`[VU${__VU}] checkin read failed: ${checkInReadRes.status} ${checkInReadRes.body}`);
  }
  sleep(0.5);
}

// ── 시나리오 2: 동시 같은 유저 ──────────────────────────────────────────
// 10 VU 모두 userId=1로 동시에 체크인 → 멱등성과 경쟁조건(race condition) 검증
export function sameUserFlow() {
  const authHeaders = {
    'Content-Type': 'application/json',
    'X-User-Id': '1',
  };

  const res = http.post(
    `${BASE_URL}/api/challenges/${CHALLENGE_ID}/check-ins`,
    JSON.stringify({ currentLat: 37.5665, currentLng: 126.9780 }),
    { headers: authHeaders }
  );
  checkInWriteDuration.add(res.timings.duration);
  check(res, { 'concurrent same-user 2xx': (r) => r.status === 200 || r.status === 201 });
  errorRate.add(res.status >= 400);
  if (res.status >= 400) {
    console.error(`[VU${__VU}] concurrent same-user failed: ${res.status} ${res.body}`);
  }
  // sleep 없음 — 동시성 최대화
}

// ── 시나리오 3: 엣지케이스 ───────────────────────────────────────────────
// 비정상 요청이 올바르게 4xx를 반환하는지 확인
export function edgeCaseFlow() {
  const authHeaders = { 'Content-Type': 'application/json', 'X-User-Id': '1' };

  // 케이스 1: ENDED 챌린지에 체크인 시도 → 4xx 여야 함
  const endedRes = http.post(
    `${BASE_URL}/api/challenges/${ENDED_CHALLENGE_ID}/check-ins`,
    JSON.stringify({ currentLat: 37.5665, currentLng: 126.9780 }),
    { headers: authHeaders }
  );
  const endedOk = endedRes.status >= 400;
  check(endedRes, { 'ENDED 챌린지 체크인 → 4xx': () => endedOk });
  edgeCaseCorrect.add(endedOk);
  if (!endedOk) {
    console.error(`[EDGE] ENDED challenge returned ${endedRes.status} — expected 4xx`);
  }
  sleep(0.5);

  // 케이스 2: 미참여 유저(userId=99) 체크인 시도 → 4xx 여야 함
  const nonParticipantRes = http.post(
    `${BASE_URL}/api/challenges/${CHALLENGE_ID}/check-ins`,
    JSON.stringify({ currentLat: 37.5665, currentLng: 126.9780 }),
    { headers: { 'Content-Type': 'application/json', 'X-User-Id': '99' } }
  );
  const nonParticipantOk = nonParticipantRes.status >= 400;
  check(nonParticipantRes, { '미참여 유저 체크인 → 4xx': () => nonParticipantOk });
  edgeCaseCorrect.add(nonParticipantOk);
  if (!nonParticipantOk) {
    console.error(`[EDGE] non-participant returned ${nonParticipantRes.status} — expected 4xx`);
  }
  sleep(0.5);

  // 케이스 3: GPS 좌표 누락 → 4xx 여야 함
  const noGpsRes = http.post(
    `${BASE_URL}/api/challenges/${CHALLENGE_ID}/check-ins`,
    JSON.stringify({}),
    { headers: authHeaders }
  );
  const noGpsOk = noGpsRes.status >= 400;
  check(noGpsRes, { 'GPS 누락 체크인 → 4xx': () => noGpsOk });
  edgeCaseCorrect.add(noGpsOk);
  if (!noGpsOk) {
    console.error(`[EDGE] missing GPS returned ${noGpsRes.status} — expected 4xx`);
  }
  sleep(0.5);
}

// ── 시나리오 4: 팀 구성 동시성 ────────────────────────────────────────
// 10 VU 전부 동시에 같은 챌린지 참여 신청 → 팀이 정확히 1번만 구성되는지 확인
export function teamFormationFlow() {
  const userId = __VU; // VU 1~10 → userId 1~10
  const res = http.post(
    `${BASE_URL}/api/challenges/${FORMATION_CHALLENGE_ID}/participants`,
    JSON.stringify({
      personalStatement: '동시성테스트',
      gpsLat: 37.5665,
      gpsLng: 126.9780,
      gpsRadiusMeters: 100,
      gpsPlaceName: '서울시청',
    }),
    { headers: { 'Content-Type': 'application/json', 'X-User-Id': String(userId) } }
  );
  // 200/201 = 신규 참여, 409 = 이미 참여(멱등) — 모두 정상
  const ok = res.status === 200 || res.status === 201 || res.status === 409;
  check(res, { 'team formation 참여 신청 성공': () => ok });
  errorRate.add(!ok);
  if (!ok) {
    console.error(`[FORMATION] VU${__VU} userId=${userId} failed: ${res.status} ${res.body}`);
  }
  // sleep 없음 — 동시성 최대화
}
