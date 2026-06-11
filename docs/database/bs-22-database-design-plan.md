# Booster 데이터베이스 설계 계획서

> 대상: Booster B-axis 백엔드 기능을 지원하기 위한 데이터베이스 설계  
> 기준 문서: `Booster B-axis 백엔드 구현 계획서 (BS-19)`  
> 기술 스택: PostgreSQL + Spring Data JPA + Flyway  
> 상태: 계획 문서  
> 목적: 백엔드 구현 Phase에 맞춰 필요한 테이블, 제약조건, 관계, 마이그레이션 범위를 단계적으로 정의한다.

---

## 0. 문서 목적

본 문서는 Booster 서비스의 B-axis 백엔드 구현 계획에 맞춰 데이터베이스 설계 범위와 Phase별 구축 계획을 정리하기 위한 문서이다.

백엔드 구현 계획서가 Challenge / Team / ChallengeCheckIn / Settlement 흐름을 Phase 단위로 나누고 있으므로, 데이터베이스 또한 동일한 Phase 기준으로 설계한다.

이를 통해 다음을 명확히 한다.

1. 각 Phase에서 필요한 테이블과 컬럼 범위
2. 테이블 간 관계와 외래키 구조
3. 상태값과 제약조건
4. Flyway 마이그레이션 적용 순서
5. MVP 범위와 이후 확장 범위의 구분

---

## 1. 설계 원칙

### 1.1 백엔드 Phase와 DB Phase를 일치시킨다

백엔드 구현 계획서의 Phase를 기준으로 데이터베이스 설계도 동일하게 분리한다.

- Phase 1: Challenge 라이프사이클 & 참여/GPS 등록
- Phase 2: 5:5 팀 자동 구성 & GPS 위치 잠금
- Phase 3: ChallengeCheckIn 팀 인증 & 참여율
- Phase 4a: Settlement 정산
- Phase 4b: Social 팀 채팅/응원/리더보드

DB 설계는 백엔드 구현보다 앞서거나 동시에 진행되되, 각 Phase에서 실제로 필요한 테이블만 우선 확정한다.

#### approval_type 동작 기준

- `approval_type = AUTO`: 참여 신청 즉시 선착순으로 CONFIRMED 처리된다. 정원 도달 시까지 자동 승인된다.
- `approval_type = LEADER`: MVP에서 승인 권한자는 `challenges.created_by`로 고정한다. 별도 리더 위임 기능은 MVP 범위 외다. `challenges` 테이블에 별도 `leader_id` 컬럼을 두지 않는다.

---

### 1.2 MVP와 Full ERD를 분리한다

초기 V1 스키마에는 MVP 동작에 필요한 핵심 테이블만 포함한다.

기부 챌린지 고도화, AI 인증 상세 결과, 통계/리포트, 푸시 알림 로그 등은 Full ERD에는 포함할 수 있으나, 초기 Flyway V1에는 포함하지 않는다.

이를 통해 초기 개발 범위가 과도하게 커지는 것을 방지하고, 기능 확장 시점에 맞춰 V2, V3 마이그레이션으로 점진적으로 추가한다.

---

### 1.3 ChallengeCheckIn과 PersonalCheckIn은 분리한다

B-axis의 `ChallengeCheckIn`은 팀 챌린지 참여율, 승패, 정산 계산에만 사용한다.

개인 습관 스트릭, 개인 체크인, 복귀 미션은 A-axis 책임으로 분리한다.

따라서 B-axis DB 설계에서는 `PersonalCheckIn`, `RecoveryMission`, `Streak` 테이블을 직접 수정하거나 참조하는 구조를 만들지 않는다.

---

### 1.4 정산 데이터는 재현 가능해야 한다

정산은 코인 또는 예치금과 연결되는 민감한 기능이므로, 동일한 입력 데이터에 대해 항상 동일한 결과가 나와야 한다.

따라서 정산 시점에는 캐시된 참여율만 신뢰하지 않고, `challenge_check_ins`, `challenge_participants`, `teams`, `challenges` 데이터를 기반으로 권위 있는 참여율을 재계산할 수 있어야 한다.

---

### 1.5 DB 변경은 Flyway로 관리한다

DB 스키마 변경은 Flyway 마이그레이션 파일로 관리한다.

