# Booster B-axis 백엔드 구현 계획서 (BS-19)

> 대상: Challenge / Team / ChallengeCheckIn / Settlement 백엔드 (B-axis)
> 기반: deep-interview `di-booster-20260531` (Ambiguity 19.5%, PASSED)
> 기술 스택: Spring Boot REST API + PostgreSQL
> 상태: 구현 완료 (BS-26, BS-27 기준 — Phase 1~4a 백엔드 구현 완료)
> 모드: ralplan consensus — **APPROVED** (Planner→Architect→Critic 합의 완료, 2026-06-04)
> Open Questions: **전체 확정 완료** (Q1–Q5, 2026-06-07)
> DB/API 동기화: `bs-22-database-design-plan.md` + `MVP_API_SPEC.md` 기준 반영 (2026-06-11)
> Spec 정합성 업데이트: BS-30 (2026-06-23) — ChallengeStatus·CheckInStatus·VerificationType·검증 테이블 구조를 ERD/API Spec과 완전 일치시킴

---

## 0. 범위와 경계 (Scope & Boundaries)

### B-axis 책임 (이 계획의 대상)
1. Challenge CRUD (생성/탐색/상세), 공개·비공개, 초대 코드
2. 참여 신청·승인 (자동/방장 승인), ChallengeParticipant, 참여 시점 GPS 위치 등록
3. 10명 충족 시 5:5 팀 자동 구성
4. ChallengeCheckIn: 팀 챌린지 GPS 인증, 팀원별 일일 인증 상태, 팀 참여율 계산, 우리 팀 vs 상대 팀 뷰, Day N / 총일수
5. Settlement: 승팀 코인 분배, 패팀 예치금 소멸, DRAW 예치금 반환
6. 팀 채팅, 응원 이모지, 팀 리더보드

### B-axis 비책임 (A-axis 소유 — 호출만 함)
- `User` 엔티티, `coinBalance` 컬럼 소유
- `CoinTransaction` 원장 기록 (B-axis는 `CoinService` 인터페이스를 **호출**만 함)
- `PersonalCheckIn`, `RecoveryMission`, `Streak` 전부 A-axis 소유

### 핵심 불변식 (CRITICAL INVARIANT) — 인증 흐름 분리
> **B-axis는 `PersonalCheckIn`에 쓰지 않으며 스트릭 초기화를 트리거하지 않는다.**

- `ChallengeCheckIn`은 오직: 팀 참여율, 승패, 예치금 정산에만 사용
- `ChallengeCheckIn` 누락은 개인 스트릭을 초기화하지 **않음** (A-axis 관심사)
- 동일 GPS 액션이 두 흐름 모두를 갱신할 수 있으나, **실패 결과는 독립적**
- 구현 가드: B-axis 모듈은 `PersonalCheckIn`/`RecoveryMission`/`Streak` 리포지토리에 대한 **쓰기 의존성을 갖지 않는다** (컴파일·아키텍처 테스트로 강제)

---

## RALPLAN-DR 요약

### Principles (설계 원칙, 3-5개)
1. **흐름 분리 불변식 우선**: ChallengeCheckIn과 PersonalCheckIn의 결합을 코드·모듈 경계로 강제한다. 어떤 편의성도 이 분리를 깨지 않는다.
2. **정산은 결정론적·재현 가능해야 한다**: 동일 입력(인증 기록 + 탈퇴 이력)에 대해 항상 동일한 참여율·승패·코인 분배 결과를 산출한다. 정산은 멱등(idempotent)하게 1회만 적용된다.
3. **코인 원장의 단일 진실 공급원은 A-axis**: B-axis는 잔액을 직접 수정하지 않고 `CoinService`를 통해서만 변동을 일으킨다. 정산 분배·차감·반환은 모두 추적 가능한 트랜잭션으로 남긴다.
4. **상태 전이는 명시적 상태 머신으로 관리**: Challenge(READY→ACTIVE→ENDED, CANCELLED) 및 Team result는 정의된 전이만 허용한다. 정산 완료는 `SettlementStatus.COMPLETED`로 표현하며 Challenge 상태를 SETTLED로 변경하지 않는다.
5. **참여 시점 스냅샷 고정**: GPS 위치, 팀 편성 시점 인원수 등 정산에 영향을 주는 값은 챌린지 시작 후 변경 불가하게 잠근다.
6. **MVP는 모듈러 모놀리스**: A-axis와 B-axis는 패키지·아키텍처 테스트로 논리 분리하되, **동일 PostgreSQL DB와 동일 스프링 트랜잭션 경계를 공유한다**. `CoinService`는 in-process 호출이므로 D1의 동기 트랜잭션이 성립하고 비관적 락 보유 중 외부 I/O 대기 문제는 발생하지 않는다. 향후 서비스 분리 시 이 전제를 재검토한다.

### Decision Drivers (의사결정 동인, 상위 3개)
1. **정확성 > 성능**: 코인이 걸린 경쟁이므로 참여율·정산 오류는 사용자 신뢰를 직접 훼손한다. 우선 정확성, 부정 방지(시점 잠금)에 투자한다.
2. **A-axis 동시 개발과의 병렬성**: A/B 두 축이 동시에 진행되므로, 인터페이스 계약을 조기에 고정해 양쪽 차단을 최소화한다.
3. **MVP 범위 절제**: 나가기 기능·위치 변경·푸시 등은 Phase 2. B-axis는 챌린지 라이프사이클과 정산의 정확한 동작에 집중한다.

