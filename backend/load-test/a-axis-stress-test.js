// [BS-30 B: 고동시성 스트레스] A축 한계점 탐색 (k6)
// 목적: 1~3차는 100 VU까지만 봄. 여기선 100→300→500으로 밀어 "어디서 무너지나(한계점)"를 찾는다.
//       데이터 있는 유저(seed3rd)로 로그인해 읽기 5종을 두들김. 실패율/지연이 급증하는 VU 구간을 관찰.
// 선행: seed3rd@booster.test 가 시드되어 있어야 함(3차에서 생성됨).
// 실행:
//   docker run --rm -i -e BASE_URL=http://host.docker.internal:8080 -v ${PWD}:/scripts grafana/k6 run /scripts/a-axis-stress-test.js

import http from 'k6/http';
import { check, sleep, group } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const JSON_HEADERS = { 'Content-Type': 'application/json' };

export const options = {
  scenarios: {
    stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 },
        { duration: '1m', target: 300 },
        { duration: '1m', target: 500 },   // 한계 탐색 구간
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    'http_req_duration{kind:read}': ['p(95)<1000'],
  },
};

export function setup() {
  const res = http.post(`${BASE}/api/auth/login`,
    JSON.stringify({ email: __ENV.LOGIN_EMAIL || 'seed3rd@booster.test', password: __ENV.LOGIN_PASSWORD || 'seed1234' }),
    { headers: JSON_HEADERS });
  const token = res.json('accessToken');
  if (!token) throw new Error(`스트레스 로그인 실패 — seed3rd 시드 확인. status=${res.status} body=${res.body}`);
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
  group('스트레스 읽기', () => {
    for (const ep of READ_ENDPOINTS) {
      const res = http.get(`${BASE}${ep}`, Object.assign({}, params, { tags: { kind: 'read', name: ep } }));
      check(res, { [`${ep} → 200`]: (r) => r.status === 200 });
    }
  });
  sleep(1);
}
