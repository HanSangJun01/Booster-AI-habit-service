# AI Verification Service API Spec

> 대상: `ai-service/` (FastAPI). 백엔드가 `AiVerificationClient`로 호출한다.
> 상태: 확정 (Phase 2). 8/9 통합 대비 협의 회신 반영 완료. 남은 확장은 §7 (Phase 3+).
> 관련 문서: `docs/erd/MVP_ERD.md`, `docs/api/MVP_API_SPEC.md`, `docs/database/BS-27-verification-schema-decision.md`

---

## 1. 공통 규칙

### 1.1 Base URL

로컬 개발: `http://localhost:8000`
백엔드 → ai-service 호출: 환경변수 `AI_SERVICE_URL` (기본 `http://localhost:8000`)

### 1.2 인증

MVP 단계에선 인증 없음. 백엔드 ↔ ai-service는 내부 네트워크에서만 호출된다는 전제.
운영 이관 시 API Key 헤더 방식 도입 예정(§7).

### 1.3 Content-Type

- 요청: `multipart/form-data` (이미지 업로드)
- 응답: `application/json`

### 1.4 에러 응답 형식

FastAPI 표준 형식:

```json
{
  "detail": "에러 사유 (문자열)"
}
```

### 1.5 이미지 제약

| 항목 | 값 |
|---|---|
| 허용 형식 | JPEG, PNG, WebP |
| 최대 크기 | 10 MB |
| 판별 방식 | 파일 매직 넘버(PIL)로 실제 형식 검증. Content-Type 헤더만 신뢰하지 않음 |

---

## 2. 카테고리

MVP 지원 카테고리:

| 값 | 의미 |
|---|---|
| `EXERCISE` | 운동 인증 |
| `STUDY` | 공부 인증 |

카테고리 확장은 팀 협의 후 `ai-service/schemas.py::Category`와 `prompts.py::_CATEGORY_CRITERIA`에 동시 추가.

---

## 3. `GET /health`

서비스 상태 확인용.

### Response 200

```json
{
  "status": "ok",
  "model": "claude-haiku-4-5-20251001",
  "api_key_present": true
}
```

| 필드 | 타입 | 설명 |
|---|---|---|
| `status` | string | `"ok"` 고정 |
| `model` | string | 현재 사용 중인 Claude 모델 ID |
| `api_key_present` | boolean | `.env`에서 `ANTHROPIC_API_KEY` 로드됐는지 (값 자체는 노출하지 않음) |

---

## 4. `POST /verify`

이미지 + 카테고리를 받아 AI 판정 결과를 반환한다.

### Request

`Content-Type: multipart/form-data`

| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `category` | string | O | `EXERCISE` 또는 `STUDY` |
| `image` | file | O | JPEG/PNG/WebP, 10MB 이하 |

### Response 200 (성공)

```json
{
  "passed": true,
  "confidence_score": 0.87,
  "detected_labels": ["running_shoes", "outdoor_pavement", "workout_wear"],
  "model_name": "claude-haiku-4-5-20251001",
  "reason": "야외에서 러닝화와 운동복을 착용한 상태의 사진이 확인됨.",
  "storage_key": "storage/exercise/20260729/abcdef1234.jpeg",
  "raw_response": {
    "passed": true,
    "confidence_score": 0.87,
    "detected_labels": ["running_shoes", "outdoor_pavement", "workout_wear"],
    "reason": "야외에서 러닝화와 운동복을 착용한 상태의 사진이 확인됨."
  }
}
```

| 필드 | 타입 | 설명 |
|---|---|---|
| `passed` | boolean | AI 판정 결과. `true` = 인증 통과 |
| `confidence_score` | number (0.0~1.0) | AI 자체 신뢰도 |
| `detected_labels` | string[] | 이미지에서 감지한 시각적 요소들 |
| `model_name` | string | 판정에 사용된 모델 ID |
| `reason` | string | 판단 근거 (1~2문장 한국어) |
| `storage_key` | string | 서비스 내 저장 경로. 백엔드는 이 값을 `ai_verification_results.storage_key`에 그대로 저장 |
| `raw_response` | object \| null | LLM 원본 응답. 디버깅/재판정용 |

### Response 4xx / 5xx

| 상태 | 상황 | `detail` 예시 |
|---|---|---|
| 400 | 크레딧 부족 (Anthropic) | `"Your credit balance is too low..."` (upstream 그대로 전달) |
| 413 | 이미지 10MB 초과 | `"이미지 크기가 10MB를 초과함"` |
| 415 | 지원 안 하는 이미지 형식 | `"지원하지 않는 이미지 형식 (JPEG/PNG/WebP만 허용)"` |
| 422 | 필드 누락/타입 오류 | FastAPI validation 표준 |
| 5xx | Anthropic API 통신/서버 실패 | FastAPI 기본 응답. 백엔드는 이를 502로 감싸 클라이언트에 전달 (§8.4) |

---

