# A축 백엔드 구현 계획

> **상태**: `pending approval`
> **작성일**: 2026-06-06
> **작성 방식**: ralplan (Planner → Architect → Critic 합의)
> **담당 범위**: Auth/User · PersonalCheckIn · Streak · RecoveryMission · Home Dashboard
> **참조 문서**: `docs/project-plan.md`, `.omc/specs/deep-interview-booster.md`
> **주의**: ERD/API 명세 md 작성 완료 후 엔티티 필드·API 경로·DTO·응답 형식은 해당 문서 기준으로 최종 조정 예정

---

## RALPLAN-DR

### Principles

1. **PersonalCheckIn / ChallengeCheckIn 완전 분리**
   PersonalCheckIn은 개인 스트릭·코인·복귀미션만 담당한다.
   ChallengeCheckIn 실패가 PersonalCheckIn.status나 Streak에 영향을 주어서는 안 된다.

2. **CoinTransaction 단일 진실 원천**
   모든 코인 변화(+500 가입, +100 스트릭, -50 복귀성공, -100 복귀실패)는
   CoinTransaction 레코드로 기록한다. User.coinBalance는 파생값이다.

3. **PersonalCheckIn 상태 머신 명확화**
   PersonalCheckIn.status는 `SUCCESS` / `RECOVERY_PENDING` / `FAILED` 세 상태만 존재한다.
   전환 조건(GPS 성공, 데드라인 초과, 복귀 성공/실패)은 서비스 코드에서 강제한다.

4. **A축 독립 배포 가능**
   Phase 1~4 구현이 Challenge/Team/ChallengeCheckIn 엔티티 없이
   단독으로 기동·테스트 가능해야 한다. B축과의 결합은 통합 Phase에서 처리.

5. **JWT 무상태 인증**
   서버 측 세션 테이블 없음. Access Token만 발급(MVP).
   Refresh Token은 Phase 2 옵션으로 남겨둔다.

### Decision Drivers

1. PersonalCheckIn ↔ ChallengeCheckIn 경계 보장
2. 복귀 미션 상태 머신 정확성 (이중 카운트 방지, KST 23:59 데드라인)
3. B축 병렬 개발을 막지 않는 Phase 순서

### ADR — Phase 순서 선택

| 항목 | 내용 |
|------|------|
| **결정** | Option A: 비즈니스 로직 완성 우선 4-Phase 순차 |
| **드라이버** | 각 Phase가 실제 테스트 가능한 완성 단위여야 한다 |
| **검토한 대안** | Option B (Auth → Dashboard 껍데기 → CheckIn → Recovery): 프론트엔드 화면 먼저 확정 가능하지만, 실제 CheckIn 데이터 없이 Dashboard가 목업 상태가 되어 통합 테스트가 어렵다 |
| **선택 이유** | 비즈니스 로직이 올바르지 않으면 UI도 잘못됨. 완성된 단위별 검증이 우선 |
| **결과** | Dashboard API가 Phase 4에 위치하므로, 플러터 홈 탭 연동은 Phase 4 완료 후 시작 |
| **후속 과제** | ERD/API 명세 확정 후 각 Phase DTO·경로 최종 조정 |

---

## 핵심 엔티티 (초안, ERD 확정 시 조정)

| 엔티티 | 역할 | A축 사용 여부 |
|--------|------|--------------|
| `User` | 계정, coinBalance, totalAttendance | A축 핵심 |
| `CoinTransaction` | 코인 변화 이력 | A축 핵심 |
| `Streak` | currentStreak, maxStreak, lastSuccessDate | A축 핵심 |
| `PersonalCheckIn` | 개인 일일 인증 (date/status/verifiedAt) | A축 핵심 |
| `PersonalLocation` | 개인 GPS 등록 위치 (userId, lat, lng, radiusMeters) | **A축 핵심** |
| `RecoveryMission` | PersonalCheckIn 1:1, deadlineAt, status | A축 핵심 |
| `ChallengeCheckIn` | 팀 참여율 기준 인증 | **A축 미사용** — B축 전담 |
| `ChallengeParticipant` | 팀 챌린지 참여 + ChallengeCheckIn GPS | **A축 미사용** — B축 전담 |

> **설계 원칙 (Principle 1 & 4 적용)**:
> PersonalCheckIn의 GPS 검증은 `PersonalLocation` 테이블만 참조한다.
> `ChallengeParticipant`의 GPS 필드는 ChallengeCheckIn 전용이며 PersonalCheckIn에서 절대 참조하지 않는다.
> 이로써 A축은 B축(Challenge/Team) 엔티티 없이 단독으로 기동·테스트 가능하다.

