// 조회 API 포화(saturation) 테스트 — B-axis Redis 필요성 판단용
//
// think-time = 0 (sleep 없음): 현실적 트래픽 재현이 아니라, 어느 자원이
// 먼저 무너지는지 드러내기 위한 순수 포화 테스트.
//
// SCENARIO 환경변수로 한 번에 하나씩 실행 (S1 → S2 → S4 순서 권장, 사이 휴지):
//   S1  HOT PERSONAL   /{HOT_CHALLENGE_ID}/leaderboards?type=PERSONAL   (핵심 후보, GROUP BY ~1200행)
//   S2  HOT TEAM 대조군 /{HOT_CHALLENGE_ID}/leaderboards?type=TEAM       (선계산값, DB행 거의 0)
//   S3  HOT team-detail /{HOT_CHALLENGE_ID}/team-detail (JWT 앵커유저)   (참고용, 50→100→200→400)
//   S4  BREADTH PERSONAL /{rand 147..644}/leaderboards?type=PERSONAL    (요청마다 challenge_id 랜덤)
//
// 실행 예:
//   SCENARIO=S1 k6 run monitoring/k6/saturation-test.js
//   SCENARIO=S2 k6 run monitoring/k6/saturation-test.js
//   SCENARIO=S4 k6 run monitoring/k6/saturation-test.js
//
// docs/monitoring/saturation-cache/saturation-scenario-matrix.md 참고.

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

const BASE_URL          = __ENV.BASE_URL          || 'http://localhost:8080';
const SCENARIO          = __ENV.SCENARIO          || 'S1';
const HOT_CHALLENGE_ID  = __ENV.HOT_CHALLENGE_ID  || '145';
const BREADTH_MIN       = parseInt(__ENV.BREADTH_MIN || '147', 10);
const BREADTH_MAX       = parseInt(__ENV.BREADTH_MAX || '644', 10);

// [JWT 전환] A/B축 통합 후 Spring Security가 /api/auth/**, /actuator/** 를 제외한
// 모든 엔드포인트를 JWT로 보호한다(무인증 요청은 401). 따라서 leaderboards(S1/S2/S4)와
// team-detail(S3) 모두 Authorization: Bearer 토큰이 필요하다.
//   - S1/S2/S4(leaderboards): 유효한 JWT면 충분(참여 불필요)
//   - S3(team-detail): 토큰 유저가 HOT_CHALLENGE_ID의 CONFIRMED 참여자여야 함
//     → seed-saturation.sql이 심은 앵커 유저(user_id=1000001, sat_hot@booster.test)로 로그인.
// 로그인 계정은 a-axis-load-test.js처럼 LOGIN_EMAIL/LOGIN_PASSWORD로 재정의 가능.
const LOGIN_EMAIL     = __ENV.LOGIN_EMAIL    || 'sat_hot@booster.test';
const LOGIN_PASSWORD  = __ENV.LOGIN_PASSWORD || 'seed1234';
const JSON_HEADERS    = { 'Content-Type': 'application/json' };

const errorRate  = new Rate('errors');
const s1Duration = new Trend('s1_duration'); // HOT PERSONAL
const s2Duration = new Trend('s2_duration'); // HOT TEAM (control)
const s3Duration = new Trend('s3_duration'); // HOT team-detail
const s4Duration = new Trend('s4_duration'); // BREADTH PERSONAL

// 50→100→200→400→800 VU, 각 단계 30~40s, 총 ~2m40s 붕괴 임계점 관찰용 램프
const STAGES_MAIN = [
  { duration: '30s', target: 50 },
  { duration: '30s', target: 100 },
  { duration: '30s', target: 200 },
  { duration: '30s', target: 400 },
  { duration: '40s', target: 800 },
];

// S3(team-detail)은 더 무거워 800까지 안 가고 400에서 관찰
const STAGES_S3 = [
  { duration: '30s', target: 50 },
  { duration: '30s', target: 100 },
  { duration: '30s', target: 200 },
  { duration: '40s', target: 400 },
];

const EXEC_MAP = { S1: 's1Flow', S2: 's2Flow', S3: 's3Flow', S4: 's4Flow' };

if (!EXEC_MAP[SCENARIO]) {
  throw new Error(`Unknown SCENARIO=${SCENARIO}. Use one of: S1, S2, S3, S4`);
}

