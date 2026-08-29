# ai-service

Booster 인증 서비스. **사진 AI 판정**과 **GPS 반경 판정**을 한다.
사진 판정은 LangChain으로 Claude Vision(Haiku 4.5)을 부르고, GPS 판정은 서비스 안에서 직접 계산한다.

관련 문서: `../docs/api/AI_SERVICE_SPEC.md`

## 아키텍처 위치

경로가 두 개다.

```
① 백엔드 경유 (기존)
Flutter 앱 → 백엔드 (Spring) → ai-service → Anthropic Claude Vision API
                    ↓
                PostgreSQL

② ai-service 단독
Flutter 앱 → ai-service → Anthropic Claude Vision API
```

**① 백엔드 경유** — 백엔드가 `POST /api/verification-submissions/{id}/ai-verification`를 받으면
이 서비스의 `POST /verify`를 호출한다. 이 계약은 백엔드 `AiVerificationClient`가 의존하므로 바꾸지 않는다.

**② ai-service 단독** — `POST /verify/gps` · `POST /verify/photo` · `POST /verify/check-in`은
Spring을 거치지 않는다. GPS 판정 로직을 백엔드 `GpsVerificationEvaluator`에서 옮겨왔기 때문에(`gps.py`)
판정에 DB가 필요 없다.

> **단독 경로는 판정만 한다.** 인증(JWT)·소유권 확인·중복 인증 차단·체크인 레코드 생성·
> 스트릭과 코인 지급은 전부 백엔드의 몫이고 이 서비스엔 저장소가 없다.
> "이 좌표와 이 사진이 기준을 통과하는가"에만 답한다.

자세한 흐름과 API 계약은 `../docs/api/AI_SERVICE_SPEC.md` 참조.

## 로컬 실행 (개발용)

### 1. 사전 준비

```bash
cd ai-service

# 가상환경
python3 -m venv .venv
source .venv/bin/activate

# 의존성
pip install -r requirements.txt

# .env 세팅
cp .env.example .env
# .env 편집: ANTHROPIC_API_KEY=sk-ant-api03-... 입력
```

**Anthropic API 키**: https://console.anthropic.com → API Keys 에서 발급.
Billing에 최소 $5 크레딧 필요 (없으면 400 에러).

### 2. 실행

```bash
uvicorn main:app --reload --port 8000
```

### 3. 검증

```bash
# 상태 확인 (API 호출 안 함)
curl http://localhost:8000/health
# → {"status":"ok","model":"claude-haiku-4-5-20251001","api_key_present":true,
#    "orchestrator":"langchain","categories":["EXERCISE","STUDY"],"anthropic_timeout_seconds":25.0}

# 실 판정 테스트 (실제 이미지 필요, API 호출 발생)
curl -X POST http://localhost:8000/verify \
  -F "category=EXERCISE" \
  -F "image=@samples/exercise/pass/running.jpg"
```

## Docker 실행 (통합 개발용)

루트 `docker-compose.yml`에 등록되어 있음. 기본으로는 안 뜨고, `--profile ai`로 활성화.

```bash
cd ..  # 프로젝트 루트
# db + backend + ai-service 모두 기동
docker compose --profile ai up -d --build
# 로그 확인
docker compose logs -f ai-service
# 종료
docker compose --profile ai down
```

컨테이너에서 백엔드는 `AI_SERVICE_URL=http://ai-service:8000`으로 자동 연결.

## 엔드포인트

### `GET /health`
서비스 상태 확인. API 호출 없음.

**Response**:
```json
{
  "status": "ok",
  "model": "claude-haiku-4-5-20251001",
  "api_key_present": true,
  "orchestrator": "langchain",
  "categories": ["EXERCISE", "STUDY"],
  "anthropic_timeout_seconds": 25.0
}
```

`categories`·`anthropic_timeout_seconds`는 `.env`로만 바뀌는 값이라 재기동 없인
눈으로 확인할 길이 없다 — 배포 직후 "설정이 실제로 먹었는가"를 실 판정 호출 없이
확인하기 위해 노출한다.

### `POST /verify/photo` (= `POST /verify`)
사진 AI 판정. `multipart/form-data`

두 경로는 같은 핸들러다. `/verify`는 백엔드 `AiVerificationClient`가 부르는 기존 계약이라 남겨 둔다.

| 필드 | 타입 | 설명 |
|---|---|---|
| `category` | string | `EXERCISE` \| `STUDY` |
| `image` | file | JPEG/PNG/WebP, `MAX_IMAGE_MB`(기본 10) MB 이하 |

**Response 200**:
```json
{
  "passed": true,
  "confidence_score": 0.87,
  "detected_labels": ["running_shoes", "outdoor_pavement"],
  "model_name": "claude-haiku-4-5-20251001",
  "reason": "야외에서 러닝화와 운동복을 착용한 상태의 사진이 확인됨.",
  "storage_key": "storage/exercise/20260807/abcdef.jpeg",
  "raw_response": {...}
}
```

