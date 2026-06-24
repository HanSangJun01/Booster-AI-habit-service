# BS-28 인증 결과 테이블 마이그레이션 설계 (채택안)

> 대상: 인증/검증 모듈의 인증 결과 저장 구조 (DB/API 구조 설계)
> 기준 문서: `MVP_ERD.md`, `MVP_API_SPEC.md`, `bs-22-database-design-plan.md`, 실제 `V1__init_schema`
> 기술 스택: PostgreSQL + Spring Data JPA + Flyway
> 선행 이슈: BS-27 (인증 스키마 네이밍 충돌 정리, docs-only)
> 상태: **BS-28 기준 채택안 — DB 담당 결정안** (실제 Flyway SQL 파일은 별도 작업)

---

## 0. 문서 목적과 위상

본 문서는 인증 결과 저장 구조를 **`verification_submission` 기반 분리형**으로 확정하고, 실제 V1 마이그레이션에 적용된 스키마를 기준으로 신규 결과/판정 테이블의 설계를 정리하는 **DB 담당 결정안**이다.

- 이 문서는 "팀 확정을 기다리는 보류 문서"가 아니라, DB 구조 설계 책임 범위에서 내린 **채택 결정**을 기록한다.
- AGENTS 규칙에 따라, 기존 ERD/API 문서와의 충돌 사실은 삭제하지 않고 **"검토 결과 및 채택 기준"** 형태로 남긴다. (2장)
- 실제 Flyway SQL 파일 생성은 본 문서 범위가 아니다. 후속 구현 단계에서 적용 현황(8장) 확인 후 별도로 배치한다.

---

## 1. 채택 결론 요약

| # | 항목 | 채택 결정 |
|---|------|-----------|
| 1 | 인증 결과 저장 구조 | 통합형 `verification_logs` 단일 테이블이 아니라 **`verification_submission` 기반 분리형**으로 확정 |
| 2 | 기준 테이블 | 실제 V1에 존재하는 **`daily_check_in`**, **`verification_submission`** 기준. `verification_submission`은 신규 생성 대상 아님 |
| 3 | 네이밍 컨벤션 | 현재 V1과 일치시키기 위해 **단수형 snake_case** 채택 |
| 4 | 최종 판정 테이블명 | `verification_result`가 아니라 **`verification_decision`** — 중간 결과는 `result`, 최종 판정은 `decision`으로 의미 구분 |
| 5 | FK 흐름 | `daily_check_in` → `verification_submission` → {`gps_verification_result`, `ai_verification_result`, `verification_decision`}. 결과 테이블은 `daily_check_in`을 직접 참조하지 않고 **`verification_submission`을 경유** |
| 6 | AI 원본 결과 컬럼 | `ai_verification_result.raw_result` 를 **`JSONB`** 로 채택 |
| 7 | 판정 상태 표현 | `verification_decision`에 **`decision_status VARCHAR(30) NOT NULL DEFAULT 'PENDING'`** 포함. `final_passed BOOLEAN`은 최종 성공/실패 여부로 유지 |
| 8 | 판정 시간 컬럼 | 최종 판정 테이블은 `verified_at`이 아니라 **`decided_at`** 사용 |
| 9 | FK `ON DELETE` | **명시하지 않음**. 인증 제출/결과는 감사·검증 기록이므로 기본적으로 삭제하지 않음 전제. 탈퇴/개인정보 삭제는 별도 이슈 |

---

## 2. 검토된 충돌과 채택 결정 (AGENTS: 충돌 사실 보존)

인증 결과 저장 구조는 세 갈래로 표현이 갈려 있었다. 충돌 사실 자체는 기록으로 남기고, 각 항목에 대한 채택 기준을 함께 명시한다.

### 2.1 저장 구조: 통합형 vs 분리형

| 출처 | 표현 | 성격 |
|------|------|------|
| `MVP_ERD.md` (main 머지본) | `verification_logs` 단일 테이블 | GPS·사진·AI 결과를 한 테이블에 통합 |
| 실제 `V1__init_schema` / Full DDL 초안 | `verification_submission` + 결과 테이블 분리 | 제출과 판정 결과를 분리 |
| `bs-22` 후보 모델 | 분리형(복수형 네이밍) | `verification_submissions`, `verification_decisions` 등 |

