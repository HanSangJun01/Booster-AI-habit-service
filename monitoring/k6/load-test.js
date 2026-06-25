import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

const errorRate = new Rate('errors');
const challengeListDuration = new Trend('challenge_list_duration');
const challengeDetailDuration = new Trend('challenge_detail_duration');
const checkInListDuration = new Trend('checkin_list_duration');

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

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
  // 1. 챌린지 목록 조회
  const listRes = http.get(`${BASE_URL}/api/challenges`);
  challengeListDuration.add(listRes.timings.duration);
  check(listRes, { 'list status 200': (r) => r.status === 200 });
  errorRate.add(listRes.status >= 500);

  sleep(0.5);

  // 2. 챌린지 상세 조회 (id=1 고정 — 사전에 데이터 필요)
  const detailRes = http.get(`${BASE_URL}/api/challenges/1`);
  challengeDetailDuration.add(detailRes.timings.duration);
  check(detailRes, { 'detail status 200 or 404': (r) => r.status === 200 || r.status === 404 });
  errorRate.add(detailRes.status >= 500);

  sleep(0.5);

  // 3. 체크인 목록 조회
  const today = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const checkInRes = http.get(`${BASE_URL}/api/challenges/1/check-ins?date=${today}`);
  checkInListDuration.add(checkInRes.timings.duration);
  check(checkInRes, { 'checkin status 200 or 404': (r) => r.status === 200 || r.status === 404 });
  errorRate.add(checkInRes.status >= 500);

  sleep(1);
}
