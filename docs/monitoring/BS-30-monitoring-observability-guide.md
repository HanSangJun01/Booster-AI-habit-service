# BS-30 모니터링 관찰성 가이드

> 대상: B-axis 백엔드 개발/검증 환경
> 기준: Spring Boot 3.x + Actuator + Prometheus + Grafana + k6

---

## 1. SQL 쿼리 가시성 (dev 프로파일)

### 활성화 방법

```bash
# backend 디렉토리에서 실행
./gradlew bootRun --args='--spring.profiles.active=stub,dev'
```

`application-dev.yml`이 `stub` 프로파일 위에 적용되어 아래가 활성화됩니다.

| 설정 | 효과 |
|------|------|
| `org.hibernate.SQL: DEBUG` | 실행되는 모든 SQL을 콘솔에 출력 |
| `org.hibernate.orm.jdbc.bind: TRACE` | SQL 바인딩 파라미터 값 출력 |
| `org.hibernate.stat: DEBUG` | 요청 종료 시 쿼리 횟수·시간 통계 출력 |
| `org.hibernate.SQL_SLOW: WARN` | 100ms 초과 쿼리를 WARN 레벨로 별도 출력 |

### 로그 확인 예시

**쿼리 횟수 확인** (요청 종료 시 자동 출력):
```
DEBUG org.hibernate.stat - Session Metrics {
  29650 nanoseconds spent acquiring 1 JDBC connections;
  3 flushes as part of work;
  5 queries executed to database;       ← 이 요청에서 쿼리 5회 실행
}
```

**느린 쿼리 확인** (`SQL_SLOW` 로거):
```
WARN  org.hibernate.SQL_SLOW - SlowQuery: 143 milliseconds. SQL: 'select ...'
```

### 주의사항

- `application-dev.yml`은 dev 환경 전용입니다. `application.yml`(운영/기본)은 수정하지 않습니다.
- `TRACE` 레벨 바인딩 파라미터 로그는 민감 데이터를 포함할 수 있으므로 dev 환경에서만 사용합니다.

---

## 2. Grafana 대시보드 Import

### Import 파일

```
monitoring/grafana/booster-baxis-dashboard-import.json
```

### Import 방법

1. Grafana 접속 → `http://localhost:3000` (admin / admin)
2. 좌측 메뉴 **Dashboards** → **Import**
3. **Upload dashboard JSON file** 선택
4. `booster-baxis-dashboard-import.json` 업로드
5. Prometheus datasource 선택 → **Import**

### 대시보드 구성 (16개 패널, 5개 섹션)

| 섹션 | 패널 | 목적 |
|------|------|------|
| 📊 핵심 지표 | Heap 사용률, RPS, 평균 응답시간, DB 커넥션 | 한눈에 이상 여부 확인 |
| 🌐 HTTP 요청 분석 | URI별 응답시간, p50/p95/p99, RPS, 에러율 | API 성능 전반 |
| 🗄️ DB 커넥션 | active/idle/pending, 획득시간, 타임아웃 | DB 병목 감지 |
| ☕ JVM 상세 | Heap 사용/커밋/최대, GC, 스레드, Non-Heap | 메모리·GC 원인 분석 |
| 📈 응답시간 심층 분석 | **URI별 p95/p99**, **HTTP 상태코드 분포** | 느린 엔드포인트 특정 |

### 느린 API 원인 추적 순서

```
1. 핵심 지표 섹션 → 평균 응답시간이 기준선 초과 확인
2. HTTP 요청 분석 → URI별 응답시간에서 어떤 엔드포인트인지 특정
3. 응답시간 심층 분석 → URI별 p99에서 최악 케이스 확인
4. DB 커넥션 섹션 → pending 발생 여부 확인 (DB 병목인가?)
5. JVM 섹션 → GC 일시정지 시점과 응답시간 스파이크가 겹치는가?
```

---

## 3. k6 부하 테스트

### 설치

```bash
# macOS
brew install k6

# 또는 공식 설치 스크립트
# https://k6.io/docs/getting-started/installation/
```

### 실행

```bash
# 기본 실행 (백엔드가 localhost:8080에서 실행 중이어야 함)
k6 run monitoring/k6/load-test.js

# 다른 URL 대상
k6 run -e BASE_URL=http://localhost:8080 monitoring/k6/load-test.js

# 결과를 JSON으로 저장
k6 run --out json=monitoring/k6/results.json monitoring/k6/load-test.js
```

### 부하 단계

| 단계 | 동시 사용자(VU) | 시간 | 목적 |
|------|--------------|------|------|
| 워밍업 | 5 | 30초 | JVM JIT 컴파일, 커넥션 풀 준비 |
| 기본 부하 | 20 | 1분 | 일반 트래픽 시뮬레이션 |
| 피크 | 50 | 30초 | DB 커넥션 풀 포화 임박 구간 관찰 |
| 쿨다운 | 0 | 20초 | 요청 종료 후 자원 회복 확인 |

### 성공 기준 (thresholds)

| 지표 | 기준 |
|------|------|
| 전체 p99 응답시간 | < 500ms |
| 챌린지 목록 조회 p95 | < 200ms |
| 챌린지 상세 조회 p95 | < 150ms |
| 에러율 | < 1% |

기준 초과 시 k6가 exit code 1을 반환합니다.

### k6 실행 중 Grafana에서 확인할 것

```
k6 실행 시작
    ↓
Grafana 대시보드 열기 (새로고침 간격: 15s 또는 10s로 조정)
    ↓
워밍업(30s): Heap 사용량·커넥션 수가 올라오는 것 확인
    ↓
기본 부하(1m): URI별 응답시간 안정 구간 확인 → 기준선 수치 기록
    ↓
피크(30s): HikariCP pending 발생 여부, GC 빈도 증가 여부 관찰
    ↓
쿨다운(20s): Heap 회복, 커넥션 idle 복귀 확인 (메모리 누수 없음)
```

---

## 4. 1주차 기준선 기록

실험 완료 후 아래 경로에 결과를 기록합니다.

```
docs/monitoring/week1-baseline.md
```

기록 항목:
- k6 실행 결과 수치 (p50/p95/p99, 에러율)
- Grafana 대시보드 스크린샷
- HikariCP 커넥션 피크값
- JVM Heap 최대 사용률
- GC 일시정지 최대값
