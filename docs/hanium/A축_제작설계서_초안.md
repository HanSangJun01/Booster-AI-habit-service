# 한이음 드림업 제작설계서 — A축 (개인 GPS 습관 인증) 초안

> 대상: Booster — AI 습관 형성 서비스 / **A축 = 개인 GPS 기반 일일 습관 인증·스트릭·코인·복귀** 영역
> 근거: `backend/src/main/java/com/booster/**` 실제 구현 코드 (feature/BS-25-a-axis-backend 계열)
> 양식 매핑: [서식2] 제작설계서 PPTX의 슬라이드 8(요구사항 정의서) · 21·22(기능 처리도) · 25(프로그램 목록) · 27·28(핵심 소스코드)
>
> ⚠️ B축(챌린지/그룹) 기능은 의도적으로 **전부 제외**. A축은 개인 흐름 전용으로 독립 구현됨.

---

## 1. 요구사항 정의서  *(PPTX 슬라이드 8 양식: 구분 | 기능 | 설명)*

A축은 전부 **S/W**다. (H/W 없음 — 사용자 스마트폰의 GPS 좌표를 입력으로 받는 순수 백엔드 서비스)

| 구분 | 기능 | 설명 |
|------|------|------|
| S/W | 회원가입 | 이메일·비밀번호(8~64자)·닉네임으로 가입한다. 비밀번호는 BCrypt로 해싱 저장하고, 가입 보너스 코인을 지급하며 스트릭 정보를 초기화한다. |
| S/W | 로그인 | 이메일·비밀번호를 검증하고 성공 시 JWT Access Token을 발급한다. 비활성(탈퇴) 계정은 거부한다. |
| S/W | 로그아웃 | 무상태(JWT) 구조로, 서버는 토큰을 폐기하지 않고 클라이언트가 토큰을 파기하도록 안내한다. |
| S/W | 개인 인증 위치 등록 | 사용자가 습관을 인증할 기준 위치(위도·경도·반경·장소명)를 1개 등록한다. (사용자당 1개) |
| S/W | 개인 인증 위치 수정 | 등록된 기준 위치를 변경한다. |
| S/W | 개인 인증 위치 조회 | 현재 등록된 기준 위치를 조회한다. |
| S/W | 일일 GPS 인증(체크인) | 현재 GPS 좌표가 등록 위치 반경 이내인지 Haversine 거리로 판정한다. 성공 시 당일 인증 기록 생성, 스트릭 +1, 출석 +1, 보상 마일스톤 도달 시 코인 지급. 당일 중복 인증은 차단(409). |
| S/W | 오늘 인증 상태 조회 | 오늘 날짜의 인증 상태(SUCCESS / RECOVERY_PENDING / NOT_CHECKED 등)를 조회한다. |
| S/W | 복귀 미션 상태 조회 | 미인증으로 발생한 대기 중 복귀 미션(대상 날짜·마감시각)이 있는지 조회한다. |
| S/W | 복귀 미션 수행 | 마감 이내에 GPS 재인증으로 미인증일을 보정한다. 성공 시 코인 차감(-50, 잔액까지만), 스트릭 유지(증가 없음), 미인증일을 SUCCESS로 보정. |
| S/W | 대시보드(홈) 조회 | 코인 잔액, 현재/최대 스트릭, 이번 주 인증 일수, 오늘 상태, 이번 달 캘린더를 한 번에 조회한다. |
| S/W | 마이페이지 조회 | 닉네임·이메일·코인 잔액·총 출석일 등 사용자 요약 정보를 조회한다. |
| S/W | 코인 거래 내역 조회 | 코인 지급/차감 이력을 페이지 단위로 조회한다(기본 20건). |
| S/W | 회원 탈퇴 | 계정을 비활성화(soft delete)한다. |
| S/W | 일일 복귀 미션 스케줄러 | (배치) 매일 ① 마감 초과 복귀 미션 일괄 실패 처리(-100, 스트릭 0) ② 어제 미인증 활성 사용자에게 복귀 미션 자동 생성. 멱등 보장. |

**비기능 요구사항 (측정으로 검증됨 — BS-30):**

| 항목 | 요구/결과 |
|------|-----------|
| 응답시간 | 읽기 API p95 ≈ 149ms, 서버측 대시보드 0.23s / 코인 0.17s (30만 행에서도 유지) |
| 데이터 무결성 | 코인: `SUM(amount) == User.coinBalance` 항상 성립(단일 진실 원천), 비관적 락으로 동시성 보호 |
| 안정성 | 30분 soak 메모리 누수 0, 서버 5xx 0건, N+1 쿼리 0건 |
| 보안 | 비밀번호 BCrypt 해싱, JWT 인증 필터, 인증 실패 시 통일된 오류 응답 |