**채택**: 분리형. 근거는 (a) 실제 V1에 이미 `verification_submission`이 적용되어 있어 통합형으로 되돌리면 적용 스키마와 충돌하고, (b) GPS/AI/최종 판정의 수명·갱신 주기가 달라 한 테이블에 묶으면 NULL 컬럼과 상태 혼선이 커지기 때문이다. `verification_logs`는 본 설계에서 채택하지 않으며, ERD상 통합형 표현은 분리형으로 대체된 것으로 본다.

### 2.2 체크인 테이블명: `check_ins` / `challenge_check_ins` vs `daily_check_in`

문서(`MVP_ERD.md`의 `check_ins`, `bs-22`의 `challenge_check_ins`)와 실제 V1(`daily_check_in`)이 다르게 표현되어 있다.

**채택**: 이들을 **동일 개념의 다른 표현**으로 보고, BS-28은 실제 적용 스키마와의 충돌을 피하기 위해 **`daily_check_in`을 기준**으로 한다. 인증 결과 테이블은 어차피 `daily_check_in`을 직접 참조하지 않고 `verification_submission`을 경유하므로(5장), 체크인 테이블명 차이가 결과 테이블 설계에 직접 영향을 주지 않는다.

### 2.3 네이밍 컨벤션: 복수형 vs 단수형

`bs-22` 후보는 복수형(`verification_submissions`, `gps_verification_results`, `verification_decisions`), 실제 V1은 단수형(`verification_submission` 등)이다.

**채택**: 현재 V1과 일치시키기 위해 **단수형 snake_case**. 복수형 이슈명은 아래로 매핑한다.

| 이슈/문서상 표현 (복수형) | BS-28 채택 표현 (단수형) |
|---|---|
| `verification_submissions` | `verification_submission` (V1 기존) |
| `gps_verification_results` | `gps_verification_result` |
| `ai_verification_results` | `ai_verification_result` |
| `verification_decisions` | `verification_decision` |

### 2.4 최종 판정 테이블명: `verification_result` vs `verification_decision`

기존 분리형 DDL 초안(`schema_Full_toAdd.txt`)에는 최종 판정 테이블이 `verification_result`로 되어 있었다.

**채택**: **`verification_decision`**. GPS/AI 중간 결과 테이블은 `..._result`를 쓰고, 이들을 종합한 최종 판정 테이블은 `..._decision`을 써서 "중간 결과"와 "최종 판정"의 의미를 이름으로 구분한다.

---

## 3. 기준 스키마: V1 적용 현황

본 설계는 다음 V1 테이블을 **기준(이미 존재, 신규 생성 대상 아님)**으로 삼는다.

### `daily_check_in` (V1 존재)
- PK `check_in_id`
- FK `participant_id` → `challenge_participant(participant_id)`
- UNIQUE `(participant_id, check_in_date)`

### `verification_submission` (V1 존재)
- PK `submission_id`
- FK `check_in_id` → `daily_check_in(check_in_id)`
- FK `mission_id` → `challenge_mission(mission_id)`
- FK `user_id` → `app_user(user_id)`
- 주요 컬럼: `attempt_no`, `submitted_image_url`, `submitted_latitude/longitude`, `submission_status`, `submitted_at`

> 핵심: `verification_submission.check_in_id`가 이미 `daily_check_in`을 가리키고 있으므로, 신규 결과/판정 테이블은 `submission_id`만 참조하면 "결과 테이블 → 제출 → 체크인" 흐름이 자연스럽게 성립한다.

**신규 생성 대상**은 다음 3개 테이블뿐이다 (V1에 없음):
`gps_verification_result`, `ai_verification_result`, `verification_decision`.

---

## 4. FK 흐름 및 관계

```
challenge_participant
        │ (participant_id)
        ▼
   daily_check_in                         ← V1 존재, 기준
        │ (check_in_id)
        ▼
 verification_submission                  ← V1 존재, 기준 (신규 아님)
        │ (submission_id)
        ├──────────────► gps_verification_result   (신규)
        ├──────────────► ai_verification_result    (신규)
        └──────────────► verification_decision      (신규)
                                  ▲   ▲
                                  │   │ (gps_result_id, ai_result_id)
              gps_verification_result, ai_verification_result 참조
```