**Response 4xx/5xx**:
| 상태 | 상황 |
|---|---|
| 400 | Anthropic 크레딧 부족 (upstream 400 그대로 전달) |
| 413 | 이미지가 `MAX_IMAGE_MB` 초과 |
| 415 | 지원 안 하는 이미지 형식 (`ALLOWED_IMAGE_MEDIA_TYPES` 기준) |
| 422 | 필드 누락, 또는 `category`가 `EXERCISE`/`STUDY`가 아님 |
| 502 | **모델에서 판정을 못 받음** (아래 참조) |

> **502는 거절이 아니다.** 모델이 스키마대로 답하지 않으면 `passed=false`로 내리지 않고 502를 낸다.
> 예전 구현은 파싱 실패를 `passed=false`로 폴백해서 **모델이 형식을 틀린 것과 실제 인증 거절이
> 구분되지 않았다** — 멀쩡한 사진을 올린 사용자가 반려당하는 경로였다.
> 백엔드는 502를 재시도 가능한 `AI_VERIFICATION_502`로 번역한다.

### `POST /verify/gps`
GPS 반경 판정. `application/json`. 모델을 부르지 않는다.

| 필드 | 타입 | 제약 |
|---|---|---|
| `target_lat` / `target_lng` | number | 등록된 위치. -90~90 / -180~180 |
| `radius_meters` | int | 허용 반경, 0보다 커야 함 |
| `submitted_lat` / `submitted_lng` | number | 인증 시도 좌표 |

**Response 200**:
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

> **반경 밖은 200 + `passed=false`다.** 400이 아니다 — 실패는 에러가 아니라 판정 결과다.
> 백엔드 A축은 같은 상황을 400 `GPS_OUT_OF_RANGE`로 끊는데, 그건 체크인 레코드를 만들지 않으려는
> 흐름 제어이지 판정의 성패가 아니다. 흐름 제어는 이 API를 부르는 쪽이 정한다.

### `POST /verify/check-in`
인증 방식 하나로 GPS·사진을 묶어 최종 판정까지. `multipart/form-data`

| 필드 | 필수 | 설명 |
|---|---|---|
| `verification_type` | O | `GPS` \| `AI` \| `GPS_PHOTO_AI` |
| `category`, `image` | AI 계열일 때 | 사진 판정 입력 |
| `target_lat`, `target_lng`, `radius_meters`, `submitted_lat`, `submitted_lng` | GPS 계열일 때 | GPS 판정 입력 |

최종 규칙은 백엔드 `finalizeDecisionAfterAi`와 같다.

| verification_type | 최종 판정 | 실패 사유 |
|---|---|---|
| `GPS` | `gps_passed` | `GPS_OUT_OF_RADIUS` |
| `AI` | `ai_passed` (GPS를 보지 않음) | `AI_REJECTED` |
| `GPS_PHOTO_AI` | `gps_passed AND ai_passed` | GPS 실패가 우선 |

**Response 200**:
```json
{
  "verification_type": "GPS_PHOTO_AI",
  "decision_status": "CONFIRMED",
  "final_passed": true,
  "failure_reason": null,
  "gps": { "passed": true, "distance_meters": 12.34, "...": "..." },
  "ai": { "passed": true, "confidence_score": 0.87, "...": "..." }
}
```

`decision_status`는 항상 `CONFIRMED`다. 사진까지 이 요청 안에서 받으므로 유보할 이유가 없다 —
`PENDING`은 백엔드가 체크인과 업로드를 두 번에 나눠 부를 때만 생긴다.

`PHOTO`·`GPS_PHOTO`는 400이다. 백엔드도 같은 값을 체크인 시점에 거절한다.

## 코드 구조

- `main.py` — FastAPI 앱, 엔드포인트 정의, 인증 방식별 판정 조합
- `config.py` — 환경변수 로드 (`POLICY_DIR`, `ANTHROPIC_MAX_TOKENS`, `ANTHROPIC_TIMEOUT_SECONDS`, `MAX_IMAGE_MB` 등)
- `schemas.py` — 요청·응답 Pydantic 모델, `Category`·`VerificationType` enum
- `policy.py` — `policies/verification.yaml` 로더 (`PolicyError`; 기동 시 1회, 실패하면 프로세스가 안 뜬다)
- `prompts.py` — `policy.py`가 읽은 정책을 카테고리별 모델 메시지로 조립 (문구 자체는 없음)
- `policies/verification.yaml` — **판정 기준·시스템 프롬프트 원본 (튜닝 대상, gitignored 아님)**
- `verifier.py` — LangChain 체인 (`LangChainVerifier`; 프로바이더 교체 시 `Verifier` 구현 추가)
- `gps.py` — Haversine 반경 판정 (백엔드 `GpsVerificationEvaluator` 포팅)
- `storage.py` — 저장소 인터페이스 (`LocalStorage`; S3 스왑 가능)
- `Dockerfile` — 컨테이너 이미지 빌드 정의
- `storage/` — 로컬 파일 저장 위치 (gitignored)
- `samples/` — 프롬프트 튜닝용 샘플 이미지 (gitignored)
- `batch_test.sh` — 튜닝 배치 테스트 스크립트