export const options = {
  scenarios: {
    [SCENARIO]: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: SCENARIO === 'S3' ? STAGES_S3 : STAGES_MAIN,
      exec: EXEC_MAP[SCENARIO],
      gracefulStop: '5s',
    },
  },

  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(50)', 'p(95)', 'p(99)'],

  // 포화가 목적 — 에러/타임아웃 발생이 정상이므로 threshold는 관찰용 참고치일 뿐,
  // 실패해도 (exit code 외에는) 붕괴 임계점 분석을 막지 않는다.
  thresholds: {
    errors: [{ threshold: 'rate<1.0', abortOnFail: false }],
  },
};

// [JWT 전환] 전체 테스트 시작 전 1회: 앵커 유저 로그인 → 토큰 확보.
// 반환한 token은 각 flow의 첫 인자(data)로 전달되어 Authorization 헤더에 쓰인다.
export function setup() {
  const res = http.post(`${BASE_URL}/api/auth/login`,
    JSON.stringify({ email: LOGIN_EMAIL, password: LOGIN_PASSWORD }),
    { headers: JSON_HEADERS });
  const token = res.json('accessToken');
  if (!token) {
    throw new Error(
      `[JWT] 앵커 유저 로그인 실패 — seed-saturation.sql 먼저 적용했는지 확인. ` +
      `email=${LOGIN_EMAIL} status=${res.status} body=${res.body}`
    );
  }
  return { token };
}

export function handleSummary(data) {
  const outPath =
    __ENV.OUT_JSON ||
    `/Users/hansangjun/Desktop/Booster-AI-habit-service/docs/monitoring/baselines/sat-${SCENARIO}-k6.json`;
  return {
    [outPath]: JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}

// ── S1: HOT PERSONAL 고정 난타 (Redis 핵심 후보) ─────────────────────────
export function s1Flow(data) {
  // [JWT 전환] leaderboards는 유효한 JWT면 충분(참여 불필요)
  const res = http.get(
    `${BASE_URL}/api/challenges/${HOT_CHALLENGE_ID}/leaderboards?type=PERSONAL`,
    { headers: { Authorization: `Bearer ${data.token}` } }
  );
  s1Duration.add(res.timings.duration);
  const ok = res.status === 200;
  check(res, { 's1 personal 200': () => ok });
  errorRate.add(!ok);
  // sleep 없음 — 순수 포화
}

// ── S2: HOT TEAM 고정 난타 (대조군 — 선계산값, DB행 거의 0) ──────────────
export function s2Flow(data) {
  // [JWT 전환] Authorization 헤더 추가
  const res = http.get(
    `${BASE_URL}/api/challenges/${HOT_CHALLENGE_ID}/leaderboards?type=TEAM`,
    { headers: { Authorization: `Bearer ${data.token}` } }
  );
  s2Duration.add(res.timings.duration);
  const ok = res.status === 200;
  check(res, { 's2 team 200': () => ok });
  errorRate.add(!ok);
}

// ── S3: HOT team-detail (참고용 — 무거운 비교 쿼리 + 커넥션 점유) ────────
export function s3Flow(data) {
  // [JWT 전환] X-User-Id 제거 → 앵커 유저(HOT 챌린지의 CONFIRMED 참여자) 토큰 사용
  const res = http.get(
    `${BASE_URL}/api/challenges/${HOT_CHALLENGE_ID}/team-detail`,
    { headers: { Authorization: `Bearer ${data.token}` } }
  );
  s3Duration.add(res.timings.duration);
  const ok = res.status === 200;
  check(res, { 's3 team-detail 200': () => ok });
  errorRate.add(!ok);
}

// ── S4: BREADTH PERSONAL — 요청마다 challenge_id 랜덤(147..644) ──────────
export function s4Flow(data) {
  // [JWT 전환] Authorization 헤더 추가
  const id = BREADTH_MIN + Math.floor(Math.random() * (BREADTH_MAX - BREADTH_MIN + 1));
  const res = http.get(
    `${BASE_URL}/api/challenges/${id}/leaderboards?type=PERSONAL`,
    { headers: { Authorization: `Bearer ${data.token}` } }
  );
  s4Duration.add(res.timings.duration);
  const ok = res.status === 200;
  check(res, { 's4 breadth personal 200': () => ok });
  errorRate.add(!ok);
}
