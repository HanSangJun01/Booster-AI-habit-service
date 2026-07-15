import http from 'k6/http';
import exec from 'k6/execution';
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
// CHALLENGE_ID(선택): 읽기 부하 대상 — run-all-scenarios.sh가 30일 체크인을 볼륨 시딩한
// 챌린지를 넘긴다. 미지정 시 setup이 프로비저닝한 챌린지를 읽기에도 쓴다.
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

    // 2. 동시 같은 유저 (10 VU 모두 member[0] 토큰으로 체크인 — 멱등성·경쟁조건 확인)
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

// [JWT 전환] A/B축 통합 후 Spring Security가 /api/auth/**, /actuator/** 를 제외한
// 모든 엔드포인트를 JWT로 보호한다(무인증/X-User-Id 요청은 401). 이 스크립트는
// 시드 의존 없이 setup에서 실제 유저를 가입/로그인해 토큰을 확보한다.
//   - 멤버 10명(member 1~10): normalFlow는 앞 5명으로 "서로 다른 유저" 재현,
//     sameUserFlow는 member[0] 고정(구 X-User-Id=1), teamFormationFlow는 10명 순환(구 __VU).
//   - outsider 1명: edgeCaseFlow의 "미참여 유저"(구 X-User-Id=99) 대체 — 어떤 챌린지에도
//     참여하지 않은 실제 유저이므로 체크인 시 4xx가 정상.
//
// [JWT 전환 수정] 체크인 쓰기는 "CONFIRMED 참여자 + 팀 배정 + ACTIVE 챌린지"를 요구하므로
// (ChallengeCheckInService.recordCheckIn), 가입만 한 멤버로는 전량 404가 난다.
// setup에서 부하 전용 챌린지를 API로 프로비저닝한다: member[0]가 생성(AUTO 승인) →
// 멤버 10명 참여 → 10번째 참여 트랜잭션에서 백엔드가 팀 구성 + ACTIVE 전환을 수행
// (TeamFormationService.formTeamsIfReady). 이후:
//   - 쓰기(체크인 POST)  → 프로비저닝 챌린지 (멤버가 실제 참여자)
//   - 읽기(상세/체크인 GET) → env CHALLENGE_ID(오케스트레이터가 볼륨 시딩한 챌린지) 우선,
//     없으면 프로비저닝 챌린지 (참여 불필요 엔드포인트라 어느 쪽이든 200)
const MEMBER_COUNT = 10;
const JSON_HEADERS = { 'Content-Type': 'application/json' };

function login(email, password) {
  const loginRes = http.post(`${BASE_URL}/api/auth/login`,
    JSON.stringify({ email, password }), { headers: JSON_HEADERS });
  const token = loginRes.json('accessToken');
  if (!token) {
    throw new Error(`로그인 실패 — 토큰 못 받음. email=${email} status=${loginRes.status} body=${loginRes.body}`);
  }
  return token;
}

function signupAndLogin(email, password, nickname) {
  http.post(`${BASE_URL}/api/auth/signup`,
    JSON.stringify({ email, password, nickname }), { headers: JSON_HEADERS });
  return login(email, password);
}

function bearerHeaders(token) {
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
}

// 부하 전용 챌린지 프로비저닝: 생성 → 멤버 10명 참여 → ACTIVE(팀 구성) 검증.
// 제목은 '시나리오' 접두사를 써서 run-all-scenarios.sh의 DB 초기화가 다음 실행 때 정리한다.
function provisionChallenge(memberTokens, stamp) {
  const createRes = http.post(`${BASE_URL}/api/challenges`, JSON.stringify({
    title: `시나리오k6부하_${stamp}`,
    category: 'HEALTH',
    verificationType: 'GPS',
    durationDays: 14,
    depositCoins: 100,
    maxParticipants: 10,
    visibility: 'PUBLIC',
    approvalType: 'AUTO',
  }), { headers: bearerHeaders(memberTokens[0]) });
  const challengeId = createRes.json('data.id');
  if (!challengeId) {
    throw new Error(`부하용 챌린지 생성 실패. status=${createRes.status} body=${createRes.body}`);
  }

  for (let i = 0; i < MEMBER_COUNT; i++) {
    const joinRes = http.post(`${BASE_URL}/api/challenges/${challengeId}/participants`,
      JSON.stringify({
        personalStatement: '부하테스트',
        gpsLat: 37.5665,
        gpsLng: 126.9780,
        gpsRadiusMeters: 100,
        gpsPlaceName: '서울시청',
      }), { headers: bearerHeaders(memberTokens[i]) });
    if (joinRes.status !== 200 && joinRes.status !== 201) {
      throw new Error(`member ${i} 참여 실패. status=${joinRes.status} body=${joinRes.body}`);
    }
  }

  const detailRes = http.get(`${BASE_URL}/api/challenges/${challengeId}`,
    { headers: bearerHeaders(memberTokens[0]) });
  const status = detailRes.json('data.status');
  if (status !== 'ACTIVE') {
    throw new Error(
      `프로비저닝 챌린지가 ACTIVE가 아님(팀 자동 구성 실패?). id=${challengeId} status=${status}`);
  }
  return challengeId;
}