권장 마이그레이션 흐름은 다음과 같다 (Phase별 분리 방식):

```text
V1__create_challenge_and_participant_tables.sql
V2__create_team_tables.sql
V3__create_challenge_check_in_tables.sql
V4__create_settlement_tables.sql
V5__create_social_tables.sql
```

각 파일은 해당 Phase 구현 시작 전에 머지되어, 백엔드 엔티티와 API 구현이 DB 구조를 기준으로 진행될 수 있도록 한다.

> **주의**: 이미 팀 개발 환경에 `V1__init_schema.sql`이 적용된 경우, 본 문서의 Flyway 계획은 기존 V1을 기준으로 V2 이후 확장 계획으로 수정해야 한다. 현재 적용된 마이그레이션 파일 목록을 확인 후 조정한다.

---

## 2. 전체 Phase 개요

| Phase | 백엔드 기능 | DB 설계 대상 | 우선순위 |
|---|---|---|---|
| Phase 1 | 챌린지 생성, 조회, 참여 신청, GPS 등록 | `challenges`, `challenge_participants` | 최우선 |
| Phase 2 | 5:5 팀 자동 구성, GPS 잠금 | `teams`, participant team 연결 컬럼 확정 | 높음 |
| Phase 3 | 팀 챌린지 인증, 참여율 계산 | `challenge_check_ins`, 참여율 캐시 컬럼 | 높음 |
| Phase 4a | 승패 판정, 코인 정산 | `settlements`, 정산 상태 컬럼 | 중간 |
| Phase 4b | 팀 채팅, 응원, 리더보드 | `chat_messages`, `cheer_emojis` | 중간 |
| 이후 확장 | AI 상세 인증, 알림, 통계 | `verification_evidences`, `notification_logs`, `daily_stats` 등 | 낮음 |

---

## 3. Phase 1 — Challenge 라이프사이클 & 참여/GPS 등록 DB 설계

### 3.1 목표

챌린지를 생성, 탐색, 조회할 수 있고, 사용자가 챌린지에 참여 신청하면서 예치금 차감과 GPS 위치 등록을 수행할 수 있는 DB 구조를 설계한다.

이 단계에서는 팀 구성 전까지의 데이터를 안정적으로 저장하는 것이 목표이다.

---

### 3.2 주요 테이블

#### 3.2.1 `challenges`

챌린지의 기본 정보를 저장한다.

주요 컬럼 후보:

```text
id
category
title
description
verification_method
duration_days
deposit_coins
visibility
approval_type
status
invite_code
max_participants
started_at
ended_at
created_by
created_at
updated_at
```

주요 상태값:

```text
RECRUITING
ONGOING
ENDED
SETTLED
```

주요 제약조건:

```text
status IN ('RECRUITING', 'ONGOING', 'ENDED', 'SETTLED')
visibility IN ('PUBLIC', 'PRIVATE')
approval_type IN ('AUTO', 'LEADER')
invite_code UNIQUE (NULL 허용 — 비공개 챌린지에서만 사용)
deposit_coins >= 0
duration_days > 0
max_participants > 0
```

> **MVP 정책**: 기본 정원은 10명으로 설정한다. Phase 2의 5:5 팀 자동 구성 로직은 `max_participants = 10`을 전제로 동작한다. `max_participants`를 DB 고정값으로 제한하지 않고 애플리케이션 레벨에서 정책을 관리하여, 이후 다른 정원 구성으로의 확장 가능성을 열어둔다.

---

#### 3.2.2 `challenge_participants`

챌린지 참여자 정보를 저장한다.

참여 신청 상태, GPS 등록 정보, 팀 배정 정보, 탈퇴 또는 비활성화 시점을 관리한다.

주요 컬럼 후보:

```text
id
challenge_id
user_id
team_id
personal_statement
gps_lat
gps_lng
gps_radius_meters
gps_place_name
gps_locked
status
active_until
joined_at
approved_at
created_at
updated_at
```

주요 상태값 및 전환 기준:

