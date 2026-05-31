# Deep Interview Spec: Booster — 팀 기반 습관 챌린지 서비스

## Metadata
- Interview ID: di-booster-20260531
- Rounds: 11
- Final Ambiguity Score: 19.5%
- Type: greenfield
- Generated: 2026-05-31
- Threshold: 0.2 (20%)
- Threshold Source: default
- Initial Context Summarized: yes
- Status: PASSED

---

## Clarity Breakdown

| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal Clarity | 0.85 | 0.40 | 0.34 |
| Constraint Clarity | 0.80 | 0.30 | 0.24 |
| Success Criteria | 0.75 | 0.30 | 0.225 |
| **Total Clarity** | | | **0.805** |
| **Ambiguity** | | | **19.5%** |

---

## Topology

| Component | Status | Description | Coverage / Deferral Note |
|-----------|--------|-------------|--------------------------|
| Auth & User | active | 이메일+비밀번호 가입/로그인, 닉네임/프로필, 마이페이지 | MVP 완전 포함. 이메일 인증·비밀번호 재설정 없음 |
| Challenge & Team | active | 챌린지 생성/탐색/참여, 5:5 팀 자동 구성, 팀 vs 팀 경쟁, 종료 후 승패 정산 | MVP 완전 포함. 팀 채팅·응원 이모지 포함 |
| Check-in & Verification | active | 개인 습관 인증(스트릭·코인·복귀미션)과 팀 챌린지 인증(참여율·승패)을 별도 흐름으로 관리. MVP = GPS 전용. | AI 사진 인증은 deferred |
| Coin & Reward System | active | 예치금, 스트릭 보상, 미인증 패널티, 복귀 미션 경감, 팀 승패 정산 | MVP 완전 포함. 코인 충전/결제 없음 |
| Home Dashboard | active | 액션 허브 겸 개인 습관 대시보드 (코인, 스트릭, 캘린더, 인증하러 가기) | MVP 완전 포함 |
| Notifications | **deferred** | 푸시 알림 전체 (체크인 리마인더, 복귀미션 알림) | Phase 2. Firebase 등 푸시 인프라 미포함 |
| AI Photo Verification | **deferred** | 사진 촬영 + AI 분석(Object Detection 등)을 통한 인증 | Phase 2. AI Verification Module 미포함 |

---

## Goal

Booster는 팀 기반 습관 챌린지 서비스로, 사용자가 챌린지에 예치금 코인을 걸고 상대 팀과 참여율을 경쟁하여 이긴 팀이 상대 팀의 예치금을 가져가는 구조다. 개인 연속 출석 스트릭과 코인 인센티브로 일상 습관 지속을 돕는다.

MVP 목표: Auth, Challenge, Team, GPS Check-in, Coin 정산, Home Dashboard를 완전히 작동하는 백엔드 + 플러터 앱으로 구현하여 최초 베타 사용자에게 선보인다.

---

## Constraints

### 시스템 아키텍처
- Flutter 모바일 앱 (iOS/Android)
- Spring Boot REST API 백엔드
- PostgreSQL DB
- File/Object Storage (인증 사진 — Phase 2에서 사용)
- 코인 충전/결제 기능 없음 (MVP에서 코인은 가입 지급 + 챌린지 내 흐름으로만 발생)

### Auth & User
- 이메일 + 비밀번호 인증 전용 (소셜 로그인 Phase 2)
- 이메일 인증(verification link) 없음 — 가입 즉시 로그인 가능
- 비밀번호 재설정 없음 (Phase 2)
- 신규 가입 시 초기 코인 **500코인** 지급
- JWT 토큰 기반 인증

### Challenge & Team
- 챌린지 = 카테고리 + 제목 + 인증 방법 + 기간(day) + 예치금 코인 + 공개/비공개 + 자동/방장 승인
- 참여 신청 시 사용자는 수행할 구체적 내용 입력 (personal statement)
- 참여자가 예치금만큼 코인 차감 후 참여 확정
- 코인 부족 시 참여 신청 불가 (잔액 검증 필수)
- 공개 챌린지: 팀 찾기에서 카테고리/제목 검색으로 탐색
- 비공개 챌린지: 초대 코드 입력으로만 참여 신청 가능
- 10명이 채워지면 서버가 랜덤으로 5:5 팀을 구성하고 챌린지 자동 시작
- MVP에서 챌린지 나가기 기능 없음 (회원 탈퇴/계정 비활성화 예외 처리만)
- **탈퇴자 참여율 계산**: 탈퇴 이전 기간은 5명 기준, 이후 기간은 4명 기준으로 분리 계산. 탈퇴자 예치금은 반환 없음.
- **참여율 계산식**: `팀 전체 인증 횟수 합산 / (챌린지 기간 × 팀 인원)` (탈퇴 처리 반영)
- **동률 처리**: 참여율이 완전히 같으면 DRAW — 전원 예치금 반환, 추가 보상 없음

