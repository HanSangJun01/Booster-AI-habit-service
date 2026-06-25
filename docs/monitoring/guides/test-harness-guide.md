# 테스트 하네스 사용 가이드

> B-axis 백엔드 모니터링 및 성능 검증을 위한 완전한 테스트 하네스 가이드
>
> **작성일**: 2026-06-25
> **대상**: B-axis MVP 백엔드 (Spring Boot 3.x + PostgreSQL 15)

---

## 목차

1. [테스트 하네스 전체 구조](#테스트-하네스-전체-구조)
2. [사전 조건](#사전-조건)
3. [실행 방법](#실행-방법)
4. [시나리오 상세 설명](#시나리오-상세-설명)
5. [k6 로드 테스트 구조](#k6-로드-테스트-구조)
6. [Grafana/Prometheus 지표 해석](#grafanaprometheus-지표-해석)
7. [테스트 실패 시 원인 확인 순서](#테스트-실패-시-원인-확인-순서)
8. [원인 분류 기준](#원인-분류-기준)
9. [Baseline 파일 해석](#baseline-파일-해석)

---

## 테스트 하네스 전체 구조

### 개요 (smoke → scenario → load test 흐름)

```
┌─────────────────────────────────────────────────────────────────┐
│                    B-axis 테스트 하네스                          │
└─────────────────────────────────────────────────────────────────┘

1. SMOKE 검증 (0~1분)
   ├─ 환경 사전 조건 확인
   │  ├─ 백엔드 /actuator/health UP?
   │  ├─ Grafana /api/health UP?
   │  └─ PostgreSQL 컨테이너 실행 중?
   ├─ k6 설치 확인
   └─ → 실패 시 즉시 종료 (이후 시나리오 건너뜀)

2. DB 초기화 (1~2분)
   ├─ 기존 테스트 데이터 DELETE
   │  ├─ verification_decisions
   │  ├─ gps_verification_results
   │  ├─ verification_submissions
   │  ├─ settlements
   │  ├─ challenge_check_ins
   │  ├─ challenge_participants
   │  └─ challenges (시나리오* 제목만)
   └─ → 멱등성 실패 방지 (이전 실행의 데이터 영향 제거)

3. 시나리오 A: Challenge 생성·탐색 (2~3분)
   ├─ 10개 챌린지 생성 (POST /api/challenges)
   ├─ 목록 조회 5회 반복
   └─ → 기준선: HTTP 평균 응답시간, DB SELECT 부하 측정

4. 시나리오 B: 참여 신청 (1~2분)
   ├─ 챌린지 ID 추출 (A에서 생성한 첫 챌린지)
   ├─ 사용자 1~5 참여 신청 (POST /api/challenges/{id}/participants)
   ├─ CONFIRMED 참여자 수 검증 (5명 기대)
   ├─ 챌린지 상태 ACTIVE로 전환 (체크인·k6 사전조건)
   └─ → 기준선: 쓰기 트랜잭션 응답시간, DB INSERT+UPDATE 부하

5. 시나리오 C: 체크인 GPS 인증 체인 (2~3분)
   ├─ 체크인 20회 반복 (POST /api/challenges/{id}/check-ins)
   ├─ 첫 번째 호출: verification_submissions → gps_verification_results → verification_decisions (3 INSERT)
   ├─ 2~20회: 멱등 처리 (이미 존재하면 조기 반환)
   └─ → 기준선: 3단계 verification chain 응답시간, 멱등성 동작 검증

6. 시나리오 E: 동시성 부하 테스트 (2분 20초)
   ├─ k6 부하 생성
   │  ├─ 0~30초: 5 VU (워밍업)
   │  ├─ 30~90초: 20 VU (기본 부하)
   │  ├─ 90~120초: 50 VU (피크)
   │  └─ 120~140초: 0 VU (쿨다운)
   ├─ k6 내장 검증 기준 (threshold)
   │  ├─ 전체 p99 < 500ms ✅
   │  ├─ 목록 조회 p95 < 200ms ✅
   │  ├─ 상세 조회 p95 < 150ms ✅
   │  ├─ 체크인 쓰기 p95 < 300ms ✅
   │  └─ 에러율 < 1% ❌ (현재 25%)
   └─ → 측정: HikariCP 커넥션 풀 동작, GC 일시정지, 응답시간 분포

7. 시나리오 D: 정산 스케줄러 (1~2분)
   ├─ 챌린지 강제 종료 (status=ENDED, ended_at=NOW-1min)
   ├─ 정산 스케줄러 대기 (30초)
   ├─ 정산 결과 조회 (/api/challenges/{id}/result)
   └─ → 검증: SettlementService 멱등성, 정산 프로세스 동작

8. 결과 자동 기록 (1~2분)
   ├─ k6 summary 파싱
   ├─ Prometheus 메트릭 수집
   └─ → 저장: docs/monitoring/baselines/baseline-YYYY-MM-DD-HH-MM.md

**전체 소요 시간**: 약 2~3시간 (모든 시나리오 포함)
```

---

## 사전 조건

### 1. 백엔드 실행

```bash
# 프로젝트 루트에서
./gradlew bootRun
# 또는 IDE의 Run 버튼

# 확인:
curl http://localhost:8080/actuator/health
# → {"status":"UP"} 응답 확인
```

**필요한 설정**:
- `application.yml`: Spring Actuator 활성 (`management.endpoints.web.exposure.include=*`)
- `application-dev.yml`: SQL 로깅 활성 (optional, 디버깅용)

### 2. Docker Compose 환경 실행

```bash
# 프로젝트 루트에서
docker-compose -f docker-compose.monitoring.yml up -d

# 확인:
docker ps | grep -E "booster-(postgres|prometheus|grafana)"
```

**포트 확인**:
- PostgreSQL: 5432
- Prometheus: 9090
- Grafana: 3000 (admin:admin)

### 3. k6 설치

```bash
# macOS
brew install k6

# Linux (apt)
sudo apt-get install k6

# 확인:
k6 --version
```

### 4. 필요한 도구

```bash
# curl, jq, docker, python3 (스크립트 내부 사용)
which curl jq docker python3

# 모두 설치 확인되어야 함
```

---

## 실행 방법

### 전체 자동 실행 (권장)

```bash
bash monitoring/scripts/run-all-scenarios.sh
```

**동작**:
1. 환경 사전 조건 확인 (smoke)
2. DB 초기화
3. 시나리오 A~E 순차 실행
4. 결과 파일 자동 생성

**출력 예시**:
```
[12:00:00] 환경 확인 중...
[OK] 백엔드 UP
[OK] Grafana UP
[OK] PostgreSQL UP
[OK] k6 설치 확인

[12:00:05] Grafana 대시보드 Import 중...
[OK] 대시보드 Import 완료
  → http://localhost:3000/d/booster-baxis-v1

[12:00:10] 시나리오 준비: DB 테스트 데이터 초기화...
[OK] DB 초기화 완료

══ 시나리오 A: Challenge 생성·탐색 ══
[12:00:15] 챌린지 10개 생성 중...
[OK] 챌린지 생성 완료 (기준 ID: 123)
...

[12:05:30] 결과 파일 자동 생성 중...
[OK] 결과 파일 생성 완료: docs/monitoring/baselines/baseline-2026-06-25-12-05.md

════════════════════════════════════════
 모든 시나리오 완료
════════════════════════════════════════
```

### 개별 시나리오 실행

```bash
# 1. DB 초기화만
docker exec booster-postgres psql -U booster -d booster -c "
DELETE FROM challenge_check_ins WHERE id > 0;
DELETE FROM challenge_participants WHERE id > 0;
DELETE FROM challenges WHERE title LIKE '시나리오%';
"

# 2. 시나리오 A (challenged 생성)
for i in $(seq 1 10); do
  curl -X POST http://localhost:8080/api/challenges \
    -H "Content-Type: application/json" \
    -H "X-User-Id: 1" \
    -d '{
      "title":"테스트챌린지'$i'",
      "category":"HEALTH",
      "verificationType":"GPS",
      "durationDays":14,
      "depositCoins":100,
      "maxParticipants":10,
      "visibility":"PUBLIC",
      "approvalType":"AUTO"
    }'
done

# 3. k6 로드 테스트만
k6 run -e BASE_URL="http://localhost:8080" -e CHALLENGE_ID="1" monitoring/k6/load-test.js
```

---

## 시나리오 상세 설명

### 시나리오 A: Challenge 생성·탐색 (Phase 1 기준선)

**목적**: 단순 조회/생성 API의 응답시간·DB 부하 기준선 확보

**테스트 흐름**:
1. `POST /api/challenges` 10회 (챌린지 생성)
2. `GET /api/challenges` 5회 (목록 조회)

**기대 결과**:
- 평균 응답시간 < 80ms (조회)
- 총 요청 10 + 5 = 15건
- 5xx 에러 0건
- Grafana: HTTP RPS, 응답시간 분포 시각화

**확인 지표** (Grafana):
```
HTTP Requests/sec → 5~10 RPS 정도 (시간당 18,000~36,000 req)
Response Time (p95) → 18~25ms 기대
DB Connections (active) → 1~2개 정도
```

**실패 시 점검**:
- [ ] 백엔드 로그에서 `NotFoundException` 또는 `DataAccessException` 확인
- [ ] PostgreSQL 연결 상태: `docker logs booster-postgres | tail -20`
- [ ] Challenge 테이블 스키마: `docker exec booster-postgres psql -U booster -d booster -c "\d challenges"`

---

### 시나리오 B: 참여 신청 (Phase 1 쓰기 부하)

**목적**: 코인 차감 + GPS 등록 포함 쓰기 트랜잭션 레이턴시 측정

**테스트 흐름**:
1. 시나리오 A에서 생성한 챌린지 ID 추출
2. 사용자 1~5 각각 참여 신청
   - `POST /api/challenges/{id}/participants`
   - 각 요청마다 트랜잭션 시작 → 코인 차감 → GPS 저장 → COMMIT
3. CONFIRMED 상태로 전환 (AUTO approval)
4. 챌린지 상태를 ACTIVE로 변경

**기대 결과**:
- 참여 신청 응답시간 < 250ms
- 5명 모두 CONFIRMED 상태 (스크립트에서 검증)
- 5xx 에러 0건
- HikariCP active 커넥션: 1~2개 (트랜잭션 중)

**확인 지표** (Grafana):
```
POST Request Latency → 150~250ms 정도
DB Connection Peak → 2~3개 (트랜잭션 중)
```

**실패 시 점검**:
- [ ] 에러 메시지 확인: `curl http://localhost:8080/api/challenges/1/participants -X POST ...`
- [ ] 참여자 상태 확인: 
  ```bash
  docker exec booster-postgres psql -U booster -d booster -c \
    "SELECT id, user_id, status FROM challenge_participants WHERE challenge_id=1;"
  ```
- [ ] 코인 차감 로그 확인: `docker logs booster-backend | grep -i "coin\|withdrawal"`

---

### 시나리오 C: 체크인 GPS 인증 체인 + 멱등성 (Phase 3 핵심)

**목적**: verification_submissions → gps_verification_results → verification_decisions 3단계 INSERT 레이턴시 측정 및 멱등성 검증

**테스트 흐름**:
1. 체크인 요청 20회 반복
2. 첫 번째: verification chain 3 INSERT 실행 (높은 레이턴시)
3. 2~20회: 같은 날이므로 멱등 처리 (캐시 또는 조기 반환)
4. 응답 상태 로깅 (SUCCESS / FAILED)

**기대 결과**:
- 첫 번째 체크인: < 300ms
- 중복 체크인: < 50ms (멱등 처리)
- 모든 요청: SUCCESS 상태
- 5xx 에러 0건

**확인 지표** (Grafana):
```
POST /check-ins Latency (첫번째) → 200~300ms
POST /check-ins Latency (중복) → 10~50ms (급격히 단축)
```

**실패 시 점검**:
- [ ] 체크인 응답 상태: `curl http://localhost:8080/api/challenges/1/check-ins -X POST ... | jq .data.status`
- [ ] 백엔드 로그에서 GPS 인증 결과: `docker logs booster-backend | grep -i "gps\|verification"`
- [ ] DB 데이터:
  ```bash
  docker exec booster-postgres psql -U booster -d booster -c \
    "SELECT COUNT(*) FROM challenge_check_ins WHERE challenge_id=1;"
  ```

---

### 시나리오 E: 동시성 부하 테스트 (k6)

**목적**: HikariCP 커넥션 풀 동작 및 시스템 부하 최대 지점 관찰

**테스트 흐름**:
```
k6 stages (VU = Virtual User):
├─ 0~30초: 5 VU  (5명의 동시 사용자)
├─ 30~90초: 20 VU (20명)
├─ 90~120초: 50 VU (50명 - 피크)
└─ 120~140초: 0 VU (쿨다운)
```

**각 VU의 동작** (매 사이클마다 반복):
1. `GET /api/challenges` (목록 조회)
2. `GET /api/challenges/{id}` (상세 조회)
3. `POST /api/challenges/{id}/check-ins` (체크인 쓰기)
4. `GET /api/challenges/{id}/check-ins?date=...` (체크인 목록)

**기대 결과**:
| 지표 | 기준 | 현황 |
|-----|------|------|
| 전체 p99 응답시간 | < 500ms | ✅ ~33~37ms |
| 목록 조회 p95 | < 200ms | ✅ ~18ms |
| 상세 조회 p95 | < 150ms | ✅ ~22ms |
| 체크인 쓰기 p95 | < 300ms | ✅ ~31ms |
| 에러율 | < 1% | ❌ 25% |
| HikariCP active max | < 9 | ✅ 0~2 |
| HikariCP pending | 0 | ✅ 0 |

**실시간 모니터링** (다른 터미널에서 실행):
```bash
# Grafana 대시보드 열기
open http://localhost:3000/d/booster-baxis-v1

# 또는 실시간 메트릭 조회
watch -n 1 'curl -s localhost:8080/actuator/prometheus | \
  grep -E "hikaricp_connections_(active|pending|idle|acquire)" | \
  grep -v "^#"'
```

**실패 시 점검**:
- [ ] 에러율이 높은 경우 (> 5%):
  - 백엔드 로그: `docker logs booster-backend | tail -50`
  - 에러 타입: APP_ERROR (500), TEST_SCRIPT_ERROR (check fail), DB_ERROR (timeout)
- [ ] HikariCP 커넥션 부족 (pending > 0):
  - `application.yml`에서 `hikaricp.maximum-pool-size` 증가
  - 또는 DB 쿼리 최적화 필요

---

## k6 로드 테스트 구조

### 파일 위치
`monitoring/k6/load-test.js`

### 주요 구성 요소

#### 1. 메트릭 정의
```javascript
const errorRate = new Rate('errors');  // 에러율 추적
const challengeListDuration = new Trend('challenge_list_duration');  // 목록 조회 응답시간
const challengeDetailDuration = new Trend('challenge_detail_duration');  // 상세 조회
const checkInWriteDuration = new Trend('checkin_write_duration');  // 체크인 쓰기
const checkInReadDuration = new Trend('checkin_read_duration');  // 체크인 읽기
```

#### 2. 부하 단계 설정 (stages)
```javascript
export const options = {
  stages: [
    { duration: '30s', target: 5  },   // 워밍업: 5명 동시 요청
    { duration: '1m',  target: 20 },   // 기본: 20명
    { duration: '30s', target: 50 },   // 피크: 50명
    { duration: '20s', target: 0  },   // 쿨다운
  ],
  thresholds: {
    http_req_duration:        ['p(99)<500'],   // 전체 p99 < 500ms
    challenge_list_duration:  ['p(95)<200'],   // 목록 p95 < 200ms
    challenge_detail_duration:['p(95)<150'],   // 상세 p95 < 150ms
    checkin_write_duration:   ['p(95)<300'],   // 체크인 p95 < 300ms
    errors:                   ['rate<0.01'],   // 에러율 < 1%
  },
};
```

#### 3. 메인 테스트 함수 (default)
```javascript
export default function () {
  const userId = (__VU % 5) + 1;  // VU 번호 기반 userId 순환 (1~5)
  
  // 1. 목록 조회 (GET)
  // 2. 상세 조회 (GET)
  // 3. 체크인 쓰기 (POST)
  // 4. 체크인 읽기 (GET)
  
  // 각 요청마다 check() 함수로 상태 코드 검증
  // 실패 시 errorRate.add(true) 호출
}
```

#### 4. 환경 변수
```bash
# 실행 시 전달
k6 run -e BASE_URL="http://localhost:8080" \
       -e CHALLENGE_ID="1" \
       monitoring/k6/load-test.js
```

### k6 결과 해석

k6 실행 후 콘솔 출력:
```
     GET /api/challenges: 평균=13.04ms, 최소=5.2ms, 최대=45.1ms
       p(50)=11.26ms, p(95)=29.02ms, p(99)=37.21ms

     POST /api/challenges/.../check-ins: 평균=87.3ms
       p(95)=212ms, p(99)=441ms

     ✓ list 200
     ✓ detail 200
     ✗ checkin write 2xx  ← 일부 요청이 check 실패
     ✓ checkin read 200

     errors......: 25.0% (에러율이 높음)
```

**해석 기준**:
- `p(99) < 500ms`: 99%의 요청이 500ms 이내 → ✅ 양호
- `errors < 0.01` (1%): 에러율 < 1% → ❌ 현재 25%로 높음
- `check` 실패: k6 내부 검증 실패 (상태 코드 검증 등)

---

## Grafana/Prometheus 지표 해석

### 주요 대시보드 패널

#### 1. HTTP RPS (Requests Per Second)
**Prometheus 쿼리**: `rate(http_server_requests_seconds_count[1m])`

**기준**:
- 평시: 10~50 RPS
- 시나리오 E (50 VU): 100~200 RPS
- 기준치 초과 시: 성능 저하 또는 메모리 누수 신호

**해석**:
```
RPS가 증가하다가 감소 → 정상 (부하 단계 진행)
RPS가 급격히 떨어짐 → ⚠️ 병목 발생 (DB, GC, 메모리)
RPS가 0으로 유지 → ❌ 서비스 다운
```

#### 2. 응답시간 분포 (p50, p95, p99)
**Prometheus 쿼리**: `histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m]))`

**기준**:
| 지표 | 양호 | 주의 | 위험 |
|-----|------|------|------|
| p50 | < 20ms | 20~50ms | > 50ms |
| p95 | < 100ms | 100~300ms | > 300ms |
| p99 | < 500ms | 500~1000ms | > 1000ms |

**해석**:
```
p95 = 100ms, p99 = 500ms → 정상 분포 (95%는 빠르고 일부 느림)
p50 = p95 = p99 → ⚠️ 응답이 일정함 (동시성 이슈)
p99 >> p95 → 일부 극단적 지연 (GC, 쿼리 timeout)
```

#### 3. 에러율 (5xx / 4xx)
**Prometheus 쿼리**: `rate(http_server_requests_seconds_count{status=~"5.."}[1m])`

**기준**:
- 5xx (Server Error): 0건 기대
- 4xx (Client Error): < 5% 기대

**해석**:
```
5xx = 0 → ✅ 정상
5xx > 0 → ❌ 응용 버그
4xx 증가 → ⚠️ 데이터 검증 실패 (입력 오류)
```

#### 4. HikariCP 커넥션 풀
**지표**:
- `hikaricp_connections_active`: 현재 사용 중인 커넥션
- `hikaricp_connections_idle`: 대기 중인 커넥션
- `hikaricp_connections_pending`: 대기 중인 요청 (풀에서 커넥션 가져올 때까지)

**기준** (pool-size=10 기본값):
| 지표 | 양호 | 주의 | 위험 |
|-----|------|------|------|
| active | 0~3 | 4~7 | 8~10 |
| idle | 3~10 | 2~3 | 0~1 |
| pending | 0 | 0~1 (간헐) | > 1 (지속) |

**해석**:
```
active=2, idle=8 → ✅ 풀 여유 충분
active=8, idle=2 → ⚠️ 풀 압박 시작
active=10, pending>0 → ❌ 풀 포화, 요청 대기 발생
```

#### 5. JVM Heap 사용률
**Prometheus 쿼리**: `jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}`

**기준**:
- < 60%: 여유 충분
- 60~70%: 정상 범위
- 70~85%: GC 압박 시작
- > 85%: ⚠️ Full GC 위험

**해석**:
```
Heap 30% 유지 → ✅ 정상 (메모리 누수 없음)
Heap이 점진적 증가 → ⚠️ 메모리 누수 의심
Heap 급격히 상승 후 감소 → ✅ GC 동작 (정상)
```

#### 6. GC 일시정지 (Garbage Collection Pause)
**Prometheus 쿼리**: `rate(jvm_gc_pause_seconds_sum[1m])`

**기준**:
- < 20ms/분: 양호 (일반적인 부하)
- 20~100ms/분: 주의 (GC 활동 증가)
- > 100ms/분: ⚠️ Full GC 또는 메모리 압박

**해석**:
```
GC 0~10ms/분 → ✅ 정상
GC 50ms/분 이상 → ⚠️ Heap 메모리 부족 신호
응답 지연 시점 = GC 피크 시점 → GC pause가 병목
```

---

## 테스트 실패 시 원인 확인 순서

### 1단계: 사전 조건 재확인 (smoke)

```bash
# 백엔드 헬스 체크
curl -s http://localhost:8080/actuator/health | jq .status
# → "UP" 확인

# Grafana 체크
curl -s http://localhost:3000/api/health | jq '.database'
# → "ok" 확인

# PostgreSQL 체크
docker exec booster-postgres pg_isready -U booster
# → "accepting connections" 확인

# k6 체크
k6 --version
# → 버전 출력 확인
```

**실패 시**:
- [ ] 백엔드: `./gradlew bootRun` 재시작
- [ ] Grafana: `docker-compose -f docker-compose.monitoring.yml up -d booster-grafana`
- [ ] PostgreSQL: `docker-compose -f docker-compose.monitoring.yml up -d booster-postgres`
- [ ] k6: `brew install k6` (또는 재설치)

### 2단계: 에러 로그 확인

```bash
# 백엔드 에러 로그
docker logs booster-backend | grep -E "ERROR|Exception|WARN" | tail -50

# PostgreSQL 에러 로그
docker logs booster-postgres | grep -E "ERROR|FATAL" | tail -20

# k6 실행 중 콘솔 에러
# k6 run 출력에서 "✗ check fail" 또는 "error" 메시지 확인
```

### 3단계: DB 상태 확인

```bash
# 데이터 정상 여부
docker exec booster-postgres psql -U booster -d booster -c \
  "SELECT COUNT(*) FROM challenges; \
   SELECT COUNT(*) FROM challenge_participants; \
   SELECT COUNT(*) FROM challenge_check_ins;"

# DB 연결 상태
docker exec booster-postgres psql -U booster -d booster -c \
  "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"

# 느린 쿼리 (100ms 이상)
docker exec booster-postgres psql -U booster -d booster -c \
  "SELECT query, mean_exec_time, calls FROM pg_stat_statements \
   WHERE mean_exec_time > 100 ORDER BY mean_exec_time DESC LIMIT 10;"
```

### 4단계: Grafana 패널별 분석

```
1. HTTP RPS 패널
   → RPS가 0이거나 급락? → 백엔드 다운 또는 DB 타임아웃
   
2. 응답시간 분포 (p95, p99)
   → p99 > 1000ms? → 느린 쿼리 또는 GC
   
3. 에러율 (5xx 비율)
   → 5xx 에러 있음? → 응용 버그
   
4. HikariCP 커넥션
   → pending > 0? → 풀 포화, 커넥션 리크 의심
   → active=0 지속? → 요청 없음 또는 연결 끊김
   
5. JVM Heap
   → 점진적 증가? → 메모리 누수
   → 급격히 상승? → 대용량 쿼리 결과 로드
   
6. GC 일시정지
   → 응답 지연 시점 = GC 피크? → GC pause가 병목
```

### 5단계: 원인별 상세 디버깅

#### APP_ERROR (응용 버그)
```bash
# 백엔드 로그에서 Exception 스택 추적
docker logs booster-backend 2>&1 | grep -A 20 "Exception"

# 특정 API 엔드포인트 수동 테스트
curl -X POST http://localhost:8080/api/challenges/1/check-ins \
  -H "Content-Type: application/json" \
  -H "X-User-Id: 1" \
  -d '{"currentLat":37.5665,"currentLng":126.9780}' | jq .

# 응답이 에러라면 .error 필드 확인
```

#### DB_ERROR (데이터베이스 문제)
```bash
# 커넥션 풀 상태
docker exec booster-postgres psql -U booster -d booster -c \
  "SELECT pid, state, wait_event_type, query FROM pg_stat_activity LIMIT 10;"

# 느린 쿼리 실행 계획
docker exec booster-postgres psql -U booster -d booster -c \
  "EXPLAIN ANALYZE SELECT * FROM challenges WHERE id=1;"

# 인덱스 확인
docker exec booster-postgres psql -U booster -d booster -c "\d challenges"
```

#### GC_ERROR (메모리 부족)
```bash
# JVM 설정 확인 (application.yml)
grep -E "Xmx|Xms|XX" application.yml

# 현재 힙 사용량 (런타임)
curl -s http://localhost:8080/actuator/prometheus | grep "jvm_memory"

# 메모리 누수 확인 (힙이 계속 증가)
# → 서비스 재시작 필요
```

---

## 원인 분류 기준

### 분류 체계

```
테스트 실패 원인
├─ APP_ERROR (응용 버그)
│  ├─ NullPointerException (null 값 처리 미흡)
│  ├─ ValidationException (데이터 검증 실패)
│  ├─ BusinessLogicException (비즈니스 규칙 위반)
│  └─ SQLException (DB 제약 조건 위반 - NOT NULL, FK, UNIQUE)
│
├─ DB_ERROR (데이터베이스 문제)
│  ├─ Connection Timeout (풀 포화 또는 DB 다운)
│  ├─ Query Timeout (느린 쿼리)
│  ├─ Deadlock (트랜잭션 충돌)
│  └─ Migration Failed (Flyway 마이그레이션 실패)
│
├─ TEST_SCRIPT_ERROR (테스트 스크립트 오류)
│  ├─ Check Fail (k6 검증 조건 불일치)
│  ├─ Data Parsing Error (응답 파싱 실패)
│  └─ Configuration Error (환경 변수 오류)
│
├─ TEST_DATA_ERROR (테스트 데이터 문제)
│  ├─ Stale Data (이전 실행의 잔존 데이터)
│  ├─ Missing Prerequisites (전제 데이터 부족)
│  └─ Constraint Violation (데이터 무결성 위반)
│
├─ INFRASTRUCTURE_ERROR (인프라 문제)
│  ├─ Docker Container Down (컨테이너 미실행)
│  ├─ Port Conflict (포트 충돌)
│  └─ Resource Exhaustion (CPU/메모리 부족)
│
└─ PERFORMANCE_ERROR (성능 저하)
   ├─ Response Timeout (응답 시간 초과)
   ├─ High GC Pressure (GC 압박)
   └─ Connection Pool Saturation (커넥션 풀 포화)
```

### 각 원인별 진단 방법

| 원인 | 특징 | 확인 방법 | 해결 방안 |
|-----|------|---------|---------|
| **APP_ERROR** | 5xx 응답, 스택 트레이스 | 백엔드 로그 grep "Exception" | 코드 수정 + 백엔드 재시작 |
| **DB_ERROR** | 시간 초과 오류, "connection refused" | `pg_stat_activity`, 쿼리 실행 계획 | 쿼리 최적화, 커넥션 풀 조정 |
| **TEST_SCRIPT_ERROR** | k6 check fail, 파싱 오류 | k6 콘솔 출력, 응답 body 로그 | k6 스크립트 수정 |
| **TEST_DATA_ERROR** | 멱등성 경로 진입, 제약 조건 위반 | DB 직접 쿼리 (데이터 확인) | DB 초기화 스크립트 개선 |
| **INFRASTRUCTURE_ERROR** | 연결 거부, "no such container" | `docker ps`, `curl` 헬스 체크 | 컨테이너 재시작 |
| **PERFORMANCE_ERROR** | 기준 초과 (p99 > 500ms, 에러율 > 1%) | Grafana 패널, JVM 메트릭 | GC 튜닝, 쿼리 최적화 |

---

## Baseline 파일 해석

### 파일 위치
`docs/monitoring/baselines/baseline-YYYY-MM-DD-HH-MM.md`

### 파일 구조

```markdown
# 성능 기준선 — 2026-06-25 16:57

**측정일시**: 2026-06-25 16:57
**환경**: Docker Compose (PostgreSQL 15, Spring Boot 3.x)
**HikariCP pool-size**: 10 (default)
**부하 도구**: k6 (5VU → 20VU → 50VU → 0VU), 총 2분 20초

---

## HTTP 응답시간 (k6 결과)

| 지표 | 값 |
| 평균 | 13.04ms |
| p50 | 11.26ms |
| p95 | 29.02ms |
| p99 | 37.21ms |
| 에러율 | 25.0% |
| 총 요청 수 | 6,508건 |
| RPS | 46.19 req/s |

### API별 p95 / p99
[각 API별 응답시간 분포]

## JVM (부하 직후 측정)
[Heap 사용률, GC 횟수 등]

## DB 커넥션 (부하 직후, HikariCP)
[커넥션 풀 상태]

## k6 기준(threshold) 달성 여부
[각 기준별 성공/실패]
```

### 해석 방법

#### 1. 응답시간 분포 해석

```
p50  = 중간값 (50%의 요청이 이보다 빠름)
p95  = 95% 빠름 (상위 5%가 느림)
p99  = 99% 빠름 (상위 1%가 매우 느림)
avg  = 평균 (이상치에 민감함)

예시:
p50=10ms, p95=50ms, p99=500ms
→ 절반은 매우 빠르지만, 최악의 1%는 500ms 소요
→ 응답 시간 편차가 큼 → DB 쿼리 또는 GC 영향
```

#### 2. API별 성능 비교

```
GET /api/challenges (목록)     → p95=18ms (빠름, 단순 조회)
GET /api/challenges/{id}       → p95=25ms (약간 느림, JOIN)
POST /api/challenges/{id}/check-ins → p95=35ms (가장 느림, 3 INSERT)
GET /api/challenges/{id}/check-ins  → p95=23ms (조회, 빠름)

분석: 쓰기(INSERT) > 복잡 조회 > 단순 조회
```

#### 3. 기준(Threshold) 달성 여부

```
| 기준 | 목표 | 결과 | 판정 |
| 전체 p99 | < 500ms | 37.21ms | ✅ 충족 (큰 마진) |
| 목록 조회 p95 | < 200ms | 18.29ms | ✅ 충족 (10배 이상 여유) |
| 체크인 쓰기 p95 | < 300ms | 35.09ms | ✅ 충족 (8배 이상 여유) |
| 에러율 | < 1% | 25.0% | ❌ 미충족 (25배 초과) |

분석: 응답시간은 우수하지만 에러율이 심각한 문제
```

#### 4. 리소스 사용률 해석

```
Heap 사용률 1.35% → ✅ 정상 (< 70% 기준)
GC 일시정지 1.4ms/분 → ✅ 정상 (< 20ms 기준)
HikariCP active 0 → ✅ 정상 (트랜잭션 완료)
HikariCP pending 0 → ✅ 정상 (요청 대기 없음)

분석: 리소스는 충분하고 안정적 → 성능은 우수
```

### Baseline 비교 분석 (다중 실행)

```
실행 1차 (16:57): 에러율 25.0%, p99 37.21ms
실행 2차 (17:03): 에러율 25.0%, p99 35.5ms  (응답 개선, 에러 동일)
실행 3차 (17:08): 에러율 25.0%, p99 33.45ms (응답 계속 개선, 에러 동일)

해석:
1. 에러율이 정확히 25%로 고정 → 체계적 버그 (NOT NULL constraint)
2. 응답시간은 점진적 개선 → 캐싱 또는 워밍업 효과
3. 결론: 백엔드 수정 필수 (V8 migration + null-check)
```

---

## 빠른 참고

### 명령어 치트시트

```bash
# 전체 자동 실행
bash monitoring/scripts/run-all-scenarios.sh

# Grafana 열기
open http://localhost:3000

# Prometheus 질의
curl 'http://localhost:9090/api/v1/query?query=http_req_duration'

# 백엔드 헬스 체크
curl http://localhost:8080/actuator/health | jq .

# DB 초기화
docker exec booster-postgres psql -U booster -d booster -c \
  "DELETE FROM challenge_check_ins WHERE id > 0;"

# k6 개별 실행
k6 run monitoring/k6/load-test.js

# 백엔드 로그 보기
docker logs booster-backend -f | grep -E "ERROR|Exception"

# 마이그레이션 확인
docker exec booster-postgres psql -U booster -d booster -c \
  "SELECT * FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 5;"
```

### 주요 문제 해결

| 증상 | 원인 | 해결 방법 |
|-----|------|---------|
| "백엔드가 실행 중이지 않습니다" | 백엔드 미실행 | `./gradlew bootRun` |
| "k6가 설치되지 않았습니다" | k6 미설치 | `brew install k6` |
| 에러율 25% 고정 | NOT NULL constraint | V8 migration + null-check (백엔드 재시작) |
| HikariCP pending > 0 | 풀 포화 | pool-size 증가 또는 쿼리 최적화 |
| Grafana "No Data" | 메트릭 없음 | Prometheus target UP 확인 |
| 응답 시간 > 1000ms | GC 또는 느린 쿼리 | Grafana JVM/DB 패널 확인 |

---

**최종 점검 리스트**

- [ ] 백엔드 `./gradlew bootRun` 실행 중 확인
- [ ] Docker 컨테이너 실행 중: `docker ps | grep booster`
- [ ] k6 설치: `k6 --version`
- [ ] 시나리오 실행: `bash monitoring/scripts/run-all-scenarios.sh`
- [ ] Grafana 대시보드 확인: `http://localhost:3000`
- [ ] Baseline 파일 생성 확인: `ls docs/monitoring/baselines/baseline-*.md`
- [ ] 에러율 < 1% 확인 (또는 원인 파악)
