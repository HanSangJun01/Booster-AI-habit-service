# A축 계획서(bs-20) ↔ 실제 기준 대조 / 어긋난 부분 정리

> 작성일: 2026-06-20
> 목적: A축 구현 착수 전, `docs/plan-axis-a-backend.md`(bs-20) 초안을 **실제 기준**과 대조하여 조정 지점을 확정한다.
> 비교 대상:
> - (가) 범용 MVP 스펙 — `docs/erd/MVP_ERD.md`, `docs/api/MVP_API_SPEC.md` (main)
> - (나) B축 실제 구현 — `origin/feature/BS-26-b-axis-backend` (Spring Boot, `com.booster`)

---

## 0. 핵심 결론

**A축은 bs-20 계획서를 단일 기준으로 독립 구현한다. B축과의 결합은 통합 Phase(나중)로 분리한다.** (사용자 확정: 2026-06-20)

- (가) 범용 `MVP_ERD/API_SPEC`은 A축 핵심 도메인(coin / streak / personal check-in / personal location)을 **거의 다루지 않는 초기 범용 모델**이다. 인증도 `verification_submissions → gps/ai_verification_results → verification_decisions` 분리형으로 정의돼 있으나, A축/B축 모두 이를 따르지 않고 단일 체크인 + 공유 `GpsVerificationEvaluator` 모델을 채택한다.
- (나) B축은 `CoinService/UserService/PersonalCheckInPort`를 `@Profile("stub")`로 비워 두었다. 통합 시 A축의 실제 도메인이 이 계약을 충족하게 되지만, **이번 A축 단독 구현에서는 B축 stub/계약에 의존하지 않는다**(독립 기동·테스트 보장, bs-20 Principle 4).
- 따라서 아래 갭 중 **B축 연동 관련 항목(G1 enum 통합, G5 응답 포맷 통일, G10 탈퇴 마킹)은 통합 Phase로 보류**하고, A축은 bs-20 모델/포맷을 그대로 구현한다.

---

## 1. B축이 비워 둔 공유 계약 (A축이 반드시 구현)

B축은 아래를 `@Profile("stub")` 더미로만 구현해 두었다. **기본(default) 프로파일에서 동작할 실제 구현은 A축 책임이다.**

| 계약 (인터페이스) | 위치 | A축 구현 내용 |
|---|---|---|
| `CoinService` | `shared.contract` | `deduct/credit/getBalance` — `CoinTransaction` 기록 + `User.coinBalance` 갱신 |
| `UserService` | `shared.contract` | `existsById/isActive` — `users` 테이블 조회 |
| `PersonalCheckInPort` | `shared.contract` | `recordPersonalCheckIn(userId, date, lat, lng)` — 개인 GPS 인증 처리 |

> `CheckInOrchestrator`(shared.checkin)가 B축 `ChallengeCheckInService`와 A축 `PersonalCheckInPort`를 독립 호출한다. A축이 `PersonalCheckInPort` 실제 구현을 제공하면 분리 불변식이 런타임에서도 성립한다.

---

## 2. 어긋난 부분 (조정 지점) — 우선순위순

### G1. 🔴 `CoinTransactionReason` enum에 A축 사유 없음 (공유 파일 수정 필요)
- B축 현재: `CHALLENGE_DEPOSIT, SETTLEMENT_WIN, DEPOSIT_REFUND, DEPOSIT_CANCEL_REFUND` (B축 사유만)
- bs-20 필요: `SIGNUP_BONUS(+500)`, `STREAK_REWARD(+100)`, `RECOVERY_SUCCESS(-50)`, `RECOVERY_FAILURE(-100)`
- **조치**: 공유 enum `shared.contract.CoinTransactionReason`에 A축 4개 값 추가. (B축 파일을 A축이 확장)

### G2. 🔴 A축 핵심 테이블이 (가) ERD에 없음
- 없음: `coin_transactions`, `streaks`, `personal_check_ins`, `personal_locations`
- `recovery_missions`는 (가)에 있으나 **B축 `challenge_check_ins`에 연결된 모델**(missionType/description/dueAt)로 정의됨 → bs-20의 `PersonalCheckIn 1:1 + deadlineAt + 코인 패널티` 모델과 **불일치**.
- **조치**: bs-20 모델 기준으로 신규 테이블 정의(Flyway V6+). `recovery_missions`는 bs-20 모델로 구현.

### G3. 🟠 `users` 테이블 컬럼 불일치
- (가) ERD 설명: 이메일/비밀번호/닉네임/가입일/상태만 언급
- bs-20 필요: `coinBalance`, `totalAttendance`, `isActive`, `passwordHash`
- **조치**: bs-20 기준으로 `users` 정의. (B축은 users 테이블이 없어 논리 FK만 사용 중 → A축이 V6에서 최초 생성)