---

## Phase 구성 개요

```
Phase 1: Auth & User 기초          (1~2일)
Phase 2: PersonalCheckIn & Streak  (2~3일)
Phase 3: RecoveryMission           (2일)
Phase 4: MyPage & Home Dashboard   (1~2일)
```

각 Phase는 독립적으로 테스트 가능한 완성 단위로 구성된다.

---

## Phase 1 — Auth & User 기초

### 목표
회원가입/로그인/로그아웃과 코인 초기 지급 흐름을 완성한다.
이후 모든 API가 의존하는 인증 기반을 확립한다.

### 구현 대상

#### 엔티티
- `User`: id, email, passwordHash, nickname, joinedAt, coinBalance, totalAttendance, isActive
- `CoinTransaction`: id, userId, type(enum), amount, balanceAfter, referenceId, createdAt
- `Streak`: userId(PK/FK), currentStreak, maxStreak, lastSuccessDate

#### API (경로는 ERD/명세 확정 후 조정)

| 메서드 | 경로(초안) | 설명 |
|--------|-----------|------|
| POST | /api/auth/signup | 회원가입 → 500코인 CoinTransaction 생성 + Streak 초기화 |
| POST | /api/auth/login | 이메일+비밀번호 검증 → JWT Access Token 반환 |
| POST | /api/auth/logout | 클라이언트 토큰 파기 안내 (서버 무상태) |

