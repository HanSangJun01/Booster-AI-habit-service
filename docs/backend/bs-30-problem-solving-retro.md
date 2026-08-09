# BS-30 백엔드 문제 해결 회고 — 정산 · 체크인 · 정합성

> 브랜치: `test/BS-30-backend-validation-b-axis` · 정리일: 2026-06-30
> 형식: 문제 → 적용한 해결 방식 → 해결 후보군 → 선정 이유(장점)

각 문제의 실제 구현 위치(`파일:라인`)를 근거로 정리한다.

---

## A. 성능

### A-1. N+1 — 날짜별 반복 쿼리 → 전체 기간 단일 조회
**위치**: `ParticipationRateCalculator.authoritativeRate()`

- **적용 방식**: `findByChallengeIdAndCheckInDateBetween(challengeId, start, end)`로 기간 전체 체크인을 **1쿼리**로 받아 `Collectors.groupingBy(checkInDate)`로 날짜별 SUCCESS 건수를 메모리 집계. 루프는 맵 조회(`getOrDefault`)만.
- **후보군**
  - 날짜별 반복 조회(기존) — N+1 (일수 × 팀수)
  - **Between 단일 조회 + 메모리 집계** ✅
  - DB `GROUP BY check_in_date` 집계 (행 미로딩, 집계값만)
  - `@BatchSize`/fetch join — 연관관계 N+1이 아니라 부적용
- **선정 이유(장점)**
  - **동작 100% 보존**: 활성 멤버 판정이 자바에 복잡하게 있어, 집계를 자바에 두면 기존 결과(승패·배당)가 그대로 — 정산 결과 일치로 검증됨
  - **추가 비용 0**: `findBy...Between`가 리포지토리에 이미 존재
  - **쿼리 수 고정**: 기간과 무관하게 팀당 1쿼리 (실측 28 → 2)

---

## B. 정산 정합성 (회계 — 코인 총량 보존)

### B-1. 코인 나머지 소실 방지
**위치**: `SettlementService.java:139-145`

- **적용 방식**: `perWinnerPayout = totalPool / n`, `remainder = totalPool % n` 를 계산해 **나머지를 첫 번째 승자에게 추가 지급**(`i==0 ? payout+remainder : payout`).
- **후보군**
  - 정수 나눗셈만 — 나머지 코인 증발 (지급합 < totalPool)
  - **나머지를 첫 승자에게** ✅
  - BigDecimal 소수 분배 — 코인은 정수 단위라 불가
  - 나머지 이월/소각 — 정책·추적 복잡
- **선정 이유(장점)**
  - **총량 보존 보장**: 지급 합계가 항상 `totalPool`과 정확히 일치
  - **단순**: 분기 한 줄, 추가 테이블·정책 불필요
  - **정수 도메인 일관**: 코인(정수)과 모순 없음

### B-2. 승팀 전원 LEFT 시 pool 소실 방지
**위치**: `SettlementService.java:146-154`

- **적용 방식**: 승팀의 CONFIRMED 참여자(`winnerParticipants`)가 비면 → **CONFIRMED 참여자 전원에게 예치금 환불**(DRAW와 동일 환불 경로 재사용).
- **후보군**
  - 지급 스킵 — pool 통째로 증발
  - **CONFIRMED 전원 예치금 환불** ✅
  - 패팀에게 지급 — 규칙 왜곡
  - 운영자 수동 보류 — 자동 복구 불가
- **선정 이유(장점)**
  - **코인 증발 차단**: "승자 없음" 엣지에서도 totalPool 보존
  - **참여자 손해 없음**: 정상 참가자 원금 회수
  - **재사용**: DRAW 환불 로직과 동일 → 코드·동작 일관성

---

## C. 트랜잭션 정합성

### C-1. 정산 중 예외 시 부분 커밋 방지 — FAILED를 REQUIRES_NEW로 별도 저장
**위치**: `SettlementFailureRecorder.recordFailure()` (`@Transactional(REQUIRES_NEW)`), 호출부 `SettlementService.java:171-176`

- **적용 방식**: 정산 본체 catch에서 `failureRecorder.recordFailure()`를 **REQUIRES_NEW 별도 트랜잭션**으로 호출해 `FAILED`를 독립 커밋한 뒤 예외 재throw. 본체(코인 지급 등)는 롤백.
- **후보군**
  - 같은 트랜잭션에서 FAILED 저장 — 외부 롤백 시 FAILED도 롤백되어 상태 소실
  - **REQUIRES_NEW 별도 커밋** ✅
  - `afterCompletion` 콜백 — 구현 복잡, 매니저 의존
  - 별도 에러 테이블 — 스키마·연동 부담
- **선정 이유(장점)**
  - **상태 생존 보장**: 지급 롤백돼도 `FAILED`는 DB에 남아 재시도 스케줄러가 인지
  - **부분 지급 차단**: 멱등 게이트(D-1)와 결합해 실패는 기록·지급은 원자적 롤백
  - **인프라 무추가**: 스프링 전파 속성만으로 해결
  - **패턴 재사용**: 동일 패턴이 체크인 중복 insert 격리(`CheckInInsertHelper`)에도 적용됨