- 인증 결과 테이블(`gps/ai/decision`)은 **`daily_check_in`을 직접 참조하지 않는다.** 모두 `verification_submission`을 경유한다.
- `verification_decision`은 종합 판정 테이블로서 `verification_submission`을 참조하고, 선택적으로 `gps_verification_result`/`ai_verification_result`를 함께 참조해 어떤 중간 결과를 근거로 판정했는지 추적한다.
- 각 결과/판정 테이블의 `submission_id`는 `UNIQUE` — 제출 1건당 GPS 결과 1건, AI 결과 1건, 최종 판정 1건(1:0..1).

---

## 5. 신규 테이블 DDL 초안

> 아래는 **설계 초안**이며, 실제 Flyway 파일은 8장의 적용 현황 확인 후 별도 배치한다. 본 문서에서 `.sql` 파일을 생성하지 않는다.

### 5.1 `gps_verification_result` — GPS 인증 중간 결과

```sql
CREATE TABLE gps_verification_result (
    gps_result_id        BIGSERIAL PRIMARY KEY,
    submission_id        BIGINT NOT NULL UNIQUE,
    target_latitude      NUMERIC(10, 7),
    target_longitude     NUMERIC(10, 7),
    submitted_latitude   NUMERIC(10, 7),
    submitted_longitude  NUMERIC(10, 7),
    allowed_radius_meter INTEGER,
    distance_meter       INTEGER,
    is_within_range      BOOLEAN,
    verified_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_gps_verification_result_submission
        FOREIGN KEY (submission_id)
        REFERENCES verification_submission(submission_id)
);
```

- 중간 결과 테이블이므로 측정 시각은 `verified_at`을 유지한다(최종 판정 시각 `decided_at`과 구분).

### 5.2 `ai_verification_result` — AI 인증 중간 결과

```sql
CREATE TABLE ai_verification_result (
    ai_result_id     BIGSERIAL PRIMARY KEY,
    submission_id    BIGINT NOT NULL UNIQUE,
    model_name       VARCHAR(100),
    ai_task_type     VARCHAR(50),
    detected_label   VARCHAR(100),
    confidence_score NUMERIC(5, 4),
    is_passed        BOOLEAN,
    raw_result       JSONB,
    verified_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_ai_verification_result_submission
        FOREIGN KEY (submission_id)
        REFERENCES verification_submission(submission_id)
);
```

- `raw_result`는 모델 원본 출력(탐지 박스/라벨/스코어 등)을 보존하기 위해 **`JSONB`** 로 채택한다. PostgreSQL에서 키 기반 질의·부분 인덱싱(GIN)이 가능하다.
- AI 인증은 Phase 2 구현 대상이므로, MVP 시점에는 테이블만 정의하고 적재는 AI 모듈 연동 이후 시작될 수 있다(8장 확인 항목).

### 5.3 `verification_decision` — 최종 판정

```sql
CREATE TABLE verification_decision (
    verification_decision_id BIGSERIAL PRIMARY KEY,
    submission_id            BIGINT NOT NULL UNIQUE,
    gps_result_id            BIGINT,
    ai_result_id             BIGINT,
    gps_passed               BOOLEAN,
    ai_passed                BOOLEAN,
    final_passed             BOOLEAN,
    decision_status          VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    failure_reason           TEXT,
    decided_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_verification_decision_submission
        FOREIGN KEY (submission_id)
        REFERENCES verification_submission(submission_id),

    CONSTRAINT fk_verification_decision_gps
        FOREIGN KEY (gps_result_id)
        REFERENCES gps_verification_result(gps_result_id),

    CONSTRAINT fk_verification_decision_ai
        FOREIGN KEY (ai_result_id)
        REFERENCES ai_verification_result(ai_result_id)
);
```

