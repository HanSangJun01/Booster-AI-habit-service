# AI Verification Service API Spec

> 대상: `ai-service/` (FastAPI).
> 상태: 확정 (Phase 2). 8/9 통합 대비 협의 회신 반영 완료. 남은 확장은 §7 (Phase 3+).
>
> **§1~§8은 백엔드 경유 경로다** — 백엔드가 `AiVerificationClient`로 `POST /verify`를 호출한다.
> **§9는 Spring을 거치지 않는 단독 경로**(GPS·사진·통합 판정), **§10은 LangChain 오케스트레이션**이다.
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

카테고리 확장은 팀 협의 후 `ai-service/schemas.py::Category`와 `ai-service/policies/verification.yaml::categories`에 동시 추가 (한쪽만 고치면 `policy.py`가 기동을 막는다).

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

문구 원본은 `ai-service/policies/verification.yaml`에 있다 (`ai-service/policy.py`가 기동 시
1회 읽어 `ai-service/prompts.py`가 카테고리별 모델 메시지로 조립 — §10 참조). 요약:

- 카테고리별 명시적 통과/실패 기준 제시
- 화면 캡처·재촬영·명백한 도용은 실패로 판정
- 애매하거나 증거가 약하면 `confidence_score`를 낮게, 기본 실패로 판정

**"응답은 반드시 지정된 JSON 형식으로만 반환"은 더 이상 사실이 아니다.** LangChain
structured output 전환(§10) 이후 `PhotoVerdict` 스키마가 도구(tool) 정의로 모델에
강제되므로, 프롬프트에 출력 형식 지시를 넣을 필요 자체가 없어졌다.

프롬프트 튜닝은 실 샘플 이미지 확보 후 `ai-service/batch_test.sh` + `ai-service/samples/`로
반복 진행 (`ai-service/README.md` 참조). 별도 튜닝 로그 문서는 두지 않는다 — 정책
자체가 `policies/verification.yaml`이라는 단일 소스로 버전 관리된다.

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
| 카테고리 확장 (수면, 식사, 명상 등) | Phase 3 | `schemas.py::Category`와 `policies/verification.yaml::categories`에 동시 추가 |
| 재판정 (`storage_key`로 재호출) | Phase 3 | 오판 케이스 재검토 목적 |
| 비동기 큐 (요청 폭주 대비) | Phase 3 | 현재 동기 호출 + 30s timeout으로 충분 |
| S3 저장소 스왑 | Phase 3 | `storage.py::Storage` 인터페이스로 준비됨 |
| Anthropic 실패 시 fallback provider | Phase 3 | `verifier.py::Verifier` 인터페이스로 준비됨. 현재는 5xx→백엔드 502 |

---

## 8. 백엔드 통합 지점

백엔드는 `AiVerificationClient`(위치: `com.booster.challengecheckin.service`)에서 이 서비스를 호출한다.
백엔드 신설 엔드포인트: `POST /api/verification-submissions/{submissionId}/ai-verification`

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

### 8.5 verification_type 매트릭스 (백엔드 흐름 요약)

| verification_type | recordCheckIn 결과 | /ai-verification 호출 필요? | 최종 판정 규칙 |
|---|---|---|---|
| `GPS` | 즉시 CONFIRMED, final=gps | 불필요 | gps_passed |
| `AI` | PENDING, final=null | 필요 | ai_passed |
| `GPS_PHOTO_AI` | PENDING, gps 결과는 저장 후 대기 | 필요 | gps_passed AND ai_passed |
| `PHOTO`, `GPS_PHOTO` | **체크인 시점에 400 (ILLEGAL_STATE)** | — | MVP 미지원 |


---

## 9. 단독 인증 엔드포인트 (Spring 미경유)