| 상태 | 설명 | 전환 조건 |
|---|---|---|
| `PENDING` | 참여 신청 완료, 승인 대기 | `approval_type = LEADER`인 챌린지에서 신청 시 |
| `CONFIRMED` | 챌린지 참여 확정 | AUTO: 신청 즉시 / LEADER: 리더(`created_by`) 승인 시 |
| `REJECTED` | 참여 신청 거절 | `approval_type = LEADER`인 챌린지에서 리더가 거절 시 |
| `CANCELLED` | 참여 취소 | 챌린지 **시작 전** 사용자가 자발적으로 취소 시 |
| `LEFT` | 중도 탈퇴 | 챌린지 **시작 후** 사용자가 탈퇴 시 |

주요 제약조건:

```text
UNIQUE (challenge_id, user_id)
status IN ('PENDING', 'CONFIRMED', 'REJECTED', 'CANCELLED', 'LEFT')
gps_radius_meters > 0
team_id NULL 허용 (Phase 2 팀 구성 후 채워짐)
```

---

### 3.3 Phase 1 설계 검토 사항

- `challenge_participants.team_id`는 Phase 1에서는 NULL이지만, Phase 2에서 팀 구성 후 값이 채워진다.
- `challenge_participants.active_until`은 팀 구성 완료 시점에 `challenge.ended_at` 값으로 설정된다. 이후 LEFT 처리 시 실제 탈퇴 시점으로 갱신할 수 있다. LEFT 사용자의 `active_until`을 정산 분모 계산에 반영하는 방식은 추후 정산 정책에서 확정한다.
- 정산 분모 기준: 챌린지 시작 시점의 `status = CONFIRMED` 참여자를 기준으로 한다.
- `gps_locked`는 Phase 2에서 true로 변경되지만, 참여 시점 GPS 등록 후 잠금 처리를 위해 초기 설계에 포함한다.
- `challenges.invite_code`는 비공개 챌린지(`visibility = PRIVATE`)에서만 사용되며, 공개 챌린지의 경우 NULL을 허용한다.
- 10명 정원 초과 방지를 위해 백엔드 트랜잭션과 함께 DB 레벨에서도 상태/정원 검증 전략을 검토한다.

---

## 4. Phase 2 — 5:5 팀 자동 구성 & GPS 위치 잠금 DB 설계

### 4.1 목표

챌린지 참여자가 10명 확정되면 서버가 자동으로 2개의 팀을 생성하고, 각 참여자를 5명씩 배정할 수 있는 구조를 설계한다.

또한 챌린지 시작 시점의 팀 인원수와 GPS 등록 정보를 고정하여 이후 정산 기준이 흔들리지 않도록 한다.

---

### 4.2 주요 테이블

#### 4.2.1 `teams`

챌린지 내 팀 정보를 저장한다.

주요 컬럼 후보:

```text
id
challenge_id
name
participation_rate
result
initial_member_count
created_at
updated_at
```

주요 상태값:

```text
WIN
LOSE
DRAW
NULL (챌린지 진행 중)
```

주요 제약조건:

```text
result IN ('WIN', 'LOSE', 'DRAW')
initial_member_count = 5
UNIQUE (challenge_id, name)
```

---

### 4.3 기존 테이블 변경

#### `challenge_participants`

Phase 2에서 다음 컬럼이 실제로 사용된다.

```text
team_id
gps_locked
active_until
```

팀 구성 완료 후:

```text
team_id = assigned_team_id
gps_locked = true
active_until = challenge.ended_at
```

#### `challenges`

팀 구성 완료 후:

```text
status = 'ONGOING'
started_at = now()
ended_at = started_at + duration_days
```

---

### 4.4 Phase 2 설계 검토 사항

- 10번째 참여 확정 트랜잭션 내에서 팀 생성, 참여자 팀 배정, 챌린지 시작 상태 변경이 함께 처리되어야 한다.
- 팀 구성 중 일부만 성공하는 상황을 방지하기 위해 하나의 트랜잭션으로 묶어야 한다.
- `teams.initial_member_count`는 정산 시 초기 분모 기준으로 활용될 수 있으므로 저장한다.
- 팀 구성 이후 참여자의 GPS 등록 정보는 변경되지 않도록 `gps_locked`를 사용한다.
- `approval_type = LEADER`인 챌린지에서 승인 권한자는 MVP 기준으로 `challenges.created_by`다. 별도 `leader_id` 컬럼은 두지 않는다.

---

## 5. Phase 3 — ChallengeCheckIn 팀 인증 & 참여율 DB 설계

