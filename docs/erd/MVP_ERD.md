# Booster MVP ERD

> **실제 스키마 기준 문서.** `backend/src/main/resources/db/migration/V1~V16` 을 반영한다.
> 컬럼 수준의 진실은 마이그레이션 파일이고, 이 문서는 **테이블의 역할과 관계**를 설명한다.
>
> 최종 갱신: 2026-08-27 · 기준: V16

---

## 1. 테이블 목록 (19개)

### 공통

| 테이블 | 도입 | 설명 |
|---|---|---|
| `users` | V6 | 계정, 코인 잔액, 누적 출석, 구제권 보유량 |
| `coin_transactions` | V6 | 코인 변동 내역 (사유·금액·변동 후 잔액) |
| `streaks` | V6 | 누적 인증 횟수 + 최고 기록 |
| `shedlock` | V10 | 다중 인스턴스 스케줄러 분산락 |

### A축 — 개인 습관

| 테이블 | 도입 | 설명 |
|---|---|---|
| `personal_locations` | V7 (V14·V16 확장) | 인증 기준 좌표·반경 + 주간 목표 + 인증 방식 |
| `personal_check_ins` | V7 | 개인 인증 기록 |
| `personal_ai_verifications` | V16 | 개인 AI 판정 결과 |
| `weekly_evaluations` | V14 (V15 확장) | 주간 목표 채점 결과 |

### B축 — 팀 챌린지

| 테이블 | 도입 | 설명 |
|---|---|---|
| `challenges` | V1 | 챌린지 설정 |
| `challenge_participants` | V1 | 참여자 + 개별 GPS 위치 + 팀 배정 |
| `teams` | V2 (V11 확장) | 챌린지 내 경쟁 단위 (A/B) |
| `challenge_check_ins` | V3 | 팀 챌린지 인증 기록 |
| `verification_submissions` | V3 | 인증 제출 단위 |
| `gps_verification_results` | V3 | 제출별 GPS 판정 |
| `ai_verification_results` | V12 | 제출별 AI 판정 |
| `verification_decisions` | V3 (V13 확장) | 제출별 최종 판정 |
| `settlements` | V4 | 정산 결과 |
| `chat_messages` | V5 | 팀 채팅 |
| `cheer_emojis` | V5 | 응원 이모지 |

### 존재하지 않는 테이블

이전 판 ERD에 있었으나 **만들지 않았거나 삭제**했다.

| 테이블 | 사유 |
|---|---|
| `recovery_missions` | **V14에서 DROP.** 복귀 미션 폐지 → 주간 목표 모델로 전환 |
| `team_members` | 팀은 챌린지에 종속되고 참여자는 `challenge_participants.team_id` 로 배정된다. 사용자-팀 다대다가 성립하지 않음 |
| `leaderboards` | 저장하지 않고 `challenge_check_ins` 에서 계산 |
| `notifications` / `user_settings` | 미구현 (Phase 2) |
| `challenge_rules` | 규칙을 `challenges` 컬럼으로 흡수 |
| ~~`verification_logs`~~ | 통합형 초기안, 미채택 — `docs/database/BS-27-verification-schema-decision.md` |

---

## 2. 관계

```
users 1:1 streaks
users 1:N coin_transactions
users 1:1 personal_locations              ← user_id 가 PK (사용자당 1행)
users 1:N personal_check_ins              ← UNIQUE(user_id, check_in_date)
users 1:N weekly_evaluations              ← UNIQUE(user_id, week_start)
personal_check_ins 1:0..1 personal_ai_verifications   ← ON DELETE CASCADE

users 1:N challenge_participants
challenges 1:N challenge_participants
challenges 1:N teams                      ← 챌린지당 2팀 (A/B)
teams 1:N challenge_participants          ← team_id 배정 (편성 전 NULL)
challenge_participants 1:N challenge_check_ins
challenge_check_ins 1:N verification_submissions
verification_submissions 1:0..1 gps_verification_results
verification_submissions 1:0..1 ai_verification_results
verification_submissions 1:0..1 verification_decisions
challenges 1:N settlements
teams 1:N chat_messages
challenges 1:N cheer_emojis
```

**A축과 B축은 `users` 와 `coin_transactions` 에서만 만난다.** 인증 기록은 완전히 분리돼 있다.

