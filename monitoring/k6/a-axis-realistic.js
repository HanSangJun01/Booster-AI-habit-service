// A축 부하 시나리오 통합 러너 (k6)
//
// 예전엔 load / stress / soak / write 4개 파일을 따로 켜야 했다("한 개 켜고 또 한 개 켜고").
// 이제 이 한 파일에서 SCENARIO 환경변수로 원하는 시나리오만 골라 돌린다.
// (B축 team-detail-realistic.js 와 같은 방식 — 시나리오 스위처 + 공통코드 1회.)
//
// 서버 쪽 진짜 수치는 Grafana(localhost:3000)에서 보고, 여기 stdout은 클라이언트 관점 + 합격/불합격.
//
// ─────────────────────────────────────────────────────────────────────────────
// SCENARIO 목록 (한 번에 하나씩):
//   load    읽기 5종 부하. 0→20→50→100 VU 점증. "트래픽 몰릴 때 어디가 느리나".
//           기본은 setup에서 유저 1명 자가시딩(가입+로그인+위치+체크인).
//           LOGIN_EMAIL 주면 미리 SQL 시딩해둔 고정 유저로 로그인만 함.
//   stress  읽기 5종 한계탐색. 100→300→500 VU. "어디서 무너지나".
//           선행: seed3rd@booster.test 가 시드돼 있어야 함(seed-3rd.sql).
//   soak    읽기 5종을 30 VU로 30분 지속. 메모리/커넥션 누수·서서히 새는 성능저하 관찰.
//           자가시딩. JVM heap 추이는 Grafana/Prometheus로 본다.
//   write   신규 유저 온보딩(쓰기) 부하. 매 반복마다 새 유저가 가입→로그인→위치→체크인.
//           0→20→50→100 VU. BCrypt CPU 한계, 코인 락 경합, 쓰기 처리량을 드러냄.
// ─────────────────────────────────────────────────────────────────────────────
//
// 실행 (k6 로컬 설치 시):
//   k6 run -e SCENARIO=load   a-axis-realistic.js
//   k6 run -e SCENARIO=stress a-axis-realistic.js
//   k6 run -e SCENARIO=soak   a-axis-realistic.js
//   k6 run -e SCENARIO=write  a-axis-realistic.js
//
// 실행 (Docker, 저장소 루트에서 — k6 미설치 시):
//   docker run --rm -i -e BASE_URL=http://host.docker.internal:8080 -e SCENARIO=load \
//     -v ${PWD}/monitoring/k6:/scripts grafana/k6 run /scripts/a-axis-realistic.js
//
// 부하 세기 조절: 아래 SCENARIOS[...].scenario 의 stages target(=동시 가상유저 수)을 바꾼다.

import http from 'k6/http';
import { check, sleep, group } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const SCENARIO = __ENV.SCENARIO || 'load';
const JSON_HEADERS = { 'Content-Type': 'application/json' };

// 부하 유저의 인증 장소 좌표(서울 시청 부근). 체크인도 같은 좌표로 보내 반경 안에 들어오게 함.
const SEED_LAT = 37.5665;
const SEED_LNG = 126.9780;

// A축 읽기 엔드포인트들 (전부 JWT 필요). tags.name 으로 엔드포인트별 통계가 따로 잡힘.
const READ_ENDPOINTS = [
  '/api/dashboard/home',
  '/api/users/me/coins',
  '/api/personal/check-in/today',
  '/api/personal/recovery/status',
  '/api/users/me/location',
];