### 5.1 목표

팀 챌린지에서 사용자의 일일 GPS 인증 결과를 저장하고, 팀 단위 참여율을 계산할 수 있는 DB 구조를 설계한다.

이 테이블은 개인 습관 체크인과 분리되며, 팀 챌린지 승패 및 정산 계산에만 사용된다.

---

### 5.2 주요 테이블

#### 5.2.1 `challenge_check_ins`

팀 챌린지 일일 인증 기록을 저장한다.

주요 컬럼 후보:

```text
id
participant_id
challenge_id
team_id
check_in_date
status
verified_at
current_lat
current_lng
created_at
updated_at
```

주요 상태값 (V1):

```text
SUCCESS
FAILED
```

- `SUCCESS`: 인증 시도 결과 GPS 범위 및 인증 조건을 충족한 경우
- `FAILED`: 인증을 시도했으나 GPS 범위 불일치, 인증 조건 미충족 등으로 실패한 경우

> **MISSED 처리 방침 (V1)**: 단순 미수행은 레코드를 생성하지 않는다. 참여율 계산 시 해당 날짜의 SUCCESS 레코드 부재로 미수행을 판단한다. 매일 자정 MISSED 레코드를 배치 생성하는 방식은 이후 통계/리포트 고도화 단계에서 검토한다.

주요 제약조건:

```text
UNIQUE (participant_id, check_in_date)
status IN ('SUCCESS', 'FAILED')
```

---

### 5.3 참여율 캐시

팀 상세 화면에서 빠른 조회를 위해 `teams.participation_rate`를 캐시 컬럼으로 사용할 수 있다.

다만 정산 시점에는 캐시값을 최종 기준으로 사용하지 않고, `challenge_check_ins` 원본 데이터를 기반으로 재계산한다.

---

### 5.4 Phase 3 설계 검토 사항

- `participant_id`는 `challenge_participants.id`를 의미한다. 동일 사용자가 여러 챌린지에 참여하더라도 챌린지별로 독립된 `participant_id`를 가지므로, `UNIQUE (participant_id, check_in_date)` 제약은 챌린지별 하루 1회 인증을 보장한다.
- 같은 사용자가 같은 날짜에 여러 번 인증 시도해도 최종적으로 1건의 결과만 유효하다. `UNIQUE (participant_id, check_in_date)` 제약으로 DB 레벨에서 보장한다.
- `check_in_date`는 `DATE` 타입으로 저장한다. DB 서버 타임존에 의존하지 않고, 애플리케이션 레벨에서 KST 기준 `LocalDate`를 계산하여 저장한다. 자정 직후 인증(00:00~00:05 KST)도 서버에서 KST 날짜를 산출하므로 날짜 경합 없이 동작한다.
- `challenge_check_ins`는 `PersonalCheckIn`과 분리한다.
- 팀 상세 화면 조회 편의를 위해 `challenge_id`, `team_id`를 중복 저장할지 여부를 검토한다.
  - 정규화 관점에서는 `participant_id`만으로 추적 가능하다.
  - 조회 성능과 쿼리 단순성을 위해 중복 저장을 허용할 수 있다.

---

## 6. Phase 4a — Settlement 정산 DB 설계

### 6.1 목표

챌린지 종료 후 팀 참여율을 재계산하여 승패를 결정하고, 정산 결과를 감사 가능하게 저장하는 구조를 설계한다.

코인 잔액 변경 자체는 A-axis의 `CoinService`가 담당하며, B-axis DB는 정산 결과와 감사 기록을 남기는 역할을 한다.

---

### 6.2 주요 테이블

#### 6.2.1 `settlements`

챌린지 정산 결과를 저장한다.

주요 컬럼 후보:

```text
id
challenge_id
computed_at
total_pool
per_winner_payout
status
winner_team_id
loser_team_id
draw
created_at
updated_at
```

주요 상태값:

```text
PENDING
COMPLETED
FAILED
```

주요 제약조건:

```text
UNIQUE (challenge_id)
status IN ('PENDING', 'COMPLETED', 'FAILED')
total_pool >= 0
per_winner_payout >= 0
```

#### `draw` 컬럼 유지 여부