## 프롬프트 튜닝

### 1. 샘플 이미지 준비

`samples/{exercise,study}/{pass,fail}/` 폴더 아래에 카테고리·기대 결과별로
사진을 넣는다 (JPEG/PNG/WebP; 폴더 구조 자체가 기대값이므로 반대 폴더에
넣으면 정확도 집계가 틀어진다):

```
samples/
├── exercise/
│   ├── pass/   # 인증 통과해야 할 사진
│   └── fail/   # 거절돼야 할 사진
└── study/
    ├── pass/
    └── fail/
```

`samples/`는 gitignored라 커밋되지 않는다 — 각자 로컬에 채워 넣는다.

### 2. 서버 기동 + 실행

`.env`에 실제 `ANTHROPIC_API_KEY`가 있어야 한다 (§1 참조). 서버를 띄운 뒤:

```bash
uvicorn main:app --reload --port 8000   # 별도 터미널
bash batch_test.sh                      # 전체 카테고리
bash batch_test.sh EXERCISE             # 특정 카테고리만
```

서버가 안 떠 있거나, `.env`에 키가 없거나(`/health`의 `api_key_present`로 확인),
`samples/`가 아예 없으면 `batch_test.sh`가 curl 에러를 그대로 뱉는 대신 **무엇이
빠졌는지** 먼저 알려주고 종료한다.

### 3. 튜닝 루프 — 오판 찾기 → 정책 수정 → 골든 갱신 → 재실행

표 마지막 줄의 `정확도: N / M`으로 전체 성공률을 확인한다. `M`은 **채점 가능한**
사진(`pass`/`fail` 폴더 안에 있고 지원 형식인 것)만 센다 — 아래 두 종류는 분모에서 빠진다:

- `samples/<category>/` 바로 아래, `pass`/`fail` 밖에 있는 사진: 기대값이 없어 채점은
  안 되지만 판정 결과(“채점제외”로 표시)는 표에 그대로 나온다.
- `.HEIC` 등 지원하지 않는 형식: ai-service가 애초에 받지 않는 형식이라(§1.5) 호출
  자체를 안 하고 건너뛴다 — 아이폰이 같은 이름의 `.jpg`를 같이 내려주는 경우가 많으니
  `.jpg`/`.png`/`.webp`만 있으면 된다.

`✗` 나온 케이스를 확인했으면 다음 순서로 반영한다:

1. **`bash batch_test.sh`로 오판 찾기** (위 §2) — `✗` 표시된 케이스, 이유 칸 확인.
2. **`policies/verification.yaml`의 `categories.<CATEGORY>` 수정**으로 기준을 튜닝.
3. **골든 스냅샷 갱신 + 그 diff를 같은 커밋에 포함:**
   ```bash
   UPDATE_PROMPT_GOLDEN=1 .venv/bin/python -m pytest tests/test_prompt_policy.py
   ```
   `tests/test_prompt_policy.py`가 모델에게 실제로 나가는 payload 전체(system·
   instruction·필드 description·도구 description)를 `tests/golden/`에 스냅샷으로
   고정해 둔다. **YAML을 고쳤는데 골든을 안 갱신하면 이 테스트가 실패한다 —
   의도된 실패다.** 갱신된 golden diff를 리뷰어가 눈으로 보고 "프롬프트가 이렇게
   바뀌었다"를 확인할 수 있게, 정책 diff와 골든 diff를 같은 커밋에 넣어라.

   **반대 경우를 헷갈리지 마라:** `policies/verification.yaml`을 **안 건드렸는데**
   이 골든 테스트가 깨졌다면, 그건 튜닝이 아니라 **코드 변경이 프롬프트를 몰래
   바꿨다는 사고 신호**다 (예: `schemas.py`의 필드 정의나 `policy.py`의 조립 로직을
   건드렸을 때). 이 경우 골든을 갱신하지 말고 **원인부터 찾아라** — 갱신부터 하면
   그 사고가 리뷰 없이 그대로 들어간다.
