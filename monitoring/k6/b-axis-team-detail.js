// team-detail 현실 트래픽 재현 테스트 — hot-key 편중 vs distributed-key 재현 비교
//
// b-axis-saturation.js의 S3(team-detail)는 "고정 1키 난타"로 캐시 적중률을 인위적으로
// 100%에 가깝게 만든다. 실제 트래픽은 인기 챌린지(hot)에 요청이 몰리되, 나머지
// 챌린지(normal)에도 분산되어 들어온다. 이 스크립트는 b-axis-team-detail-targets.json에 담긴
// hot/normal 챌린지·유저 조합으로 두 가지 현실적 시나리오를 재현해, 캐시 적중률이
// 실제로 어느 수준으로 떨어지는지 관찰한다.
//
// think-time = 0 (sleep 없음): S3와 동일하게 순수 부하로 임계점을 관찰.
//
// SCENARIO 환경변수로 한 번에 하나씩 실행:
//   hot            매 요청마다 hot 챌린지 중 랜덤 + 그 챌린지의 랜덤 유저 (키 집중 → 높은 캐시 적중 기대)
//   dist           20%는 hot, 80%는 normal에서 랜덤 선택 (실제 트래픽 분포 재현 → 낮은 캐시 적중 기대)
//   hotonly-singlekey  참고용 — 항상 첫 hot 챌린지 + 첫 유저 고정 (구 S3와 동일, 100% 적중 기준선)
//
// 사전 조건: monitoring/k6/b-axis-team-detail-targets.json 이 최신이어야 한다. challenge id는 시퀀스라
// 재시딩마다 바뀌므로, 시딩 후 반드시 생성 스크립트로 재생성한다:
//   docker exec -i booster-db psql -U booster -d booster < monitoring/scripts/b-axis-seed-team-detail.sql
//   monitoring/scripts/b-axis-gen-team-detail-targets.sh
//   { "hot": [{ "challengeId": N, "email": "rt_c<N>@booster.test", "password": "seed1234" }, ...],
//     "normal": [{ "challengeId": N, "email": "...", "password": "..." }, ...] }
//   각 엔트리는 해당 챌린지의 CONFIRMED 참여자 앵커 로그인 정보를 담는다.
//
// 실행 예:
//   SCENARIO=hot  k6 run monitoring/k6/b-axis-team-detail.js
//   SCENARIO=dist k6 run monitoring/k6/b-axis-team-detail.js

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const SCENARIO = __ENV.SCENARIO || 'dist';

const T = JSON.parse(open('./b-axis-team-detail-targets.json'));

if (!T || !Array.isArray(T.hot) || !Array.isArray(T.normal) || T.hot.length === 0 || T.normal.length === 0) {
  throw new Error(
    'b-axis-team-detail-targets.json이 비어있거나 형식이 올바르지 않습니다. 시더를 먼저 실행해 ' +
      'monitoring/k6/b-axis-team-detail-targets.json 을 생성하세요. 기대 형식: ' +
      '{"hot":[{"challengeId":N,"email":"...","password":"..."}...],"normal":[...]}'
  );
}

const errorRate  = new Rate('errors');
const tdDuration = new Trend('td_duration');

// team-detail은 무거운 비교 쿼리 + 커넥션 점유가 있어 saturation-test S3와 동일하게
// 800까지 가지 않고 400에서 관찰 종료. 총 ~2분.
const STAGES = [
  { duration: '30s', target: 50 },
  { duration: '30s', target: 100 },
  { duration: '30s', target: 200 },
  { duration: '30s', target: 400 },
];

const EXEC_MAP = {
  hot: 'hotFlow',
  dist: 'distFlow',
  'hotonly-singlekey': 'singleKeyFlow',
};

if (!EXEC_MAP[SCENARIO]) {
  throw new Error(`Unknown SCENARIO=${SCENARIO}. Use one of: hot, dist, hotonly-singlekey`);
}