---

## D. 멱등성

### D-1. 정산 중복 실행 방지 — PENDING/COMPLETED gate
**위치**: `SettlementService.java:53-72`

- **적용 방식**: ① 기존 settlement가 `COMPLETED`/`PENDING`이면 즉시 skip. ② 없으면 `PENDING` row 선점 저장(유니크 제약이 직렬화 지점). ③ `DataIntegrityViolationException` 시 동시 시도로 보고 skip.
- **후보군**
  - 게이트 없음 — 스케줄러 중복 진입 시 이중 지급
  - **PENDING 선점 + unique 제약** ✅
  - 비관적 락(SELECT FOR UPDATE) — 락 보유·교착 위험
  - 분산락(Redis) — 외부 인프라 의존
- **선정 이유(장점)**
  - **이중 지급 원천 차단**: COMPLETED/PENDING 둘 다 skip → 60초·5분 스케줄러 동시 진입에도 1회만 지급
  - **DB가 직렬화 담당**: `settlements.challenge_id` 유니크 제약이 게이트 → 추가 인프라 불필요
  - **재진입 안전**: 재시도 스케줄러가 같은 챌린지를 다시 불러도 멱등

### D-2. 체크인 중복 요청 방어 (3중 방어)
**위치**: `ChallengeCheckInService.java:77-88`, `CheckInInsertHelper.java`, `V3__...sql:14`

- **적용 방식**:
  1. **DB 유니크 제약** `unique_participant_date (participant_id, check_in_date)` — 같은 참가자+같은 날 1건만.
  2. **멱등 재조회**: 당일 SUCCESS 체크인이 있으면 새 처리 없이 기존 결과 반환. PENDING/FAILED면 그 레코드 재사용.
  3. **경쟁 조건 가드**: insert를 `REQUIRES_NEW`로 격리, 유니크 위반 시 동시 삽입된 행을 재조회 반환(바깥 트랜잭션 오염 방지).
  - 날짜 경계는 `LocalDate.now(ZoneId.of("Asia/Seoul"))`.
- **후보군**
  - 애플리케이션 재조회만 — TOCTOU 경쟁에서 누수
  - DB 유니크 제약만 — 위반 예외가 바깥 트랜잭션을 rollback-only로 오염
  - **유니크 제약 + 멱등 재조회 + REQUIRES_NEW 격리(3중)** ✅
- **선정 이유(장점)**
  - **다층 안전망**: 정상/재시도/동시요청 각 경로를 계층별로 커버
  - **바깥 트랜잭션 보호**: REQUIRES_NEW로 제약 위반이 상위 트랜잭션을 오염시키지 않음
  - **멱등 응답**: 중복 요청도 동일 결과 반환 → 클라이언트 재시도 안전

---

## E. 상태머신 검증

### E-1. 체크인 차단 — ACTIVE 상태에서만 허용
**위치**: `ChallengeCheckInService.java:61-66` (추가 `:69-72` 팀 미배정 차단)

- **적용 방식**: `status != ACTIVE`이면 `IllegalStateException` (화이트리스트). READY·ENDED 등 그 외 상태 전부 차단. 팀 미배정(`teamId == null`)도 차단.
- **후보군**
  - 블랙리스트(특정 상태만 차단) — 새 상태 추가 시 누락 위험
  - **화이트리스트(ACTIVE만 허용)** ✅
- **선정 이유(장점)**
  - **안전 기본값**: 미래에 상태가 추가돼도 명시적으로 허용하지 않는 한 차단 → 누락 사고 방지
  - **단일 지점 검증**: 오케스트레이터가 아닌 서비스에서 일괄 검사 → 우회 경로 차단

### E-2. 11번째 승인 차단 — 정원 초과 방지
**위치**: `ParticipationService.java:110-113`(승인), `:50-53`(신청), 락 `ChallengeRepository.findByIdWithLock()`

- **적용 방식**: CONFIRMED 인원수가 `challenge.getMaxParticipants()` 이상이면 `ChallengeFullException`. 정원 10이면 11번째 승인이 `count(10) >= 10`으로 차단. 검사 전 챌린지 행을 **PESSIMISTIC_WRITE 락**으로 잠금. (실질 정원 10 = `TeamFormationService.TEAM_SIZE(5) × 2`)
- **후보군**
  - 락 없이 카운트 검사 — 동시 승인 시 정원 초과(race)
  - **PESSIMISTIC_WRITE 락 + 카운트 검사** ✅
  - 유니크/체크 제약만 — 인원 상한은 제약으로 표현 어려움
- **선정 이유(장점)**
  - **동시성 정확성**: 행 락으로 동시 승인을 직렬화 → 정원 초과 원천 차단
  - **설정 기반**: 정원이 하드코딩이 아니라 `maxParticipants` 필드 → 챌린지별 유연
  - **상태 함께 검증**: `READY` 아님/대상 `PENDING` 아님도 같이 거부해 상태머신 일관

---

## F. 동시성