- `decision_status`: 판정 진행 상태를 표현하는 상태 컬럼. 기본값 `'PENDING'`. 후보 값(초안): `PENDING`(판정 대기), `PASSED`(통과), `FAILED`(불통과), `MANUAL_REVIEW`(수동 검토). 최종 상태값 집합은 서비스 로직 확정 시 좁힌다.
- `final_passed`: 최종 성공/실패 여부(BOOLEAN)로 유지. `decision_status`가 진행/예외 상태를 표현하고, `final_passed`는 통과 여부의 단일 불리언 결론을 담는다.
- `decided_at`: 최종 판정이 내려진 시각. 중간 결과의 `verified_at`과 의미를 분리한다.

---

## 6. `ON DELETE` 및 데이터 수명 정책

- 모든 FK는 **`ON DELETE` 정책을 명시하지 않는다.** (PostgreSQL 기본 동작인 `NO ACTION`을 따른다.)
- 근거: 인증 제출/결과/판정 데이터는 **감사·검증 기록 성격**이 있어, 참조 무결성을 유지한 채 기본적으로 삭제하지 않는 것을 전제로 한다. 부모 행(제출)이 임의로 삭제되어 결과/판정이 연쇄 삭제되는 동작을 의도적으로 피한다.
- 사용자 탈퇴/개인정보 삭제(예: 이미지 URL·좌표의 마스킹·파기, 보관 기간) 정책은 **별도 이슈**에서 다룬다. 본 문서 범위가 아니다.

---

## 7. ERD/API 문서 정합성 메모

- `MVP_ERD.md`는 통합형 `verification_logs`를 기준으로 서술되어 있으나, 본 설계는 분리형을 채택하므로 ERD 문서상 `verification_logs` 항목은 분리형(`verification_submission` + 결과/판정 3종)으로 대체된 것으로 본다. (BS-27에서 `verification_logs` deprecated 처리와 일치)
- `MVP_API_SPEC.md`의 인증 관련 엔드포인트는 `verification_submission` 기반 흐름을 전제로 한다. 본 결정안과 충돌하는 잔여 표현(통합 로그 기준 경로 등)이 있으면 API 스펙 측에서 분리형 기준으로 맞춘다.
- `bs-22`의 복수형 후보 네이밍은 4·2.3장의 단수형 매핑으로 대체된다.

---

## 8. 후속 구현 시 확인 항목 (최소화)

본 설계는 결정안이므로 모델/네이밍/컬럼 관련 항목은 더 이상 미결로 두지 않는다. 다만 **실제 Flyway SQL을 배치하는 구현 단계**에서 다음만 확인이 필요하다.

1. **V1~V5 적용 현황** — 공유 팀 DB에 V1~V5 마이그레이션이 이미 적용되었는지 확인. 적용되었다면 Flyway 불변성에 따라 기존 파일을 수정하지 않고, 신규 결과/판정 3종은 **새 버전 파일**(예: 형 스캐폴딩 기준의 다음 번호)로 추가한다.
2. **마이그레이션 폴더 위치/네이밍** — 스캐폴딩·마이그레이션 폴더는 형이 담당하므로, 폴더 경로와 파일 네이밍 컨벤션을 안내받은 뒤 SQL을 배치한다.
3. **`ai_verification_result` 적재 시점** — AI 인증은 Phase 2 대상. MVP 마이그레이션에서 테이블만 미리 생성할지, AI 모듈 연동 시점에 테이블 생성까지 함께 진행할지 결정한다. (테이블 정의 자체는 본 문서에서 확정)

---

## 9. 적용 범위 / 비범위

**범위 (본 문서에서 확정)**
- 인증 결과 저장 구조: 분리형 채택
- 신규 3종 테이블의 컬럼/타입/제약/FK 흐름 설계
- 네이밍 컨벤션(단수형) 및 최종 판정 테이블명(`verification_decision`) 확정

**비범위 (별도 이슈/단계)**
- 실제 Flyway `.sql` 파일 생성 및 배치 (8장 확인 후)
- 사용자 탈퇴/개인정보 삭제·보관 정책
- 범용 `stored_file` 테이블(MVP 범위의 인증 첨부와 별개)
- A-axis 개인 체크인 FK 확장 경로