§4까지가 **백엔드 경유** 경로다. 아래는 Spring을 거치지 않고 ai-service만으로 판정을 받는 경로다.
GPS 판정 로직을 백엔드 `GpsVerificationEvaluator`에서 ai-service로 옮겼기 때문에(`ai-service/gps.py`)
판정에 DB가 필요 없다. **백엔드 코드는 이 작업에서 변경하지 않았다.**

### 9.1 무엇을 하지 않는가

**판정만 한다.** 아래는 전부 백엔드의 몫이고 ai-service엔 저장소가 없다.

- 인증(JWT)·소유권 검증 — 지금은 무인증이다 (§1.2와 같은 내부망 전제)
- 중복 인증 차단, 체크인 레코드 생성·갱신
- 스트릭·코인·참여율 갱신
- `verification_decisions` 등 판정 이력 저장

앱이 이 경로만으로 인증을 "완료"할 수는 없다. 기록이 필요한 흐름은 여전히 백엔드를 거쳐야 한다.

### 9.2 `POST /verify/gps`

`application/json`. 모델을 호출하지 않는다.

| 필드 | 타입 | 제약 |
|---|---|---|
| `target_lat` / `target_lng` | number | -90~90 / -180~180 (백엔드 `LocationRequest`와 동일) |
| `radius_meters` | int | > 0 (백엔드 `@Positive`, DB `CHECK`와 동일) |
| `submitted_lat` / `submitted_lng` | number | 동일 |

**Response 200**

```json
{
  "passed": false,
  "distance_meters": 111.19,
  "radius_meters": 50,
  "target_lat": 37.5665, "target_lng": 126.9780,
  "submitted_lat": 37.5675, "submitted_lng": 126.9780,
  "failure_reason": "GPS_OUT_OF_RADIUS"
}
```

**반경 밖은 200 + `passed=false`다.** 백엔드 A축은 같은 상황을 400 `GPS_OUT_OF_RANGE`로 끊지만
그건 체크인 레코드를 만들지 않으려는 흐름 제어이지 판정의 성패가 아니다. 흐름 제어는 호출자가 정한다.

**백엔드와 같은 답을 내기 위해 지킨 것** (`ai-service/gps.py`)

- 지구 반지름 `6_371_000.0` m, Haversine 공식 동일
- 판정은 **반올림 전 거리**로 `distance <= radius` — 경계값(거리 == 반경)은 통과
- 보고용 `distance_meters`만 소수 둘째 자리 `HALF_UP` (백엔드 `NUMERIC(10,2)`와 동일)

### 9.3 `POST /verify/photo`

`POST /verify`(§4)와 **같은 핸들러**다. 요청·응답 형식이 완전히 같다.
`/verify`는 백엔드 `AiVerificationClient`가 부르는 기존 계약이라 남겨 둔다.

### 9.4 `POST /verify/check-in`

`multipart/form-data`. 인증 방식 하나로 GPS·사진을 묶어 최종 판정까지 낸다 —
백엔드가 체크인과 사진 업로드 두 번에 나눠 하던 판정을 한 번에 한다.

| 필드 | 필수 | 설명 |
|---|---|---|
| `verification_type` | O | `GPS` \| `AI` \| `GPS_PHOTO_AI` |
| `category`, `image` | AI 계열일 때 | §4와 동일한 제약 |
| `target_lat`, `target_lng`, `radius_meters`, `submitted_lat`, `submitted_lng` | GPS 계열일 때 | §9.2와 동일 |

최종 규칙은 백엔드 `finalizeDecisionAfterAi`와 같다 (§8.5 표와 동일).

| verification_type | 최종 판정 | 실패 사유 |
|---|---|---|
| `GPS` | `gps_passed` | `GPS_OUT_OF_RADIUS` |
| `AI` | `ai_passed` (GPS를 보지 않음) | `AI_REJECTED` |
| `GPS_PHOTO_AI` | `gps_passed AND ai_passed` | GPS 실패가 우선 |

**Response 200**