### F-1. 팀 구성 중복 실행 방어 (3중 가드)
**위치**: `TeamFormationService.formTeamsIfReady()` (`:33-48`), `V2__...sql:13`

- **적용 방식**:
  1. **상태 체크(멱등)**: `existsByChallengeId`로 이미 팀이 있으면 즉시 return.
  2. **정원 가드**: CONFIRMED < 10이면 no-op.
  3. **DB 유니크 제약**: `unique_challenge_team_name (challenge_id, name)`로 "A팀/B팀" 중복 insert 거부.
  - 또한 `ParticipationService`가 챌린지 행에 PESSIMISTIC_WRITE 락을 잡은 상태로 동기 호출 → 동시 진입 직렬화.
- **후보군**
  - 가드 없음 — 동시 호출 시 팀 중복 생성
  - 애플리케이션 상태 체크만 — TOCTOU 경쟁
  - **상태 체크 + 정원 가드 + DB 유니크 + 상위 락(다중)** ✅
- **선정 이유(장점)**
  - **다층 방어**: 애플리케이션·DB·락 세 층에서 중복 차단
  - **멱등**: 재호출해도 안전(이미 있으면 skip)
  - **DB 최후 방어선**: 애플리케이션 가드를 뚫어도 유니크 제약이 최종 차단

---

## G. 운영 복구

### G-1. ENDED/FAILED 정산 재시도 스케줄러
**위치**: `ChallengeEndScheduler.retryFailedSettlements()` (5분 주기)

- **적용 방식**: `markEndedChallenges`(60초)와 **별도 주기(5분)**로 ENDED 챌린지 중 settlement가 FAILED이거나 아예 없는 것(`orElse(true)`)을 재정산.
- **후보군**
  - 운영자 수동 재처리 — 누락·지연
  - 즉시 재시도 루프 — 영구 실패 시 폭주
  - **별도 주기 스케줄러** ✅
  - 메시지큐/DLQ — 인프라 추가
- **선정 이유(장점)**
  - **FAILED 고착 해소**: 일시 오류는 다음 주기에 자동 복구
  - **마킹과 분리**: 종료 처리와 재시도를 분리해 간섭·폭주 없음
  - **누락 케이스 커버**: settlement row 자체가 없는 챌린지도 `orElse(true)`로 포함
  - **무인 운영**: 외부 큐 없이 자가 치유

### G-2. 스케줄러 스레드 죽음 방지 가드
**위치**: `ChallengeEndScheduler` — 두 스케줄 메서드 본문을 `try/catch(Throwable)`로 래핑

- **적용 방식**: 개별 챌린지 처리 + 메서드 전체를 각각 try/catch(Throwable)로 감싸, 한 틱의 예외가 **단일 스케줄링 스레드를 죽이지 못하게** 함.
- **후보군**
  - 가드 없음 — 예외 1건이 스케줄러 스레드 종료 → 이후 모든 정산 정지
  - 메서드 레벨만 catch — 루프 중 1건 실패가 나머지 챌린지 처리 막음
  - **개별 + 메서드 이중 catch(Throwable)** ✅
- **선정 이유(장점)**
  - **스레드 생존**: 어떤 오류에도 스케줄러가 계속 동작
  - **부분 실패 격리**: 한 챌린지 실패가 다른 챌린지 처리를 막지 않음
  - **`Throwable`까지 포착**: `Error` 계열(예: 일부 런타임 이상)도 스레드를 끌어내리지 않음

---

## H. 인프라 보강 (이번 세션 추가)

### H-1. DB 커넥션 타임아웃
**위치**: `application.yml`

- **적용 방식**: `socketTimeout=30`, `tcpKeepAlive=true`, `hikari.connection-timeout=5000`, `jakarta.persistence.query.timeout=30000` 추가.
- **배경(중요)**: D-1의 "PENDING 선점 + 유니크 락"이, 커넥션이 끊긴 채 트랜잭션이 락을 쥐고 누수됐을 때 **단일 스케줄러 스레드를 영구 wedge**시키는 원인이 됐다(Docker↔PG 커넥션 불안정 `08006`).
- **선정 이유(장점)**
  - **빠른 실패**: 끊긴 커넥션/락 대기를 무한 대기 대신 타임아웃으로 종료 → 스케줄러가 계속 진행
  - **G-2와 짝**: 타임아웃이 예외를 발생시키고, G-2의 catch가 그것을 흡수 → 스레드 생존
  - **설정만으로 해결**: 코드 변경 없이 인프라 견고화

---

## 관통 주제
- **C·D·G** = "정산은 한 번만, 실패는 남기고, 자동으로 되살린다" (REQUIRES_NEW 격리 + 멱등 게이트 + 재시도 스케줄러).
- **B** = "코인 총량은 어떤 엣지에서도 보존된다" (회계 정합성).
- **E·F** = "허용된 상태·인원에서만, 동시에도 한 번만" (화이트리스트 상태머신 + 락/유니크 동시성).
- **A·H** = "쿼리는 최소로, 커넥션은 무한 대기하지 않는다" (성능 + 인프라 견고성).