### Check-in & Verification (GPS)

> **핵심 설계 원칙**: 개인 습관 인증과 팀 챌린지 인증은 별도 흐름으로 관리한다.
> 동일한 GPS 인증 액션이 두 흐름 모두에 기록될 수 있지만, 각 흐름의 실패 결과와 후속 처리는 독립적으로 동작한다.

#### 공통 GPS 인증 조건
- 챌린지 인증 방법이 GPS인 경우 적용
- **위치 등록**: 참여자가 챌린지 참여 시점에 본인 인증 장소를 등록 (`latitude`, `longitude`, `radiusMeters`, `placeName`)
- 등록 단위: `challenge_member` (챌린지별 참여자별 개별 등록)
- 챌린지 시작 후 위치 변경 불가 (Phase 2에서 방장 승인/횟수 제한으로 변경 가능)
- **인증 시간**: KST 기준 00:00~23:59 — 시간 창 제한 없음
- 인증 성공 조건 = 사용자의 현재 위치가 등록된 위치 반경 내에 있을 것

#### 1. 개인 습관 인증 흐름
- 사용자가 자신의 일상 습관 수행 여부를 인증하는 흐름
- 성공 시: 개인 연속 출석 스트릭 +1, 홈 대시보드의 오늘 상태·캘린더·이번 주 성공 일수 갱신
- 미완료 시: 즉시 최종 실패 확정이 아닌 **복귀 미션 대기 상태**로 전환
- **복귀 미션**: 다음 날 00:00부터 23:59까지 수행 가능
  - 성공: 미인증일 보정 처리 + 다음 날 개인 인증 완료로 간주, 스트릭 유지, **-50코인** 차감
  - 실패: 최종 실패 확정, **-100코인** 차감 + 스트릭 초기화
- 복귀 미션 성공 후 당일 일반 인증 추가 불가 (이중 카운트 방지)

#### 2. 팀 챌린지 인증 흐름
- 팀 경쟁을 위한 인증으로, 챌린지 참여율 산정에 사용되는 흐름
- 성공 시: 해당 팀원의 오늘 인증 완료 상태 기록 → 팀 참여율, 팀 상세 화면 갱신
- 미완료 시: 해당 날짜의 팀 참여율 분자에 미포함 (팀 승패·정산에 영향)
- **팀 챌린지 인증 미완료가 개인 스트릭 초기화로 직접 이어지지 않음** (개인 습관 인증 기준으로만 관리)

- AI 사진 인증은 Phase 2

### Coin & Reward System
- 신규 가입 시 **500코인** 지급
- **스트릭 보상**: 7일 연속 달성 시 +100코인 자동 지급
- **미인증 패널티 흐름**:
  1. 당일 23:59 미인증 → 즉시 실패 확정 아님, **복귀 미션 대기 상태** 전환
  2. 다음 날 23:59 이내 복귀 미션 성공 → **-50코인** 차감 (패널티 경감), 스트릭 유지
  3. 복귀 미션도 실패 → **-100코인** 차감 + **스트릭 초기화**
- **복귀 미션 성공 시 스트릭**: 스트릭 유지 (미인증일 보정 처리, 다음 날 인증 대체)
- 복귀 미션 성공 후 당일 일반 인증 추가 불가 (이중 카운트 방지)
- **팀 승패 정산**:
  - 승팀: 전체 모금 코인(양 팀 예치금 총합) / 승팀 인원수 = 1인당 지급
  - 패팀: 예치금 소멸
  - DRAW: 전원 예치금 반환
- 코인 충전/결제 기능 없음

### Home Dashboard
- 탭 진입 시 최신 데이터 API 조회 (표준 REST pull 방식)
- 표시 항목: 보유 코인, 현재 연속 출석 일수, 최고 스트릭 기록, 이번 주 성공 일수(N/7), 월별 개인 습관 캘린더
- 캘린더: 인증 성공일, 미완료일, 오늘 상태 표시. 연속 출석 날짜에는 획득 코인 아이콘 표시
- 인증하러 가기 버튼: 인증 탭으로 이동 (오늘 인증 상태 연동)

---

## Non-Goals (MVP 제외)

