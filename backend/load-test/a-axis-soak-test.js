// [BS-30 A: soak/지속 부하] A축 안정성 테스트 (k6)
// 목적: 30분간 "일정한 중간 부하"를 꾸준히 걸어 메모리 누수 / 커넥션 누수 / 시간에 따른 성능 저하를 관찰.
//       버스트(3분)로는 안 드러나는 "서서히 새는" 문제를 잡는다. JVM heap 추이를 Grafana/Prometheus로 본다.
// 실행:
//   docker run --rm -i -e BASE_URL=http://host.docker.internal:8080 -v ${PWD}:/scripts grafana/k6 run /scripts/a-axis-soak-test.js

import http from 'k6/http';
import { check, sleep, group } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const JSON_HEADERS = { 'Content-Type': 'application/json' };
const LAT = 37.5665;
const LNG = 126.9780;

export const options = {
  scenarios: {
    soak: {
      executor: 'constant-vus',
      vus: 30,            // 중간 부하 일정 유지
      duration: '30m',    // 길게 — 누수/저하는 시간이 지나야 보임
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{kind:read}': ['p(95)<500'],
  },
};

export function setup() {
  const email = `soak_${Date.now()}@booster.test`;
  const password = 'soaktest1234';
  http.post(`${BASE}/api/auth/signup`,
    JSON.stringify({ email, password, nickname: 'soaker' }), { headers: JSON_HEADERS });
  const loginRes = http.post(`${BASE}/api/auth/login`,
    JSON.stringify({ email, password }), { headers: JSON_HEADERS });
  const token = loginRes.json('accessToken');
  if (!token) throw new Error(`soak 로그인 실패. status=${loginRes.status}`);
  const authHeaders = Object.assign({ Authorization: `Bearer ${token}` }, JSON_HEADERS);
  http.post(`${BASE}/api/users/me/location`,
    JSON.stringify({ lat: LAT, lng: LNG, radiusMeters: 200, placeName: 'soak' }), { headers: authHeaders });
  http.post(`${BASE}/api/personal/check-in`,
    JSON.stringify({ lat: LAT, lng: LNG }), { headers: authHeaders });
  return { token };
}

const READ_ENDPOINTS = [
  '/api/dashboard/home',
  '/api/users/me/coins',
  '/api/personal/check-in/today',
  '/api/personal/recovery/status',
  '/api/users/me/location',
];

export default function (data) {
  const params = { headers: { Authorization: `Bearer ${data.token}` }, tags: { kind: 'read' } };
  group('soak 읽기', () => {
    for (const ep of READ_ENDPOINTS) {
      const res = http.get(`${BASE}${ep}`, Object.assign({}, params, { tags: { kind: 'read', name: ep } }));
      check(res, { [`${ep} → 200`]: (r) => r.status === 200 });
    }
  });
  sleep(1);
}