## 5. 판정 프롬프트 원칙

`ai-service/prompts.py`에 정의. 요약:

- 카테고리별 명시적 통과/실패 기준 제시
- 화면 캡처·재촬영·명백한 도용은 실패로 판정
- 애매하거나 증거가 약하면 `confidence_score`를 낮게, 기본 실패로 판정
- 응답은 반드시 지정된 JSON 형식으로만 반환

프롬프트 튜닝은 실 샘플 이미지 확보 후 반복 진행. 튜닝 로그는 `docs/ai/prompt-tuning.md`(예정)에 기록.

---

## 6. 저장소 (`storage_key` 규약)

- 현재: 로컬 파일시스템 (`ai-service/storage/`)
- 경로 포맷: `storage/<category>/<yyyymmdd>/<uuid>.<ext>`
- 예: `storage/exercise/20260729/a1b2c3d4e5f6.jpeg`
- 향후: S3 등으로 이관 시 `storage_key` 규약은 유지하고 `Storage` 인터페이스 구현체만 교체

---

## 7. Phase 3+ 확장 항목

Phase 2 협의(8/8)로 결정된 항목은 §8에 반영됐다. 아래는 명시적으로 다음 페이즈로 미룬 것들.

| 항목 | 상태 | 비고 |
|---|---|---|
| 백엔드 ↔ ai-service 인증 (API Key 등) | Phase 3 | MVP는 내부망 전제. 운영 이관 시 헤더 방식 도입 |
| 카테고리 확장 (수면, 식사, 명상 등) | Phase 3 | `schemas.py::Category`와 `prompts.py::_CATEGORY_CRITERIA`에 동시 추가 |
| 재판정 (`storage_key`로 재호출) | Phase 3 | 오판 케이스 재검토 목적 |
| 비동기 큐 (요청 폭주 대비) | Phase 3 | 현재 동기 호출 + 30s timeout으로 충분 |
| S3 저장소 스왑 | Phase 3 | `storage.py::Storage` 인터페이스로 준비됨 |
| Anthropic 실패 시 fallback provider | Phase 3 | `verifier.py::Verifier` 인터페이스로 준비됨. 현재는 5xx→백엔드 502 |

---

## 8. 백엔드 통합 지점

백엔드는 `AiVerificationClient`(위치: `com.booster.challengecheckin.service`)에서 이 서비스를 호출한다.

> **[2026-08-27 갱신] 호출자가 둘로 늘었다.** 이 문서를 쓸 당시(08-08)에는 팀 챌린지만 AI를 썼지만,
> V16에서 **개인 습관(A축)에도 AI 인증이 추가**됐다. `AiVerificationClient` 를 그대로 재사용하므로
> **ai-service 쪽 계약·구현 변경은 없다.** 자세한 흐름은 §8.6.

| 호출 경로 | 백엔드 엔드포인트 |
|---|---|
| 팀 챌린지 (B축) | `POST /api/verification-submissions/{submissionId}/ai-verification` |
| **개인 습관 (A축)** | `POST /api/personal/check-in/{checkInId}/ai-verification` |

### 8.1 verification_type별 흐름

`challenges.verification_type` (V1 정의)에 따라 백엔드 판정 흐름이 갈린다.

| verification_type | 체크인 시점 | AI 인증 API 호출 후 |
|---|---|---|
| `GPS` | GPS 판정 → `verification_decisions.decision_status = CONFIRMED`, `final_passed = gps` | AI 콜 불필요 |
| `AI` | GPS 미판정, `decision_status = PENDING`, `final_passed = null` | `final_passed = ai_passed`, `CONFIRMED`로 전환 |
| `GPS_PHOTO_AI` | GPS 판정 저장, `decision_status = PENDING`, `final_passed = null` | `final_passed = gps AND ai`, `CONFIRMED`로 전환 |
| `PHOTO`, `GPS_PHOTO` | **미지원 — 체크인 시점에 400 반환** | — |

### 8.2 백엔드 응답 (신설 엔드포인트)

```
POST /api/verification-submissions/{submissionId}/ai-verification
Content-Type: multipart/form-data

- category: EXERCISE | STUDY
- image: <파일>

Response 201:
{
  "success": true,
  "data": {
    "aiResultId": 42,
    "submissionId": 123,
    "passed": true,          // AI 자체 판정
    "confidenceScore": 0.87,
    "detectedLabels": [...],
    "reason": "...",
    "modelName": "claude-haiku-4-5-20251001",
    "storageKey": "storage/exercise/20260801/abcdef.jpeg",
    "createdAt": "2026-08-01T14:30:00",
    "finalPassed": true      // GPS+AI 종합 최종 결과
  }
}
```

### 8.3 프론트 대응 필요 사항

- 챌린지 생성 시 `verificationType` 선택 UI 필요 (현재 GPS 하드코딩).
  체크박스형(GPS/AI 다중선택) → 다음과 같이 서버 값 매핑:
  - GPS만 → `GPS`
  - AI만 → `AI`
  - 둘 다 → `GPS_PHOTO_AI`