---

## 2. 기능 처리도 (기능 흐름도)  *(PPTX 슬라이드 21·22 양식)*

### 개요
> 사용자가 등록한 기준 위치 반경 안에서 GPS 인증을 수행하면 습관 스트릭이 쌓이고, 일정 주기마다 코인이 보상으로 지급된다. 인증을 놓친 날은 다음 날 복귀 미션으로 보정할 수 있으며, 마감을 넘기면 스트릭이 초기화된다.

### 2-1. 일일 GPS 인증(체크인) 처리 흐름  *(A축 핵심 기능)*

```
[시작] 사용자: POST /api/personal/check-in  { lat, lng } + JWT
   │
   ▼
① 기준 위치 등록 여부 확인 ──(없음)──▶ 400 LOCATION_NOT_REGISTERED ─▶[종료]
   │ (있음)
   ▼
② 당일 인증 기록 조회 ──(이미 SUCCESS)──▶ 409 DUPLICATE_CHECK_IN ─▶[종료]
   │ (없음 또는 RECOVERY_PENDING)
   ▼
③ GPS 반경 판정 (Haversine 거리 ≤ 등록 반경?)
   │
   ├──(반경 밖)──▶ 400 GPS_OUT_OF_RANGE  ※실패 시 레코드 생성 안 함 ─▶[종료]
   │ (반경 안)
   ▼
④ 인증 기록 확정
   ├─ 기존 레코드 존재 → markSuccess() 보정
   └─ 없음 → PersonalCheckIn.success() 신규 저장
   ▼
⑤ 스트릭 +1 (currentStreak↑, maxStreak 갱신, lastSuccessDate=오늘)
   ▼
⑥ 출석일수 +1 (User.totalAttendance)
   ▼
⑦ 보상 마일스톤 판정 (currentStreak % rewardIntervalDays == 0 ?)
   ├──(해당)──▶ CoinService.grant(+rewardCoins, STREAK_REWARD) → 코인 거래 기록
   │ (미해당)
   ▼
⑧ 응답 반환 { 날짜, SUCCESS, 인증시각, currentStreak, maxStreak, coinBalance, rewardGranted } ─▶[종료]
```

### 2-2. 복귀 미션 전체 생애주기 흐름  *(스케줄러 + 사용자 수행)*

```
[매일 배치 — DailyMissionScheduler]
   │
   ▼
①단계 expireOverdueMissions(): 마감(deadlineAt) 초과 PENDING 미션 일괄 처리
   └─ 미션 FAILED + 미인증일 FAILED + 코인 -100(클램핑) + 스트릭 reset(0)
   │
   ▼
②단계 generatePendingForYesterday(): 어제 미인증 '활성' 사용자 대상
   └─ PersonalCheckIn(RECOVERY_PENDING) 생성 + RecoveryMission(PENDING, 마감=오늘 23:59:59) 생성
       (멱등: 어제 레코드가 이미 있으면 건너뜀)
   │
   ▼
[사용자] GET /api/personal/recovery/status → 대기 미션 확인
   │
   ▼
[사용자] POST /api/personal/recovery  { lat, lng }
   │
   ├─ 마감 초과? ──▶ 400 RECOVERY_EXPIRED
   ├─ GPS 반경 밖? ──▶ 400 GPS_OUT_OF_RANGE
   │ (마감 이내 & 반경 안)
   ▼
   미션 COMPLETED + 미인증일 SUCCESS 보정 + 코인 -50(클램핑)
   + 출석 +1 + 스트릭 keepAlive(증가 없이 유지) ─▶[종료]
```

> 💡 작성 팁: PPTX에 옮길 때는 위 텍스트 흐름을 도형(사각형=처리, 마름모=판단)으로 바꾸고, 우측에 ①~⑧ 번호 설명을 붙이면 슬라이드 21 샘플과 동일한 형식이 된다.

---

## 3. 프로그램 목록  *(PPTX 슬라이드 25 양식: 기능 분류 | 기능번호 | 기능 명)*

