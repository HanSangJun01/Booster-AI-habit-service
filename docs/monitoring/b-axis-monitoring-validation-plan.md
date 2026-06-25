# B-axis 백엔드 모니터링 및 검증 계획서

> 상태: pending approval
> 작성: 2026-06-25
> 기반 환경: Spring Boot 3.x + Actuator + Micrometer + Prometheus + Grafana (Docker Compose)
> 브랜치: test/BS-30-backend-validation

---

## 0. 현황 요약

| 구성 요소 | 상태 | 설정 위치 |
|----------|------|----------|
| Spring Actuator | ✅ 활성 (health, prometheus, info, metrics) | `application.yml:management` |
| Prometheus scrape | ✅ 15s 간격, `host.docker.internal:8080` | `prometheus.yml` |
| Grafana datasource | ✅ Prometheus 연결 완료 | `docker-compose.monitoring.yml` |
| Grafana 대시보드 | ✅ 16개 패널 (핵심지표·HTTP·DB·JVM·응답시간심층) | `monitoring/grafana/booster-baxis-dashboard-import.json` |
| SQL 가시성 | ✅ dev 프로파일 활성 시 SQL 전체 출력·100ms 슬로우 쿼리 경고 | `application-dev.yml` |
| k6 부하 테스트 | ✅ 4단계 VU 시나리오, p99/에러율 기준 내장 | `monitoring/k6/load-test.js` |
| HikariCP 풀 | ✅ 기본값 (max 10) | Spring Boot 자동 구성 |
| 아키텍처 테스트 | ✅ `BAxisIsolationTest` (흐름 분리 불변식) | `src/test/java/com/booster/arch/` |
| DB 마이그레이션 | ✅ V1~V7 적용 완료 | `src/main/resources/db/migration/` |

---

## 1. 목표 및 범위

### 목표
1. **기능 정합성 검증**: B-axis 핵심 흐름(참여 신청 → 체크인 → 정산)이 ERD/API Spec대로 동작함을 확인한다.
2. **성능 기준선 수립**: 1주차 기준선(baseline) 지표를 측정해 향후 회귀 탐지의 기준으로 삼는다.
3. **이상 징후 감지 체계 구축**: Grafana 패널과 Prometheus 쿼리로 병목·에러를 조기에 포착하는 관찰 기준을 정의한다.

### 범위 (B-axis MVP)
- Phase 1: Challenge 생성·탐색·참여 신청·취소
- Phase 3: ChallengeCheckIn (GPS 인증 체인)
- Phase 4a: Settlement (정산 스케줄러)
- 제외: A-axis(PersonalCheckIn, Streak, RecoveryMission), Phase 4b(소셜)

---

## 2. 모니터링 지표 정의

### 2-1. HTTP 레이어

| 지표 | Prometheus 표현식 | 기준선 목표 | 이상 징후 임계값 |
|-----|-----------------|-----------|--------------|
| 평균 응답시간 (조회) | `rate(http_server_requests_seconds_sum{uri=~".*/challenges.*",method="GET"}[1m]) / rate(http_server_requests_seconds_count{...}[1m])` | < 80ms | ≥ 300ms |
| 평균 응답시간 (쓰기) | 위와 동일, `method="POST"` | < 250ms | ≥ 800ms |
| p99 응답시간 | `histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m]))` | < 500ms | ≥ 1500ms |
| 5xx 에러율 | `rate(http_server_requests_seconds_count{status=~"5.."}[1m])` | 0 | > 0 건/분 |
| 4xx 에러율 | `rate(http_server_requests_seconds_count{status=~"4.."}[1m])` | < 5% | > 20% |
| 초당 요청 수 (RPS) | `rate(http_server_requests_seconds_count[1m])` | 기준선 측정 후 결정 | 기준선 × 3배 초과 |

### 2-2. JVM 레이어

| 지표 | Prometheus 표현식 | 기준선 목표 | 이상 징후 임계값 |
|-----|-----------------|-----------|--------------|
| Heap 사용률 | `jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}` | < 60% | ≥ 85% |
| GC 일시정지 횟수 | `rate(jvm_gc_pause_seconds_count[1m])` | < 2회/분 | ≥ 10회/분 |
| GC 일시정지 시간 | `rate(jvm_gc_pause_seconds_sum[1m])` | < 20ms/분 | ≥ 200ms/분 |
| 활성 스레드 수 | `jvm_threads_live_threads` | < 30 | ≥ 60 |

### 2-3. DB 커넥션 레이어 (HikariCP)

