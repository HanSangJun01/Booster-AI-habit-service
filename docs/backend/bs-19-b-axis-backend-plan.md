# Booster B-axis 백엔드 구현 계획서 (BS-19)

> 대상: Challenge / Team / ChallengeCheckIn / Settlement 백엔드 (B-axis)
> 기반: deep-interview `di-booster-20260531` (Ambiguity 19.5%, PASSED)
> 기술 스택: Spring Boot REST API + PostgreSQL
> 상태: 계획 문서 (코드 미생성). ERD/API 스펙 확정 시 필드명·경로 조정 예정.
> 모드: ralplan consensus — **APPROVED** (Planner→Architect→Critic 합의 완료, 2026-06-04)

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
4. **상태 전이는 명시적 상태 머신으로 관리**: Challenge(RECRUITING→ONGOING→ENDED→SETTLED) 및 Team result는 정의된 전이만 허용한다.
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
  - 10번째 참여자 확정(코인 차감 완료) 시점에 같은 트랜잭션에서 셔플·팀 배정·`status=ONGOING`·`startedAt` 설정.
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
    ├── settlement       # Phase 4 (정산)
    ├── social           # Phase 4 (채팅·응원·리더보드)
    └── shared
        ├── gps          # GpsVerificationEvaluator (A/B 공유)
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

### 관련 엔티티/테이블
- `Challenge` (id, category, title, verificationMethod, durationDays, depositCoins, visibility, approvalType, status, inviteCode, startedAt, endedAt)
- `ChallengeParticipant` (id, userId, challengeId, teamId(nullable), personalStatement, gpsLat, gpsLng, gpsRadiusMeters, gpsPlaceName, status(PENDING/CONFIRMED), activeUntil)
- Challenge.status 상태머신: `RECRUITING → ONGOING → ENDED → SETTLED`

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

### API 엔드포인트 (개략, 확정 아님)
- `POST /challenges` — 생성
- `GET /challenges?category=&keyword=` — 공개 탐색
- `GET /challenges/invite/{code}` — 초대 코드 조회
- `GET /challenges/{id}` — 상세
- `POST /challenges/{id}/participants` — 참여 신청 (personalStatement + GPS 등록 포함)
- `POST /challenges/{id}/participants/{participantId}/approve` — 방장 승인

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
- Challenge `status = ONGOING`, `startedAt = now(KST)`, `endedAt = startedAt + durationDays`
- 시작 시점에 모든 참여자 GPS 위치 불변(locked) 마킹
- 시작 시점 팀 인원수 스냅샷 기록 (정산 분모 기준값)

### 관련 엔티티/테이블
- `Team` (id, challengeId, name, participationRate(cache), result(nullable), initialMemberCount)
- `ChallengeParticipant.teamId` 채워짐, `activeUntil` 초기값(=endedAt) 설정

### 서비스 클래스 & 핵심 메서드
- `TeamFormationService`
  - `formTeamsIfReady(challengeId)` — 정원 도달 검사 후 셔플·배정 (Phase 1의 확정 트랜잭션 내 동기 호출)
  - `assignTeams(participants)` — 랜덤 5:5 배정, 시드/공정성 정책
- `ChallengeLifecycleService`
  - `startChallenge(challengeId)` — 상태 전이 + 시각 설정 + GPS 잠금 + 인원 스냅샷

### API 엔드포인트 (개략)
- 별도 외부 트리거 없음 (내부 자동). 단, 디버깅/운영용 `GET /challenges/{id}/teams` 정도 제공
- `GET /challenges/{id}/teams` — 구성된 팀 조회

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

### 관련 엔티티/테이블
- `ChallengeCheckIn` (id, participantId, date(KST), status(SUCCESS/MISSED), verifiedAt)
  - **NOT PersonalCheckIn** — 별도 테이블, 별도 리포지토리
- `Team.participationRate` 캐시 컬럼 갱신
- (unique constraint: participantId + date — 일자별 1건 보장)

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

### API 엔드포인트 (개략)
- `POST /challenges/{id}/checkin` — 팀 챌린지 GPS 인증 (현재 좌표 전송)
- `GET /challenges/{id}/team-detail` — 우리 팀 vs 상대 팀 비교 뷰
- `GET /challenges/{id}/checkins/today` — 팀원별 오늘 상태

### Phase 내 의존성
- recordCheckIn → GpsVerificationEvaluator, ChallengeParticipant(등록 위치)
- TeamDetailViewService → ParticipationRateCalculator, ChallengeLifecycleService(시작 시각으로 Day N 산출)

### A-axis 인터페이스 계약 (★중요)
- **단방향, 쓰기 없음**: B-axis는 A-axis의 PersonalCheckIn을 호출하거나 수정하지 않는다.
- 동일 GPS 인증 이벤트를 두 흐름이 처리해야 한다면, **공통 진입점(Verification orchestration)** 이 A-axis `PersonalCheckInService`와 B-axis `ChallengeCheckInService`를 **각각 독립 호출**한다. 이 오케스트레이션 진입점의 소유권은 A/B 경계 협의 필요 → **Open Question**.
- 공유 컴포넌트: `GpsVerificationEvaluator` (반경 판정 로직) — A/B 공용 shared 모듈.