| 기능 분류 | 기능 번호 | 기능 명 | API 엔드포인트 |
|-----------|-----------|---------|----------------|
| AUTH (인증) | AUTH-01 | 회원가입 | `POST /api/auth/signup` |
| AUTH | AUTH-02 | 로그인 (JWT 발급) | `POST /api/auth/login` |
| AUTH | AUTH-03 | 로그아웃 | `POST /api/auth/logout` |
| LOC (위치) | LOC-01 | 개인 인증 위치 등록 | `POST /api/users/me/location` |
| LOC | LOC-02 | 개인 인증 위치 수정 | `PUT /api/users/me/location` |
| LOC | LOC-03 | 개인 인증 위치 조회 | `GET /api/users/me/location` |
| CHK (인증/체크인) | CHK-01 | 일일 GPS 인증 | `POST /api/personal/check-in` |
| CHK | CHK-02 | 오늘 인증 상태 조회 | `GET /api/personal/check-in/today` |
| RCV (복귀) | RCV-01 | 복귀 미션 상태 조회 | `GET /api/personal/recovery/status` |
| RCV | RCV-02 | 복귀 미션 수행 | `POST /api/personal/recovery` |
| DASH (대시보드) | DASH-01 | 홈 대시보드 조회 | `GET /api/dashboard/home` |
| USER (사용자) | USER-01 | 마이페이지 조회 | `GET /api/users/me` |
| USER | USER-02 | 코인 거래 내역 조회 | `GET /api/users/me/coins` |
| USER | USER-03 | 회원 탈퇴 | `DELETE /api/users/me` |
| BATCH (배치) | BATCH-01 | 일일 복귀 미션 스케줄러 | `DailyMissionScheduler` (cron) |

**내부 공통 컴포넌트 (직접 노출 X, 위 기능들이 공유):**

| 분류 | 컴포넌트 | 역할 |
|------|----------|------|
| 공통 | `GpsVerificationEvaluator` | Haversine 거리 기반 GPS 반경 판정 |
| 공통 | `CoinService` | 코인 지급/차감 단일 진입점 (잔액-거래내역 동기화, 비관적 락) |
| 공통 | `JwtTokenProvider` / `JwtAuthenticationFilter` | JWT 발급·검증, `@AuthenticationPrincipal Long userId` 주입 |
| 공통 | `GlobalExceptionHandler` / `BusinessException` | 통일된 오류 응답(코드+메시지) |

---

## 4. 핵심 소스코드  *(PPTX 슬라이드 27·28 양식: 코드 + 설명)*

### 4-1. GPS 반경 판정 — Haversine 알고리즘
> 핵심 적용 기술. 두 위경도 좌표 사이의 지표면 거리(m)를 구해 등록 반경과 비교한다.

```java
// shared/gps/GpsVerificationEvaluator.java
@Component
public class GpsVerificationEvaluator {

    private static final double EARTH_RADIUS_METERS = 6_371_000.0;

    public boolean isWithinRadius(double registeredLat, double registeredLng,
                                  int radiusMeters,
                                  double currentLat, double currentLng) {
        double distance = haversineDistance(registeredLat, registeredLng, currentLat, currentLng);
        return distance <= radiusMeters;
    }

    private double haversineDistance(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_METERS * c;
    }
}
```
**설명:** 지구를 반지름 6,371km 구로 근사하여 두 좌표의 대원거리(great-circle distance)를 계산한다. 외부 지도 API 호출 없이 서버 내 연산만으로 ms 단위 판정이 가능해, 인증 요청이 몰려도 외부 의존성 병목이 없다.

### 4-2. 일일 GPS 인증 처리 — 핵심 비즈니스 흐름
> 위치 확인 → 중복 방지 → 반경 판정 → 스트릭/출석/코인 보상까지 하나의 트랜잭션으로 처리.

