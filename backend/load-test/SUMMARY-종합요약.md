# A축 성능/오류 측정 — 종합 요약 (BS-30)

> **이 문서 = 1~6차 전체 종합 + 현재 상태 + 다음 단계.** (새 채팅/월요일 최종보고서용 핸드오프)
> 작성: 2026-06-25 / 개정: 2026-06-30(6차 추가) / 브랜치: `test/BS-30-backend-validation-a-axis`
> 회차별 상세는 `FINDINGS_1차~4차.md`, `FINDINGS_5차-출시검증.md`, **`FINDINGS_6차-시나리오리뷰.md`** 참고.
>
> ⚠️ **두 종류의 결과가 섞여 있으니 구분할 것:**
> - **1~5차 = 성능/부하 측정** → 결론: 성능·안정성 양호, 긴급 성능버그 없음(용량 산정이 과제).
> - **6차 = 시나리오/동시성 코드리뷰 + 테스트** → 결론: **정합성 버그 7건 발견(RED 테스트로 증명).** 부하측정이 구조적으로 못 잡던 단일유저 동시요청·다일 상태머신 버그.

---

## 0. 이번 주 목표 & 방식

- **목표: "찾기"만.** 어디가 느리고 어디서 에러 나는지 문제 목록 확정. **수정은 다음 주.**
- **방식:** Spring Boot Actuator + Prometheus + Grafana(자동 프로비저닝) 계기판 + k6 부하. 응답시간(p95/p99)·JVM·DB 커넥션을 함께 보며 "느린 원인이 API로직 / JVM자원 / DB커넥션 중 무엇인지" 구분.
- **브랜치 격리:** A축 원본 `feature/BS-25-a-axis-backend`는 안 건드림. 측정 코드는 전부 이 BS-30 브랜치에만.

## 1. 회차별 요약 (변수 하나씩 바꿔가며)

| 회차 | 바꾼 변수 | 핵심 결과 |
|------|-----------|-----------|
| 1차 | 빈 DB 기준선(읽기) | 읽기 p95 149ms 양호. 실패 20%는 location 404(측정 셋업 빈틈, 버그 아님) |
| 2차 | 위치·체크인 시드(읽기) | 실패 0.01%, location 200 측정. "dashboard 500" 가설 → Prometheus로 반증(5xx 0) |
| 3차 | 데이터 대량(체크인25+코인300) | 데이터 늘려도 안 느려짐. 서버측 max dashboard 0.23s/coins 0.17s |
| 4차 | 쓰기+로그인+다중유저 | **로그인 병목 발견**: 서버측 0.79s/건, p95 1.73s. 원인 BCrypt(CPU) |
| 5차 | A soak / B 고동시성 / C 대용량 | soak 누수0. 500VU서 Hikari pending 189. 30만행 인덱스 0.04ms. N+1 구조상 없음 |
| **6차** | **방법 전환: 부하 → 코드리뷰+시나리오 테스트** | **정합성 버그 7건 발견·RED 고정.** 코드리뷰어 2레인(동시성/로직) → 명세 대조 → 실패 테스트(H2 + Testcontainers PG) |

## 2. 최종 부하 지점 (조금이라도 부담 있는 곳 전부, 심각도순)

| 순위 | 위치 | 측정값 | 원인 | 보강 방법 | 성격 |
|------|------|--------|------|-----------|------|
| 🔴 1 | 인증 BCrypt (`/auth/login`,`/signup`) | 로그인 서버측 0.79s/건, 100VU p95 1.73s, 66 req/s | BCrypt 해싱 CPU | 인스턴스 수평확장 + 인증 레이트리밋. **BCrypt 강도 낮추기 금지** | 실질 병목 |
| 🟡 2 | DB 커넥션풀/스레드 (`application.yml`) | 500VU서 서버 0.23→0.70s, **Hikari pending 189/active 10** | 기본 풀 10개 부족 | `hikari.maximum-pool-size` 20~30 명시 + DB max_connections 정합 + 인스턴스 계획 | 고동시성 |
| 🟢 3 | 코인 COUNT (`/users/me/coins`) | 30만행 COUNT만 Seq Scan 28ms (조회는 0.04ms) | Page가 매번 전체 COUNT | `Page`→`Slice`(총개수 불필요 시) | 경미/선택 |
| 🟢 4 | 연결 수락 stall (앱 밖) | ~31s stall 재현(0.008~0.01%), 500VU 51s, dial i/o timeout 소수 | 버스트 순간 TCP accept 대기열 | Tomcat accept-count/max-connections 또는 LB | 경미/인프라 |
| 🟢 5 | dashboard 5쿼리 (`DashboardService`) | 30만행에도 서버 0.23s(빠름) | DB 5번 왕복 | 5→3(오늘/이번주를 월 결과서 계산) | 코드정리/선택 |
| 🟢 6 | 콜드스타트 스파이크 | 1차 max 1.02s 단발 | JVM 워밍업/JIT | 기동 후 워밍업 요청 or Hikari 최소 커넥션 선점 | 미미/선택 |