---

## Phase 4a — Settlement (정산)

### 목표
챌린지 종료 시 권위 있는 참여율 재계산으로 승패를 결정하고, 코인 정산(승팀 분배/패팀 소멸/DRAW 반환)을 원자적·멱등하게 처리한다.

> **Phase 4a 착수 선결 조건**: 탈퇴 일관성 계약(Open Q[탈퇴]) 해소 후 착수.

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
- **정산 멱등성**: `UPDATE challenge SET status = SETTLED WHERE id = ? AND status = ENDED` 의 affected-rows = 1 인 호출자만 코인 분배를 수행한다. affected-rows = 0 이면 즉시 no-op 반환. 상태 플래그 조회 후 전이하는 방식(check-then-set)은 race condition 위험으로 사용하지 않는다.

### 관련 엔티티/테이블 (4a)
- `Team.result` (WIN/LOSE/DRAW), `Team.participationRate` 최종 확정값
- `Settlement` (id, challengeId, computedAt, totalPool, perWinnerPayout, status) — 정산 감사 기록

### 서비스 클래스 & 핵심 메서드 (4a)
- `SettlementService`
  - `settleChallenge(challengeId)` — 원자 UPDATE(`WHERE status=ENDED`) → affected-rows=0이면 no-op 반환. affected-rows=1인 호출자만 이하 로직 수행.
  - `computeAuthoritativeRate(teamId)` — 구간 분할 재계산 (ParticipationRateCalculator 권위 모드)
  - `determineResult(teamA, teamB)` — WIN/LOSE/DRAW
  - `distributeCoins(...)` — CoinService 호출로 분배/반환 (DRAW는 활성 참여자만 대상)
- `ChallengeEndScheduler`
  - `markEndedChallenges()` — endedAt 경과 챌린지 ENDED 전이 (주기 작업, 정산 트리거와 역할 분리)

### API 엔드포인트 (개략, 4a)
- `GET /challenges/{id}/result` — 정산 결과 조회

### Phase 4a 내 의존성
- SettlementService → ParticipationRateCalculator(권위 모드), ChallengeLifecycleService(인원 스냅샷·탈퇴 이력), CoinService
- ChallengeEndScheduler → status=ENDED 전이만 담당. 정산(`settleChallenge`) 트리거 방식은 별도 결정 (Open Q[정산 트리거])

### A-axis 인터페이스 계약 — Phase 4a (★중요)
- `CoinService.credit(userId, amount, reason=SETTLEMENT_WIN | DEPOSIT_REFUND, referenceId=challengeId)` — 정산 분배·반환
- 패팀 소멸: 추가 코인 동작 없음 (참여 시 이미 차감). 감사용 소멸 기록은 B-axis Settlement에 남김
- **탈퇴 일관성 계약**: 정산 착수 전, A-axis로부터 해당 챌린지 참여자 전원의 `ChallengeParticipant.activeUntil`이 확정됨을 동기적으로 보장. 수신 방식(동기 조회·이벤트·배치)은 탈퇴 일관성 계약 Open Q에서 결정.

---

## Phase 4b — 소셜 (팀 채팅/응원 이모지/팀 리더보드)

### 목표
팀 내 소통과 참여 동기를 강화하는 소셜 기능을 제공한다. Phase 2/3 데이터에만 의존하므로 Phase 4a와 병렬 진행 가능.

### 구현 기능/작업
- 팀 채팅 (메시지 CRUD, REST pull 방식 — 푸시는 Phase 2)
- 응원 이모지 (참여자 간 이모지 반응)
- 팀 리더보드 (참여율/인증 순위)

### 관련 엔티티/테이블 (4b)
- `ChatMessage` (id, teamId, senderId, content, createdAt)
- `CheerEmoji` (id, challengeId, fromParticipantId, **toParticipantId**, emojiType, createdAt) — 팀 전체 대상(`toTeamId`)은 Phase 2. MVP는 참여자 개인 대상만.

### 서비스 클래스 & 핵심 메서드 (4b)
- `TeamChatService` — REST pull 전용 (WebSocket 제외, Phase 2)
- `CheerService` — 개인 대상 이모지 전송·조회
- `LeaderboardService`

### API 엔드포인트 (개략, 4b)
- `GET /challenges/{id}/leaderboard` — 팀 리더보드
- `GET /teams/{id}/chat?page=` — 채팅 조회 (페이지네이션)
- `POST /teams/{id}/chat` — 메시지 전송 (팀 소속 사용자만)
- `POST /challenges/{id}/cheers` — 응원 이모지 전송 (toParticipantId 대상)

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
| GPS 인증 오케스트레이션 | 공유 | 1회 GPS 액션 → A·B 흐름 각각 독립 호출 |
| `GpsVerificationEvaluator` | 공유 모듈 | 반경 판정 로직 (중복 제거) |
| 금지: PersonalCheckIn 쓰기 | — | B-axis는 절대 수행하지 않음 (불변식) |

---