| 지표 | Prometheus 표현식 | 기준선 목표 | 이상 징후 임계값 |
|-----|-----------------|-----------|--------------|
| 활성 커넥션 | `hikaricp_connections_active` | < 5 (평시) | ≥ 9 (풀 포화 임박) |
| 대기 중 요청 | `hikaricp_connections_pending` | 0 | ≥ 1 지속 |
| 커넥션 획득 시간 | `hikaricp_connections_acquire_seconds{quantile="0.99"}` | < 5ms | ≥ 50ms |
| 커넥션 타임아웃 | `hikaricp_connections_timeout_total` | 0 | ≥ 1 |
| 유휴 커넥션 | `hikaricp_connections_idle` | > 2 | 0 지속 (모두 소진) |

---

## 3. B-axis 흐름별 실험 시나리오

### 시나리오 A — Challenge 생성·탐색 (Phase 1 기준선)

**목적**: 단순 조회/생성 API의 응답시간·DB 부하 기준선 확보

**실행 절차**:
```bash
# 1. 챌린지 생성 (10회)
for i in $(seq 1 10); do
  curl -s -X POST http://localhost:8080/api/challenges \
    -H "Content-Type: application/json" \
    -d '{"title":"테스트챌린지'$i'","category":"HEALTH","verificationType":"GPS",
         "durationDays":14,"depositCoins":100,"visibility":"PUBLIC",
         "approvalType":"AUTO","createdBy":1}' > /dev/null
done

# 2. 목록 조회 부하 — k6로 실행
k6 run monitoring/k6/load-test.js
```

**확인 지표**:
- `http_server_requests_seconds` (POST /api/challenges, GET /api/challenges)
- `hikaricp_connections_active` 피크값
- 5xx 응답 없음 확인

---

### 시나리오 B — 참여 신청 (Phase 1 쓰기 부하)

**목적**: 코인 차감 + GPS 등록 포함 쓰기 트랜잭션 레이턴시 측정

**전제조건**: challengeId=1 존재, userId 1~5 사용 가능

**실행 절차**:
```bash
for userId in 1 2 3 4 5; do
  curl -s -X POST http://localhost:8080/api/challenges/1/participants \
    -H "Content-Type: application/json" \
    -H "X-User-Id: $userId" \
    -d '{"personalStatement":"참여합니다",
         "gpsLat":37.5665,"gpsLng":126.9780,"gpsRadiusMeters":100,
         "gpsPlaceName":"서울시청"}' > /dev/null
done
```

**확인 지표**:
- POST `/api/challenges/{id}/participants` 응답시간
- `hikaricp_connections_active` (트랜잭션 중 최대)
- 정원 초과(10명+) 시 409 응답 확인
- 로그: `INFO ParticipationService` 패턴

---

### 시나리오 C — 체크인 GPS 인증 체인 (Phase 3 핵심)

**목적**: verification_submissions → gps_verification_results → verification_decisions 3단계 INSERT 레이턴시 측정

**전제조건**: ACTIVE 상태 챌린지, CONFIRMED 참여자 존재

**실행 절차**:
```bash
# 20회 반복 (멱등성 포함: 같은 날 중복 체크인은 1건 처리 확인)
for i in $(seq 1 20); do
  curl -s -X POST http://localhost:8080/api/challenges/1/check-ins \
    -H "Content-Type: application/json" \
    -H "X-User-Id: 1" \
    -d '{"currentLat":37.5665,"currentLng":126.9780}' \
    | jq -r '.data.status'
done
```

**확인 지표**:
- POST `/api/challenges/{id}/check-ins` 응답시간 분포
- 첫 번째 호출(3 INSERT) vs 이후 호출(멱등 조기 반환) 응답시간 차이
- `hikaricp_connections_active` — 3단계 INSERT 구간
- 로그: `INFO CheckIn SUCCESS` / `INFO CheckIn FAILED (GPS)` 패턴

**기대 결과**:
- 첫 번째 호출: < 300ms
- 중복 SUCCESS 호출: < 50ms (멱등 조기 반환)
- GPS 반경 외 호출: FAILED 응답, 5xx 없음

---

### 시나리오 D — 정산 스케줄러 (Phase 4a)

**목적**: SettlementService 멱등성 및 DB 부하 확인

**전제조건**: ENDED 상태 챌린지 (DB에서 직접 `UPDATE challenges SET ended_at = NOW() - INTERVAL '1 minute' WHERE id = 1` 로 강제 종료)

**실행 절차**:
```bash
# 1. DB에서 챌린지 강제 종료
docker exec booster-postgres psql -U booster -c \
  "UPDATE challenges SET status='ENDED', ended_at=NOW()-INTERVAL '1 minute' WHERE id=1;"

# 2. 스케줄러 주기 대기 또는 REST 엔드포인트로 수동 트리거
docker logs booster-backend -f | grep -E "Settlement|Scheduler|COMPLETED|FAILED"

# 3. 정산 결과 조회
curl -s http://localhost:8080/api/challenges/1/result | jq
```