- `verificationType`이 AI 계열인 챌린지는 체크인 응답이 PENDING 상태 → 이후 AI 인증 API 호출 → `finalPassed`로 최종 상태 표시
- 카테고리는 챌린지 저장이 아닌 **AI 인증 API 호출 시점**에 프론트가 명시 전달

### 8.4 ai-service upstream 실패 처리

백엔드 `AiVerificationClient`는 ai-service 응답을 다음과 같이 변환한다.

| ai-service 응답 | 백엔드 → 클라이언트 응답 |
|---|---|
| 2xx | 성공 그대로 |
| 5xx (Anthropic 오류·서버 예외 포함) | **502 Bad Gateway** — `AI_VERIFICATION_502` 에러 코드 |
| timeout (30s) / IO 실패 | **502 Bad Gateway** — 동일 에러 코드 |
| 4xx (계약 오류) | 500 Internal Server Error — 클라이언트에는 서버 버그로 노출 (배포 전 잡혀야 함) |

이미지 검증 실패(400/413/415)는 백엔드 `AiVerificationService`가 자체적으로 즉시 반환한다 — ai-service까지 도달하지 않는다.

### 8.6 개인 습관(A축) 통합 — V16 신규

**ai-service 입장에서는 팀 챌린지와 완전히 동일한 호출이다.** `POST /verify` 에 `category` + `image`
를 보내고 판정을 받는다. 다른 건 백엔드 쪽 저장 구조뿐이다.

```
팀   challenge_check_ins → verification_submissions(N) → ai_verification_results → decisions
개인 personal_check_ins  → personal_ai_verifications(1)
```

개인 트랙은 `UNIQUE(user_id, check_in_date)` 로 하루 1건이라 재시도 이력을 남길 자리가 없어,
제출 테이블 없이 체크인에 판정을 1:1로 붙였다.

| | 팀 (B축) | 개인 (A축) |
|---|---|---|
| 인증 방식 저장 | `challenges.verification_type` | `personal_locations.verification_type` (**기본 `GPS`**) |
| 사진 업로드 입력 | 체크인 응답의 `submissionId` | 체크인 응답의 `checkInId` |
| AI 거절 시 | `FAILED` 레코드로 남음 | **체크인 레코드를 삭제** — 그날 재시도를 열어주기 위해 |

**호출량 영향**: 개인 트랙의 인증 방식 기본값이 `GPS` 라 **AI는 사용자가 직접 바꿔야 쓰는 옵트인**이다.
따라서 당장 호출이 급증하지는 않는다. 다만 **호출 경로가 하나 더 생겼으므로**, 사용자가 개인 습관에서
AI를 택하기 시작하면 Anthropic 비용·레이트리밋이 먼저 걸리는 지점이 된다. 모니터링 대상.

### 8.7 ⚠️ category 검증이 어디에도 없다 (미해결)

§2에서 카테고리를 `EXERCISE`/`STUDY` 로 확정했지만, **그 값을 강제하는 코드가 백엔드에 없다.**
컨트롤러가 `@RequestParam String category` 로 받아 검증 없이 그대로 전달한다.

- `challenges.category` 는 `VARCHAR(50)` 자유 문자열이라 `"독서"`·`"기상"` 같은 값이 저장된다
- **앱은 현재 한글 4종(`운동`·`공부`·`독서`·`기상`)을 그대로 보낸다** → ai-service 가 422 →
  §8.4 규칙에 따라 **500**으로 나간다
- 개인 트랙에는 카테고리를 저장하는 컬럼조차 없어 클라이언트가 매번 지정한다

§8.4에 적어둔 *"(배포 전 잡혀야 함)"* 이 아직 안 잡힌 상태다.

**팀 결정 (2026-08-27)**: 카테고리는 **`EXERCISE`/`STUDY` 2개를 유지**하고 늘리지 않는다.
`독서` 는 `STUDY` 로 매핑한다(§2 프롬프트에 활자책 독서가 통과 기준으로 이미 있다).
`기상` 은 AI 인증 대상에서 제외한다. **앱이 영문 값으로 변환해 보내는 것**으로 막는다.
근본 해결(생성 단계 검증)은 후속 과제.

### 8.5 verification_type 매트릭스 (백엔드 흐름 요약)

| verification_type | recordCheckIn 결과 | /ai-verification 호출 필요? | 최종 판정 규칙 |
|---|---|---|---|
| `GPS` | 즉시 CONFIRMED, final=gps | 불필요 | gps_passed |
| `AI` | PENDING, final=null | 필요 | ai_passed |
| `GPS_PHOTO_AI` | PENDING, gps 결과는 저장 후 대기 | 필요 | gps_passed AND ai_passed |
| `PHOTO`, `GPS_PHOTO` | **체크인 시점에 400 (ILLEGAL_STATE)** | — | MVP 미지원 |