- 이메일 인증 및 비밀번호 재설정
- 소셜 로그인 (Google, Apple)
- AI 사진 인증 및 AI Verification Module
- 푸시 알림 (체크인 리마인더, 복귀미션 알림)
- 코인 충전 / 결제
- 챌린지 나가기 기능 (일반)
- 인증 위치 변경 기능
- 개인 리더보드 (팀 리더보드는 포함)
- 복귀 횟수 제한 또는 고급 복귀 로직

---

## Acceptance Criteria

### Auth & User
- [ ] 이메일 + 비밀번호로 회원가입 시 500코인이 지급된 계정이 생성된다
- [ ] 가입 즉시 로그인 가능하다 (이메일 인증 없음)
- [ ] 로그인 성공 시 JWT 토큰이 반환된다
- [ ] 로그인 실패 시 적절한 에러 응답이 반환된다
- [ ] 마이페이지에서 닉네임, 가입일, 누적 출석, 보유 코인, 코인 내역, 로그아웃, 회원 탈퇴를 제공한다

### Challenge & Team
- [ ] 챌린지 생성 시 카테고리/제목/인증 방법/기간/예치금/공개여부/승인방식을 설정할 수 있다
- [ ] 참여 신청 시 예치금만큼 코인이 차감되고, 코인 부족 시 신청이 거절된다
- [ ] 공개 챌린지는 팀 찾기에서 카테고리 필터 및 제목 검색으로 탐색 가능하다
- [ ] 비공개 챌린지는 초대 코드 입력으로만 참여 신청 가능하다
- [ ] 10명이 채워지면 서버가 자동으로 5:5 팀을 구성하고 챌린지가 시작된다
- [ ] 팀 상세 화면에서 우리 팀/상대 팀의 오늘 인증 여부, 연속 출석 일수, 전체 참여율, Day N/총일수를 비교할 수 있다
- [ ] 챌린지 종료 후 참여율 계산식(합산/기간×인원)으로 승패가 결정된다
- [ ] 동률 시 DRAW로 처리되며 전원 예치금이 반환된다
- [ ] 탈퇴자 발생 시 탈퇴 전후 기간별로 분모가 재계산된다
- [ ] 승팀은 모금 코인을 인원수로 나눠 분배받고, 패팀 예치금은 소멸된다

### Check-in & Verification

**공통**
- [ ] GPS 챌린지 참여 시 위치(위도/경도/반경/장소명)를 등록할 수 있다
- [ ] 챌린지 시작 후 위치 변경은 불가하다
- [ ] KST 00:00~23:59 내에 현재 위치가 등록 반경 안이면 인증이 성공된다

**개인 습관 인증 흐름**
- [ ] 인증 성공 시 개인 연속 출석 스트릭이 +1 갱신되고 홈 대시보드 캘린더·오늘 상태가 반영된다
- [ ] 당일 23:59 미인증 시 다음 날부터 복귀 미션 대기 상태로 전환된다 (즉시 실패 확정 아님)
- [ ] 복귀 미션 성공(다음 날 23:59 이내) 시 -50코인이 차감되고 스트릭이 유지된다
- [ ] 복귀 미션 실패 시 -100코인이 차감되고 스트릭이 초기화된다
- [ ] 복귀 미션 성공 후 당일 추가 인증은 불가하다

**팀 챌린지 인증 흐름**
- [ ] 인증 성공 시 해당 팀원의 오늘 인증 완료 상태가 기록되고 팀 상세 화면에 반영된다
- [ ] 인증 미완료 시 해당 날짜의 팀 참여율 분자에 포함되지 않는다 (개인 스트릭과 독립적)

### Coin & Reward System
- [ ] 가입 시 500코인이 지급된다
- [ ] 7일 연속 인증 성공 시 +100코인이 자동 지급된다
- [ ] 코인 차감/지급 내역이 마이페이지에서 조회 가능하다
- [ ] 챌린지 예치금 코인이 잔액보다 많으면 참여 신청이 거절된다
- [ ] 팀 승패 정산이 챌린지 종료 후 자동으로 처리된다

### Home Dashboard
- [ ] 홈 탭 진입 시 최신 코인 잔액, 스트릭, 이번 주 성공 일수가 표시된다
- [ ] 월별 캘린더에서 각 날짜의 인증 상태(성공/미완료/오늘)를 확인할 수 있다
- [ ] 오늘 미인증 상태일 때 "인증하러 가기" 버튼이 활성화된다

---

## Assumptions Exposed & Resolved