### 주요 설계 선택지 (Viable Options)

#### 선택지 A — ChallengeCheckIn ↔ PersonalCheckIn 연동 방식
- **Option A1 (채택): 도메인 이벤트 기반 단방향 통지**
  - GPS 인증 1회 → `Verification` 진입점이 두 흐름을 각각 별도로 호출. B-axis는 `ChallengeCheckInService.recordCheckIn()` 만 담당. A-axis는 동일 인증 이벤트를 자신의 `PersonalCheckInService`에서 별도 구독/호출.
  - Pros: 두 흐름의 실패가 완전히 독립, 모듈 경계 명확, 불변식을 구조로 강제
  - Cons: 동일 GPS 검증 로직(반경 판정)을 공유 컴포넌트로 분리해야 함 (중복 방지)
- **Option A2 (기각): 단일 CheckIn 테이블에 type 컬럼**
  - Pros: 인증 1회 쓰기, 단순
  - Cons: 흐름 분리 불변식이 코드로 강제되지 않음 — 한쪽 실패 처리가 다른 쪽에 누출될 위험. **Principle 1 위반으로 기각.**
- **Why A1**: 핵심 불변식(흐름 분리)을 데이터·코드 구조로 보장한다. 공유 GPS 판정은 `GpsVerificationEvaluator` 유틸로 추출해 중복을 제거한다.

#### 선택지 B — 참여율·정산 계산 시점
- **Option B1 (채택): 정산 시 일괄 재계산 + 화면용 분자(인증 수) 캐시**
  - 정산(챌린지 종료) 시 인증 기록 전체를 권위 있게(authoritative) 재계산. 팀 상세 화면용 참여율은 **분자(인증 수)만 캐시**하고, **분모는 조회 시 ChallengeParticipant 활성 이력을 기반으로 실시간 계산**한다. 팀 10명 규모에서 분모 실시간 계산 비용은 무시 가능.
  - Pros: 탈퇴 발생 후 화면 참여율과 정산 참여율이 동일 로직을 따라 일치, 정산은 원천 재계산으로 정확
  - Cons: 분자 캐시 + 분모 실시간이라는 2경로 유지. 단, 정산은 항상 재계산이 진실이므로 금전 오류 없음.
- **Option B2 (기각): 매 인증마다 완전 누적 캐시만 사용**
  - Cons: 탈퇴 시 분모가 소급 변경되는 구간 분할(C1)을 즉시 누적값으로 정확히 반영 불가. 화면값≠정산값 불일치 발생. 기각.
- **Why B1**: 화면 정확성(탈퇴 후 화면=정산 일치)과 성능(분자 캐시)을 동시에 만족. "정산은 항상 권위 재계산"으로 Principle 2 보장.

#### 선택지 C — 탈퇴자 참여율 분모 처리
- **Option C1 (채택): 기간 구간 분할(period segmentation) 합산**
  - 챌린지 기간을 탈퇴 시점 기준 구간으로 분할. 각 구간마다 `(구간 일수 × 구간 인원수)`를 분모로 누적 합산. 분자는 구간 내 실제 인증 수 합산.
  - **구간 경계 규칙 (확정)**: 탈퇴 당일(Day N)까지는 참여자로 간주하여 이전 구간에 포함, Day N+1부터 잔여 인원 기준 구간 적용.
  - 예: 14일 챌린지, Day7에 1명 탈퇴 → 분모 = (7일 × 5명) + (7일 × 4명) = 35 + 28 = 63
  - Pros: 탈퇴 당일 참여 책임 유지 + 탈퇴 이후 남은 팀원 과도한 불이익 방지, 결정론적
  - Cons: 없음 (경계 규칙 확정으로 모호성 해소됨)
- **Option C2 (기각): 단순 평균 인원수 사용**
  - Cons: 스펙의 구간별 분리 요구를 위반. 기각.
- **Why C1**: 확정 스펙을 정확히 구현하는 유일한 방식.

#### 선택지 D — 5:5 팀 자동 구성 트리거
- **Option D1 (채택): 10번째 참여 확정 트랜잭션 내 동기 구성**
  - 10번째 참여자 확정(코인 차감 완료) 시점에 같은 트랜잭션에서 셔플·팀 배정·`status=ACTIVE`·`startedAt` 설정.
  - Pros: 경쟁 조건 없음, "10명=즉시 시작" 스펙 부합, 별도 스케줄러 불필요
  - Cons: 10번째 참여 요청의 응답 시간이 약간 길어짐(허용 범위)
- **Option D2 (기각): 비동기 워커/스케줄러로 주기 폴링**
  - Cons: 시작 지연, 추가 인프라, 동시성 처리 복잡. MVP 과설계.
- **Why D1**: 단순·정확·즉시성. 비관적 락(`SELECT ... FOR UPDATE on challenge row`)으로 11명 초과 참여를 방지.

---

## 1. 모듈/패키지 구조 (제안, 확정 아님)

```
backend (Spring Boot)
└── com.booster
    ├── challenge        # Phase 1
    ├── participant      # Phase 1 (참여·GPS 등록·승인)
    ├── team             # Phase 2 (팀 구성)
    ├── challengecheckin # Phase 3 (팀 인증·참여율)
    ├── settlement       # Phase 4a (정산)
    ├── social           # Phase 4b (채팅·응원·리더보드)
    └── shared
        ├── gps          # GpsVerificationEvaluator (A/B 공유)
        ├── checkin      # CheckInOrchestrator (GPS 인증 단일 진입점, A/B 공유)
        └── contract     # A-axis 인터페이스 (CoinService 등)
```

