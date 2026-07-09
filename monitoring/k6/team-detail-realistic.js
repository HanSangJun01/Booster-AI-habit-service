// team-detail 현실 트래픽 재현 테스트 — hot-key 편중 vs distributed-key 재현 비교
//
// saturation-test.js의 S3(team-detail)는 "고정 1키 난타"로 캐시 적중률을 인위적으로
// 100%에 가깝게 만든다. 실제 트래픽은 인기 챌린지(hot)에 요청이 몰리되, 나머지
// 챌린지(normal)에도 분산되어 들어온다. 이 스크립트는 rt-targets.json에 담긴
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
// 사전 조건: monitoring/k6/rt-targets.json 이 시더에 의해 생성되어 있어야 한다.
//   { "hot": [{ "challengeId": N, "userIds": [...] }, ...],   // 인기 챌린지 ~10개 (20%)
//     "normal": [{ "challengeId": N, "userIds": [...] }, ...] } // 나머지 챌린지 ~40개 (80%)
//
// 실행 예:
//   SCENARIO=hot  k6 run monitoring/k6/team-detail-realistic.js
//   SCENARIO=dist k6 run monitoring/k6/team-detail-realistic.js

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const SCENARIO = __ENV.SCENARIO || 'dist';

const T = JSON.parse(open('./rt-targets.json'));

if (!T || !Array.isArray(T.hot) || !Array.isArray(T.normal) || T.hot.length === 0 || T.normal.length === 0) {
  throw new Error(
    'rt-targets.json이 비어있거나 형식이 올바르지 않습니다. 시더를 먼저 실행해 ' +
      'monitoring/k6/rt-targets.json 을 생성하세요. 기대 형식: ' +
      '{"hot":[{"challengeId":N,"userIds":[...]}...],"normal":[...]}'
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

export function handleSummary(data) {
  const outPath =
    __ENV.OUT_JSON ||
    `/Users/hansangjun/Desktop/Booster-AI-habit-service/docs/monitoring/baselines/td-realistic-${SCENARIO}-k6.json`;
  return {
    [outPath]: JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}

function pickFrom(group) {
  const entry = group[Math.floor(Math.random() * group.length)];
  const userId = entry.userIds[Math.floor(Math.random() * entry.userIds.length)];
  return { challengeId: entry.challengeId, userId };
}

function requestTeamDetail(challengeId, userId) {
  const res = http.get(`${BASE_URL}/api/challenges/${challengeId}/team-detail`, {
    headers: { 'X-User-Id': String(userId) },
  });
  tdDuration.add(res.timings.duration);
  const ok = res.status === 200;
  check(res, { 'team-detail 200': () => ok });
  errorRate.add(!ok);
}

// ── hot: 매 요청마다 hot 챌린지 중 랜덤 + 그 챌린지의 랜덤 유저 ──────────
// 챌린지 수는 적지만(~10) 요청마다 바뀌므로 단일키보다는 낮되, dist보다는
// 훨씬 높은 캐시 적중률이 기대된다.
export function hotFlow() {
  const { challengeId, userId } = pickFrom(T.hot);
  requestTeamDetail(challengeId, userId);
}

// ── dist: 20%는 hot, 80%는 normal에서 랜덤 선택 (실제 트래픽 분포 재현) ──
// 챌린지 후보가 hot(~10) + normal(~40) = ~50개로 늘어나 키 공간이 넓어지므로
// 캐시 적중률이 hot 시나리오보다 뚜렷하게 낮아질 것으로 예상.
export function distFlow() {
  const group = Math.random() < 0.2 ? T.hot : T.normal;
  const { challengeId, userId } = pickFrom(group);
  requestTeamDetail(challengeId, userId);
}

// ── hotonly-singlekey: 참고용 — 항상 동일한 첫 hot 챌린지 + 첫 유저 고정 ─
// 구 saturation-test.js S3와 동일한 조건(100% 적중 기준선)으로, hot/dist 결과와
// 나란히 놓고 "키 다양성이 늘어날수록 적중률이 어떻게 떨어지는지"를 비교하기 위함.
export function singleKeyFlow() {
  const entry = T.hot[0];
  requestTeamDetail(entry.challengeId, entry.userIds[0]);
}