**확인 지표**:
- `hikaricp_connections_active` 정산 실행 구간 피크
- 로그: `SettlementService` 멱등 게이트 통과 확인 (2회 실행 시 두 번째 no-op)
- `settlements` 테이블 `COMPLETED` 레코드 존재
- Challenge `status` = `ENDED` 유지 (SETTLED 상태 없음 확인)

---

### 시나리오 E — 동시성 부하 (DB 커넥션 풀 관찰)

**목적**: 동시 요청 시 HikariCP 커넥션 거동 측정 (k6 피크 단계: 50 VU)

**실행 절차**:
```bash
# k6 부하 테스트 실행 (워밍업 5VU → 기본부하 20VU → 피크 50VU → 쿨다운)
k6 run monitoring/k6/load-test.js

# 실시간 커넥션 관찰 (별도 터미널)
watch -n 1 'curl -s localhost:8080/actuator/prometheus | \
  grep -E "hikaricp_connections_(active|pending|idle|acquire)"'
```

**k6 내장 성공 기준**:
| 지표 | 기준 |
|------|------|
| 전체 p99 응답시간 | < 500ms |
| 챌린지 목록 조회 p95 | < 200ms |
| 챌린지 상세 조회 p95 | < 150ms |
| 체크인 쓰기 p95 | < 300ms |
| 에러율 | < 1% |

**확인 지표**:
- `hikaricp_connections_pending` > 0 지속 여부 (풀 포화 신호)
- `hikaricp_connections_acquire_seconds_max` 피크
- 응답 타임아웃(HikariCP 기본 30s) 발생 여부
- Grafana 대시보드 → 응답시간 심층 분석 섹션: URI별 p95/p99, HTTP 상태코드 분포

---

## 4. Docker 환경 관찰 명령어

```bash
# 컨테이너별 리소스 실시간 모니터링
docker stats booster-backend booster-postgres booster-prometheus booster-grafana --no-stream

# PostgreSQL 활성 쿼리 및 커넥션 상태
docker exec booster-postgres psql -U booster -c \
  "SELECT pid, state, wait_event_type, left(query,60) AS query
   FROM pg_stat_activity WHERE datname='booster' ORDER BY state;"

# Flyway 마이그레이션 이력 확인
docker exec booster-postgres psql -U booster -c \
  "SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank;"

# 슬로우 쿼리 (100ms 이상)
docker exec booster-postgres psql -U booster -c \
  "SELECT query, mean_exec_time, calls FROM pg_stat_statements
   WHERE mean_exec_time > 100 ORDER BY mean_exec_time DESC LIMIT 10;"
```

---

## 5. 수락 기준 (Acceptance Criteria)

### 기능 정합성

| # | 기준 | 검증 방법 |
|---|------|----------|
| AC-01 | `GET /actuator/health` → `{"status":"UP"}` | curl 직접 확인 |
| AC-02 | `GET /actuator/prometheus` → `http_server_requests_seconds_count` 포함 | grep 확인 |
| AC-03 | Prometheus target `booster-backend` → State: UP | http://localhost:9090/targets |
| AC-04 | Grafana 대시보드 16개 패널 모두 데이터 표시 | http://localhost:3000 시각 확인 |
| AC-05 | 체크인 동일 날짜 중복 호출 → 2번째부터 멱등 처리 (SUCCESS 유지) | 시나리오 C 실행 |
| AC-06 | 정산 2회 실행 → 두 번째는 no-op (settlements 레코드 1건 유지) | 시나리오 D 실행 |
| AC-07 | `BAxisIsolationTest` 통과 (PersonalCheckIn/Streak/RecoveryMission 참조 없음) | `./gradlew test` |
| AC-08 | V7까지 Flyway 마이그레이션 모두 `success=true` | pg_stat 쿼리 |

### 성능 기준선

| # | 기준 | 측정 방법 |
|---|------|----------|
| AC-09 | GET /api/challenges p95 응답시간 < 200ms (k6 기본부하 20VU) | k6 결과 |
| AC-10 | POST /api/challenges/{id}/check-ins p95 응답시간 < 300ms | k6 결과 (시나리오 E) |
| AC-11 | 5xx 응답 0건 (모든 시나리오 통틀어) | Prometheus 쿼리 |
| AC-12 | `hikaricp_connections_pending` = 0 (20VU 이하 부하) | 시나리오 E |
| AC-13 | JVM Heap 사용률 < 70% (부하 후) | Grafana 패널 |

---

## 6. 1주차 기준선 문서화 템플릿