// ─── 시나리오 정의 ────────────────────────────────────────────────────────────
// seed 모드:  'self'  setup에서 유저1명 자가시딩(가입+로그인+위치+체크인) → data.token
//            'login' setup에서 미리 시딩된 고정 유저로 로그인만 → data.token
//            'none'  setup 없음(write는 매 반복 새 유저를 직접 만듦)
const SCENARIOS = {
  load: {
    exec: 'readFlow',
    seed: 'self', // LOGIN_EMAIL 주면 login-only로 전환됨(setup 참고)
    scenario: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },  // 워밍업
        { duration: '1m', target: 50 },   // 중간 부하
        { duration: '1m', target: 100 },  // 고부하 (여기서 약점 드러남)
        { duration: '30s', target: 0 },   // 쿨다운
      ],
      gracefulRampDown: '10s',
    },
    thresholds: {
      http_req_failed: ['rate<0.01'],
      'http_req_duration{kind:read}': ['p(95)<500'],
    },
  },

  stress: {
    exec: 'readFlow',
    seed: 'login', // 기본 seed3rd@booster.test (데이터 많은 유저로 한계탐색)
    scenario: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 },
        { duration: '1m', target: 300 },
        { duration: '1m', target: 500 },  // 한계 탐색 구간
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
    thresholds: {
      http_req_failed: ['rate<0.05'],
      'http_req_duration{kind:read}': ['p(95)<1000'],
    },
  },

  soak: {
    exec: 'readFlow',
    seed: 'self',
    scenario: {
      executor: 'constant-vus',
      vus: 30,          // 중간 부하 일정 유지
      duration: '30m',  // 길게 — 누수/저하는 시간이 지나야 보임
    },
    thresholds: {
      http_req_failed: ['rate<0.01'],
      'http_req_duration{kind:read}': ['p(95)<500'],
    },
  },

  write: {
    exec: 'writeFlow',
    seed: 'none', // 매 반복마다 새 유저 생성이 곧 부하 자체
    scenario: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },
        { duration: '1m', target: 50 },
        { duration: '1m', target: 100 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
    thresholds: {
      http_req_failed: ['rate<0.01'],
      // 쓰기/BCrypt는 읽기보다 무거움 → 느슨한 상한으로 "수치를 드러내기" 용도(엔드포인트별 p95 출력)
      'http_req_duration{name:signup}': ['p(95)<3000'],
      'http_req_duration{name:login}': ['p(95)<3000'],
      'http_req_duration{name:location}': ['p(95)<3000'],
      'http_req_duration{name:checkin}': ['p(95)<3000'],
    },
  },
};

const CFG = SCENARIOS[SCENARIO];
if (!CFG) {
  throw new Error(
    `알 수 없는 SCENARIO=${SCENARIO}. 다음 중 하나를 쓰세요: ${Object.keys(SCENARIOS).join(', ')} ` +
      `(예: k6 run -e SCENARIO=load a-axis-realistic.js)`
  );
}

export const options = {
  scenarios: {
    [SCENARIO]: Object.assign({ exec: CFG.exec }, CFG.scenario),
  },
  thresholds: CFG.thresholds,
};

// ─── 공통 헬퍼 ────────────────────────────────────────────────────────────────
function login(email, password) {
  return http.post(`${BASE}/api/auth/login`,
    JSON.stringify({ email, password }), { headers: JSON_HEADERS });
}

function tokenOrThrow(res, msg) {
  const token = res.json('accessToken');
  if (!token) throw new Error(`${msg} status=${res.status} body=${res.body}`);
  return token;
}

// ─── setup: 시나리오별 시딩/로그인 (전체 테스트 시작 전 1회) ────────────────────
export function setup() {
  if (CFG.seed === 'none') return {}; // write: 반복마다 새 유저

  // login-only: seed 모드가 'login'이거나, 명시적으로 LOGIN_EMAIL을 준 경우.
  // (load는 기본 자가시딩이지만 LOGIN_EMAIL을 주면 대량 시딩 유저로 로그인만 하도록 전환)
  const loginEmail = __ENV.LOGIN_EMAIL || (CFG.seed === 'login' ? 'seed3rd@booster.test' : null);
  if (loginEmail) {
    const res = login(loginEmail, __ENV.LOGIN_PASSWORD || 'seed1234');
    return {
      token: tokenOrThrow(res,
        `[${SCENARIO}] 시드 유저(${loginEmail}) 로그인 실패 — SQL 시드/가입 먼저 했는지 확인.`),
    };
  }

  // self-seed: 가입 + 로그인 + 위치등록 + 오늘 체크인 → 읽기 5종이 전부 실제 데이터로 200
  const email = `${SCENARIO}_${Date.now()}@booster.test`;
  const password = 'loadtest1234';

  http.post(`${BASE}/api/auth/signup`,
    JSON.stringify({ email, password, nickname: `${SCENARIO}er` }), { headers: JSON_HEADERS });

  const token = tokenOrThrow(login(email, password), `[${SCENARIO}] 자가시딩 로그인 실패 — 토큰 못 받음.`);
  const authHeaders = Object.assign({ Authorization: `Bearer ${token}` }, JSON_HEADERS);

  // ① 인증 장소 등록 → 이후 GET /location 이 200
  const locRes = http.post(`${BASE}/api/users/me/location`,
    JSON.stringify({ lat: SEED_LAT, lng: SEED_LNG, radiusMeters: 200, placeName: `${SCENARIO}-home` }),
    { headers: authHeaders });
  if (locRes.status !== 201) throw new Error(`[${SCENARIO}] 위치 등록 실패. status=${locRes.status} body=${locRes.body}`);

  // ② 오늘 체크인(같은 좌표라 반경 내 → SUCCESS) → dashboard/today 가 실제 데이터로 응답
  const checkInRes = http.post(`${BASE}/api/personal/check-in`,
    JSON.stringify({ lat: SEED_LAT, lng: SEED_LNG }), { headers: authHeaders });
  if (checkInRes.status !== 201) throw new Error(`[${SCENARIO}] 체크인 시드 실패. status=${checkInRes.status} body=${checkInRes.body}`);

  return { token };
}