## 3. 검증 완료 — 안심해도 되는 것

- 읽기/쓰기 DB 쿼리, 인덱스(30만행에서도 Index/Bitmap Scan), **N+1 없음**(JPA 연관관계 0개, 논리FK)
- **메모리 누수 없음**(soak 30m heap 102→108MB 평평), GC 건강(5.3s/30m), 스레드 반납
- **서버 5xx 0건**(전 구간). 데이터·동시성·시간 어디서도 크래시 없음
- ※ 단 이 "안심"은 **성능/안정성** 한정. **정합성(로직) 버그는 6차에서 별도로 발견됨** ↓

## 3-2. 6차 — 시나리오/동시성 정합성 버그 (코드리뷰 + RED 테스트)

> 부하측정(1~5차)은 **서로 다른 유저**로 돌려서 "단일 유저 동시요청 레이스"나 "여러 날 상태머신 갭"을 구조적으로 못 잡음. 6차는 방법을 **코드리뷰어 2레인 + 시나리오 테스트**로 바꿔 그 사각지대를 팠고, **A축 계획서(Phase 1~4)·명세와 대조**해 확정했다.

**확정 버그 7건 (전부 실패 테스트로 증명):**

| # | 버그 | 심각도 | 명세 대조 | RED 증거 |
|---|------|--------|-----------|----------|
| C2 | 동시 복귀미션 이중처리 | 🔴 | **명세 위반** — "WHERE status='PENDING'" 미구현 | RECOVERY_SUCCESS 거래 2행, 코인 -100, 출석 +2 |
| C4 | 첫 인증 동시요청 500 누출 | 🔴 | **명세 위반** — "위반 시 409" 인데 500 | 원시 `DataIntegrityViolationException`→500 |
| C1 | 코인 lost update | 🔴 | **불변식 위반**(Principle 2) | `coin_balance=958 ≠ SUM=920` (38코인 소실) |
| C5 | Streak lost update | 🔴 | 상태머신 정합성 위반 | 30/30 라운드 +1 소실 |
| C6 | 스케줄러/수행 경계 불일치 | 🟡 | **명세 위반** — strict `<` 인데 코드 `<=` | deadline==now서 -150 이중차감 |
| C7 | 스케줄러 멱등성(동시) | 🟡 | **명세 위반** — "ON CONFLICT" 미구현 | 동시 실행 시 배치 롤백 |
| B2 | 가입일 off-by-one | 🟡 | 코드가 자기 주석과 모순 | 가입일==어제 유저에 복귀미션 생성 |
| B3 | 탈퇴 후 가드 누락 | 🟡 | 명세 공백(로그인만 차단) | 탈퇴 유저가 인증·복귀 성공 |

**팀/제품 결정 필요 (명세 공백):** B1(마일스톤 보상 타이밍 — 잠정 스트릭에 영구 보상), B2(가입일 면제 정책), B3(탈퇴 후 차단 범위).
**오판 정정:** ~~B4(복귀 당일 출석)~~ → Phase 3 명세상 의도된 동작이라 **버그 아님**(테스트 GREEN 반전 완료).

**6차 핵심 메시지:** 1~5차 "버그 없음"은 *성능* 한정이 맞았고, *정합성*은 6차가 따로 잡았다. 특히 **C2·C4는 명세가 해법을 적어놨는데 코드가 빠뜨린 것**이라 반박 불가.

## 4. 결론 & 다음 주 액션