| 가정 | 도전 | 결론 |
|------|------|------|
| 참여율 = 개인 성공일수 평균 | "팀 합산 / (기간×인원) vs 개인 평균" | 합산 후 평균(전체 콴 합산) 방식으로 확정 |
| 탈퇴 시 5명 기준 유지 | "탈퇴자 페널티 vs 팀 불이익" | 탈퇴 전후 기간별 분모 분리 재계산 |
| 챌린지 나가기 제공 | "MVP 복잡도" | 나가기 없음. 회원 탈퇴 예외만 처리 |
| 복귀 미션 성공 = +50코인 보너스 | "보너스 vs 경감 패널티" | -50코인 경감 방식으로 수정 확정 |
| 복귀 미션 성공 후 스트릭 초기화 | "스트릭 유지 vs 리셋" | 스트릭 유지 (미인증일 보정 처리) |
| GPS = 챌린지 단위 고정 위치 | "방장 지정 vs 참여자 개별 등록" | 참여자별 개별 위치 등록 방식으로 확정 |
| 동률 시 추가 보상 분배 | "승자 없으면 모금 코인 어떻게?" | DRAW = 전원 예치금 반환, 추가 보상 없음 |
| 인증 시간 제한 있음 | "특정 시간 창 vs 하루 종일" | KST 하루 종일 (00:00~23:59), 창 제한 없음 |
| 인증 한 번으로 챌린지+개인 동시 기록 | "단일 흐름 vs 두 개 독립 흐름" | **별도 흐름으로 분리 확정**: PersonalCheckIn(스트릭·코인·복귀미션)과 ChallengeCheckIn(팀 참여율·승패)은 독립적으로 관리. 동일 GPS 액션이 두 기록에 연결될 수 있으나 실패 결과와 후속 처리는 각각 독립 |
| 이메일 인증 필요 | "보안 vs UX" | MVP에서 이메일 인증 없음, 즉시 로그인 가능 |
| 소셜 로그인 포함 | "구현 복잡도" | MVP에서 이메일+비밀번호만, 소셜은 Phase 2 |

---

## Technical Context

### 시스템 구성
- **Flutter** 모바일 앱: 홈, 팀, 인증, 마이페이지 4탭
- **Spring Boot** 백엔드: Auth/User, Challenge, Team, CheckIn, RecoveryMission, Coin, Leaderboard, Verification (GPS) 서비스
- **PostgreSQL**: 전체 도메인 데이터 저장
- **File/Object Storage**: Phase 2 (사진 인증 시 사용)
- **AI Verification Module**: Phase 2 (사진 인증 AI 분석)
- **Push Notification**: Phase 2

### MVP 구현 우선순위 (권장)
1. **Backend 먼저**: Auth → Challenge/Team → CheckIn(GPS) → Coin 정산 순으로 핵심 비즈니스 로직 완성
2. **Frontend 병렬**: 백엔드 API 확정 후 Flutter 화면 연동
3. **AI Service**: Phase 2 (GPS 인증으로 MVP 충분)

---

## Ontology (Key Entities)

| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| User | core domain | id, email, passwordHash, nickname, joinedAt, totalAttendance, coinBalance | User participates in Challenge via ChallengeParticipant |
| Challenge | core domain | id, category, title, verificationMethod, durationDays, depositCoins, visibility, approvalType, status, startedAt, endedAt | Challenge has many ChallengeParticipants; Challenge has 2 Teams |
| Team | core domain | id, challengeId, name, participationRate, result | Team belongs to Challenge; Team has many ChallengeParticipants |
| ChallengeParticipant | core domain | id, userId, challengeId, teamId, personalStatement, gpsLat, gpsLng, gpsRadiusMeters, gpsPlaceName, activeUntil | ChallengeParticipant belongs to User, Challenge, Team |
| PersonalCheckIn | core domain | id, userId, date (KST), status (SUCCESS/RECOVERY_PENDING/FAILED), verifiedAt | PersonalCheckIn belongs to User (daily). 스트릭·코인·복귀미션의 기준 단위 |
| ChallengeCheckIn | core domain | id, participantId, date (KST), status (SUCCESS/MISSED), verifiedAt | ChallengeCheckIn belongs to ChallengeParticipant. 팀 참여율·승패 산정의 기준 단위 |
| RecoveryMission | supporting | id, personalCheckInId, deadlineAt, completedAt, status | RecoveryMission belongs to PersonalCheckIn (1:1). 개인 습관 인증 흐름에만 연결 |
| CoinTransaction | supporting | id, userId, type, amount, referenceId, createdAt | CoinTransaction belongs to User |
| Streak | supporting | userId, currentStreak, maxStreak, lastSuccessDate | Streak belongs to User (1:1) |