## 구현 순서 & 위험 (Implementation Order)

1. **Phase 1** (Challenge + 참여/GPS) — A-axis CoinService 스텁/계약만 있으면 즉시 착수 가능. Challenge CRUD·탐색·초대코드부터 시작.
2. **Phase 2** (팀 구성) — Phase 1 참여 확정에 의존. A-axis 없이도 내부 로직 착수 가능.
3. **Phase 3** (ChallengeCheckIn) — Phase 2 팀·시작시각에 의존. **Open Q1(GPS 오케스트레이션 진입점)** 을 Phase 3 착수 전 배치 결정 필요. `ChallengeCheckInService` 구현은 이 결정 전에도 가능.
4. **Phase 4a** (정산) — Phase 3 인증 데이터에 의존. **[탈퇴 일관성 계약] (Open Q2)** 해소 필수. `CoinService.credit` 계약 확정 필요.
5. **Phase 4b** (소셜) — Phase 2/3에만 의존. **Phase 4a와 병렬 착수 가능**. 채팅(REST pull)·이모지(개인 대상) 방향 확정으로 즉시 착수 가능.

**병렬화 권장**:
- Phase 1 진행 중 CoinService 계약 + GPS 오케스트레이션 소유권(Open Q1)을 A-axis 팀과 조기 합의 → Phase 3 차단 최소화.
- Phase 3 진행 중 탈퇴 일관성 계약(Open Q2) 해소 → Phase 4a 착수 지연 방지.
- Phase 4b는 Phase 4a 결과 없이도 독립 진행 가능 → 정산 블로커에 발이 묶이지 않음.

---

## Open Questions (실행 전/중 해소 필요)

`.omc/plans/open-questions.md`에도 기록됨.

1. **GPS 인증 오케스트레이션 진입점 소유권**: 1회 GPS 액션이 PersonalCheckIn(A-axis)과 ChallengeCheckIn(B-axis) 둘 다 갱신할 때, 누가(A or B or 공유 컨트롤러) 두 서비스를 독립 호출하는가? — **Phase 3 착수 전 배치 결정 필요**. 단, B-axis `ChallengeCheckInService.recordCheckIn()` 시그니처는 이 결정과 무관하게 먼저 구현 가능.
2. **[탈퇴 일관성 계약] — Phase 4a 착수 전 필수 해소 (Open Q2+Q3 통합)**
   - **2a. 탈퇴일 구간 경계 규칙**: 탈퇴한 날(Day N)을 탈퇴 전 구간에 포함하는가, 이후 구간에 포함하는가? 정산 분모 수식에 직접 영향.
   - **2b. activeUntil 마킹 수신 방식**: A-axis 탈퇴 이벤트를 B-axis가 어떻게 수신하는가 (동기 조회·도메인 이벤트·배치)? Principle 6(모듈러 모놀리스) 전제 하에 동기 in-process 호출이 기본 권장.
   - **2c. 정산 착수 precondition**: 정산 시작 전 모든 참여자의 `activeUntil`이 확정됨을 A-axis에 동기 조회로 검증하거나, 스케줄러가 정산 전 마킹 완료를 보장하는 순서를 명시. 이 precondition이 없으면 비동기 탈퇴 이벤트 지연 시 Principle 2(결정론) 위반 가능.
3. **정산 트리거 방식**: `ChallengeEndScheduler`가 ENDED 전이만 담당하고 정산은 별도 트리거인가, 스케줄러가 정산까지 수행하는가? 두 호출자가 동시에 `settleChallenge`를 호출할 수 있는 경로를 제거하도록 트리거를 단일화 권장.
4. **팀 채팅 실시간성**: MVP는 REST pull로 충분한가, WebSocket이 필요한가? (스펙상 푸시 Phase 2 → REST pull 기본 권장)
5. **응원 이모지 대상 단위**: 참여자 개인 대상인가 팀 대상인가? (스펙 미명시 → Phase 4b 착수 전 결정)

---

## 성공 기준 (Success Criteria)

- [ ] Challenge 생성/탐색(필터·검색)/상세/초대코드 조회가 동작한다
- [ ] 참여 신청 시 잔액 검증 후 예치금이 원자적으로 차감되고, 부족 시 거절된다
- [ ] 참여 시점 GPS 위치가 등록되고 챌린지 시작 후 변경 불가하다
- [ ] 10명 확정 시 랜덤 5:5 팀이 구성되고 챌린지가 ONGOING으로 자동 시작된다 (11명 초과 방지)
- [ ] ChallengeCheckIn이 일자별 멱등하게 기록되고, PersonalCheckIn/스트릭에 절대 쓰지 않는다 (아키텍처 테스트로 검증)
- [ ] 팀 상세 뷰가 우리 팀/상대 팀 참여율·오늘 상태·Day N/총일수를 제공한다
- [ ] 정산이 구간 분할 참여율로 승패를 결정하고 멱등하게 1회 적용된다
- [ ] 승팀 분배/패팀 소멸/DRAW 반환이 CoinService를 통해 정확히 처리된다
- [ ] 팀 채팅·응원 이모지·팀 리더보드가 동작한다