// ─── readFlow: 읽기 5종 두들김 (load / stress / soak 공용) ─────────────────────
export function readFlow(data) {
  const params = { headers: { Authorization: `Bearer ${data.token}` }, tags: { kind: 'read' } };
  group('A축 읽기 API', () => {
    for (const ep of READ_ENDPOINTS) {
      const res = http.get(`${BASE}${ep}`, Object.assign({}, params, { tags: { kind: 'read', name: ep } }));
      check(res, { [`${ep} → 200`]: (r) => r.status === 200 });
    }
  });
  sleep(1); // 유저당 1초 간격 (현실적인 사용 패턴 흉내)
}

// ─── writeFlow: 신규 유저 온보딩(쓰기) — 매 반복 새 유저 ───────────────────────
export function writeFlow() {
  // VU+반복+시각 조합으로 전역 유니크 이메일 보장
  const email = `w_${__VU}_${__ITER}_${Date.now()}@booster.test`;
  const password = 'writetest1234';

  group('신규 유저 온보딩(쓰기)', () => {
    // ① 가입: BCrypt + insert + 코인 보너스(비관적 락 findByIdForUpdate)
    const signupRes = http.post(`${BASE}/api/auth/signup`,
      JSON.stringify({ email, password, nickname: 'wtester' }),
      { headers: JSON_HEADERS, tags: { name: 'signup', kind: 'write' } });
    check(signupRes, { 'signup → 201': (r) => r.status === 201 });
    if (signupRes.status !== 201) return; // 가입 실패 시 이후 단계 무의미

    // ② 로그인: BCrypt 검증(CPU 집약)
    const loginRes = http.post(`${BASE}/api/auth/login`,
      JSON.stringify({ email, password }),
      { headers: JSON_HEADERS, tags: { name: 'login', kind: 'write' } });
    check(loginRes, { 'login → 200': (r) => r.status === 200 });
    const token = loginRes.json('accessToken');
    if (!token) return;

    const authHeaders = Object.assign({ Authorization: `Bearer ${token}` }, JSON_HEADERS);

    // ③ 위치 등록: 쓰기
    const locRes = http.post(`${BASE}/api/users/me/location`,
      JSON.stringify({ lat: SEED_LAT, lng: SEED_LNG, radiusMeters: 200, placeName: 'wtest' }),
      { headers: authHeaders, tags: { name: 'location', kind: 'write' } });
    check(locRes, { 'location → 201': (r) => r.status === 201 });

    // ④ 체크인: 쓰기(insert + streak/attendance 갱신, 같은 좌표라 반경 내 성공)
    const checkInRes = http.post(`${BASE}/api/personal/check-in`,
      JSON.stringify({ lat: SEED_LAT, lng: SEED_LNG }),
      { headers: authHeaders, tags: { name: 'checkin', kind: 'write' } });
    check(checkInRes, { 'checkin → 201': (r) => r.status === 201 });
  });

  sleep(1);
}