export const options = {
  scenarios: {
    [SCENARIO]: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: STAGES,
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

// [JWT 전환] 전체 테스트 시작 전 1회: 모든 챌린지 앵커 유저를 로그인시켜
// { challengeId: token } 맵을 만든다. A/B축 통합 후 team-detail은 Spring Security로
// 보호되며, "토큰 유저가 그 챌린지의 CONFIRMED 참여자"일 것을 요구하므로,
// 각 요청은 반드시 해당 챌린지 앵커의 토큰으로 보내야 한다(구 X-User-Id 대체).
// 반환한 tokens 맵은 각 flow의 첫 인자(data)로 전달된다.
export function setup() {
  const tokens = {};
  const entries = T.hot.concat(T.normal);
  for (const e of entries) {
    const res = http.post(`${BASE_URL}/api/auth/login`,
      JSON.stringify({ email: e.email, password: e.password }),
      { headers: { 'Content-Type': 'application/json' } });
    const token = res.json('accessToken');
    if (!token) {
      throw new Error(
        `[JWT] 앵커 유저 로그인 실패 — b-axis-seed-team-detail.sql 먼저 적용/재생성했는지 확인. ` +
        `challengeId=${e.challengeId} email=${e.email} status=${res.status} body=${res.body}`
      );
    }
    tokens[e.challengeId] = token;
  }
  return { tokens };
}

export function handleSummary(data) {
  // 저장소 루트에서 실행 기준 상대경로 (OUT_JSON env로 재정의 가능)
  const outPath = __ENV.OUT_JSON || `docs/monitoring/baselines/td-realistic-${SCENARIO}-k6.json`;
  return {
    [outPath]: JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}

// group에서 랜덤 엔트리 하나를 골라 challengeId 반환.
// [JWT 전환] 유저는 더 이상 랜덤 선택하지 않는다 — 챌린지당 앵커 토큰이 1개이므로
// (challenge,user) 캐시 키는 챌린지별로 정확히 하나가 된다(캐시 다양성 = 챌린지 다양성).
function pickChallenge(group) {
  return group[Math.floor(Math.random() * group.length)].challengeId;
}

function requestTeamDetail(challengeId, token) {
  // [JWT 전환] X-User-Id 제거 → 해당 챌린지 앵커의 Bearer 토큰 사용
  const res = http.get(`${BASE_URL}/api/challenges/${challengeId}/team-detail`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  tdDuration.add(res.timings.duration);
  const ok = res.status === 200;
  check(res, { 'team-detail 200': () => ok });
  errorRate.add(!ok);
}

// ── hot: 매 요청마다 hot 챌린지 중 랜덤 ─────────────────────────────────
// 챌린지 수는 적지만(~10) 요청마다 바뀌므로 단일키보다는 낮되, dist보다는
// 훨씬 높은 캐시 적중률이 기대된다.
export function hotFlow(data) {
  const challengeId = pickChallenge(T.hot);
  requestTeamDetail(challengeId, data.tokens[challengeId]);
}

// ── dist: 20%는 hot, 80%는 normal에서 랜덤 선택 (실제 트래픽 분포 재현) ──
// 챌린지 후보가 hot(~10) + normal(~40) = ~50개로 늘어나 키 공간이 넓어지므로
// 캐시 적중률이 hot 시나리오보다 뚜렷하게 낮아질 것으로 예상.
export function distFlow(data) {
  const group = Math.random() < 0.2 ? T.hot : T.normal;
  const challengeId = pickChallenge(group);
  requestTeamDetail(challengeId, data.tokens[challengeId]);
}

// ── hotonly-singlekey: 참고용 — 항상 동일한 첫 hot 챌린지 고정 ──────────
// 구 b-axis-saturation.js S3와 동일한 조건(100% 적중 기준선)으로, hot/dist 결과와
// 나란히 놓고 "키 다양성이 늘어날수록 적중률이 어떻게 떨어지는지"를 비교하기 위함.
export function singleKeyFlow(data) {
  const challengeId = T.hot[0].challengeId;
  requestTeamDetail(challengeId, data.tokens[challengeId]);
}
