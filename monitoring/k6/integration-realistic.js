// A×B 통합 부하 시나리오 통합 러너 (k6)
//
// 기존 자산은 축별로 따로 논다:
//   a-axis-realistic.js   → A축(개인 인증)만
//   b-axis-load/saturation/team-detail.js → B축(챌린지)만
// 그래서 "한 유저가 A축을 쓰다 B축 챌린지까지 타고 가는 하나의 여정"은 아무도 안 본다.
// 이 파일은 그 통합면을 훑어서 (1) 느린 엔드포인트를 p95로 드러내고
// (2) 두 축이 같은 자원(코인·User락)을 동시에 건드릴 때 터지는지 본다.
//
// 서버 쪽 진짜 수치는 Grafana(localhost:3000), 여기 stdout은 클라이언트 관점 + 합격/불합격.
//
// ─────────────────────────────────────────────────────────────────────────────
// SCENARIO 목록 (한 번에 하나씩):
//   journey   A축 읽기 6종 + B축 읽기 8종을 한 유저가 순회. 0→20→50 VU.
//             엔드포인트별 p95 가 찍히므로 "어디가 느린가"가 바로 드러난다.
//   search    챌린지 검색(LIKE %keyword%)만 집중 난타. 선행 와일드카드라
//             인덱스를 못 타는 게 실제로 얼마나 느린지 격리 측정.
//   teamdetail team-detail 만 난타. 캐시키가 challengeId_userId 라
//             유저가 늘수록 적중률이 떨어지는지 관찰.
//   contention A축 개인체크인 + B축 챌린지체크인을 같은 유저가 동시에.
//             두 축의 User 락 순서가 달라 데드락/타임아웃이 나는지 본다.
//             (A축은 User락만, B축 참여는 Challenge→User 순, 정산은 User 10개 루프)
// ─────────────────────────────────────────────────────────────────────────────
//
// 실행 (Docker, 저장소 루트에서):
//   docker run --rm -i -e BASE_URL=http://host.docker.internal:8080 -e SCENARIO=journey \
//     -v ${PWD}/monitoring/k6://scripts grafana/k6 run //scripts/integration-realistic.js
//   ※ Git Bash 에서는 MSYS_NO_PATHCONV=1 + 경로 앞 // (경로 뭉개짐 방지)
//
// 전제: docker compose up -d (백엔드 8080 + booster-db). 시딩은 setup()이 스스로 한다.

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const SCENARIO = __ENV.SCENARIO || 'journey';
const JSON_HEADERS = { 'Content-Type': 'application/json' };

// 인증 장소(서울 시청). 체크인도 같은 좌표라 반경 안 → SUCCESS.
const SEED_LAT = 37.5665;
const SEED_LNG = 126.9780;

// 팀 자동편성 정원. 10명이 CONFIRMED 되면 팀 2개 생성 + 챌린지 ACTIVE 전환.
const TEAM_SIZE = 10;