---

## 3. 두 축의 인증 구조가 다른 이유

```
팀   check_in → submissions(N) → gps/ai_results → decisions
개인 check_in → ai_verification(1)
```

팀은 한 체크인에 여러 번 제출할 수 있어 시도 이력이 필요하다.
개인은 `UNIQUE(user_id, check_in_date)` 로 **하루 1건**이고 재시도 이력을 남길 이유가 없어,
제출 테이블 없이 체크인에 판정을 1:1로 붙였다. 팀 구조를 복제하지 않고 단순화한 것이다.

---

## 4. 테이블별 역할

### users
계정 정보와 **코인 잔액의 단일 진실 원천**. 코인은 `CoinService` 를 통해서만 변경되고
모든 변동이 `coin_transactions` 에 기록된다.

구제권 관련 컬럼(V14):

| 컬럼 | 설명 |
|---|---|
| `free_recovery_tickets` | 무료 구제권. 매월 1일 1개로 **재설정**(이월 없음) |
| `paid_recovery_tickets` | 코인으로 산 구제권. **소멸하지 않는다** |
| `tickets_granted_month` | 월 1회 지급의 멱등 키 (해당 월 1일) |

무료/구매를 나눠 세는 이유는 **소멸 규칙이 다르기** 때문이다. 소모는 무료분 → 구매분 순서다
(무료분이 어차피 월말에 사라지므로 그게 사용자에게 유리하다).

`is_active` 는 회원 탈퇴(soft delete) 플래그다. JWT 필터가 **매 요청 확인**하므로
탈퇴 후에는 발급된 토큰이 남아 있어도 즉시 차단된다.

### coin_transactions
코인 변동 이력. `type`(사유), `amount`(부호 포함), `balance_after`, `reference_id`.
**잔액 = 거래 내역 합** 이 항상 성립해야 하며, 어긋나면 코인 증발/증식이다
(`monitoring/postgres-exporter/queries.yaml` 이 이 불변식을 감시한다).

### streaks
`current_streak` 은 **누적 인증 횟수**다(연속 일수 아님). 인증할 때마다 +1 되고
날짜 갭과 무관하다. 초기화는 **주간 채점의 FAILED 확정 시에만** 일어난다.

### personal_locations
사용자당 1행(`user_id` PK). 인증 기준 좌표·반경에 더해 **A축 개인 설정 전체**를 담는다.

| 컬럼 | 도입 | 설명 |
|---|---|---|
| `lat` / `lng` / `radius_meters` / `place_name` | V7 | 인증 기준 위치 |
| `weekly_target_days` | V14 | 주간 목표 (2~7, 기본 3) |
| `pending_target_days` | V14 | 예약된 목표. 다음 달 1일에 승격 |
| `verification_type` | V16 | `GPS` / `AI` / `GPS_PHOTO_AI` |

목표를 즉시 반영하지 않고 예약하는 이유: 주 중간에 목표를 낮춰 그 주 채점을 통과하는 회피를 막는다.

> ⚠️ `radius_meters` 에 **상한이 없다**(`> 0` 만 검사). 크게 잡으면 어디서나 인증이 통과한다.
> `challenge_participants.gps_radius_meters` 도 동일. 미해결 항목.

### personal_check_ins
개인 인증 기록. `UNIQUE(user_id, check_in_date)` 로 하루 1건.

`status` 는 `SUCCESS` / `PENDING` 두 가지다(V16). `PENDING` 은 AI 인증에서 사진을 기다리는 상태다.
**"그날 안 함"은 레코드 부재로 표현**하고 별도 상태를 두지 않는다 — GPS 실패는 400으로 즉시
거절하고 레코드를 만들지 않으므로 그날 재시도가 가능하다.

### personal_ai_verifications
개인 AI 판정 (체크인과 1:1, `ON DELETE CASCADE`). 모델명·통과 여부·신뢰도·라벨·사유·`storage_key`.
이미지 원본은 `ai-service` 가 소유하고 여기서는 키로만 참조한다.

> AI가 거절하면 체크인 레코드를 삭제한다(재시도를 열어주기 위해). CASCADE로 판정 행도 함께
> 지워지므로 **거절 이력은 로그에만 남는다.**

