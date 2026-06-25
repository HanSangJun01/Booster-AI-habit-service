// [BS-30 ① 부하 도구] A축 엔드포인트 부하 테스트 (k6)
//
// 목적: 같은 API를 점점 세게 두들겨서 "트래픽 몰릴 때 어디가 느리고 어디서 터지나"를 드러냄.
//       서버 쪽 진짜 수치는 Grafana(localhost:3000)에서 보고, 여기 출력은 클라이언트 관점 + 합격/불합격.
//
// 실행 (k6 설치 필요: https://k6.io/docs/get-started/installation/):
//   k6 run a-axis-load-test.js
//   k6 run -e BASE_URL=http://localhost:8080 a-axis-load-test.js
//
// 부하 세기 조절은 아래 stages 숫자(target = 동시 가상유저 수)를 바꾸면 됨.

import http from 'k6/http';
import { check, sleep, group } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const JSON_HEADERS = { 'Content-Type': 'application/json' };

export const options = {
  scenarios: {
    // 점진적 증가(ramping): 0 → 20 → 50 → 100명으로 올리며 어디서 무너지는지 관찰
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },   // 워밍업
        { duration: '1m', target: 50 },    // 중간 부하
        { duration: '1m', target: 100 },   // 고부하 (여기서 약점 드러남)
        { duration: '30s', target: 0 },    // 쿨다운
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    // 이 선을 넘으면 "문제 있음" 신호 (테스트가 빨강으로 끝남)
    http_req_failed: ['rate<0.01'],        // 실패율 1% 미만이어야 통과
    'http_req_duration{kind:read}': ['p(95)<500'], // 읽기 API p95 0.5초 미만 목표
  },
};

// 부하 유저의 인증 장소 좌표(서울 시청 부근). 체크인도 같은 좌표로 보내 반경 안에 들어오게 함.
const SEED_LAT = 37.5665;
const SEED_LNG = 126.9780;

// 전체 테스트 시작 전 1회: 부하용 유저 생성 + 로그인 → 토큰 확보
// [2차 변경] 1차는 가입/로그인만 해서 /location이 100% 404(위치 미등록)였음.
//           2차는 setup에서 위치 등록 + 오늘 체크인까지 시드 → 읽기 5종이 전부 실제 데이터로 200 응답하도록.
// [3차 변경] LOGIN_EMAIL 환경변수를 주면, 미리 SQL로 대량 시딩해 둔 고정 유저로 "로그인만" 함
//           (signup/위치/체크인 시드 생략). 데이터 많은 유저로 dashboard/coins 부하를 측정하기 위함.
//           예: docker run ... -e LOGIN_EMAIL=seed3rd@booster.test -e LOGIN_PASSWORD=seed1234 ...
export function setup() {
  const loginEmail = __ENV.LOGIN_EMAIL;
  if (loginEmail) {
    const res = http.post(`${BASE}/api/auth/login`,
      JSON.stringify({ email: loginEmail, password: __ENV.LOGIN_PASSWORD || 'seed1234' }),
      { headers: JSON_HEADERS });
    const token = res.json('accessToken');
    if (!token) {
      throw new Error(`[3차] 시드 유저 로그인 실패 — SQL 시드/가입 먼저 했는지 확인. status=${res.status} body=${res.body}`);
    }
    return { token };
  }

  const email = `loadtest_${Date.now()}@booster.test`;
  const password = 'loadtest1234';
  const nickname = 'loadtester';

  http.post(`${BASE}/api/auth/signup`,
    JSON.stringify({ email, password, nickname }),
    { headers: JSON_HEADERS });

  const loginRes = http.post(`${BASE}/api/auth/login`,
    JSON.stringify({ email, password }),
    { headers: JSON_HEADERS });

  const token = loginRes.json('accessToken');
  if (!token) {
    throw new Error(`로그인 실패 — 토큰 못 받음. status=${loginRes.status} body=${loginRes.body}`);
  }

  const authHeaders = Object.assign({ Authorization: `Bearer ${token}` }, JSON_HEADERS);

  // ① 인증 장소 등록 → 이후 GET /location이 200을 돌려주게 됨 (1차 E1 404 착시 제거)
  const locRes = http.post(`${BASE}/api/users/me/location`,
    JSON.stringify({ lat: SEED_LAT, lng: SEED_LNG, radiusMeters: 200, placeName: 'loadtest-home' }),
    { headers: authHeaders });
  if (locRes.status !== 201) {
    throw new Error(`위치 등록 실패. status=${locRes.status} body=${locRes.body}`);
  }

  // ② 오늘 체크인(같은 좌표라 반경 내 → SUCCESS) → dashboard/today가 실제 데이터로 응답
  const checkInRes = http.post(`${BASE}/api/personal/check-in`,
    JSON.stringify({ lat: SEED_LAT, lng: SEED_LNG }),
    { headers: authHeaders });
  if (checkInRes.status !== 201) {
    throw new Error(`체크인 시드 실패. status=${checkInRes.status} body=${checkInRes.body}`);
  }

  return { token };
}

// A축 읽기 엔드포인트들 (전부 JWT 필요). name 태그로 엔드포인트별 통계가 따로 잡힘.
const READ_ENDPOINTS = [
  '/api/dashboard/home',
  '/api/users/me/coins',
  '/api/personal/check-in/today',
  '/api/personal/recovery/status',
  '/api/users/me/location',
];

export default function (data) {
  const params = {
    headers: { Authorization: `Bearer ${data.token}` },
    tags: { kind: 'read' },
  };

  group('A축 읽기 API', () => {
    for (const ep of READ_ENDPOINTS) {
      // tags.name = ep  →  k6 요약에서 엔드포인트별로 응답시간/실패율이 분리되어 나옴
      const res = http.get(`${BASE}${ep}`, Object.assign({}, params, { tags: { kind: 'read', name: ep } }));
      check(res, {
        [`${ep} → 200`]: (r) => r.status === 200,
      });
    }
  });

  sleep(1); // 유저당 1초 간격 (현실적인 사용 패턴 흉내)
}