---

## Phase 1 — Challenge 라이프사이클 & 참여/GPS 등록

### 목표
챌린지를 생성·탐색·조회하고, 사용자가 예치금을 차감하며 참여 신청·승인하고, 참여 시점에 GPS 위치를 등록할 수 있게 한다. (팀 구성 직전까지)

### 구현 기능/작업
- Challenge 생성 (카테고리/제목/인증방법/기간/예치금/공개여부/승인방식)
- 공개 챌린지 탐색 (카테고리 필터 + 제목 검색)
- 비공개 챌린지: 초대 코드 생성 및 코드 기반 조회
- Challenge 상세 조회 (현재 참여 인원, 상태, Day 정보 등)
- 참여 신청: 코인 잔액 검증 → 예치금 차감 → personalStatement 입력 → GPS 위치 등록
- 승인 흐름: `approvalType = AUTO` (즉시 확정) vs `LEADER` (방장 승인 대기)
- 참여 확정 동시성 제어 (10명 정원, 11명 초과 방지)

### 관련 엔티티/테이블 (bs-22 확정 기준)

**`challenges`**
```
id, category, title, description, verification_type, duration_days, deposit_coins,
visibility, approval_type, status, invite_code, max_participants,
started_at, ended_at, created_by, created_at, updated_at
```
- status: `READY | ACTIVE | ENDED | CANCELLED`
  - `READY`: 모집 중 (구 RECRUITING)
  - `ACTIVE`: 진행 중 (구 ONGOING)
  - `ENDED`: 종료 (정산 완료 여부는 `settlements.status`로 구분)
  - `CANCELLED`: 취소됨
  - ⚠️ **SETTLED 상태 없음**: 정산 완료는 `SettlementStatus.COMPLETED` + `settlements` UNIQUE(challenge_id) 제약으로 멱등성 보장
- verification_type: `GPS | PHOTO | AI | GPS_PHOTO | GPS_PHOTO_AI` (구 free-text `verification_method`)
- visibility: `PUBLIC | PRIVATE`
- approval_type: `AUTO | LEADER`
  - `LEADER` 승인 권한자 = `created_by` 고정 (별도 `leader_id` 컬럼 없음)
- `invite_code`: UNIQUE, `PRIVATE` 챌린지에서만 사용 (PUBLIC은 NULL)
- `max_participants`: 기본 10명. 애플리케이션 레벨에서 정책 관리 (DB 고정 아님)

**`challenge_participants`**
```
id, challenge_id, user_id, team_id(nullable), personal_statement,
gps_lat, gps_lng, gps_radius_meters, gps_place_name, gps_locked,
status, active_until, joined_at, approved_at, created_at, updated_at
```
- status: `PENDING | CONFIRMED | REJECTED | CANCELLED | LEFT`
  - `PENDING`: LEADER 승인 대기
  - `CONFIRMED`: 참여 확정 (AUTO: 즉시, LEADER: 승인 후)
  - `REJECTED`: LEADER가 거절
  - `CANCELLED`: 챌린지 **시작 전** 자발적 취소
  - `LEFT`: 챌린지 **시작 후** 탈퇴 (회원 탈퇴 등)
- UNIQUE (challenge_id, user_id)
- `gps_locked`: Phase 2 팀 구성 시 true로 변경

Challenge.status 상태머신: `READY → ACTIVE → ENDED` (취소 시 `→ CANCELLED`)

### 서비스 클래스 & 핵심 메서드 (개념 수준)
- `ChallengeService`
  - `createChallenge(...)` — 생성, 비공개 시 초대코드 발급
  - `searchPublicChallenges(category, keyword, paging)`
  - `getChallengeByInviteCode(code)`
  - `getChallengeDetail(challengeId)`
- `ParticipationService`
  - `requestParticipation(userId, challengeId, personalStatement, gpsRegistration)` — 잔액 검증 + 코인 차감(CoinService 호출) + 위치 등록 + 정원/승인 분기
  - `approveParticipation(leaderId, participantId)` — LEADER 승인형
  - `confirmParticipation(...)` — 확정 시 정원 체크 (10명 도달 시 Phase 2 팀 구성 트리거로 위임)
- `InviteCodeGenerator` — 충돌 없는 코드 생성

### API 엔드포인트 (MVP_API_SPEC 기준)
- `POST /api/challenges` — 생성 (personalStatement + GPS 등록 없이 챌린지 기본 정보만)
- `GET /api/challenges/{challengeId}` — 상세 (스펙 확정)
- `GET /api/challenges?category=&keyword=` — 공개 탐색
- `GET /api/challenges/invite/{code}` — 초대 코드 조회
- `POST /api/challenges/{challengeId}/participants` — 참여 신청 (personalStatement + GPS 등록 포함, 스펙 확정)
- `DELETE /api/challenges/{challengeId}/participants/{userId}` — 참여 취소 (챌린지 시작 전, 스펙 확정)
- `POST /api/challenges/{challengeId}/participants/{participantId}/approve` — 방장 승인

