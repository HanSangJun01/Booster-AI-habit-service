// [BS-30 4차 부하] A축 "쓰기 + 로그인 + 다중 유저" 부하 테스트 (k6)
//
// 1~3차는 GET(읽기)·단일 유저만 측정 → 출시 리스크인 쓰기/로그인/동시 유저는 미검증이었음.
// 4차는 매 반복마다 "새 유저"가 가입→로그인→위치등록→체크인까지 수행(신규 유저 몰림 시나리오).
//   - signup : BCrypt 해시 + 유저/스트릭 insert + 코인 보너스(비관적 락 findByIdForUpdate)
//   - login  : BCrypt 검증(CPU 집약)
//   - location/check-in : 쓰기 경로(insert + streak/attendance 갱신)
// 목적: BCrypt CPU 한계, 코인 락 경합, 쓰기 처리량을 숫자로 드러내기.
//
// 실행:
//   docker run --rm -i -e BASE_URL=http://host.docker.internal:8080 -v ${PWD}:/scripts grafana/k6 run /scripts/a-axis-write-load-test.js

import http from 'k6/http';
import { check, sleep, group } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const JSON_HEADERS = { 'Content-Type': 'application/json' };

// 인증 장소 좌표(서울 시청). 체크인도 같은 좌표로 보내 반경 내 성공시킴.
const LAT = 37.5665;
const LNG = 126.9780;

export const options = {
  scenarios: {
    ramp_up: {
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
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    // 쓰기/BCrypt는 읽기보다 무거움 → 느슨한 상한으로 "수치를 드러내기" 용도(엔드포인트별 p95 출력)
    'http_req_duration{name:signup}': ['p(95)<3000'],
    'http_req_duration{name:login}': ['p(95)<3000'],
    'http_req_duration{name:location}': ['p(95)<3000'],
    'http_req_duration{name:checkin}': ['p(95)<3000'],
  },
};

export default function () {
  // VU+반복+시각 조합으로 전역 유니크 이메일 보장
  const email = `w_${__VU}_${__ITER}_${Date.now()}@booster.test`;
  const password = 'writetest1234';
  const nickname = 'wtester';

  group('신규 유저 온보딩(쓰기)', () => {
    // ① 가입: BCrypt + insert + 코인 보너스(락)
    const signupRes = http.post(`${BASE}/api/auth/signup`,
      JSON.stringify({ email, password, nickname }),
      { headers: JSON_HEADERS, tags: { name: 'signup', kind: 'write' } });
    check(signupRes, { 'signup → 201': (r) => r.status === 201 });
    if (signupRes.status !== 201) return; // 가입 실패 시 이후 단계 무의미

    // ② 로그인: BCrypt 검증
    const loginRes = http.post(`${BASE}/api/auth/login`,
      JSON.stringify({ email, password }),
      { headers: JSON_HEADERS, tags: { name: 'login', kind: 'write' } });
    check(loginRes, { 'login → 200': (r) => r.status === 200 });
    const token = loginRes.json('accessToken');
    if (!token) return;

    const authHeaders = Object.assign({ Authorization: `Bearer ${token}` }, JSON_HEADERS);

    // ③ 위치 등록: 쓰기
    const locRes = http.post(`${BASE}/api/users/me/location`,
      JSON.stringify({ lat: LAT, lng: LNG, radiusMeters: 200, placeName: 'wtest' }),
      { headers: authHeaders, tags: { name: 'location', kind: 'write' } });
    check(locRes, { 'location → 201': (r) => r.status === 201 });

    // ④ 체크인: 쓰기(insert + streak/attendance 갱신, 같은 좌표라 반경 내 성공)
    const checkInRes = http.post(`${BASE}/api/personal/check-in`,
      JSON.stringify({ lat: LAT, lng: LNG }),
      { headers: authHeaders, tags: { name: 'checkin', kind: 'write' } });
    check(checkInRes, { 'checkin → 201': (r) => r.status === 201 });
  });

  sleep(1);
}