// 전체 테스트 시작 전 1회: 부하용 유저 가입+로그인 → 챌린지 프로비저닝 → 토큰/대상 확보.
// 반환값은 각 flow의 첫 인자(data)로 전달된다.
export function setup() {
  const stamp = Date.now();
  const password = 'loadtest1234';
  const memberTokens = [];
  for (let i = 0; i < MEMBER_COUNT; i++) {
    memberTokens.push(signupAndLogin(`loadtest_m${i}_${stamp}@booster.test`, password, `lt_m${i}`));
  }
  const outsiderToken = signupAndLogin(`loadtest_out_${stamp}@booster.test`, password, 'lt_out');

  const writeChallengeId = provisionChallenge(memberTokens, stamp);
  // 읽기 대상: 오케스트레이터가 볼륨 시딩한 챌린지(env) 우선, 없으면 프로비저닝 챌린지
  const readChallengeId = __ENV.CHALLENGE_ID || String(writeChallengeId);

  // [수정] ENDED 엣지케이스: ENDED_MEMBER_EMAIL이 주어지면 "ENDED 챌린지의 실제 참여자"
  // 토큰을 확보한다. 이 토큰으로 체크인하면 참여자 조회(404)가 아니라 ACTIVE 상태 검증
  // (409 Conflict) 경로가 실제로 검증된다. 미지정 시 member[0](미참여 → 404)로 폴백.
  const endedMemberToken = __ENV.ENDED_MEMBER_EMAIL
    ? login(__ENV.ENDED_MEMBER_EMAIL, __ENV.ENDED_MEMBER_PASSWORD || password)
    : null;

  return { memberTokens, outsiderToken, writeChallengeId, readChallengeId, endedMemberToken };
}