> **API 스펙 충돌 주의**: MVP_API_SPEC은 `POST /api/teams/{teamId}/challenges`로 챌린지를 팀 하위 리소스로 정의하지만, bs-19/project-plan은 챌린지-first 모델(챌린지 → 10명 모집 → 팀 자동 구성)을 따른다. 위 경로는 bs-19 모델 기준으로 유지하며, A-axis 팀과 경로 최종 합의 필요.

### Phase 내 의존성
- ParticipationService → ChallengeService (상태·정원 조회)
- 참여 확정 → Phase 2 팀 구성 진입점 (인터페이스로 분리해 Phase 2 미완 시에도 컴파일 가능)

### A-axis 인터페이스 계약
- `CoinService.deduct(userId, amount, reason=CHALLENGE_DEPOSIT, referenceId=challengeId)` — 잔액 부족 시 도메인 예외, 부분 차감 없음(원자적)
- `CoinService.getBalance(userId)` — 신청 전 검증용 (또는 deduct가 검증 포함)
- `UserService.exists(userId)` / 활성 상태 조회

---

## Phase 2 — 5:5 팀 자동 구성 & GPS 위치 잠금

### 목표
10명 참여 확정 시 서버가 랜덤 5:5 팀을 구성하고 챌린지를 자동 시작하며, 모든 참여자의 GPS 위치를 잠근다.

### 구현 기능/작업
- 10명 충족 감지 → 랜덤 셔플 → 2개 팀(5명씩) 배정
- Team 엔티티 2개 생성, 각 ChallengeParticipant에 teamId 할당
- Challenge `status = ACTIVE`, `startedAt = now(KST)`, `endedAt = startedAt + durationDays`
- 시작 시점에 모든 참여자 GPS 위치 불변(locked) 마킹
- 시작 시점 팀 인원수 스냅샷 기록 (정산 분모 기준값)

### 관련 엔티티/테이블 (bs-22 확정 기준)

**`teams`**
```
id, challenge_id, name, participation_rate(cache), result(nullable),
initial_member_count, created_at, updated_at
```
- result: `WIN | LOSE | DRAW | NULL(진행 중)`
- `initial_member_count = 5` 고정 (5:5 구성)
- UNIQUE (challenge_id, name)
- `participation_rate`: 화면용 캐시. 정산 시에는 원본 재계산값 사용.

**`challenge_participants` 변경 사항 (팀 구성 완료 후)**
```
team_id       → assigned_team_id
gps_locked    → true
active_until  → challenge.ended_at
```

### 서비스 클래스 & 핵심 메서드
- `TeamFormationService`
  - `formTeamsIfReady(challengeId)` — 정원 도달 검사 후 셔플·배정 (Phase 1의 확정 트랜잭션 내 동기 호출)
  - `assignTeams(participants)` — 랜덤 5:5 배정, 시드/공정성 정책
- `ChallengeLifecycleService`
  - `startChallenge(challengeId)` — 상태 전이 + 시각 설정 + GPS 잠금 + 인원 스냅샷

### API 엔드포인트 (개략)
- 별도 외부 트리거 없음 (내부 자동). 단, 디버깅/운영용 `GET /api/challenges/{challengeId}/teams` 정도 제공
- `GET /api/challenges/{challengeId}/teams` — 구성된 팀 조회

### Phase 내 의존성
- TeamFormationService ← Phase 1 ParticipationService.confirmParticipation 가 호출
- ChallengeLifecycleService → Phase 3/4가 의존 (시작·종료 시각, 인원 스냅샷)

### A-axis 인터페이스 계약
- 없음 (코인 변동 없는 순수 B-axis 내부 로직). User 활성 상태만 참조 가능.

---

## Phase 3 — ChallengeCheckIn (팀 인증 & 참여율)

### 목표
GPS 기반 팀 챌린지 인증을 기록하고, 팀 참여율을 계산하며, 우리 팀 vs 상대 팀 비교 뷰(Day N/총일수 포함)를 제공한다. **개인 스트릭/PersonalCheckIn에는 절대 쓰지 않는다.**

### 구현 기능/작업
- 팀 챌린지 GPS 인증 기록 (현재 위치가 등록 반경 내인지 판정)
- 일자(KST) 기준 멱등 처리: 같은 날 중복 인증은 1건으로 (SUCCESS 유지)
- 인증 시간: KST 00:00~23:59 (시간 창 제한 없음)
- 팀원별 오늘 인증 상태 조회
- 팀 참여율 점진 캐시 갱신 (화면용)
- 팀 상세 뷰: 우리 팀/상대 팀의 오늘 인증 여부·연속 출석·전체 참여율·Day N/총일수

### 관련 엔티티/테이블 (bs-22 확정 기준)

**`challenge_check_ins`** — **NOT `check_ins`(A-axis)** — 별도 테이블, 별도 리포지토리
```
id, participant_id, challenge_id, team_id, check_in_date(DATE),
status, verified_at, created_at, updated_at
```
- status: `SUCCESS | FAILED | LATE_SUCCESS | PENDING`
  - `PENDING`: 인증 제출 직후 판정 대기 상태 (신규)
  - `SUCCESS`: GPS 반경 내 인증 성공
  - `LATE_SUCCESS`: 지연 성공 (시간 창 이후 인증, 향후 사용)
  - `FAILED`: GPS 반경 외 판정 실패
  - **MISSED = 레코드 미생성**. 참여율 계산 시 SUCCESS 레코드 부재로 미수행 판단.