```java
// personalcheckin/service/PersonalCheckInService.java
@Transactional
public CheckInResponse checkIn(Long userId, double currentLat, double currentLng) {
    LocalDate today = LocalDate.now(clock);

    PersonalLocation location = personalLocationRepository.findById(userId)
            .orElseThrow(() -> BusinessException.badRequest(
                    "LOCATION_NOT_REGISTERED", "개인 GPS 위치를 먼저 등록하세요."));

    // 당일 중복 인증 방지 (이미 SUCCESS면 409)
    PersonalCheckIn existing = personalCheckInRepository
            .findByUserIdAndDate(userId, today).orElse(null);
    if (existing != null && existing.isSuccess()) {
        throw BusinessException.conflict("DUPLICATE_CHECK_IN", "오늘 이미 인증을 완료했습니다.");
    }

    // GPS 반경 판정 — 실패 시 레코드 생성하지 않음
    boolean within = gpsEvaluator.isWithinRadius(
            location.getLat(), location.getLng(), location.getRadiusMeters(),
            currentLat, currentLng);
    if (!within) {
        throw BusinessException.badRequest("GPS_OUT_OF_RANGE", "등록된 위치 반경을 벗어났습니다.");
    }

    OffsetDateTime now = OffsetDateTime.now(clock);
    if (existing != null) {
        existing.markSuccess(now);                       // 복귀 대기 레코드 보정
    } else {
        personalCheckInRepository.save(PersonalCheckIn.success(userId, today, now));
    }

    Streak streak = streakRepository.findById(userId).orElseThrow(...);
    streak.recordSuccess(today);                          // 스트릭 +1

    User user = userRepository.findById(userId).orElseThrow(...);
    user.increaseAttendance();                            // 출석 +1

    boolean rewardGranted = false;
    if (isRewardEligible(streak.getCurrentStreak())) {    // 마일스톤 도달 시
        coinService.grant(userId, rewardCoins, CoinTransactionReason.STREAK_REWARD, null);
        rewardGranted = true;
    }
    return new CheckInResponse(today, SUCCESS, now,
            streak.getCurrentStreak(), streak.getMaxStreak(), user.getCoinBalance(), rewardGranted);
}
```
**설명:** `UNIQUE(user_id, check_in_date)` 제약 + 애플리케이션 단 중복 검사로 하루 1회 인증을 보장한다. GPS 실패 시에는 레코드를 만들지 않아 데이터가 오염되지 않으며, 인증·스트릭·출석·코인 변경이 하나의 `@Transactional`로 묶여 부분 반영을 방지한다.

### 4-3. 코인 단일 진실 원천(Single Source of Truth)
> 모든 코인 변동을 한 메서드로만 처리해 `잔액 = 거래내역 합계` 불변식을 보장한다.

```java
// coin/service/CoinService.java
@Transactional
public long charge(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
    if (amount < 0) throw new IllegalArgumentException("charge amount must be >= 0: " + amount);
    User user = lockUser(userId);                         // 비관적 락 (동시 차감 방지)
    long effective = Math.min(amount, user.getCoinBalance());  // 잔액까지만 차감(음수 방지)
    user.addCoins(-effective);
    coinTransactionRepository.save(
            CoinTransaction.of(userId, reason, -effective, user.getCoinBalance(), referenceId));
    return effective;                                     // 실제 차감액 반환
}

private User lockUser(Long userId) {
    return userRepository.findByIdForUpdate(userId)      // SELECT ... FOR UPDATE
            .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
}
```
**설명:** 지급(`grant`)·차감(`charge`)이 항상 `CoinTransaction` 기록과 `User.coinBalance` 갱신을 함께 수행하므로 `SUM(amount) == coinBalance`가 항상 성립한다. `SELECT ... FOR UPDATE` 비관적 락으로 동시 요청에도 잔액 정합성이 깨지지 않으며, 부하 테스트(BS-30)에서 동시성 오류 0건으로 검증되었다.

---

## 5. (참조) 데이터 모델 — A축 테이블

| 테이블 | PK | 주요 컬럼 | 관계/제약 |
|--------|----|-----------|-----------|
| `users` | id | email(unique), password_hash, nickname, coin_balance, total_attendance, is_active, joined_at | 모든 A축 도메인의 기준 |
| `personal_locations` | user_id | lat, lng, radius_meters, place_name | user_id 공유(1:1) |
| `streaks` | user_id | current_streak, max_streak, last_success_date | user_id 공유(1:1) |
| `personal_check_ins` | id | user_id, check_in_date, status, verified_at | **UNIQUE(user_id, check_in_date)** |
| `recovery_missions` | id | personal_check_in_id(unique), user_id, deadline_at, completed_at, status | check_in과 1:1 |
| `coin_transactions` | id | user_id, type, amount(부호 있음), balance_after, reference_id | 코인 변동 단일 이력 |

> ※ 연관관계는 JPA 객체 매핑이 아니라 **논리 FK(Long id)**로 설계 → 의도적으로 N+1 쿼리 0건 (BS-30 검증).
> ※ status enum: PersonalCheckIn = `SUCCESS / RECOVERY_PENDING / FAILED`, Recovery = `PENDING / COMPLETED / FAILED`.