`settlements.draw` 컬럼은 `teams.result = DRAW`와 의미가 중복될 수 있다. 실제 스키마 작성 시 유지 여부를 결정한다. `draw` 컬럼을 유지하는 경우 `draw = true`일 때 `winner_team_id`, `loser_team_id`는 NULL로 처리한다.

#### 정산 재시도 전략

- `challenge_id` 기준 하나의 `settlement` 레코드만 유지한다.
- `status = FAILED` 발생 시 DELETE 후 재INSERT하지 않고, 기존 레코드를 UPDATE하여 재시도한다.
- 멱등성 1차 방어: DB의 `UNIQUE (challenge_id)` 제약
- 멱등성 2차 방어: 애플리케이션 레벨에서 정산 상태 확인 후 처리

#### `per_winner_payout` 계산 기준

- 코인 단위는 정수로 가정한다.
- 소수점이 발생하는 경우 내림(floor) 처리한다.
- 내림 후 남은 잔액(remainder)의 귀속 기준은 현재 미정이며, Open Question으로 남긴다.

---

### 6.3 기존 테이블 변경

#### `teams`

정산 완료 후:

```text
result = 'WIN' | 'LOSE' | 'DRAW'
participation_rate = 최종 재계산 값
```

#### `challenges`

정산 완료 후:

```text
status = 'SETTLED'
```

---

### 6.4 Phase 4a 설계 검토 사항

- 정산은 반드시 멱등하게 처리되어야 한다. FAILED 시 기존 레코드를 UPDATE하여 재시도한다.
- `settlements.challenge_id`는 UNIQUE로 설정하여 같은 챌린지가 중복 정산되지 않도록 한다.
- 정산 시 참여율은 캐시값이 아니라 원본 체크인 기록을 기준으로 재계산한다.
- 탈퇴자 처리 기준은 `challenge_participants.active_until`을 기반으로 계산한다. LEFT 사용자의 분모 반영 방식은 추후 정산 정책에서 확정한다.
- DRAW 시 반환 대상과 탈퇴자 처리 기준은 백엔드 계약과 일치해야 한다.
- `settlements`는 챌린지 단위 결과만 저장한다. 개별 참여자 지급 이력은 V1에서 A-axis `CoinTransaction`에 의존한다. 개별 지급 조회 API 필요 시 `settlement_participants` 테이블을 Phase 4a 확장으로 추가한다.

---

## 7. Phase 4b — Social 팀 채팅/응원/리더보드 DB 설계

### 7.1 목표

팀 내 소통과 동기부여를 위한 채팅, 응원 이모지, 리더보드 조회를 지원하는 DB 구조를 설계한다.

이 Phase는 정산 기능과 직접적으로 의존하지 않으므로 Phase 4a와 병렬로 진행할 수 있다.

---

### 7.2 주요 테이블

#### 7.2.1 `chat_messages`

팀 채팅 메시지를 저장한다.

주요 컬럼 후보:

```text
id
team_id
sender_id
content
created_at
updated_at
deleted_at
```

주요 제약조건:

```text
content NOT NULL
team_id NOT NULL
sender_id NOT NULL
```

---

#### 7.2.2 `cheer_emojis`

참여자 간 응원 이모지 기록을 저장한다.

주요 컬럼 후보:

```text
id
challenge_id
from_participant_id
to_participant_id
emoji_type
created_at
```

주요 제약조건:

```text
emoji_type NOT NULL
from_participant_id <> to_participant_id
```

---

### 7.3 리더보드 설계 방향

리더보드는 별도 테이블로 저장하기보다, MVP에서는 `teams`, `challenge_check_ins`, `challenge_participants`를 기반으로 조회한다.

필요 시 이후 Phase에서 집계 테이블을 추가할 수 있다.

후보 확장 테이블:

```text
team_leaderboard_snapshots
participant_leaderboard_snapshots
```

---

## 8. 이후 확장 Phase

### 8.1 AI 인증 상세 결과

초기 MVP에서는 GPS 인증 중심으로 설계하고, 이미지/AI 인증 결과는 이후 확장한다.

후보 테이블:

```text
verification_evidences
ai_verification_results
verification_models
```

저장 후보 데이터:

```text
image_url
detected_object
gesture_type
confidence_score
model_version
ai_decision
```

---

### 8.2 알림/푸시 로그

후보 테이블:

```text
notifications
notification_logs
```