- `check_in_date`: `DATE` 타입. DB 타임존 의존 없이 애플리케이션에서 KST 기준 `LocalDate` 계산 후 저장.
- ⚠️ `current_lat`, `current_lng` **제거됨** (BS-27): 인증 시점 좌표는 `verification_submissions`로 이동
- `challenge_id`, `team_id`: 정규화 관점에서 `participant_id`로 추적 가능하나 조회 성능·쿼리 단순성을 위해 중복 저장.
- UNIQUE (participant_id, check_in_date) — 챌린지별 하루 1건 보장

**`verification_submissions`** — BS-27 검증 요청 이력 (challenge_check_ins 1:N)
```
id, check_in_id, submitted_at, submitted_lat(DOUBLE PRECISION), submitted_lng(DOUBLE PRECISION),
attempt_number, created_at
```
- 하나의 체크인에 대한 인증 시도를 순번별로 기록

**`gps_verification_results`** — GPS 판정 결과 (verification_submissions 1:1)
```
id, submission_id(UNIQUE), target_lat(DOUBLE PRECISION), target_lng(DOUBLE PRECISION),
radius_meters(INTEGER), distance_meters(NUMERIC 10,2), is_within_radius(BOOLEAN), created_at
```
- `distance_meters`: 정밀 소수 계산 (BigDecimal, NUMERIC 10,2)
- GPS 이외 인증 방식(PHOTO, AI 등)은 별도 result 테이블로 확장 예정

**`verification_decisions`** — 최종 판정 (verification_submissions 1:1)
```
id, submission_id(UNIQUE), final_passed(BOOLEAN), failure_reason(VARCHAR 200), created_at
```
- MVP: GPS 결과만으로 최종 판정 (`GPS_OUT_OF_RADIUS` 등)

`teams.participation_rate` 캐시 컬럼 갱신 (분자 기준)

### 서비스 클래스 & 핵심 메서드
- `ChallengeCheckInService`
  - `recordCheckIn(participantId, currentLat, currentLng, atKst)` — GPS 반경 판정 → SUCCESS 기록(멱등) → 팀 참여율 캐시 갱신
  - `getTeamDailyStatus(teamId, date)` — 팀원별 오늘 상태
  - **PersonalCheckIn/Streak 리포지토리 의존성 없음 (불변식 가드)**
- `ParticipationRateCalculator`
  - `currentRate(teamId)` — 캐시 또는 현재까지 누적 기준 (화면용)
- `TeamDetailViewService`
  - `getTeamComparison(challengeId, requesterId)` — 우리 팀/상대 팀, Day N/총일수, 참여율 비교
- `GpsVerificationEvaluator` (shared.gps)
  - `isWithinRadius(registered, current)` — A/B 공유, 중복 제거

### API 엔드포인트 (MVP_API_SPEC 기준)
- `POST /api/challenges/{challengeId}/check-ins` — 팀 챌린지 GPS 인증 (현재 좌표 전송, 스펙 확정)
- `GET /api/challenges/{challengeId}/check-ins` — 팀 체크인 목록 조회 (스펙 확정)
- `GET /api/challenges/{challengeId}/check-ins?date={yyyyMMdd}` — 특정 날짜 팀원별 인증 상태 (date 파라미터 방식 검토)
- `GET /api/challenges/{challengeId}/team-detail` — 우리 팀 vs 상대 팀 비교 뷰 (스펙 미포함 — B-axis 추가 API)

### Phase 내 의존성
- recordCheckIn → GpsVerificationEvaluator, ChallengeParticipant(등록 위치)
- TeamDetailViewService → ParticipationRateCalculator, ChallengeLifecycleService(시작 시각으로 Day N 산출)

### A-axis 인터페이스 계약 (★중요)
- **단방향, 쓰기 없음**: B-axis는 A-axis의 PersonalCheckIn을 호출하거나 수정하지 않는다.
- **GPS 오케스트레이션 진입점 (확정)**: `shared.checkin.CheckInOrchestrator`가 1회 GPS 액션을 수신해 A-axis `PersonalCheckInService`와 B-axis `ChallengeCheckInService`를 각각 독립 호출한다. 두 흐름의 성공·실패는 완전히 독립이며, ChallengeCheckIn 실패가 PersonalCheckIn에 영향을 주지 않는다.
- 공유 컴포넌트: `GpsVerificationEvaluator` (반경 판정 로직) — A/B 공용 shared 모듈. `CheckInOrchestrator`가 내부에서 사용.

---

## Phase 4a — Settlement (정산)

### 목표
챌린지 종료 시 권위 있는 참여율 재계산으로 승패를 결정하고, 코인 정산(승팀 분배/패팀 소멸/DRAW 반환)을 원자적·멱등하게 처리한다.

> **Phase 4a 착수 선결 조건**: 탈퇴 일관성 계약(Q2b/Q2c) 및 정산 트리거(Q3) 확정 완료 — 착수 가능.