### G4. 🟠 인증 모델 충돌 — 분리형(가) vs 단일+공유GPS(나/bs-20)
- (가): `verification_submissions / gps_verification_results / verification_decisions` 3테이블 분리형
- bs-20 & B축 실제: 단일 체크인 레코드 + 공유 `GpsVerificationEvaluator`(Haversine) 반경 판정
- **조치**: bs-20/B축 모델 채택. 분리형 범용 스펙은 MVP 미채택(over-spec). A축은 `personal_check_ins` 단일 + `personal_locations` 기반 검증.

### G5. 🟡 API 응답 포맷 불일치
- (가) `MVP_API_SPEC`: `{ "success": true/false, "message", "data" }`
- (나) B축 `ApiResponse<T>`: `{ "status": "success"/"error", "message", "data" }`
- bs-20 초안: 성공=DTO 직접 반환(래퍼 없음), 에러=`{ "code", "message" }`
- **조치(확정)**: A축은 **독립 구현**이므로 **bs-20 포맷 채택** — 성공은 DTO 직접 반환, 에러는 `ErrorResponse{code,message}` + `GlobalExceptionHandler`. B축 `ApiResponse` 강제는 **통합 Phase로 보류**(두 축 합칠 때 통일).

### G6. 🟡 Spring Security / JWT 의존성 미존재
- B축 `build.gradle`에 security 없음(B축은 `Long userId`를 그대로 받음 + `StubUserService`).
- bs-20 Phase 1: JWT 무상태 인증 + BCrypt 필요.
- **조치**: `build.gradle`에 `spring-boot-starter-security` + JWT(`jjwt`) 추가. `/api/auth/**` 외 JWT 필수 필터 체인 구성. 기존 B축 컨트롤러들이 `userId`를 어떻게 받을지(SecurityContext 전환)는 통합 Phase 과제로 두되, A축 엔드포인트부터 인증 적용.

### G7. 🟡 Flyway 버전 번호 / FK 방향
- B축이 `V1~V5` 점유. A축은 **V6부터** 시작.
- `users`가 B축 테이블보다 늦게 생성되므로 B축의 `user_id` 등에 물리 FK 소급 불가 → **논리 FK 유지**(B축이 이미 선택한 정책과 동일).

### G8. 🟡 API 경로 차이
- bs-20 초안: `/api/users/me`, `/api/users/me/location`, `/api/personal/check-in`, `/api/personal/recovery`, `/api/dashboard/home`, `/api/users/me/coins`
- (가) 범용 스펙: `/api/users/{userId}`(me 아님), 개인 체크인/대시보드/코인 경로 **없음**
- **조치**: A축 개인 도메인 특성상 **bs-20 경로 채택**. 추후 `MVP_API_SPEC`에 A축 섹션으로 반영 필요.

### G9. 🟡 [미결] 스트릭 보상 반복 지급 (제품 결정 필요)
- bs-20: `currentStreak % 7 == 0` → 7·14·21일마다 반복 지급(현재 가정)
- 단회라면 `currentStreak == 7`로 변경
- **조치**: 제품 책임자 확인. 미확정 시 **반복(%7) + 설정 플래그**로 구현하고 주석에 명시.

### G10. 🟢 회원 탈퇴 ↔ B축 `activeUntil` 마킹 계약 (통합 Phase로 보류)
- bs-19 Q2b: A축 탈퇴 API가 동일 트랜잭션에서 `ChallengeParticipant.activeUntil` 마킹 요구
- 현재 B축에 이를 수신할 진입점이 명확치 않음 → bs-20도 "통합 Phase에서 처리"로 명시
- **조치**: MVP A축 탈퇴는 `User.isActive=false`(soft delete)만. B축 연동은 통합 Phase.

---

## 3. 채택 결정 요약 (구현 기준)

| 항목 | 채택 |
|---|---|
| 도메인 모델 | **bs-20 계획서** 기준 (coin/streak/personal-checkin/personal-location/recovery) |
| 공유 계약 | B축 `CoinService/UserService/PersonalCheckInPort` **실제 구현** 제공 |
| `CoinTransactionReason` | 공유 enum에 A축 4개 사유 **추가** |
| 응답 포맷 | B축 `ApiResponse{status,message,data}` |
| 인증 모델 | 단일 `personal_check_ins` + 공유 `GpsVerificationEvaluator` |
| 보안 | `spring-boot-starter-security` + JWT 추가 (A축이 도입) |
| Flyway | V6부터, 논리 FK |
| API 경로 | bs-20 초안 경로 |
| 범용 MVP 분리형 인증 | **미채택**(Phase 2 이후) |

