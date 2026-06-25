# A축 성능/오류 측정 보고서 — 1차 (BS-30)

> 부하 테스트 + Grafana 관찰로 발견한 "느린 곳 / 터지는 곳 / 개선 후보"를 정리한 1차 보고서.
> **이번 주는 기록만.** 고치는 건 다음 주 A축 원본 브랜치에서.
> 2차·3차 측정은 별도 파일(`FINDINGS_2차.md`, `FINDINGS_3차.md`)로 누적한다.

---

## 사용한 도구

| 도구 | 버전/형태 | 역할 |
|------|----------|------|
| Docker / Docker Compose | Desktop | DB·모니터링 스택·k6를 컨테이너로 실행 |
| PostgreSQL | 16 | 실제 측정용 DB (docker-compose.yml) |
| Spring Boot Actuator + Micrometer | prometheus registry | 앱이 응답시간·에러·자원 수치를 `/actuator/prometheus`로 노출(계기판) |
| Prometheus | docker-compose.monitoring.yml | 수치를 5초마다 긁어 시간순 저장 (localhost:9090) |
| Grafana | 자동 프로비저닝, A축 전용 대시보드 | 수치 시각화 (localhost:3000, admin/admin) |
| k6 | `grafana/k6` Docker 이미지로 실행 | 부하 생성(ramping VUs). 로컬 미설치 → `docker run` 사용 |
| Hibernate 통계 | `generate_statistics` + `LOG_QUERIES_SLOWER_THAN_MS=100` | 요청당 쿼리 수·느린 쿼리(SQL_SLOW) 가시성 |

> 실행 절차는 `backend/MONITORING.md` 참고. 부하 스크립트는 `backend/load-test/a-axis-load-test.js`.

---

## 측정 환경

- 일시: 2026-06-25
- 부하 프로필: ramping-vus 0→20→50→100, 약 3분
- DB: 빈 DB에서 시작(Flyway 체크섬 충돌로 볼륨 재생성 후). 부하용 유저 1명, 위치/체크인 데이터 없음
- k6: `docker run grafana/k6`, BASE_URL=host.docker.internal:8080
- 전체: 34,187 요청 / 180 req/s / 실패율 19.99% / 읽기 p95 149ms

---

## 🐢 느린 곳 (성능)

| 엔드포인트 | 평균 | p95 | p99 | 부하 올릴 때 변화 | 추정 원인(힌트) |
|-----------|------|-----|-----|------------------|----------------|
| 전체 읽기 API(5종 합산) | 45ms | 149ms | — | 100명에서도 안정 | 없음(목표 500ms 대비 양호) |

- **성능은 현재 문제 없음.** 100 VU 고부하에서도 읽기 p95 149ms로 목표(500ms) 한참 아래.
- `max=1.02s` 단발 스파이크 관찰 → 콜드스타트/일시 GC 추정. 재현 빈도 낮음. (k6 요약엔 p99 미표기 → Grafana p99 패널로 재확인 필요)

## 💥 터지는 곳 (오류)

| ID | 엔드포인트 | 상태코드 | 언제 발생 | 빈도 | 성격 |
|----|-----------|---------|----------|------|------|
| E1 | GET /api/users/me/location | 404 (LOCATION_NOT_FOUND) | 매 요청 | 6837/6837 (100%) | **제품 버그 아님 — 측정 셋업 빈틈** |

- **E1 해석:** 부하 스크립트 setup()이 유저 가입·로그인만 하고 **위치 등록(POST /location)을 안 함** → 위치 없는 유저가 GET을 부르면 서비스가 의도대로 404 반환(`PersonalLocationService.get` 42~45줄). GlobalExceptionHandler가 404로 정상 처리, **500/서버 크래시 0건**.
- 전체 실패율 19.99%는 이 한 엔드포인트의 정당한 404가 만든 수치(5개 중 1개 = 20%). **서버 안정성 문제 아님.**
- 나머지 4개(`/dashboard/home`, `/users/me/coins`, `/personal/check-in/today`, `/personal/recovery/status`)는 100% 200 OK.

## 🔌 자원 병목 (DB풀 / 메모리 등)

| 증상 | 관찰값 | 관련 엔드포인트 |
|------|--------|----------------|
| 이번 측정에선 Hikari pending/SQL_SLOW 뚜렷한 신호 미확인 | Grafana 관찰값 기록 안 됨 | — |

---

## 🔧 개선 후보 (코드 분석 기반)

> 성능 자체는 양호하나, 데이터가 쌓일수록 효과가 커질 "더 다듬기" 후보. 이번 주는 기록만, 다음 주 개선 대상.

| 순위 | 위치 | 내용 | 효과 | 비고 |
|------|------|------|------|------|
| 1 | `DashboardService.getHome` | DB 왕복 5번 → 3번. 오늘/이번주 데이터를 "이번 달 조회" 결과에서 메모리로 계산 | DB 왕복 감소(데이터·동시접속 많을수록 큼) | 주가 월 경계 걸치는 달말/달초만 예외 처리 |
| 2 | `CoinTransactionRepository.findByUserIdOrderByCreatedAtDesc` | 코인 내역 `Page` → `Slice`. 전체개수 COUNT 쿼리 제거 | 페이지당 쿼리 2→1 | 화면에 "총 N건" 필요 없을 때만(제품 결정) |
| 3 | 앱 기동/JVM | `max=1.02s` 단발 스파이크 → 워밍업 요청 또는 Hikari 최소 커넥션 선점으로 첫 요청 지연 완화 | 첫 요청 체감속도 | 코드 결함 아닌 콜드스타트 추정. 관찰 후보 |

### 손대지 않아도 되는 부분 (양호)
- **인덱스 양호:** `coin_transactions(user_id, created_at DESC)`, `personal_check_ins(user_id, check_in_date)` 등 조회 패턴에 맞게 이미 구성됨.
- **동시성 양호:** 코인 변동은 `findByIdForUpdate` 비관적 락으로 처리 → 잔액 경쟁 안전.

---

## 1차 결론

- 빈 DB·저데이터 상태에선 **성능/안정성 양호**(읽기 p95 149ms, 서버 크래시 0건).
- 실패율 20%는 제품 결함이 아니라 **측정 스크립트가 위치를 안 만들고 조회한** 셋업 빈틈(E1).
- 개선 후보 1~3은 "이미 빠른 걸 더 다듬는" 수준 → **2차(시드 데이터 + 위치 등록)에서 실제로 차이 나는지 검증 필요.** 빈 DB에선 차이가 안 드러남.