```json
{
  "verification_type": "GPS_PHOTO_AI",
  "decision_status": "CONFIRMED",
  "final_passed": true,
  "failure_reason": null,
  "gps": { "passed": true, "distance_meters": 12.34, "radius_meters": 50, "failure_reason": null },
  "ai": { "passed": true, "confidence_score": 0.87, "storage_key": "exercise/20260829/ab12.png" }
}
```

`decision_status`는 항상 `CONFIRMED`다 — 사진까지 이 요청 안에서 받으므로 유보할 이유가 없다.
`PENDING`은 백엔드가 두 단계로 나눠 부를 때만 생긴다.

**Response 4xx**

| 상태 | 상황 |
|---|---|
| 400 | `verification_type`이 `PHOTO`·`GPS_PHOTO` 등 미지원 (백엔드도 체크인 시점에 거절) |
| 400 | 인증 방식이 요구하는 필드 누락 (어떤 필드인지 `detail`에 나열) |
| 413 / 415 / 422 | §4와 동일 |

---

## 10. AI 오케스트레이션 — LangChain

모델 호출은 전부 LangChain을 거친다.

```python
ChatPromptTemplate | ChatAnthropic.with_structured_output(PhotoVerdict, include_raw=True)
```

`PhotoVerdict` 스키마가 도구 정의로 바뀌어 `tool_choice`로 모델에 강제되므로,
응답 본문을 손으로 파싱할 일이 없다. 프롬프트에서 "JSON만 반환하라" 지시를 뺀 것도 그래서다.

### 10.1 계약에 생긴 변화 — 502

**모델에서 판정을 못 받으면 이제 502다.** 예전 구현은 파싱 실패를 `passed=false`로 폴백해서
**모델이 형식을 틀린 것과 실제 인증 거절이 구분되지 않았다** — 멀쩡한 사진을 올린 사용자가
반려당하는 경로였다. 백엔드는 5xx를 재시도 가능한 `AI_VERIFICATION_502`로 번역하므로
(§8.4) 거짓 거절 대신 재시도가 된다. **백엔드 코드 변경 없이 동작하는 개선이다.**

### 10.2 전환 범위

| 항목 | 전환 여부 |
|---|---|
| 사진 판정 모델 호출 | ✅ LangChain (`ChatAnthropic`) |
| 프롬프트 조립 | ✅ `ChatPromptTemplate` |
| 출력 파싱 | ✅ structured output (수동 파서 삭제) |
| GPS 판정 | ❌ 전환 대상 아님 — 모델이 개입하지 않는 순수 계산 |
| 이미지 저장 | ❌ 전환 대상 아님 — `Storage` 인터페이스 유지 |

### 10.3 모델에게 나가는 문구는 네 갈래다

structured output으로 바뀌면서 "프롬프트"의 범위가 넓어졌다. `system`과 사용자
메시지 텍스트만이 아니라, LangChain이 도구 정의로 실어 보내는 다음 두 곳도
그대로 모델이 읽는 지시문이다.

1. `system` — 판별기 역할·판단 원칙
2. 사용자 메시지 텍스트 블록 — 카테고리별 판정 기준
3. `tools[].input_schema.properties[].description` — `PhotoVerdict` 필드별 출력 지시
4. `tools[].description` — 도구 자체의 설명

3·4번이 함정이었다. 특히 4번은 한때 `PhotoVerdict` 클래스의 **docstring**이었다 —
코드를 설명하려고 쓴 문장이 그대로 판정 프롬프트로 나가고 있었고, 실제로 리팩터링
중 그 docstring을 고쳤다가 라이브 프롬프트가 바뀌는 사고가 있었다. 지금은 네 갈래
전부 `ai-service/policies/verification.yaml`에서 나온다 (`schemas.py`가
`json_schema_extra`로 도구 설명을 덮어써 docstring이 새어 나가지 않게 막는다).
`ai-service/tests/test_prompt_policy.py`가 조립된 payload 전체를 골든 스냅샷으로
고정해 이 중 하나라도 조용히 바뀌는 것을 잡는다.
