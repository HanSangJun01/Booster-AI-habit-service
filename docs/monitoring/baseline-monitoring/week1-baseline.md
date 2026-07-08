# 1주차 성능 기준선

**측정일**: 2026-06-25
**환경**: Docker Compose (PostgreSQL 15, Spring Boot 3.x)
**HikariCP pool-size**: 10 (default)
**부하 도구**: k6 (5VU → 20VU → 50VU → 0VU), 총 2분 20초
**실행 스크립트**: `monitoring/scripts/run-all-scenarios.sh`

---

## HTTP 응답시간 (k6 시나리오 E 결과)

| API | avg | p50 | p90 | p95 | p99 | 에러율 |
|-----|-----|-----|-----|-----|-----|-------|
| GET /api/challenges | 9.7ms | 8.9ms | 16.3ms | 18.9ms | — | 0% |
| GET /api/challenges/{id} | 12.7ms | 12.7ms | 20.6ms | 22.7ms | — | 0% |
| GET /api/challenges/{id}/check-ins | 10.3ms | 9.1ms | 17.5ms | 19.6ms | — | 0% |
| **전체** | **10.9ms** | **9.8ms** | **18.5ms** | **21.0ms** | **27.1ms** | **0%** |

**총 요청**: 3,516건 / **RPS**: 24.9 req/s / **http_req_failed**: 0.00%

---

## k6 기준(threshold) 달성 여부

| 기준 | 목표 | 결과 | 판정 |
|------|------|------|------|
| 전체 p99 응답시간 | < 500ms | 27.1ms | ✅ |
| 챌린지 목록 p95 | < 200ms | 18.9ms | ✅ |
| 챌린지 상세 p95 | < 150ms | 22.7ms | ✅ |
| 에러율 | < 1% | 0.00% | ✅ |

---

## JVM (부하 직후 측정)

| 지표 | 측정값 |
|------|-------|
| Heap 사용량 | 68.5 MB |
| Heap 최대 | 4,096 MB |
| **Heap 사용률** | **1.7%** |
| 활성 스레드 수 | 24개 |

---

## DB 커넥션 (부하 직후 측정, HikariCP)

| 지표 | 측정값 |
|------|-------|
| active | 0 (부하 종료 후 정상 반환) |
| idle | 10 (풀 전체 유휴 상태) |
| pending | 0 |

---

## 시나리오별 실행 결과

| 시나리오 | 내용 | 결과 |
|---------|------|------|
| A — 챌린지 생성·탐색 | 챌린지 10개 생성 + 목록 조회 5회 | ✅ HTTP 201 |
| B — 참여 신청 | userId 1~5 참여 신청 | ✅ 전원 HTTP 201 |
| C — 체크인 GPS 인증 | 체크인 20회 (멱등성 포함) | ✅ 실행 완료 |
| D — 정산 스케줄러 | 챌린지 강제 종료 후 정산 대기 | ✅ UPDATE 1건 |
| E — 동시성 부하 | k6 50VU 피크, 3,516건 처리 | ✅ 전 기준 통과 |

---

## 이상 없음 확인 체크리스트

- [x] 5xx 에러 0건
- [x] hikaricp_connections_pending = 0
- [x] Heap 사용률 < 70% (실측 1.7%)
- [x] http_req_failed = 0.00%
- [ ] GC 일시정지 < 100ms (Grafana 시각 확인 필요)
- [ ] BAxisIsolationTest PASS (`./gradlew clean test` 실행 필요)
- [ ] Flyway V1~V7 전체 success=true (pg_stat 확인 필요)
- [ ] Grafana 스크린샷 첨부

---

## 비고

- 로컬 환경(MacOS, Docker Compose) 기준 수치이며 운영 환경과 차이 있을 수 있음
- HikariCP pending = 0 → 50VU 동시 부하에서도 커넥션 풀 포화 없음
- 응답시간 기준선: p99 **27ms** (목표 500ms 대비 충분한 여유)