저장 후보 데이터:

```text
user_id
notification_type
title
message
sent_at
read_at
status
```

---

### 8.3 통계/리포트

후보 테이블:

```text
user_daily_stats
team_daily_stats
challenge_daily_stats
recovery_metrics
retention_metrics
```

이 테이블들은 서비스 사용 데이터가 충분히 쌓인 후 추가한다.

---

### 8.4 개별 참여자 정산 이력 (Phase 4a 확장)

V1의 `settlements`는 챌린지 단위 결과만 저장한다. 개별 참여자의 지급 이력 조회 API가 필요해지는 시점에 아래 테이블을 추가한다.

후보 테이블:

```text
settlement_participants
```

저장 후보 데이터:

```text
settlement_id
participant_id
payout_coins
result_type (WIN / LOSE / DRAW / LEFT)
created_at
```

---

## 9. 마이그레이션 계획

### 9.1 권장 Flyway 분리안 (Phase별 분리)

```text
V1__create_challenge_and_participant_tables.sql
V2__create_team_tables.sql
V3__create_challenge_check_in_tables.sql
V4__create_settlement_tables.sql
V5__create_social_tables.sql
```

각 파일은 해당 Phase 구현 시작 전에 먼저 머지되어야 한다.

> **전제 조건**: 이미 팀 개발 환경에 별도 V1이 적용된 경우, 기존 V1을 기준으로 이후 파일 번호를 조정한다.

---

### 9.2 MVP 핵심 테이블 포함 범위 (V1 ~ V4 기준)

| Flyway 파일 | 포함 테이블 |
|---|---|
| V1 | `challenges`, `challenge_participants` |
| V2 | `teams` (+ participants team 연결 컬럼) |
| V3 | `challenge_check_ins` |
| V4 | `settlements` |
| V5 | `chat_messages`, `cheer_emojis` |

소셜 기능(`chat_messages`, `cheer_emojis`)은 V5로 분리한다.

---

## 10. ERD 반영 기준

DB ERD에는 다음 관계를 반영한다.

```text
challenges 1:N challenge_participants
challenges 1:N teams
teams 1:N challenge_participants
challenge_participants 1:N challenge_check_ins
challenges 1:1 settlements
teams 1:N chat_messages
challenge_participants 1:N cheer_emojis
```

---

## 11. 인덱스 설계 후보

### 11.1 challenges

```text
idx_challenges_status
idx_challenges_category
idx_challenges_visibility
idx_challenges_invite_code
```

### 11.2 challenge_participants

```text
idx_participants_challenge_id
idx_participants_user_id
idx_participants_team_id
idx_participants_status
unique_challenge_user
```

### 11.3 challenge_check_ins

```text
idx_checkins_participant_id
idx_checkins_challenge_id
idx_checkins_team_id
idx_checkins_date
unique_participant_date
```

### 11.4 settlements

```text
unique_settlement_challenge_id
idx_settlements_status
```

### 11.5 chat_messages

```text
idx_chat_messages_team_id_created_at
```

---

## 12. Open Questions

### 12.1 A-axis User 테이블과의 FK 연결 여부

B-axis 테이블의 `user_id`, `created_by`, `sender_id`는 A-axis의 `users.id`를 참조한다.

다만 A-axis와 B-axis가 동일 DB를 공유하는 MVP 구조에서는 FK를 걸 수 있지만, 향후 서비스 분리를 고려하면 논리 참조만 사용할 수도 있다.

결정 필요:

```text
1. users.id에 실제 FK를 설정할 것인가?
2. 아니면 user_id만 저장하고 애플리케이션 레벨에서 검증할 것인가?
```

---

### 12.2 CoinTransaction 원장과 Settlement의 연결 방식

코인 잔액과 원장은 A-axis가 담당한다. B-axis의 `settlements`는 정산 결과만 저장하고, 실제 코인 이동 기록은 A-axis의 `CoinTransaction`에 남긴다.

MVP에서는 `referenceId = challengeId` 기준으로만 추적한다. `settlements`에 `coin_transaction_id`를 직접 저장하는 방식은 도입하지 않는다.

개별 참여자 지급 이력 조회가 필요해지는 시점에 `settlement_participants` 테이블을 추가하고, 해당 테이블에서 코인 이동 기록과 연결하는 구조로 확장한다.