---

## Ontology Convergence

| Round | Entity Count | New | Changed | Stable | Stability Ratio |
|-------|-------------|-----|---------|--------|----------------|
| 1 | 7 | 7 | - | - | N/A |
| 2 | 7 | 0 | 0 | 7 | 100% |
| 3 | 7 | 0 | 1 (Participant→ChallengeParticipant) | 6 | 100% |
| 4 | 7 | 0 | 0 | 7 | 100% |
| 5-6 | 8 | 1 (RecoveryMission 상태머신) | 0 | 7 | 87.5% |
| 7-11 | 8 | 0 | 0 | 8 | 100% |

도메인 모델 Round 3 이후 안정. ChallengeParticipant의 GPS 필드 보강이 유일한 변화.

---

## Interview Transcript

<details>
<summary>Full Q&A (11 rounds)</summary>

### Round 0 — Topology
**Q:** 6개 컴포넌트(Auth, Challenge&Team, CheckIn, Coin, Home, Notifications) 토폴로지가 맞나요?
**A:** 일부 defer — Notifications 전체 + AI 사진 인증 서브기능 Phase 2로 이동

### Round 1 — Challenge & Team / Success Criteria
**Q:** 참여율 계산식 — 팀 전체 합산 / (기간 × 인원) vs 개인 평균?
**A:** 팀 전체 콴을 합산 후 평균 (합산 / (기간×인원))
**Ambiguity:** 100% → 48%

### Round 2 — Auth & User / Constraint Clarity
**Q:** 회원가입 방식 — 이메일 전용 vs 소셜 포함?
**A:** 이메일 + 비밀번호만
**Ambiguity:** 48%

### Round 3 — Check-in & Verification / Constraint Clarity
**Q:** GPS "지정 위치"를 누가, 언제 설정하나요?
**A:** 참여자가 참여 시점에 개인 위치 등록 (lat/lng/radius/placeName). 챌린지 시작 후 변경 불가.
**Ambiguity:** 45%

### Round 4 — Challenge & Team / Constraint Clarity [Contrarian]
**Q:** 탈퇴자 발생 시 참여율 분모 처리?
**A:** 탈퇴 전 기간은 5명 기준, 이후 기간은 4명 기준으로 분리. 나가기 기능 MVP 제외.
**Ambiguity:** 42%

### Round 5 — Coin / Constraint Clarity
**Q:** 신규 가입 초기 코인, 부족 시 처리?
**A:** 초기 코인 있음 + 부족 시 다른 방식 (상세 미답)

### Round 6 — Coin / Constraint Clarity [Simplifier]
**Q:** 4가지 코인 규칙 중 MVP에서 하나만 선택한다면?
**A:** 4가지 모두 MVP에 필요. 단, 복귀 미션 = 패널티 경감(-50) 방식으로 수정. 코인 충전/결제 제외.
**Ambiguity:** 38%

### Round 7 — Coin / Constraint Clarity
**Q:** 복귀 미션 성공 후 스트릭 상태?
**A:** 스트릭 유지 (미인증일 보정 처리, 다음 날 인증 대체). 이중 카운트 불가.
**Ambiguity:** 38%

### Round 8 — Home Dashboard / Goal [Ontologist]
**Q:** 홈 대시보드는 액션 허브인가, 통계 대시보드인가?
**A:** 둘 다. 오늘 인증 유도(액션 허브) + 습관 상태 요약(대시보드)
**Ambiguity:** 32%

### Round 9 — Challenge & Team / Constraint Clarity
**Q:** 동률 처리?
**A:** DRAW — 전원 예치금 반환, 추가 보상 없음, result = DRAW 저장
**Ambiguity:** 32%

### Round 10a — Auth & User / Constraint Clarity
**Q:** Auth MVP 범위 (이메일 인증, 비밀번호 재설정)?
**A:** 둘 다 없음 (가입 즉시 로그인)
**Ambiguity:** 23%

### Round 10b — Coin / Constraint Clarity
**Q:** 신규 가입 초기 코인 잔액?
**A:** 500코인
**Ambiguity:** 23%

### Round 11 — Check-in / Constraint Clarity
**Q:** 일일 인증 시간 창 (특정 시간 vs 종일)?
**A:** KST 00:00~23:59 종일, 시간 제한 없음
**Ambiguity:** 19.5% ← THRESHOLD MET

</details>

---

*Status: PASSED — 스펙 작성 완료. 실행 전 명시적 승인 필요.*