// ─── 시나리오 정의 ────────────────────────────────────────────────────────────
const SCENARIOS = {
  journey: {
    exec: 'journeyFlow',
    scenario: {
      executor: 'ramping-vus', startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },
        { duration: '1m', target: 50 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
    thresholds: {
      http_req_failed: ['rate<0.01'],
      // 개별 엔드포인트 p95는 summary 에서 name 태그별로 본다.
      // 여기 상한은 "느린 놈을 드러내는" 용도지 합격선이 아니다.
      'http_req_duration{kind:read}': ['p(95)<1000'],
    },
  },

  search: {
    exec: 'searchFlow',
    scenario: {
      executor: 'ramping-vus', startVUs: 0,
      stages: [
        { duration: '30s', target: 30 },
        { duration: '1m', target: 80 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
    thresholds: { http_req_failed: ['rate<0.05'] },
  },

  teamdetail: {
    exec: 'teamDetailFlow',
    scenario: {
      executor: 'ramping-vus', startVUs: 0,
      stages: [
        { duration: '30s', target: 50 },
        { duration: '1m', target: 150 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
    thresholds: { http_req_failed: ['rate<0.05'] },
  },

  contention: {
    exec: 'contentionFlow',
    scenario: {
      executor: 'constant-vus',
      vus: 30,          // 같은 유저 풀(10명)을 30 VU가 물고 늘어짐 → 락 경합 강제
      duration: '1m',
    },
    // 경합이 목적 — 실패가 나오는 게 정보다. 상한은 관찰용.
    thresholds: { http_req_failed: ['rate<0.50'] },
  },
};

const CFG = SCENARIOS[SCENARIO];
if (!CFG) {
  throw new Error(
    `알 수 없는 SCENARIO=${SCENARIO}. 다음 중 하나를 쓰세요: ${Object.keys(SCENARIOS).join(', ')} ` +
      `(예: k6 run -e SCENARIO=journey integration-realistic.js)`
  );
}

export const options = {
  scenarios: { [SCENARIO]: Object.assign({ exec: CFG.exec }, CFG.scenario) },
  thresholds: CFG.thresholds,
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

// 축별 총합 — "A축이 느린가 B축이 느린가"를 한 줄로 답하기 위해.
const aAxisRead = new Trend('a_axis_read', true);
const bAxisRead = new Trend('b_axis_read', true);

// 엔드포인트별 Trend — 이게 이 스크립트의 핵심 산출물이다.
// k6 기본 summary 는 tag 별로 p95 를 쪼개주지 않으므로(태그는 필터링용),
// "어느 엔드포인트가 느린가"에 답하려면 엔드포인트마다 Trend 를 따로 들어야 한다.
// 이름을 ep_ 로 맞춰두면 summary 에서 한 덩어리로 모여 비교하기 쉽다.
const EP_NAMES = [
  'A:dashboard', 'A:me', 'A:coins', 'A:checkin-today', 'A:recovery', 'A:location',
  'B:challenge-list', 'B:challenge-detail', 'B:team-detail', 'B:teams',
  'B:checkin-list', 'B:leaderboard-team', 'B:leaderboard-personal', 'B:chat',
  'B:search', 'A:personal-checkin', 'B:challenge-checkin',
];
const EP = {};
for (const n of EP_NAMES) {
  // 메트릭 이름에 : 가 들어가면 보기 나쁘므로 _ 로 정규화
  EP[n] = new Trend(`ep_${n.replace(/[:-]/g, '_')}`, true);
}

// ─── 공통 헬퍼 ────────────────────────────────────────────────────────────────
function login(email, password) {
  return http.post(`${BASE}/api/auth/login`, JSON.stringify({ email, password }),
    { headers: JSON_HEADERS });
}

function authHdr(token, name, kind) {
  return { headers: { Authorization: `Bearer ${token}` }, tags: { kind: kind || 'read', name: name } };
}

// 응답 1건을 축 Trend + 엔드포인트 Trend 양쪽에 적재.
function record(res, name, axis) {
  (axis === 'a' ? aAxisRead : bAxisRead).add(res.timings.duration);
  if (EP[name]) EP[name].add(res.timings.duration);
}

// GET 한 방 + 체크 + Trend 적재.
function getTagged(path, token, name, axis) {
  const res = http.get(`${BASE}${path}`, authHdr(token, name, 'read'));
  check(res, { [`${name} → 200`]: (r) => r.status === 200 });
  record(res, name, axis);
  return res;
}

// ─── setup: 통합 여정에 필요한 판을 스스로 깐다 (전체 1회) ──────────────────
// 유저 10명 가입 → 각자 A축 위치등록 → 챌린지 1개 생성 → 10명 전원 참여
// → 팀 자동편성 + ACTIVE 전환. 반환값은 모든 flow 의 첫 인자(data)로 전달된다.
export function setup() {
  const stamp = Date.now();
  const users = [];

  for (let i = 0; i < TEAM_SIZE; i++) {
    const email = `itg_${stamp}_${i}@booster.test`;
    const password = 'itgtest1234';

    const su = http.post(`${BASE}/api/auth/signup`,
      JSON.stringify({ email, password, nickname: `itg${i}` }), { headers: JSON_HEADERS });
    if (su.status !== 201) throw new Error(`[setup] 가입 실패 i=${i} status=${su.status} body=${su.body}`);

    const lr = login(email, password);
    const token = lr.json('accessToken');
    const userId = lr.json('userId');
    if (!token) throw new Error(`[setup] 로그인 실패 i=${i} status=${lr.status} body=${lr.body}`);

    // A축 인증 장소 등록 — 이게 있어야 개인 체크인/위치조회가 실데이터로 200.
    // (없으면 B축 체크인 시 A축 연쇄가 조용히 실패한다 — probe-integration.sh P7 참고)
    const loc = http.post(`${BASE}/api/users/me/location`,
      JSON.stringify({ lat: SEED_LAT, lng: SEED_LNG, radiusMeters: 200, placeName: `itg-home-${i}` }),
      { headers: Object.assign({ Authorization: `Bearer ${token}` }, JSON_HEADERS) });
    if (loc.status !== 201) throw new Error(`[setup] 위치등록 실패 i=${i} status=${loc.status} body=${loc.body}`);

    users.push({ token, userId, email, password });
  }

  const owner = { headers: Object.assign({ Authorization: `Bearer ${users[0].token}` }, JSON_HEADERS) };

  // 챌린지 생성. depositCoins=0 — 참가비 차감이 목적이 아니라 판 깔기가 목적이라
  // 신규 유저 기본 코인(500)이 모자라 참여가 튕기는 일을 막는다.
  // title 은 ASCII 로 둔다: Git Bash 에서 한글 인자가 CP949 로 뭉개져 400 나는 걸 피함.
  const chRes = http.post(`${BASE}/api/challenges`, JSON.stringify({
    title: `itg_challenge_${stamp}`, category: 'HEALTH', verificationType: 'GPS',
    durationDays: 14, depositCoins: 0, maxParticipants: TEAM_SIZE,
    visibility: 'PUBLIC', approvalType: 'AUTO',
  }), owner);
  const challengeId = chRes.json('data.id');
  if (!challengeId) throw new Error(`[setup] 챌린지 생성 실패 status=${chRes.status} body=${chRes.body}`);

  // 10명 전원 참여 → 마지막 참여에서 팀 자동편성 + ACTIVE 전환 트리거
  for (let i = 0; i < TEAM_SIZE; i++) {
    const pr = http.post(`${BASE}/api/challenges/${challengeId}/participants`, JSON.stringify({
      personalStatement: 'join', gpsLat: SEED_LAT, gpsLng: SEED_LNG,
      gpsRadiusMeters: 100, gpsPlaceName: 'CityHall',
    }), { headers: Object.assign({ Authorization: `Bearer ${users[i].token}` }, JSON_HEADERS) });
    if (pr.status !== 201) throw new Error(`[setup] 참여 실패 i=${i} status=${pr.status} body=${pr.body}`);
  }

  // 팀 편성 결과 확인 — 여기서 teamId 를 못 얻으면 채팅/팀상세 측정이 불가하므로 즉시 실패시킨다.
  const teamsRes = http.get(`${BASE}/api/challenges/${challengeId}/teams`, owner);
  const teams = teamsRes.json('data');
  if (!teams || teams.length === 0) {
    throw new Error(`[setup] 팀 미편성 — ${TEAM_SIZE}명 참여 후에도 팀 0개. status=${teamsRes.status} body=${teamsRes.body}`);
  }
  const teamId = teams[0].id;

  return { users, challengeId, teamId, stamp };
}

function pickUser(data) {
  return data.users[__VU % data.users.length];
}

// ─── journey: A축 6종 + B축 8종 순회 — 엔드포인트별 p95 를 드러낸다 ──────────
export function journeyFlow(data) {
  const u = pickUser(data);
  const t = u.token;
  const cid = data.challengeId;

  group('A축 읽기', () => {
    getTagged('/api/dashboard/home', t, 'A:dashboard', 'a');
    getTagged('/api/users/me', t, 'A:me', 'a');
    getTagged('/api/users/me/coins?page=0&size=20', t, 'A:coins', 'a');
    getTagged('/api/personal/check-in/today', t, 'A:checkin-today', 'a');
    getTagged('/api/personal/recovery/status', t, 'A:recovery', 'a');
    getTagged('/api/users/me/location', t, 'A:location', 'a');
  });

  group('B축 읽기', () => {
    getTagged('/api/challenges?page=0&size=20', t, 'B:challenge-list', 'b');
    getTagged(`/api/challenges/${cid}`, t, 'B:challenge-detail', 'b');
    getTagged(`/api/challenges/${cid}/team-detail`, t, 'B:team-detail', 'b');
    getTagged(`/api/challenges/${cid}/teams`, t, 'B:teams', 'b');
    getTagged(`/api/challenges/${cid}/check-ins`, t, 'B:checkin-list', 'b');
    getTagged(`/api/challenges/${cid}/leaderboards?type=TEAM`, t, 'B:leaderboard-team', 'b');
    getTagged(`/api/challenges/${cid}/leaderboards?type=PERSONAL`, t, 'B:leaderboard-personal', 'b');
    getTagged(`/api/teams/${data.teamId}/chat?page=0&size=20`, t, 'B:chat', 'b');
  });

  sleep(1);
}

// ─── search: LIKE %keyword% 격리 측정 ────────────────────────────────────────
// 선행 와일드카드라 btree 인덱스를 못 탄다. 실제로 얼마나 느린지 다른 요청과 섞지 않고 본다.
export function searchFlow(data) {
  const t = pickUser(data).token;
  // 매번 다른 키워드 → 혹시 있을 캐시/플랜 재사용 효과를 배제
  const kw = `itg_${(__ITER % 50)}`;
  const res = http.get(`${BASE}/api/challenges?keyword=${kw}&page=0&size=20`,
    authHdr(t, 'B:search', 'read'));
  check(res, { 'search → 200': (r) => r.status === 200 });
  record(res, 'B:search', 'b');
}

// ─── teamdetail: 캐시키(challengeId_userId) 다양성에 따른 적중률 관찰 ────────
export function teamDetailFlow(data) {
  const t = pickUser(data).token; // VU 마다 다른 유저 → 캐시키가 유저 수만큼 갈림
  const res = http.get(`${BASE}/api/challenges/${data.challengeId}/team-detail`,
    authHdr(t, 'B:team-detail', 'read'));
  check(res, { 'team-detail → 200': (r) => r.status === 200 });
  record(res, 'B:team-detail', 'b');
}

// ─── contention: A축 개인체크인 ↔ B축 챌린지체크인 동시 (락 경합/데드락 탐지) ──
// A축 개인체크인은 User 를 비관락하고, B축 챌린지체크인은 그 안에서 A축을 다시 호출한다.
// 같은 유저에 두 경로가 동시에 들어갈 때 데드락/락타임아웃이 나는지가 관심사.
// 체크인은 하루 1회 멱등이라 2회차부터는 409/멱등 응답이 정상 — 여기선 상태코드가 아니라
// "5xx / 타임아웃 / 락 예외가 나는가"를 본다.
export function contentionFlow(data) {
  const u = pickUser(data);
  const hdr = { headers: Object.assign({ Authorization: `Bearer ${u.token}` }, JSON_HEADERS) };
  const body = JSON.stringify({ lat: SEED_LAT, lng: SEED_LNG });
  const bBody = JSON.stringify({ currentLat: SEED_LAT, currentLng: SEED_LNG });

  // 두 축을 같은 순간에 (k6 batch = 병렬 발사)
  const responses = http.batch([
    { method: 'POST', url: `${BASE}/api/personal/check-in`, body: body,
      params: Object.assign({}, hdr, { tags: { kind: 'write', name: 'A:personal-checkin' } }) },
    { method: 'POST', url: `${BASE}/api/challenges/${data.challengeId}/check-ins`, body: bBody,
      params: Object.assign({}, hdr, { tags: { kind: 'write', name: 'B:challenge-checkin' } }) },
  ]);

  // 5xx 만 실패로 센다 — 409(멱등/중복)는 정상 동작이다.
  const names = ['A:personal-checkin', 'B:challenge-checkin'];
  for (let i = 0; i < responses.length; i++) {
    check(responses[i], { '5xx 아님': (x) => x.status < 500 });
    record(responses[i], names[i], i === 0 ? 'a' : 'b');
  }
  sleep(0.5);
}