---

### 12.3 ChallengeCheckIn에 GPS 좌표를 저장할 것인가?

현재 인증은 GPS 기반이므로 실제 인증 시점 좌표를 저장하면 감사와 디버깅에 유리하다.

다만 위치정보는 민감 데이터이므로 최소 저장 원칙이 필요하다.

결정 필요:

```text
1. 인증 시점 current_lat/current_lng를 저장할 것인가?
2. 저장한다면 소수점 정밀도를 어느 정도로 제한할 것인가?
3. 일정 기간 이후 마스킹 또는 삭제 정책을 둘 것인가?
```

---

### 12.4 소셜 기능을 MVP DB에 포함할 것인가?

채팅과 응원 이모지는 팀 챌린지 몰입도를 높이지만, 핵심 정산 흐름에는 필수는 아니다.

결정 필요:

```text
1. chat_messages, cheer_emojis를 V1에 포함할 것인가?
2. 아니면 Phase 4b에서 별도 V5 마이그레이션으로 추가할 것인가?
```

---

### 12.5 정산 잔액(remainder) 귀속 기준

`per_winner_payout`은 코인 단위 정수로, 소수점 발생 시 내림 처리한다.

내림 후 남은 잔액(예: 총 풀 100코인, 승자 3명 → 1인당 33코인, 잔액 1코인)의 귀속 기준이 미정이다.

결정 필요:

```text
1. 잔액을 플랫폼 수수료로 처리할 것인가?
2. 임의의 1명에게 추가 지급할 것인가?
3. 풀에 소각할 것인가?
```

---

### 12.6 LEFT 참여자의 정산 분모 반영 방식

정산 분모는 챌린지 시작 시점의 CONFIRMED 참여자를 기준으로 한다.

그러나 챌린지 진행 중 LEFT 처리된 참여자를 분모에 유지할지, `active_until` 시점까지만 반영할지에 대한 정책이 미정이다.

결정 필요:

```text
1. LEFT 참여자를 전체 기간 분모에 포함할 것인가?
2. active_until 이후 기간의 분모에서 제외할 것인가?
3. LEFT 참여자의 예치금 반환 여부는 어떻게 처리할 것인가?
```

### 12.7 기존 `teams` 테이블과 챌린지 팀 테이블의 역할 구분

기존 MVP ERD에서 `teams` 테이블이 일반 사용자 팀 또는 서비스 내 고정 팀을 의미하는 경우, B-axis의 5:5 챌린지 팀과 역할이 충돌할 수 있다.

결정 필요:

```text
1. 기존 teams 테이블을 챌린지 팀으로 재사용할 것인가?
2. 일반 팀과 챌린지 팀을 분리하기 위해 challenge_teams로 테이블명을 변경할 것인가?
3. team_members와 challenge_participants의 책임을 어떻게 구분할 것인가?
```

---

## 13. 완료 기준

본 DB 설계 계획의 완료 기준은 다음과 같다.

```text
1. 백엔드 Phase별 필요한 테이블 목록 정리
2. 각 테이블의 주요 컬럼, 상태값, 제약조건 초안 작성
3. ERD 관계 구조 반영
4. Flyway 마이그레이션 파일 분리 기준 정리
5. A-axis와 B-axis 간 DB 경계 및 Open Question 정리
6. 백엔드 API 명세서와 데이터 요구사항 정합성 검토
```

---

## 14. 현재 작업 상태

현재까지 MVP 기준 핵심 ERD와 V1 스키마 초안은 작성된 상태이다.

따라서 본 작업은 새로운 DB를 처음부터 설계하는 것이 아니라, 기존 ERD와 스키마를 백엔드 구현 Phase에 맞게 재정렬하고, 향후 마이그레이션 계획과 검토 기준을 명확히 하는 작업이다.

즉, Phase 1 설계는 완료에 가깝고, 현재 단계의 핵심은 다음과 같다.

```text
1. B-axis 백엔드 계획서와 기존 ERD 정합성 검토
2. Phase별 테이블 추가/변경 범위 재분류
3. Flyway V1/V2/V3 분리 기준 확정 (기존 배포된 마이그레이션 파일 확인 후 조정)
4. Open Question 정리 후 팀 회의에서 결정
```
