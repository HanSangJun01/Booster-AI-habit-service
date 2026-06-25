import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

const errorRate = new Rate('errors');
const challengeListDuration = new Trend('challenge_list_duration');
const challengeDetailDuration = new Trend('challenge_detail_duration');
const checkInWriteDuration = new Trend('checkin_write_duration');
const checkInReadDuration = new Trend('checkin_read_duration');

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const CHALLENGE_ID = __ENV.CHALLENGE_ID || '1';

export const options = {
  stages: [
    { duration: '30s', target: 5  },  // 워밍업
    { duration: '1m',  target: 20 },  // 기본 부하
    { duration: '30s', target: 50 },  // 피크
    { duration: '20s', target: 0  },  // 쿨다운
  ],
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(50)', 'p(90)', 'p(95)', 'p(99)'],
  thresholds: {
    http_req_duration:        ['p(99)<500'],   // 전체 p99 < 500ms
    challenge_list_duration:  ['p(95)<200'],   // 목록 조회 p95 < 200ms
    challenge_detail_duration:['p(95)<150'],   // 상세 조회 p95 < 150ms
    checkin_write_duration:   ['p(95)<300'],   // 체크인 쓰기 p95 < 300ms
    errors:                   ['rate<0.01'],   // 에러율 1% 미만
  },
};

export function handleSummary(data) {
  return {
    '/tmp/k6-summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}

export default function () {
  // VU 번호 기반으로 userId 1~5 순환 (시나리오 B에서 참여 신청한 사용자)
  const userId = (__VU % 5) + 1;
  const authHeaders = {
    'Content-Type': 'application/json',
    'X-User-Id': String(userId),
  };
  const today = new Date().toISOString().slice(0, 10).replace(/-/g, '');

  // 1. 챌린지 목록 조회 (읽기)
  const listRes = http.get(`${BASE_URL}/api/challenges`);
  challengeListDuration.add(listRes.timings.duration);
  check(listRes, { 'list 200': (r) => r.status === 200 });
  errorRate.add(listRes.status >= 400);

  sleep(0.3);

  // 2. 챌린지 상세 조회 (읽기)
  const detailRes = http.get(`${BASE_URL}/api/challenges/${CHALLENGE_ID}`, { headers: authHeaders });
  challengeDetailDuration.add(detailRes.timings.duration);
  check(detailRes, { 'detail 200': (r) => r.status === 200 });
  errorRate.add(detailRes.status >= 400);

  sleep(0.3);

  // 3. 체크인 POST (쓰기) — 같은 날 중복 체크인은 멱등성으로 처리됨
  const checkInWriteRes = http.post(
    `${BASE_URL}/api/challenges/${CHALLENGE_ID}/check-ins`,
    JSON.stringify({ currentLat: 37.5665, currentLng: 126.9780 }),
    { headers: authHeaders }
  );
  checkInWriteDuration.add(checkInWriteRes.timings.duration);
  check(checkInWriteRes, { 'checkin write 200': (r) => r.status === 200 });
  errorRate.add(checkInWriteRes.status >= 400);

  sleep(0.3);

  // 4. 체크인 목록 조회 (읽기)
  const checkInReadRes = http.get(
    `${BASE_URL}/api/challenges/${CHALLENGE_ID}/check-ins?date=${today}`,
    { headers: authHeaders }
  );
  checkInReadDuration.add(checkInReadRes.timings.duration);
  check(checkInReadRes, { 'checkin read 200': (r) => r.status === 200 });
  errorRate.add(checkInReadRes.status >= 400);

  sleep(0.5);
}