### 구현 기능/작업
- 챌린지 종료 감지 (`endedAt` 도달) → `status = ENDED` (스케줄러 담당, Phase 4a 내에서 결정)
- 탈퇴 일관성 확정: 정산 시작 전 A-axis로부터 모든 참여자의 `activeUntil`이 확정된 상태임을 동기적으로 검증
- 권위 있는 참여율 재계산 (구간 분할: 탈퇴 전후 분모 분리, 탈퇴일 경계 규칙 적용)
- 승패 판정: 참여율 비교, 완전 동률 시 DRAW (정수 분자/분모 기준 비교로 부동소수 오차 방지)
- 코인 정산:
  - 승팀: `(양 팀 예치금 총합) / 승팀 인원수` = 1인당 지급 (CoinService 호출)
  - 패팀: 예치금 소멸 (지급 없음 — 참여 시 이미 차감됨. 감사 기록은 Settlement 테이블에 남김)
  - DRAW: **활성 참여자(탈퇴자 제외)에게만** 본인 예치금 반환 (CoinService 호출). 탈퇴자는 DRAW 여부와 무관하게 반환 없음.
  - 탈퇴자: 승·패·DRAW 모두 예치금 반환 없음. 탈퇴자 예치금은 별도 재분배 없이 소멸 처리한다 (DRAW 시 활성자의 분배 풀에 합산되지 않는다).
- **정산 멱등성**: `settlements` 테이블의 `SettlementStatus.COMPLETED` 레코드 존재 여부로 중복 실행을 방지한다. `UNIQUE(challenge_id)` DB 제약이 이중 실행 시 예외를 발생시키며, 서비스 레이어에서 `findByChallengeId(...).filter(COMPLETED).isPresent()` 게이트로 no-op 반환한다. Challenge 상태를 SETTLED로 변경하지 않는다(ChallengeStatus에 SETTLED 없음).

### 관련 엔티티/테이블 (bs-22 확정 기준)

**`teams` 변경 사항 (정산 완료 후)**
```
result              → 'WIN' | 'LOSE' | 'DRAW'
participation_rate  → 최종 재계산값으로 확정
```

**`settlements`** — 챌린지 단위 정산 감사 기록
```
id, challenge_id, computed_at, total_pool, per_winner_payout, status,
winner_team_id, loser_team_id, draw, created_at, updated_at
```
- UNIQUE (challenge_id)
- status: `PENDING | COMPLETED | FAILED`
- `draw = true` 시 `winner_team_id`, `loser_team_id`는 NULL
- `per_winner_payout`: 정수 코인, 소수점 발생 시 내림(floor) 처리. 잔액(remainder) 귀속 기준 미정 (bs-22 Open Question 12.5)
- 재시도 전략: `status = FAILED` 시 DELETE+INSERT 아닌 기존 레코드 `UPDATE`
- 개별 참여자 지급 이력이 필요해지면 `settlement_participants` 테이블 확장 (bs-22 8.4)

**정산 완료 후 Challenge 상태**: Challenge.status는 `ENDED`를 유지한다. 정산 완료 여부는 `settlements.status = COMPLETED`로 확인한다.

### 서비스 클래스 & 핵심 메서드 (4a)
- `SettlementService`
  - `settleChallenge(challengeId)` — `SettlementStatus.COMPLETED` 레코드 존재 시 즉시 no-op 반환(멱등 게이트). 없으면 참여율 재계산 → 승패 판정 → 코인 분배 수행.
  - `computeAuthoritativeRate(teamId)` — 구간 분할 재계산 (ParticipationRateCalculator 권위 모드)
  - `determineResult(teamA, teamB)` — WIN/LOSE/DRAW
  - `distributeCoins(...)` — CoinService 호출로 분배/반환 (DRAW는 활성 참여자만 대상)
- `ChallengeEndScheduler`
  - `markEndedChallenges()` — `ACTIVE` 챌린지 중 `endedAt` 경과한 것을 `ENDED`로 전이한 뒤, 동일 실행에서 `SettlementService.settleChallenge()`를 호출. 정산 트리거 경로는 이 스케줄러 단일. 멱등 보장으로 수동 재시도 API도 동일 settleChallenge() 재사용 가능.

### API 엔드포인트 (MVP_API_SPEC 기준, 4a)
- `GET /api/challenges/{challengeId}/result` — 정산 결과 조회 (B-axis 추가 API)

### Phase 4a 내 의존성
- SettlementService → ParticipationRateCalculator(권위 모드), ChallengeLifecycleService(인원 스냅샷·탈퇴 이력), CoinService
- ChallengeEndScheduler → ENDED 전이 + settleChallenge() 직접 호출. 단일 트리거 경로 (확정)

### A-axis 인터페이스 계약 — Phase 4a (★중요)
- `CoinService.credit(userId, amount, reason=SETTLEMENT_WIN | DEPOSIT_REFUND, referenceId=challengeId)` — 정산 분배·반환
- 패팀 소멸: 추가 코인 동작 없음 (참여 시 이미 차감). 감사용 소멸 기록은 B-axis Settlement에 남김
- **탈퇴 일관성 계약 (확정)**: A-axis 탈퇴 API가 `User.isActive = false` 처리와 동일 트랜잭션에서 `ChallengeParticipant.activeUntil`을 즉시 기록 (동기 in-process 호출, Q2b 확정). 정산 로직은 DB에 있는 `activeUntil` 값을 그대로 읽어 구간 분할 계산. `activeUntil IS NULL`인 참여자는 챌린지 `endedAt`까지 활성으로 간주 (Q2c 확정).

---

## Phase 4b — 소셜 (팀 채팅/응원 이모지/팀 리더보드)

### 목표
팀 내 소통과 참여 동기를 강화하는 소셜 기능을 제공한다. Phase 2/3 데이터에만 의존하므로 Phase 4a와 병렬 진행 가능.

