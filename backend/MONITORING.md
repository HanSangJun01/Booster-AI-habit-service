# A축 성능/오류 측정 가이드 (BS-30)

> 이번 주 목표: **찾기만.** 어디가 느리고 어디서 에러 나는지 "문제 목록"을 확정한다.
> 고치는 건 다음 주에 A축 원본 브랜치(`feature/BS-25-a-axis-backend`)에서. 이 브랜치(`test/BS-30-...`)는 측정 전용.

## 구성 (셋이 역할 분담)

| 도구 | 역할 | 어디서 보나 |
|------|------|-------------|
| **Actuator** | 앱이 수치를 수집·노출 (`/actuator/prometheus`) | — |
| **Prometheus** | 그 수치를 5초마다 긁어 시간순 저장 | http://localhost:9090 |
| **Grafana** | 저장된 수치를 그래프로 (A축 대시보드 자동 로딩) | http://localhost:3000 (admin/admin) |
| **k6** | 부하를 줘서 약점을 드러냄 | 터미널 출력 |

## 실행 순서

### 1. DB + 백엔드 띄우기
```bash
# DB (기존 compose)
docker compose -f docker-compose.yml up -d db
# 백엔드 (호스트에서 실행 → Prometheus가 host.docker.internal:8080로 긁음)
./gradlew bootRun
```
확인: http://localhost:8080/actuator/prometheus 에 수치 텍스트가 뜨면 계기판 OK.

### 2. 모니터링 스택 띄우기
```bash
docker compose -f docker-compose.monitoring.yml up -d
```
- Grafana(http://localhost:3000, admin/admin) → 대시보드 "Booster A-axis - 성능/오류 개요" 자동 로딩됨.
- Prometheus(http://localhost:9090/targets) → `booster-a-axis` 타깃이 **UP**이면 연결 성공.

### 3. 부하 주기
```bash
cd load-test
k6 run a-axis-load-test.js
```
- 0 → 20 → 50 → 100명으로 점점 세게 두들김(약 3분).
- 도는 동안 Grafana를 띄워놓고 **어느 엔드포인트의 p95/p99가 튀는지, 에러율이 올라가는지** 관찰.

## 무엇을 보고 무엇을 기록하나

- **느린 곳:** Grafana "p95/p99 응답시간" 패널에서 유독 높은 엔드포인트. (평균 말고 p95/p99를 봐야 가끔 느린 게 잡힘)
- **터지는 곳:** "에러율(4xx/5xx)" 패널에서 부하 올라갈 때 빨강 막대가 뜨는 엔드포인트.
- **DB 병목:** "Hikari pending"이 0보다 커지면 커넥션풀 부족 신호. 백엔드 콘솔 로그의 `SQL_SLOW`(느린 쿼리)와 `generate_statistics`(요청당 쿼리 수)로 원인 힌트.
- 발견한 건 전부 `load-test/FINDINGS.md`에 적는다. ← **이게 이번 주 결과물**

## 정리(끄기)
```bash
docker compose -f docker-compose.monitoring.yml down
```