#### 보안 설정
- Spring Security + JWT 필터 체인
- BCrypt 비밀번호 해시
- /api/auth/** 는 인증 제외, 나머지는 JWT 필수

#### 코인 로직
- 가입 시: `CoinTransaction(type=SIGNUP_BONUS, amount=+500)` 생성
- `User.coinBalance` = 500으로 초기화

### 완료 기준 (Acceptance Criteria)
- [ ] 이메일+비밀번호 가입 → DB에 User 생성, coinBalance=500, Streak 레코드 생성
- [ ] 가입 직후 로그인 → JWT 반환
- [ ] 잘못된 비밀번호 로그인 → 401 에러
- [ ] JWT로 보호된 엔드포인트 호출 성공
- [ ] 중복 이메일 가입 시 409 에러

---

## Phase 2 — PersonalCheckIn & Streak

### 목표
개인 GPS 인증 흐름을 완성한다.
인증 성공 시 스트릭 +1, 7일 달성 시 +100코인 자동 지급, 미인증 시 RECOVERY_PENDING 전환.

### 구현 대상

#### 엔티티
- `PersonalCheckIn`: id, userId, date(KST), status(SUCCESS/RECOVERY_PENDING/FAILED), verifiedAt
  - **DB 제약**: `UNIQUE(userId, date)` — 동일 사용자·날짜 중복 레코드 불가
- `PersonalLocation`: userId(PK/FK), lat, lng, radiusMeters, placeName, createdAt
  - 사용자당 1개 (1:1). 개인 GPS 등록 위치 전용. ChallengeParticipant와 무관.
  - 등록 API: `POST /api/users/me/location`, 수정 API: `PUT /api/users/me/location`
- (Phase 1에서 생성한 `Streak` 재사용)

#### API

| 메서드 | 경로(초안) | 설명 |
|--------|-----------|------|
| POST | /api/users/me/location | 개인 GPS 위치 등록 (최초 1회) |
| PUT | /api/users/me/location | 개인 GPS 위치 수정 |
| POST | /api/personal/check-in | 개인 GPS 인증 수행 |
| GET | /api/personal/check-in/today | 오늘 인증 상태 조회 |

#### 핵심 로직

**GPS 검증**
```
Haversine(현재위도경도, 등록위도경도) <= 등록반경(meters)
```
- 인증 가능 시간: KST 00:00~23:59 (ZoneId.of("Asia/Seoul"))
- 당일 중복 인증 방지: 동일 userId + date(KST) PersonalCheckIn이 SUCCESS이면 409

**인증 성공 시 처리**
1. PersonalCheckIn 생성 (status=SUCCESS) — UNIQUE(userId, date) 위반 시 409 반환
2. Streak.currentStreak +1, lastSuccessDate = 오늘
3. Streak.maxStreak 갱신 (현재 > 최고면 업데이트)
4. User.totalAttendance +1
5. currentStreak % 7 == 0 이면: CoinTransaction(type=STREAK_REWARD, amount=+100) 생성, coinBalance +100
   - **[미결]** 스트릭 보상 반복 지급 여부: 현재 `% 7 == 0` 구현은 7일, 14일, 21일마다 지급.
     스펙에서 "7일 연속 달성 시 +100코인" 표현이 단회인지 반복인지 명시되지 않음.
     → **제품 책임자 확인 필요**. 단회라면 `currentStreak == 7`으로 변경.

**스케줄러 (매일 KST 00:01 실행) — 처리 순서 필수 준수**

단일 스케줄러에서 아래 순서로 실행한다. Phase 3 만료 처리가 반드시 먼저 실행되어야
새 RECOVERY_PENDING 생성이 이미 만료된 건을 덮어쓰지 않는다.

**① [Phase 3 로직] 만료된 RecoveryMission FAILED 처리** (→ 상세는 Phase 3 참조)
- deadlineAt ≤ 현재 시각이고 status = PENDING인 RecoveryMission 일괄 처리

**② [Phase 2 로직] 전일 미인증자 RECOVERY_PENDING 생성**
- 어제(KST) PersonalCheckIn 레코드가 없는 모든 활성 User에 대해:
  - `INSERT INTO personal_check_in (userId, date, status) VALUES (?, ?, 'RECOVERY_PENDING') ON CONFLICT (userId, date) DO NOTHING`
  - RecoveryMission 생성: `deadlineAt = 어제 날짜 + 1일의 23:59:59 KST`
    (= 오늘 23:59:59 KST)

**멱등성 보장 구체 방법**
- `PersonalCheckIn`에 `UNIQUE(userId, date)` DB 제약 설정
- INSERT 시 `ON CONFLICT (userId, date) DO NOTHING` 사용 → 중복 실행 시 skip
- RecoveryMission도 `personalCheckInId UNIQUE` 제약으로 이중 생성 방지

> **중요**: 이 스케줄러는 PersonalCheckIn 기준으로만 실행.
> ChallengeCheckIn 미완료는 이 스케줄러와 무관.

### 완료 기준
- [ ] GPS 반경 내 → PersonalCheckIn SUCCESS, 스트릭 +1
- [ ] GPS 반경 외 → 인증 실패 응답 (PersonalCheckIn 생성 안 함)
- [ ] 7일 연속 성공 → CoinTransaction +100 자동 생성
- [ ] 당일 중복 인증 → 409 에러
- [ ] 스케줄러 실행 후 미인증자 PersonalCheckIn(RECOVERY_PENDING) 생성 확인

---

## Phase 3 — RecoveryMission

### 목표
복귀 미션 흐름을 완성한다.
성공 시 -50코인 + 스트릭 유지, 실패(데드라인 초과) 시 -100코인 + 스트릭 초기화.
복귀는 미인증일(missed_date)의 PersonalCheckIn만 SUCCESS로 보정하며, 복귀 수행일(오늘)의 레코드를 새로 생성하지 않는다. 단, 오늘의 일반 인증은 별개로 허용된다(이중 카운트 없음).

### 구현 대상

#### 엔티티
- `RecoveryMission`: id, personalCheckInId(FK, unique), userId, deadlineAt(KST), completedAt, status(PENDING/COMPLETED/FAILED)

#### API

| 메서드 | 경로(초안) | 설명 |
|--------|-----------|------|
| GET | /api/personal/recovery/status | 현재 복귀 미션 대기 여부 조회 |
| POST | /api/personal/recovery | 복귀 미션 GPS 인증 수행 |

#### 핵심 로직

**복귀 미션 수행 조건**
- RecoveryMission.status = PENDING
- 현재 시각 < deadlineAt (KST 다음 날 23:59:59)
- GPS 검증 통과

**성공 시 처리**
1. RecoveryMission.status → COMPLETED, completedAt = 현재 시각
2. PersonalCheckIn.status → SUCCESS (미인증일 보정, `deadlineAt`의 날짜 기준)
3. CoinTransaction(type=RECOVERY_SUCCESS, amount=-50, balanceAfter=coinBalance-50) 생성, coinBalance -50
4. User.totalAttendance +1 (복귀 성공도 출석으로 집계)
5. Streak 유지: currentStreak 변화 없음, lastSuccessDate = 복귀 미션 수행일(오늘 KST)
6. 복귀는 오늘 날짜의 PersonalCheckIn을 새로 생성하지 않음 (단, 오늘의 일반 인증은 별개로 허용):
   - 복귀 미션으로 보정된 PersonalCheckIn(missed_date).status = SUCCESS 상태
   - 복귀 수행일(today) PersonalCheckIn이 없어도 오늘의 일반 인증은 허용
   - 단, 복귀가 오늘 날짜의 PersonalCheckIn을 생성하지는 않으므로 이중 카운트 없음

**실패 처리 (스케줄러 ① 단계)**
- deadlineAt ≤ 현재 시각이고 status = PENDING인 RecoveryMission:
  1. RecoveryMission.status → FAILED
  2. PersonalCheckIn.status → FAILED
  3. 코인 차감 계산: `effectiveAmount = max(-coinBalance, -100)` (잔액이 100 미만이면 실제 잔액만큼 차감)
     - CoinTransaction(type=RECOVERY_FAILURE, **amount=effectiveAmount**, balanceAfter=0 or 남은 잔액) 생성
     - coinBalance += effectiveAmount (결과: 최소 0)
  4. Streak.currentStreak = 0, lastSuccessDate = null (초기화)

> **CoinTransaction 회계 정책** (Principle 2 준수):
> `CoinTransaction.amount`는 **실제 차감된 금액**(effective amount)을 기록한다.
> 코인이 30 남은 상태에서 -100 패널티 발생 시: `amount = -30, balanceAfter = 0`.
> 이렇게 해야 `SUM(CoinTransaction.amount)` = `User.coinBalance` 재현이 항상 성립한다.
> nominal(-100) vs effective(-30) 구분이 필요하면 `nominalAmount` 컬럼 추가 (ERD 확정 시).

### 완료 기준
- [ ] RECOVERY_PENDING 상태에서 GPS 성공 + 데드라인 이내 → -50코인, 스트릭 유지, totalAttendance +1
- [ ] 복귀 성공 후 미인증일(missed_date) PersonalCheckIn.status = SUCCESS 확인
- [ ] 데드라인 초과 RecoveryMission → 스케줄러 실행 후 FAILED, 스트릭 0
- [ ] 잔액 30코인에서 -100 패널티 → CoinTransaction.amount = -30, balanceAfter = 0 (effective amount)
- [ ] 복귀 미션 없이 /api/personal/recovery 호출 → 404 에러
- [ ] 스케줄러 이중 실행 → RecoveryMission.status 중복 변경 없음 (멱등성 확인)

---

## Phase 4 — MyPage & Home Dashboard

### 목표
마이페이지와 홈 대시보드 API를 완성한다.
프론트엔드 홈 탭과 마이페이지 탭이 이 Phase 이후 연동 가능해진다.

### 구현 대상

#### API

| 메서드 | 경로(초안) | 설명 |
|--------|-----------|------|
| GET | /api/users/me | 마이페이지 기본 정보 |
| GET | /api/users/me/coins | 코인 내역 (페이지네이션) |
| DELETE | /api/users/me | 회원 탈퇴 (계정 비활성화) |
| GET | /api/dashboard/home | 홈 대시보드 전체 데이터 |

#### 마이페이지 응답 (초안)

```json
GET /api/users/me
{
  "nickname": "string",
  "email": "string",
  "joinedAt": "2026-01-01",
  "totalAttendance": 42,
  "coinBalance": 650
}
```

#### 코인 내역 응답 (초안)

```json
GET /api/users/me/coins?page=0&size=20
{
  "transactions": [
    {
      "type": "STREAK_REWARD",
      "amount": 100,
      "balanceAfter": 650,
      "createdAt": "2026-06-06T10:00:00+09:00"
    }
  ],
  "totalCount": 15
}
```

#### 회원 탈퇴
- Soft Delete: User.isActive = false
- 탈퇴 시 진행 중인 챌린지 처리(B축 연동)는 통합 Phase에서 처리
- 탈퇴 후 동일 이메일 재가입 가능 여부: ERD 확정 시 결정

#### 홈 대시보드 응답 (초안)

```json
GET /api/dashboard/home
{
  "coinBalance": 650,
  "streak": {
    "current": 5,
    "max": 12
  },
  "weeklySuccessCount": 4,
  "todayStatus": "SUCCESS | RECOVERY_PENDING | FAILED | NOT_CHECKED",
  "calendar": {
    "year": 2026,
    "month": 6,
    "days": [
      { "date": "2026-06-01", "status": "SUCCESS" },
      { "date": "2026-06-02", "status": "FAILED" },
      { "date": "2026-06-06", "status": "SUCCESS" }
    ]
  }
}
```

- `weeklySuccessCount`: 이번 주(월~일) 기준 PersonalCheckIn.status = SUCCESS 개수
- `calendar.days`: 해당 월의 PersonalCheckIn 레코드 전체. 레코드 없으면 `NOT_CHECKED`
- `todayStatus`: 오늘 PersonalCheckIn.status (없으면 NOT_CHECKED)

### 완료 기준
- [ ] GET /api/users/me → 닉네임, 가입일, 누적 출석, 보유 코인 반환
- [ ] GET /api/users/me/coins → 코인 내역 페이지네이션 정상 동작
- [ ] DELETE /api/users/me → 탈퇴 후 로그인 불가 (isActive=false 체크)
- [ ] GET /api/dashboard/home → 단일 호출로 전체 대시보드 데이터 반환
- [ ] 월별 캘린더에서 각 날짜 상태 정확히 반영
- [ ] 이번 주 성공 일수 계산 정확성 (KST 기준 주 경계)

---

## 공통 고려사항

### KST 시간 처리
- 모든 날짜 계산은 `ZoneId.of("Asia/Seoul")` 기준
- DB 저장: UTC (표준), 응답: ISO 8601 with +09:00 오프셋
- `LocalDate`로 "오늘" 판단 시 반드시 KST ZoneId 사용

### 스케줄러 설계
- Spring `@Scheduled` + `@Transactional`
- 실행 시각: 매일 KST 00:01 (cron = `"1 0 0 * * *"`, `zone = "Asia/Seoul"`)
- **실행 순서 (반드시 준수)**:
  1. 만료 RecoveryMission FAILED 처리 (Phase 3)
  2. 전일 미인증자 RECOVERY_PENDING 생성 (Phase 2)
- **멱등성 구현**:
  - `PersonalCheckIn`: `UNIQUE(userId, date)` + `ON CONFLICT DO NOTHING`
  - `RecoveryMission`: `UNIQUE(personalCheckInId)` + `ON CONFLICT DO NOTHING`
  - `RecoveryMission` 상태 업데이트: `WHERE status = 'PENDING'` 조건으로 중복 처리 방지

### 에러 응답 형식 (초안)
```json
{
  "code": "DUPLICATE_CHECK_IN",
  "message": "오늘 이미 인증을 완료했습니다."
}
```

### 코인 회계 정책 (Principle 2 준수)
**결정**: CoinTransaction.amount는 **실제 차감된 금액(effective amount)**을 기록한다.
- 정상 차감: `amount = -100, balanceAfter = coinBalance - 100`
- 잔액 부족 클램핑: `amount = -coinBalance (예: -30), balanceAfter = 0`
- 이 방식으로 `SUM(CoinTransaction.amount) = User.coinBalance` 재현이 항상 성립한다.
- 명목 패널티(-100)와 실효 차감(-30)의 구분이 필요하면 ERD에 `nominalAmount` 컬럼 추가 가능.

### 개인 GPS 등록 위치
**결정**: `PersonalLocation` 독립 테이블 사용 (Principle 4 — A축 독립 보장).
- ChallengeParticipant의 GPS 필드는 ChallengeCheckIn 전용. PersonalCheckIn에서 참조 금지.
- PersonalCheckIn GPS 검증: `PersonalLocation.lat/lng/radiusMeters` vs 요청의 현재 좌표로 Haversine 계산.
- 위치 미등록 상태에서 check-in 시도 → 400 에러 반환.

---

## 미결 사항 (ERD/API 명세 확정 시 해소)

| 항목 | 현재 가정 / 결정 | 확정 필요 |
|------|-----------------|----------|
| **[미결] 스트릭 보상 반복 지급** | `% 7 == 0` → 7·14·21일마다 지급 | 제품 책임자 확인 필요 (단회 vs 반복) |
| **[결정] 개인 GPS 위치** | `PersonalLocation` 독립 테이블 | ERD 필드명·인덱스 확정 시 |
| **[결정] 코인 회계 정책** | effective amount 기록 | ERD에 nominalAmount 컬럼 추가 여부 |
| 탈퇴 후 동일 이메일 재가입 | 불가 (soft delete 이메일 유지) | ERD 확정 시 |
| Refresh Token | Phase 2 옵션 (MVP 미포함) | Phase 2 진입 시 |
| API 기본 경로 prefix | /api/** | API 명세 확정 시 |
| 코인 내역 정렬 기준 | createdAt DESC | API 명세 확정 시 |
| 이번 주 기준 (월~일 vs 일~토) | 월~일 (ISO 주) | API 명세 확정 시 |

---

*이 문서는 `pending approval` 상태입니다. ERD/API 명세 md 작성 후 필드·경로·DTO를 갱신하고, 실제 구현 전 팀 검토를 완료해야 합니다.*