export function handleSummary(data) {
  return {
    '/tmp/k6-summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}

// ── 시나리오 1: 정상 흐름 ────────────────────────────────────────────────
export function normalFlow(data) {
  // [JWT 전환] 서로 다른 5명(구 userId 1~5) → member 토큰 5개를 순환 사용
  const token = data.memberTokens[__VU % 5];
  const authHeaders = bearerHeaders(token);
  const today = new Date().toISOString().slice(0, 10).replace(/-/g, '');

  // [JWT 전환] 목록 조회도 통합 후 인증 필요(구 무인증 → 401) → Bearer 토큰 사용
  const listRes = http.get(`${BASE_URL}/api/challenges`, { headers: authHeaders });
  challengeListDuration.add(listRes.timings.duration);
  check(listRes, { 'list 200': (r) => r.status === 200 });
  errorRate.add(listRes.status >= 400);
  if (listRes.status >= 400) {
    console.error(`[VU${__VU}] list failed: ${listRes.status} ${listRes.body}`);
  }
  sleep(0.3);

  const detailRes = http.get(`${BASE_URL}/api/challenges/${data.readChallengeId}`, { headers: authHeaders });
  challengeDetailDuration.add(detailRes.timings.duration);
  check(detailRes, { 'detail 200': (r) => r.status === 200 });
  errorRate.add(detailRes.status >= 400);
  if (detailRes.status >= 400) {
    console.error(`[VU${__VU}] detail failed: ${detailRes.status} ${detailRes.body}`);
  }
  sleep(0.3);

  // [JWT 전환 수정] 체크인 쓰기는 참여자여야 하므로 프로비저닝 챌린지에 쓴다
  const checkInWriteRes = http.post(
    `${BASE_URL}/api/challenges/${data.writeChallengeId}/check-ins`,
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
    `${BASE_URL}/api/challenges/${data.readChallengeId}/check-ins?date=${today}`,
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
// 10 VU 모두 동일 유저로 동시에 체크인 → 멱등성과 경쟁조건(race condition) 검증
export function sameUserFlow(data) {
  // [JWT 전환] 구 X-User-Id=1 → member[0] 토큰 고정(모든 VU가 같은 유저)
  const authHeaders = bearerHeaders(data.memberTokens[0]);

  // [JWT 전환 수정] member[0]가 참여자인 프로비저닝 챌린지에 체크인 (구: env CHALLENGE_ID)
  const res = http.post(
    `${BASE_URL}/api/challenges/${data.writeChallengeId}/check-ins`,
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
export function edgeCaseFlow(data) {
  // [JWT 전환] 구 X-User-Id=1 → member[0] 토큰
  const authHeaders = bearerHeaders(data.memberTokens[0]);

  // 케이스 1: ENDED 챌린지에 체크인 시도 → 4xx 여야 함
  // [수정] ENDED_MEMBER_EMAIL이 주어지면 그 챌린지의 실제 참여자 토큰으로 호출 →
  // "참여자인데 챌린지가 ACTIVE 아님" 검증(409)이 실제로 실행된다.
  // 미지정 시 member[0](미참여)이라 참여자 조회 404로만 4xx가 나온다.
  const endedAuth = data.endedMemberToken ? bearerHeaders(data.endedMemberToken) : authHeaders;
  const endedRes = http.post(
    `${BASE_URL}/api/challenges/${ENDED_CHALLENGE_ID}/check-ins`,
    JSON.stringify({ currentLat: 37.5665, currentLng: 126.9780 }),
    { headers: endedAuth }
  );
  const endedOk = endedRes.status >= 400;
  check(endedRes, { 'ENDED 챌린지 체크인 → 4xx': () => endedOk });
  edgeCaseCorrect.add(endedOk);
  if (!endedOk) {
    console.error(`[EDGE] ENDED challenge returned ${endedRes.status} — expected 4xx`);
  }
  sleep(0.5);

  // 케이스 2: 미참여 유저(outsider 토큰) 체크인 시도 → 4xx 여야 함
  // [JWT 전환] 구 X-User-Id=99 → 어떤 챌린지에도 참여하지 않은 실제 outsider 유저 토큰.
  // 대상은 참여자가 실존하는 프로비저닝 챌린지 — outsider만 미참여인 상황을 정확히 재현.
  const nonParticipantRes = http.post(
    `${BASE_URL}/api/challenges/${data.writeChallengeId}/check-ins`,
    JSON.stringify({ currentLat: 37.5665, currentLng: 126.9780 }),
    { headers: bearerHeaders(data.outsiderToken) }
  );
  const nonParticipantOk = nonParticipantRes.status >= 400;
  check(nonParticipantRes, { '미참여 유저 체크인 → 4xx': () => nonParticipantOk });
  edgeCaseCorrect.add(nonParticipantOk);
  if (!nonParticipantOk) {
    console.error(`[EDGE] non-participant returned ${nonParticipantRes.status} — expected 4xx`);
  }
  sleep(0.5);

  // 케이스 3: GPS 좌표 누락 → 4xx 여야 함 (@NotNull 검증 → 400)
  const noGpsRes = http.post(
    `${BASE_URL}/api/challenges/${data.writeChallengeId}/check-ins`,
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
export function teamFormationFlow(data) {
  // [JWT 전환 수정] 구 X-User-Id=__VU(1~10) → member 토큰 10개 순환.
  // __VU는 시나리오별 연속 블록이 보장되지 않는 전역 카운터라(다른 시나리오와 VU 풀 공유)
  // (__VU-1)%10 매핑은 토큰 충돌 → 참여자<10 → 팀 미구성이 될 수 있다.
  // 반복 인덱스(iterationInTest)로 순환해 10초 동안 10명 전원이 반드시 커버되게 한다.
  // (재참여 시도는 409 '이미 참여'로 멱등 처리 — 아래 ok 집합에 포함)
  const token = data.memberTokens[exec.scenario.iterationInTest % MEMBER_COUNT];
  const res = http.post(
    `${BASE_URL}/api/challenges/${FORMATION_CHALLENGE_ID}/participants`,
    JSON.stringify({
      personalStatement: '동시성테스트',
      gpsLat: 37.5665,
      gpsLng: 126.9780,
      gpsRadiusMeters: 100,
      gpsPlaceName: '서울시청',
    }),
    { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } }
  );
  // 200/201 = 신규 참여, 409 = 이미 참여(멱등) — 모두 정상
  const ok = res.status === 200 || res.status === 201 || res.status === 409;
  check(res, { 'team formation 참여 신청 성공': () => ok });
  errorRate.add(!ok);
  if (!ok) {
    console.error(`[FORMATION] VU${__VU} failed: ${res.status} ${res.body}`);
  }
  // sleep 없음 — 동시성 최대화
}