4. **재실행.** `uvicorn`을 반드시 재기동해라 — `policy.py`는 기동 시 1회만 정책
   파일을 읽고, `--reload`는 `.py` 변경만 감지할 뿐 `.yaml`은 감지하지 않아서
   YAML만 고치고 재기동을 빼먹으면 조용히 예전 기준으로 계속 판정한다.

**실패 목록은 "이건 확실히 아니다"만 담은 좁은 목록이다.** 거기 안 걸리는 애매한 사진은
통과 목록과 각 카테고리 맨 윗줄의 정의문으로 판정된다 — 정의문이 마지막 방어선이다.
실패 규칙을 지울 땐 그 케이스를 정의문이 여전히 걸러내는지 `batch_test.sh`로 확인하라.

## 트러블슈팅

**`{"detail": "credit balance is too low"}`**
- Anthropic Console → Billing → Add credit

**`/verify`에서 500 반환, backend 로그에 "422 Field required" 보임**
- 백엔드→ai-service 호출 시 multipart 필드가 안 넘어가는 경우.
- 원인: Java HttpClient 기본 HTTP/2가 uvicorn과 호환 이슈.
- 백엔드 `AiVerificationClient`에 `HttpClient.Version.HTTP_1_1` 명시 되어있는지 확인.

**`ai_verification_results` 테이블 없음**
- 백엔드 마이그레이션이 안 적용된 것. `./gradlew bootRun` 재실행 → Flyway가 V10 적용.

## AI 오케스트레이션 — LangChain

모델 호출은 전부 LangChain을 거친다. 체인은 한 줄이다:

```python
ChatPromptTemplate | ChatAnthropic.with_structured_output(PhotoVerdict, include_raw=True)
```

**structured output이 핵심이다.** `PhotoVerdict` 스키마가 도구(tool) 정의로 바뀌어
`tool_choice`로 모델에 강제되므로, 응답 본문을 손으로 파싱하거나 코드펜스를 벗겨낼 일이 없다.
프롬프트에서 "JSON만 반환하라" 지시를 뺀 것도 그래서다.

**모델에게 나가는 문구는 눈에 보이는 두 곳(`system`, 사용자 메시지 텍스트)만이 아니다.**
`tools[].input_schema.properties[].description`(필드별 지시)과 `tools[].description`
(도구 자체 설명)도 LangChain이 그대로 실어 보낸다. 특히 후자는 한때 `PhotoVerdict`의
**클래스 docstring**이었다 — 코드를 설명하려고 쓴 문장이 그대로 판정 프롬프트가 되고
있었다. 지금은 네 갈래 전부 `policies/verification.yaml`에서 나오고(`schemas.py`가
`json_schema_extra`로 도구 설명을 덮어씀), `tests/test_prompt_policy.py`가 전체 payload를
골든 스냅샷으로 고정해 이 중 하나라도 조용히 바뀌는 걸 잡는다.

전환하며 사라진 것:

| 예전 | 지금 |
|---|---|
| `anthropic` SDK 직접 호출 | `ChatAnthropic` |
| 손으로 만든 base64 image 블록 | 표준 content block → LangChain이 변환 |
| `_parse_json_response` (코드펜스 제거 + JSON 파싱) | structured output |
| 파싱 실패 → `passed=false` 폴백 | `VerdictUnavailableError` → 502 |

GPS 판정에는 LangChain이 없다 — 모델이 개입할 일이 아닌 순수 계산이다.

## 테스트

```bash
python -m pytest tests -q
```

네트워크를 타지 않는다. `tests/test_langchain_chain.py`가 `ChatAnthropic._acreate`를 가로채
**실제로 조립된 요청 payload**(이미지 블록·도구 강제)를 검증하고, 도구 호출 응답을 흉내 내 돌려준다.
`tests/test_gps.py`는 백엔드와 같은 답이 나오는지 — 특히 경계값과 반올림 순서 — 를 지킨다.
`tests/test_config_wiring.py`는 `config.py`의 값(이미지 크기 상한, timeout·max_tokens)이
실제로 배선까지 이어지는지를 본다. `tests/test_prompt_policy.py`는 모델에게 나가는 문구
네 갈래(위 참조) 전체를 골든 스냅샷(`tests/golden/`)으로 고정한다. **골든이 깨졌을 때
`policies/verification.yaml`을 의도적으로 고친 게 맞다면 갱신하고 diff를 커밋에 포함하고
(절차는 "프롬프트 튜닝" §3), 정책 파일을 안 건드렸는데 깨졌다면 코드가 프롬프트를 몰래
바꿨다는 사고 신호이니 갱신하지 말고 원인부터 찾아라.**

## 의존성

- Python 3.13+
- FastAPI 0.115+
- LangChain (`langchain-anthropic`, `langchain-core`) — `anthropic` SDK는 여기에 딸려 온다
- Pillow (이미지 형식 검증)

전체 목록은 `requirements.txt`.