- **성능/안정성(1~5차): 양호.** 긴급 성능버그 없음. 실질 과제는 **출시 용량 산정**(예상 피크 동시 로그인 → 인스턴스 수 + 커넥션풀 크기, 코드 리팩터 아님).
- **정합성(6차): 확정 버그 7건.** 동시성 6(C1·C2·C4·C5·C6·C7) + 로직 2(B2·B3). 이건 **반드시 고쳐야 하는 진짜 버그**다. 처방은 `FINDINGS_6차` 참조(요약: User 비관락 선로드 / 상태전이 조건부 원자 UPDATE / 409 핸들러 / ON CONFLICT / active 가드 / 가입일 경계 수정).
- 결정 필요 3건(B1·B2·B3 정책)은 형/팀과 합의 후 확정.
- 선택적 정리: 코인 `Page`→`Slice`, dashboard 쿼리 5→3, 복귀 스케줄러 N+1.
- ⚠️ **수정은 전부 A축 원본 `feature/BS-25-a-axis-backend`** 에서. 이 BS-30 브랜치는 측정/발견 전용(테스트 RED 포함), 제품에 섞지 않음. **커밋·푸시 안 함(현 상태).**

---

## 5. 현재 상태 (핸드오프)

- **브랜치:** `test/BS-30-backend-validation-a-axis` — origin 푸시 완료(커밋 ~a1183d9..0f117d8).
- **산출물(이 폴더):** `FINDINGS_1차~4차.md`, `FINDINGS_5차-출시검증.md`, **`FINDINGS_6차-시나리오리뷰.md`**, 본 종합요약.
  - 부하 스크립트: `a-axis-load-test.js`(읽기, LOGIN_EMAIL 모드 있음), `a-axis-write-load-test.js`(쓰기/로그인), `a-axis-stress-test.js`(고동시성 500VU), `a-axis-soak-test.js`(30m 지속)
  - 시드: `seed-3rd.sql`(체크인25+코인300), `seed-big.sql`(코인 30만행+EXPLAIN)
  - 모니터링: `../monitoring/**`(prometheus.yml, grafana provisioning, a-axis-overview.json), `../docker-compose.monitoring.yml`, 가이드 `../MONITORING.md`
  - **6차 버그핀 테스트(`backend/src/test/`):** 로직 = `personalcheckin/StreakContinuityScenarioTest`, `recovery/RecoveryScenarioBugTest`(B2 RED + B4 GREEN), `user/WithdrawnUserGuardTest` / 동시성 = `concurrency/ConcurrencyTestBase`, `FixedClockConfig`, `C1~C6` 테스트 / 인프라 = `build.gradle`(Testcontainers + `api.version=1.44` 우회), `src/test/resources/application-ct.yml`
- **측정 DB 상태:** 부하로 유저 수천 명 + 코인 30만 행 생성됨(측정용 더미, 정리 가능). 시드 유저 `seed3rd@booster.test`/`seed1234`(user_id=3).
- **테스트 상태:** 로직 RED 테스트(B1·B2·B3)는 **의도적 실패**(버그 증명) → 기본 `./gradlew test` 빨강이 정상. 동시성 테스트는 Docker 필요. 수정(BS-25) 시 GREEN 전환.
- **미완료:** 형에게 5·6차 공유, B1·B2·B3 정책 결정, BS-25에서 버그 수정, 측정 DB 정리, 월요일 최종보고서.

## 6. 재현/이어가기 빠른 참조

```powershell
# DB + 백엔드 (backend 폴더)
docker compose -f docker-compose.yml up -d db
.\gradlew.bat bootRun                      # localhost:8080/actuator/prometheus 확인
# 모니터링 스택
docker compose -f docker-compose.monitoring.yml up -d   # Grafana localhost:3000 admin/admin
# 부하(k6는 미설치 → Docker로). load-test 폴더에서:
docker run --rm -i -e BASE_URL=http://host.docker.internal:8080 -v ${PWD}:/scripts grafana/k6 run /scripts/a-axis-load-test.js
# SQL 시드(PowerShell 파이프는 깨짐 → 복사 후 -f). 저장소 루트에서:
docker compose -f backend/docker-compose.yml cp backend/load-test/seed-3rd.sql db:/tmp/seed-3rd.sql
docker compose -f backend/docker-compose.yml exec -T db psql -U booster -d booster -f /tmp/seed-3rd.sql
# Prometheus 직접 질의 예: http://localhost:9090  →  http_server_requests_seconds_count{status="500"}
```

**계기판 핵심 쿼리:**
- 서버측 p95: `histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{uri="..."}[5m])) by (le))`
- 5xx: `http_server_requests_seconds_count{status=~"5.."}`
- 커넥션 대기: `hikaricp_connections_pending`, `hikaricp_connections_active`
- 힙/누수: `jvm_memory_used_bytes{area="heap"}`
