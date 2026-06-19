# BS-27 인증 스키마 결정 기록 (ADR)

> 유형: Architecture Decision Record (결정 기록)
> 대상: Booster 인증/체크인 DB 구조
> 상태: 결정 완료 (문서 기반 결정 PR)
> 관련 이슈: BS-27 [DB] 인증 3-way 스키마 충돌 해결
> 후속 이슈: [BE/DB] 인증 스키마 Flyway 마이그레이션 반영
> 기준 문서: `docs/erd/MVP_ERD.md`, `docs/api/MVP_API_SPEC.md`, `docs/database/bs-22-database-design-plan.md`, `docs/backend/bs-19-b-axis-backend-plan.md`

---

## 1. 배경 — 인증 구조 3-way 충돌

Booster의 인증/체크인 관련 데이터 구조가 문서마다 서로 다르게 표현되어 있어, 백엔드 구현 전에 정본을 확정할 필요가 있었다. 충돌은 세 갈래였다.

1. **`verification_logs` 단일 통합 구조** (`docs/erd/MVP_ERD.md`, `docs/api/MVP_API_SPEC.md`)
   - GPS, 사진, AI 인증 결과와 최종 성공 여부를 하나의 테이블에 통합 저장.
   - 체크인 테이블 이름은 `check_ins`.

2. **GPS/AI 결과 분리 구조** (초기 DDL 초안 `verification_submission` + `gps_verification_result` + `ai_verification_result` + `verification_result`)
   - 인증 제출 단위와 GPS/AI 결과, 최종 판정을 테이블로 분리.
   - 단, 네이밍이 단수형이며 최종 판정 테이블 이름이 `verification_result`였다.

3. **`challenge_check_ins` 중심 체크인 구조** (`docs/database/bs-22-database-design-plan.md`, `docs/backend/bs-19-b-axis-backend-plan.md`)
   - 체크인 테이블을 A-axis의 개인 `check_ins`와 분리된 `challenge_check_ins`로 정의.
   - 인증 결과 분리 테이블은 Phase 2 확장 후보로만 언급(`ai_verification_results` 등).

### 추가로 확인된 사실 (정본 판단의 전제)

- 결정 시점 기준 `main` 브랜치의 `backend/`는 빈 플레이스홀더이며, **Flyway 마이그레이션 SQL 파일이 하나도 커밋되어 있지 않다.**
- 따라서 위 DDL 초안(`V1__init_schema`, `schema_Full_toAdd`)은 **적용된 스키마가 아니라 참고용 설계 초안**이며, 정본 네이밍을 제약하지 않는다.
- AGENTS.md 규칙: "ERD와 API 스펙이 충돌하면 가정하지 말고 먼저 보고하고 확인받는다." 본 문서가 그 보고 및 확정 절차에 해당한다.

---

## 2. 최종 결정 — 분리형 인증 구조 채택 (후보 B)

인증 결과는 **통합형(`verification_logs`)이 아니라 분리형 구조**로 확정한다. 적용된 SQL이 없으므로, 의미가 더 명확한 정본 네이밍을 본 문서에서 새로 확정하고, 후속 Flyway 이슈에서 SQL을 그 네이밍에 맞춰 작성한다.

확정 사항:

- 인증 결과를 제출 단위 / GPS 결과 / AI 결과 / 최종 판정으로 분리한다.
- 체크인 테이블 이름은 `challenge_check_ins`로 통일한다(`check_ins`, `daily_check_in` 표현 정리).
- 최종 판정 테이블 이름은 의미 명확성을 위해 `verification_decisions`로 한다(초안의 `verification_result` 대체).
- **테이블명은 복수형으로 통일한다.**
- 통합형 `verification_logs`는 미채택 / deprecated 처리한다.
- MVP는 GPS 인증 중심으로 구현하고, AI 인증은 구현을 보류하여 Phase 2 확장으로 문서화한다.

---

## 3. 정본 테이블 네이밍

| 정본 테이블명 | 역할 | MVP 범위 |
|---|---|---|
| `challenge_check_ins` | 일일 챌린지 수행 기록 (체크인 기준 테이블) | MVP |
| `verification_submissions` | 인증 시도/제출 단위 | MVP |
| `gps_verification_results` | GPS 인증 결과 | MVP |
| `ai_verification_results` | AI 인증 결과 | Phase 2 (구현 보류) |
| `verification_decisions` | 최종 체크인 성공/실패 판정 | MVP |
| `verification_logs` | 통합형 초기안 | 미채택 / deprecated |