실험 완료 후 자동 생성: `docs/monitoring/baseline-YYYY-MM-DD-HH-MM.md` (스크립트 실행 시 자동 저장)

```markdown
## 1주차 성능 기준선

**측정일**: YYYY-MM-DD
**환경**: Docker Compose (PostgreSQL 15, Spring Boot 3.x)
**HikariCP pool-size**: 10 (default)
**부하 도구**: k6 (5VU → 20VU → 50VU → 0VU)

### HTTP 응답시간 (k6 결과)

| API | p50 | p95 | p99 | 에러율 |
|-----|-----|-----|-----|-------|
| GET /api/challenges | _ms | _ms | _ms | _% |
| GET /api/challenges/{id} | _ms | _ms | _ms | _% |
| POST /api/challenges/{id}/check-ins | _ms | _ms | _ms | _% |

### JVM (부하 후 최대)

| 지표 | 측정값 |
|-----|-------|
| Heap 사용률 | _%  |
| GC 횟수/분 | _ |
| 활성 스레드 | _ |

### DB 커넥션 (부하 중 최대)

| 지표 | 측정값 |
|-----|-------|
| active max | _ |
| pending max | _ |
| acquire p99 | _ms |

### 체크인 멱등성

| 케이스 | 응답시간 |
|-------|---------|
| 첫 번째 체크인 (3 INSERT) | _ms |
| 중복 체크인 (멱등 반환) | _ms |

### Grafana 스냅샷
<!-- 대시보드 스크린샷 첨부 -->

### 이상 없음 확인 체크리스트
- [ ] 5xx 에러 0건
- [ ] hikaricp_connections_pending = 0
- [ ] GC 일시정지 < 100ms
- [ ] Heap 사용률 < 70%
- [ ] BAxisIsolationTest PASS
- [ ] Flyway V1~V7 전체 success=true
```

---

## 7. 실험 실행 순서

```
1. 환경 기동 확인          → bootRun + docker-compose.monitoring.yml up
2. 시나리오 A (기준선)     → 조회/생성 응답시간 측정
3. 시나리오 B (참여 신청)  → 쓰기 트랜잭션 레이턴시
4. 시나리오 C (체크인)     → verification chain + 멱등성
5. 시나리오 D (정산)       → 스케줄러 + 멱등 게이트
6. 시나리오 E (동시성)     → k6 부하 + DB 커넥션 풀 거동
7. 기준선 문서화           → docs/monitoring/week1-baseline.md 작성
8. ./gradlew clean test    → AC-07 확인
```

예상 소요 시간: **2~3시간**

---

## 8. 리스크 및 완화 방안

| 리스크 | 발생 가능성 | 완화 방안 |
|-------|-----------|----------|
| stub 프로파일 미활성 → CoinService 빈 없음 | 낮음 (application.yml 설정됨) | bootRun 직후 `/actuator/health` UP 확인 |
| PostgreSQL 컨테이너 미기동 → JPA 연결 실패 | 보통 | `docker ps` 확인 후 실험 시작 |
| HikariCP 풀 포화 (k6 피크 50VU) | 보통 | 시나리오 E에서 의도적으로 관찰, pool-size 조정 필요 시 `application.yml` 수정 |
| 정산 스케줄러 주기 불일치 | 낮음 | `ended_at` 강제 설정 후 로그 대기 or Actuator `/actuator/scheduledtasks` 확인 |
| Grafana 패널 No Data | 낮음 (datasource 연결 완료) | Prometheus target UP 재확인 후 패널 time range 조정 |

---

## 9. 참고 파일

| 파일 | 설명 |
|-----|------|
| `prometheus.yml` | scrape 설정 (15s, host.docker.internal:8080) |
| `docker-compose.monitoring.yml` | Prometheus:9090, Grafana:3000 |
| `monitoring/grafana/booster-baxis-dashboard-import.json` | Grafana Import용 대시보드 (16개 패널) |
| `monitoring/k6/load-test.js` | k6 부하 테스트 (5→20→50VU, p99/에러율 기준 내장) |
| `backend/src/main/resources/application.yml` | Actuator 노출 설정 |
| `backend/src/main/resources/application-dev.yml` | SQL 가시성 (dev 프로파일, SQL DEBUG·슬로우쿼리 WARN) |
| `docs/monitoring/BS-30-monitoring-observability-guide.md` | 관찰성 가이드 (dev 프로파일·Grafana Import·k6 실행법) |
| `backend/src/test/java/com/booster/arch/BAxisIsolationTest.java` | 흐름 분리 불변식 테스트 |
| `backend/src/main/resources/db/migration/V6__align_with_spec.sql` | BS-30 스키마 정합성 |