### weekly_evaluations
주간 채점 결과. **`UNIQUE(user_id, week_start)` 가 멱등성의 핵심**으로,
스케줄러 재실행이나 다중 인스턴스에서도 한 주가 두 번 채점되지 않는다.

| `result` | 의미 |
|---|---|
| `ACHIEVED` | 목표 달성 |
| `RESCUED` | 미달이지만 구제권 소모 또는 사후 구매로 구제 |
| `PENDING_RESCUE` | 미달 + 구제권 없음. **유예 중** (스트릭·코인 그대로) |
| `FAILED` | 유예 기한 경과로 확정. 스트릭 0 + 코인 차감 |

`rescue_deadline` 은 `PENDING_RESCUE` 일 때만 채워지고, 부분 인덱스가 만료 스케줄러의 조회 경로다.

### challenges
챌린지 설정. `verification_type` 은 DB enum에 5종이 있으나 **생성 시 3종만 허용**한다
(`GPS`/`AI`/`GPS_PHOTO_AI`). 나머지는 체크인이 처리하지 못해 좀비 챌린지가 된다.
`max_participants` 는 애플리케이션에서 **10 고정**으로 검증한다.

### challenge_participants
참여자별 챌린지 소속 + **개별 GPS 위치**. `team_id` 는 편성 전 NULL이다.
챌린지 생성자(방장)도 여기 CONFIRMED로 들어가며 예치금이 동일하게 차감된다.

### teams
챌린지 내 경쟁 단위. `participation_rate` 는 표시용 캐시이고, **정산은 체크인 테이블
재계산값을 쓴다**(낙관락 재시도가 소진돼 값이 정체돼도 자가 치유된다). `version` 은 낙관락(V11).

### challenge_check_ins → submissions → results → decisions
팀 인증의 4단 구조. 제출마다 GPS/AI 판정이 남고 `verification_decisions` 가 최종 판정을 종합한다.
`decision_status`(V13)로 PENDING(AI 대기)과 확정을 구분한다.

### settlements
챌린지 종료 시 정산 결과. 실패 시 재시도 대상이 되며 `ChallengeEndScheduler` 가
ShedLock + CAS로 이중 지급을 막는다.

### shedlock
`@SchedulerLock` 이 붙은 스케줄러만 여기에 행을 남긴다.

> ⚠️ 현재 `markEndedChallenges` / `retryFailedSettlements` 만 등록된다.
> **주간 목표 3종**(`evaluateLastWeek` / `expireOverdueRescues` / `runMonthly`)은 락이 없어
> 멀티 인스턴스 구성에서 인스턴스 수만큼 중복 실행된다. 미해결 항목.

---

## 5. 멱등성·정합성 장치

| 장치 | 보장 |
|---|---|
| `UNIQUE(user_id, week_start)` | 한 주는 한 번만 채점 |
| `UNIQUE(user_id, check_in_date)` | 하루 한 번만 인증 |
| `users.tickets_granted_month` | 월 1회 무료 구제권 |
| `User` 비관락 (`findByIdForUpdate`) | 코인·스트릭 갱신을 사용자 단위로 직렬화 |
| 락 순서 `User → Streak → Coin` | 데드락 방지 (전 경로 동일) |
| `teams.version` 낙관락 | 참여율 Lost Update 방지 |
| ShedLock | 정산 스케줄러 중복 실행 방지 |

**미보장**: 구제 만료(`expireOverdueRescues`)에는 위와 같은 DB 레벨 방어가 없다.
멀티 인스턴스에서 같은 사용자에게 벌칙이 중복 적용될 수 있다.

---

## 6. Phase 2 확장 대상

| 항목 | 처리 방향 |
|---|---|
| 알림 | `notifications` + `user_settings` 신설 |
| 기프티콘 판매 | 재고·발급 테이블 필요. 코인만 받고 물건이 안 나가는 상태 방지 |
| 코인 충전·결제 | 결제 연동 |
| 상세 통계 | 체크인 기반 조회로 우선 처리 |
| 친구/팔로우, 게시글/댓글 | 소셜·커뮤니티 확장 시 |

> **상점은 테이블을 만들지 않는다.** 파는 물건이 구제권 하나이고 이미 도메인 API가 있다.
> 자세한 근거는 `docs/project-plan.md` §6.
