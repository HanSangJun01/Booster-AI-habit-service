# ai-service

Booster AI 인증 서비스. 사진 + 카테고리(`EXERCISE`, `STUDY`)를 받아 Claude Vision(Haiku 4.5)으로 판정한다.

관련 문서: `../docs/api/AI_SERVICE_SPEC.md`

## 아키텍처 위치

```
Flutter 앱 → 백엔드 (Spring) → ai-service (FastAPI) → Anthropic Claude Vision API
                    ↓
                PostgreSQL
```

백엔드가 `POST /api/verification-submissions/{id}/ai-verification`를 받으면 이 서비스의 `POST /verify`를 호출한다.
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
# → {"status":"ok","model":"claude-haiku-4-5-20251001","api_key_present":true}

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
{"status": "ok", "model": "claude-haiku-4-5-20251001", "api_key_present": true}
```

### `POST /verify`
`multipart/form-data`

| 필드 | 타입 | 설명 |
|---|---|---|
| `category` | string | `EXERCISE` \| `STUDY` |
| `image` | file | JPEG/PNG/WebP, 10MB 이하 |

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

**Response 4xx**:
| 상태 | 상황 |
|---|---|
| 400 | Anthropic 크레딧 부족 (upstream 400 그대로 전달) |
| 413 | 이미지 10MB 초과 |
| 415 | 지원 안 하는 이미지 형식 |
| 422 | 필드 누락 |

## 코드 구조

- `main.py` — FastAPI 앱, 엔드포인트 정의
- `config.py` — 환경변수 로드
- `schemas.py` — 요청·응답 Pydantic 모델, `Category` enum
- `prompts.py` — 카테고리별 판정 프롬프트 (튜닝 대상)
- `verifier.py` — Vision API wrapper (`AnthropicVerifier`; 프로바이더 교체 시 여기 확장)
- `storage.py` — 저장소 인터페이스 (`LocalStorage`; S3 스왑 가능)
- `Dockerfile` — 컨테이너 이미지 빌드 정의
- `storage/` — 로컬 파일 저장 위치 (gitignored)
- `samples/` — 프롬프트 튜닝용 샘플 이미지 (gitignored)
- `batch_test.sh` — 튜닝 배치 테스트 스크립트

## 프롬프트 튜닝

`samples/{exercise,study}/{pass,fail}/` 폴더에 사진 넣고:

```bash
bash batch_test.sh              # 전체 카테고리
bash batch_test.sh EXERCISE     # 특정 카테고리만
```

결과 표에서 `✗` 나온 케이스 위주로 `prompts.py` 수정 후 재실행.
uvicorn `--reload`로 프롬프트 변경 자동 반영됨.

카테고리·판정 기준의 상세 정책은 `prompts.py::_CATEGORY_CRITERIA` 상단 주석 참조 (엄격 정책: 산책·저강도 스포츠·동화책 등 실패 처리).

## 트러블슈팅

**`{"detail": "credit balance is too low"}`**
- Anthropic Console → Billing → Add credit

**`/verify`에서 500 반환, backend 로그에 "422 Field required" 보임**
- 백엔드→ai-service 호출 시 multipart 필드가 안 넘어가는 경우.
- 원인: Java HttpClient 기본 HTTP/2가 uvicorn과 호환 이슈.
- 백엔드 `AiVerificationClient`에 `HttpClient.Version.HTTP_1_1` 명시 되어있는지 확인.

**`ai_verification_results` 테이블 없음**
- 백엔드 마이그레이션이 안 적용된 것. `./gradlew bootRun` 재실행 → Flyway가 V10 적용.

## 의존성

- Python 3.13+
- FastAPI 0.115+
- Anthropic SDK 0.40+
- Pillow (이미지 형식 검증)

전체 목록은 `requirements.txt`.