---

## 3-1. B축 통합 체크리스트 (A축 단독 구현 완료 후, 두 backend/ 병합 시)

> A축은 `feature/BS-20-a-axis-backend`, B축은 `feature/BS-26-b-axis-backend`. 둘 다 같은 `backend/`(`com.booster`)에 독립 작성 → 병합 시 아래를 처리해야 한다. **치명적 설계 충돌은 없음. 대부분 기계적 + 보안 1건이 실작업.**

### 🔴 실작업 (의미 있는 결정/리팩터 필요)
1. **Spring Security 전역 적용 ↔ B축 인증 부재** — A축이 `spring-boot-starter-security` 도입, `anyRequest().authenticated()`. B축 컨트롤러는 인증 개념 없이 `userId`를 body/param으로 받음. 병합 시 B축 엔드포인트가 전부 401이 됨. → B축 컨트롤러를 `@AuthenticationPrincipal Long userId` 기반으로 리팩터하거나 SecurityConfig에 B 경로 정책 추가. **가장 큰 통합 작업.**
2. **CoinService 계약 통합 + 차감 의미 차이** — B축: `CoinService`(interface) `deduct/credit/getBalance`, `deduct`는 잔액부족 시 예외(원자적, 클램핑 없음). A축: `coin.service.CoinService`(class) `grant/charge/getBalance`, `charge`는 잔액까지 클램핑. → 통합 CoinService는 **두 의미 모두** 필요: 챌린지 예치금=엄격 deduct(부족 시 예외), 복귀 패널티=클램핑 charge. A축 구현이 B축 인터페이스를 구현하도록 어댑트.
3. **응답 포맷 통일** — A: 성공=DTO/에러=`{code,message}`. B: `ApiResponse{status,message,data}`. `GlobalExceptionHandler`가 **FQN 중복**(둘 다 `shared.common.GlobalExceptionHandler`) → 컴파일 충돌, 하나로 병합 필수. 프런트 계약 통일.

### 🟠 중복 클래스 정리 (같은 FQN/역할 → 하나로)
4. `shared.gps.GpsVerificationEvaluator` (양쪽 존재, A가 `distanceMeters` 추가됨) → A 버전으로 단일화.
5. `shared.gps.GpsCoordinates` (동일 record) → 하나 유지.
6. `shared.common.GlobalExceptionHandler` (FQN 중복, 내용 상이) → 병합.
7. `CoinTransactionReason` enum 2개: B `shared.contract`(CHALLENGE_DEPOSIT/SETTLEMENT_WIN/DEPOSIT_REFUND/DEPOSIT_CANCEL_REFUND) + A `coin.domain`(SIGNUP_BONUS/STREAK_REWARD/RECOVERY_SUCCESS/RECOVERY_FAILURE) → 단일 enum 8값으로 통합.
8. **UserService/PersonalCheckInPort 어댑터** — B축 `shared.contract.UserService`/`PersonalCheckInPort`(stub, `@Profile("stub")`)의 실제 구현을 A축 도메인으로 제공: `existsById/isActive`→UserRepository, `recordPersonalCheckIn`→A축 PersonalCheckInService 위임. stub 프로파일 제거.

### 🟡 빌드/설정 머지 (수동 union)
9. `build.gradle` — A의 security+jjwt 의존성 union.
10. `settings.gradle` — A의 foojay-resolver 플러그인 유지.
11. `application.yml` / `application-test.yml` — A의 jwt/booster/dialect-override 설정 union. (특히 test의 `hibernate.dialect=H2Dialect` 오버라이드는 B축 `@Lock` 테스트에도 필요 — 사실상 B 잠재버그 해소)
12. `BoosterApplication.java`, gradle wrapper, `.gitignore` — 동일/A가 B에서 복사 → 충돌 없음.

### ✅ 충돌 없음
13. **Flyway**: A=V6~V8, B=V1~V5 → 번호 충돌 없음. 통합 시 V1~V8 순차 적용. users(V6)가 challenge 테이블(V1)보다 늦게 생기지만 B가 user_id에 물리 FK를 걸지 않음(논리 FK) → 적용 순서 문제 없음. (원하면 통합 후 물리 FK 추가 마이그레이션 별도)

## 4. 미결/확인 필요

1. **[제품] 스트릭 보상**: 7일 1회 vs 반복(%7)
2. **[팀 합의] API 경로**: bs-20 개인 도메인 경로를 `MVP_API_SPEC`에 정식 반영
3. **[통합 Phase] 탈퇴 ↔ B축 activeUntil 마킹**