### 구현 기능/작업
- 팀 채팅 (메시지 CRUD, REST pull 방식 — 푸시는 Phase 2)
- 응원 이모지 (참여자 간 이모지 반응)
- 팀 리더보드 (참여율/인증 순위)

### 관련 엔티티/테이블 (bs-22 확정 기준, 4b)

**`chat_messages`**
```
id, team_id, sender_id, content, created_at, updated_at, deleted_at
```
- `deleted_at`: 소프트 딜리트 (NULL이면 유효 메시지)
- content NOT NULL, team_id NOT NULL, sender_id NOT NULL

**`cheer_emojis`**
```
id, challenge_id, from_participant_id, to_participant_id, emoji_type, created_at
```
- `from_participant_id <> to_participant_id` 제약
- 팀 전체 대상(`to_team_id`)은 Phase 2. MVP는 참여자 개인 대상만.

### 서비스 클래스 & 핵심 메서드 (4b)
- `TeamChatService` — REST pull 전용 (WebSocket 제외, Phase 2)
- `CheerService` — 개인 대상 이모지 전송·조회
- `LeaderboardService`

### API 엔드포인트 (MVP_API_SPEC 기준, 4b)
- `GET /api/challenges/{challengeId}/leaderboards?type=PERSONAL|TEAM` — 리더보드 조회 (스펙 확정)
- `GET /api/teams/{teamId}/chat?page=` — 채팅 조회 (페이지네이션)
- `POST /api/teams/{teamId}/chat` — 메시지 전송 (팀 소속 사용자만)
- `POST /api/challenges/{challengeId}/cheers` — 응원 이모지 전송 (to_participant_id 대상)

### Phase 4b 내 의존성
- Phase 2 팀 구성, Phase 3 인증 데이터에만 의존. Phase 4a(정산) 완료 불필요 → 병렬 착수 가능.

### A-axis 인터페이스 계약 — Phase 4b
- User 프로필 조회 (닉네임·아바타) 외 없음.

---

## 인터페이스 계약 종합 (A-axis ↔ B-axis)

| 계약 | 방향 | 설명 |
|------|------|------|
| `CoinService.deduct` | B→A | 참여 시 예치금 차감 (원자적, 잔액 부족 예외) |
| `CoinService.credit` | B→A | 정산 분배/반환 (referenceId로 추적) |
| `CoinService.getBalance` | B→A | 신청 전 잔액 검증 |
| User 활성/탈퇴 이벤트 | A→B | 탈퇴 시 participant.activeUntil 마킹 트리거 |
| GPS 인증 오케스트레이션 | 공유 | `CheckInOrchestrator`(shared.checkin)가 A·B 흐름 각각 독립 호출 (확정) |
| `GpsVerificationEvaluator` | 공유 모듈 | 반경 판정 로직 (중복 제거) |
| 금지: PersonalCheckIn 쓰기 | — | B-axis는 절대 수행하지 않음 (불변식) |

---

## DB/API 정합성 주의 사항

### 미결 Open Questions (bs-22 기준, B-axis 영향 있음)

| # | 항목 | 내용 | 영향 Phase |
|---|------|------|-----------|
| OQ-DB-1 | A-axis User FK | `user_id`, `created_by`, `sender_id`를 `users.id`에 실제 FK로 걸 것인가, 논리 참조만 사용할 것인가 | Phase 1 |
| OQ-DB-2 | GPS 좌표 저장 | `challenge_check_ins.current_lat/lng` 저장 여부, 소수점 정밀도, 보관 기간/마스킹 정책 | Phase 3 |
| OQ-DB-3 | remainder 귀속 | `per_winner_payout` 소수점 내림 후 잔액 코인 귀속 기준 (플랫폼 수수료 / 임의 1명 / 소각) | Phase 4a |
| OQ-DB-4 | teams 테이블 명칭 | 일반 사용자 팀(`teams`)과 챌린지 5:5 팀의 역할이 충돌하는 경우 `challenge_teams`로 분리 검토 | Phase 2 |

### API 스펙 불일치 항목

| 항목 | MVP_API_SPEC | bs-19 계획 | 비고 |
|------|-------------|-----------|------|
| 챌린지 생성 경로 | `POST /api/teams/{teamId}/challenges` | `POST /api/challenges` | 팀-first vs 챌린지-first 모델 충돌. A-axis 팀과 경로 합의 필요 |
| 팀 상세 비교 뷰 | 스펙 미포함 | `GET /api/challenges/{challengeId}/team-detail` | B-axis 추가 API로 스펙에 반영 필요 |
| 채팅/응원 API | 스펙 미포함 | `/api/teams/{teamId}/chat`, `/api/challenges/{challengeId}/cheers` | Phase 4b에서 스펙 추가 필요 |
| 정산 결과 조회 | 스펙 미포함 | `GET /api/challenges/{challengeId}/result` | B-axis 추가 API로 스펙에 반영 필요 |

### Flyway 마이그레이션 현황 (적용 완료)

```
V1__create_challenge_and_participant_tables.sql   → Phase 1 (적용 완료)
V2__create_team_tables.sql                        → Phase 2 (적용 완료)
V3__create_challenge_check_in_tables.sql          → Phase 3 (적용 완료)
V4__create_settlement_tables.sql                  → Phase 4a (적용 완료)
V5__create_social_tables.sql                      → Phase 4b (적용 완료)
V6__align_with_spec.sql                           → BS-30 Spec 정합성 (적용 완료, 2026-06-23)
V7__fix_gps_column_types.sql                      → GPS 컬럼 DOUBLE PRECISION 변환 (적용 완료, 2026-06-23)
```