---

## 4. 테이블 역할 설명

### challenge_check_ins
사용자의 일일 챌린지 수행 기록을 저장하는 기준 테이블이다. 특정 참여자가 특정 날짜에 수행을 성공/실패했는지를 관리한다. A-axis의 개인 체크인(`check_ins`/개인 습관 스트릭)과는 분리된 팀 챌린지 전용 테이블이다.

### verification_submissions
하나의 체크인에 대해 사용자가 시도한 인증 제출 단위를 저장한다. 제출 시각, 제출 좌표, 제출 이미지(선택), 시도 회차 등을 기록한다. 하나의 체크인에 여러 제출이 있을 수 있다.

### gps_verification_results
하나의 인증 제출에 대한 GPS 위치 인증 결과를 저장한다. 목표 좌표/제출 좌표, 허용 반경, 산출된 거리, 반경 내 포함 여부 등을 기록한다. MVP 인증 판정의 핵심 입력이다.

### ai_verification_results
하나의 인증 제출에 대한 AI(사진/동작) 인증 결과를 저장한다. 모델명, 탐지 라벨, 신뢰도 점수, 통과 여부 등을 기록한다. **MVP에서는 구현을 보류하며, 테이블 정의/실제 사용은 Phase 2 확장 대상이다.**

### verification_decisions
하나의 인증 제출에 대한 최종 체크인 성공/실패 판정을 저장한다. GPS 통과 여부, AI 통과 여부, 최종 통과 여부(`final_passed`), 실패 사유 등을 종합한다. **MVP에서는 GPS 결과만으로 최종 판정을 산출한다**(AI 통과 여부는 미사용/NULL).

---

## 5. verification_logs deprecated 사유

- GPS 인증, 사진 인증, AI 인증, 최종 판정의 의미가 한 테이블에 섞여 있어 책임이 불명확하다.
- GPS 결과와 AI 결과의 수명주기(저장 시점, 보관 정책, 정밀도)가 서로 다른데 통합 구조는 이를 구분하지 못한다.
- 최종 판정과 개별 인증 결과가 분리되지 않아, MVP의 GPS 단독 판정과 Phase 2의 GPS+AI 종합 판정을 같은 구조로 표현하기 어렵다.
- 따라서 `verification_logs`는 초기 설계안으로만 기록하고, 신규 구현/문서에서는 사용하지 않는다.

---

## 6. MVP 범위와 Phase 2 범위 구분

| 구분 | 포함 테이블 / 동작 |
|---|---|
| MVP | `challenge_check_ins`, `verification_submissions`, `gps_verification_results`, `verification_decisions`. 인증은 GPS 중심, 최종 판정은 GPS 결과만으로 산출 |
| Phase 2 확장 | `ai_verification_results` 실제 구현 및 사용. AI 통과 여부를 `verification_decisions`에 종합. 사진(`imageUrl`) 기반 인증 흐름 |

---

## 7. 이번 PR 범위 / 후속 Flyway 이슈 범위

| 구분 | 범위 |
|---|---|
| 이번 PR (BS-27) | `docs/` 아래 Markdown 문서 정리만. 인증 구조 결정·네이밍 확정·deprecated 표기·API 명세 재설계 문서화 |
| 후속 이슈 [BE/DB] | 본 결정에 맞춘 Flyway 마이그레이션 SQL 신규 작성/반영, 백엔드 엔티티·리포지토리 구현 |

- 이번 PR에서는 `backend/`, `frontend/`, `ai-service/` 및 Flyway SQL 파일을 수정하지 않는다.
- 정본 네이밍/구조와 실제 SQL의 정합은 후속 이슈에서 보장한다.

---

## 8. 후속 확인 필요 사항

- `/api/check-ins/{checkInId}/verification-submissions` 엔드포인트의 소유 축(A-axis vs B-axis) 및 호출 흐름(PersonalCheckIn vs ChallengeCheckIn)은 백엔드 계획서와 함께 별도 확정이 필요하다(`docs/backend/bs-19-b-axis-backend-plan.md`, `docs/backend/a-axis-backend-plan.md` 참조).
- `gps_verification_results`의 좌표 정밀도/보관·마스킹 정책은 미정(bs-22 Open Question 12.3 참조).