**V6 주요 변경 내용**:
- `challenges.status` 값 마이그레이션: RECRUITING→READY, ONGOING→ACTIVE, SETTLED→ENDED
- `challenges.status` 제약: `('READY','ACTIVE','ENDED','CANCELLED')`
- `challenges.verification_method` 컬럼 → `verification_type` 리네임, 값 정규화
- `challenge_check_ins.status` 제약: `('SUCCESS','FAILED','LATE_SUCCESS','PENDING')`
- `challenge_check_ins.current_lat`, `current_lng` 컬럼 제거
- `verification_submissions`, `gps_verification_results`, `verification_decisions` 테이블 신규 생성

**V7 주요 변경 내용**:
- `challenge_participants.gps_lat`, `gps_lng`: `DECIMAL(10,7)` → `DOUBLE PRECISION`
  (Hibernate 6.6+가 `Double` 필드에 `float(53)` 타입을 기대하므로 스키마 검증 통과 필요)

---

## 구현 순서 & 위험 (Implementation Order)

1. **Phase 1** (Challenge + 참여/GPS) — A-axis CoinService 스텁/계약만 있으면 즉시 착수 가능. Challenge CRUD·탐색·초대코드부터 시작.
2. **Phase 2** (팀 구성) — Phase 1 참여 확정에 의존. A-axis 없이도 내부 로직 착수 가능.
3. **Phase 3** (ChallengeCheckIn) — Phase 2 팀·시작시각에 의존. `CheckInOrchestrator` 구조 확정(Q1)으로 차단 없음. `ChallengeCheckInService` 및 `CheckInOrchestrator` 함께 구현.
4. **Phase 4a** (정산) — Phase 3 인증 데이터에 의존. 탈퇴 일관성 계약(Q2b/Q2c) 및 정산 트리거(Q3) 모두 확정. `CoinService.credit` 계약 확정 후 착수.
5. **Phase 4b** (소셜) — Phase 2/3에만 의존. **Phase 4a와 병렬 착수 가능**. 채팅(REST pull)·이모지(개인 대상) 방향 확정으로 즉시 착수 가능.

**병렬화 권장**:
- Phase 1 진행 중 A-axis 팀과 CoinService 계약 조기 확정 → Phase 1 말미 참여 확정 로직 차단 최소화.
- Phase 3 진행 중 Phase 4b 소셜 기능 병렬 착수 가능 (정산 대기 불필요).
- Phase 4a와 Phase 4b 완전 독립 — 정산 블로커가 소셜 기능을 막지 않음.

---

## Resolved Questions (전체 확정 완료 — 2026-06-07)

`.omc/plans/open-questions.md`에 상세 기록됨.

1. **[Q1] GPS 인증 오케스트레이션 진입점** — `shared.checkin.CheckInOrchestrator`가 진입점. A-axis `PersonalCheckInService`와 B-axis `ChallengeCheckInService`를 각각 독립 호출. `GpsVerificationEvaluator` 공유 사용.
2. **[Q2a] 탈퇴일 구간 경계 규칙** — Day N 포함(이전 구간), Day N+1부터 잔여 인원 구간. 예) 14일 챌린지 Day7 탈퇴 → 분모 = (7×5)+(7×4) = 63.
3. **[Q2b] activeUntil 마킹 수신 방식** — A-axis 탈퇴 API 동일 트랜잭션에서 동기 in-process 마킹.
4. **[Q2c] 정산 precondition** — Q2b에 의해 탈퇴 시 즉시 기록. `activeUntil IS NULL` = 챌린지 종료일까지 활성.
5. **[Q3] 정산 트리거 방식** — `ChallengeEndScheduler` 단일 경로. ENDED 전이 후 동일 실행에서 `settleChallenge()` 호출.
6. **[Q4] 팀 채팅 실시간성** — MVP는 REST pull (페이지네이션). WebSocket Phase 2.
7. **[Q5] 응원 이모지 대상 단위** — MVP는 개인 대상(`toParticipantId`). 팀 전체 Phase 2.

---

## 성공 기준 (Success Criteria)

- [ ] Challenge 생성/탐색(필터·검색)/상세/초대코드 조회가 동작한다
- [ ] 참여 신청 시 잔액 검증 후 예치금이 원자적으로 차감되고, 부족 시 거절된다
- [ ] 참여 시점 GPS 위치가 등록되고 챌린지 시작 후 변경 불가하다
- [ ] 10명 확정 시 랜덤 5:5 팀이 구성되고 챌린지가 ACTIVE로 자동 시작된다 (11명 초과 방지)
- [ ] ChallengeCheckIn이 일자별 멱등하게 기록되고, PersonalCheckIn/스트릭에 절대 쓰지 않는다 (아키텍처 테스트로 검증)
- [ ] 팀 상세 뷰가 우리 팀/상대 팀 참여율·오늘 상태·Day N/총일수를 제공한다
- [ ] 정산이 구간 분할 참여율로 승패를 결정하고 멱등하게 1회 적용된다
- [ ] 승팀 분배/패팀 소멸/DRAW 반환이 CoinService를 통해 정확히 처리된다
- [ ] 팀 채팅·응원 이모지·팀 리더보드가 동작한다
