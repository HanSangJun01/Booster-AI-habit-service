<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-05-28 | Updated: 2026-08-29 -->

# ai-service

## Purpose
FastAPI 인증 서비스. **사진 AI 판정**과 **GPS 반경 판정**을 한다.
사진 판정은 LangChain으로 Claude Vision을 부르고, GPS 판정은 서비스 안에서 직접 계산한다.
상태를 갖지 않는다 — 저장은 전부 `../backend/` 의 몫이고, 여기엔 판정된 이미지 파일만 남는다.

## Key Files

| File | Description |
|------|-------------|
| `main.py` | FastAPI 앱. 엔드포인트 정의와 인증 방식별 판정 조합 |
| `verifier.py` | LangChain 체인 (`ChatPromptTemplate \| ChatAnthropic.with_structured_output`) |
| `gps.py` | Haversine 반경 판정. backend `GpsVerificationEvaluator` 포팅 |
| `policy.py` | `policies/verification.yaml` 로더. 기동 시 1회 읽고, 카테고리 정합성이 안 맞으면 기동 자체를 막는다 |
| `prompts.py` | `policy.py`가 읽은 정책을 모델에 보낼 메시지로 조립 (튜닝 대상 문구 자체는 없음) |
| `schemas.py` | 요청·응답 Pydantic 모델, `Category`·`VerificationType` enum |
| `storage.py` | 저장소 인터페이스 (`LocalStorage`; S3 스왑 가능) |
| `config.py` | 환경변수 로드 (`POLICY_DIR`, `ANTHROPIC_MAX_TOKENS`, `ANTHROPIC_TIMEOUT_SECONDS`, `MAX_IMAGE_MB`, `ALLOWED_IMAGE_MEDIA_TYPES`) |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `tests/` | pytest. 네트워크를 타지 않는다 |
| `storage/` | 판정된 이미지 (gitignored) |
| `samples/` | 프롬프트 튜닝용 샘플 이미지 (gitignored) |
| `prompts/` | 판정 정책 원본 (`verification.yaml`; **튜닝은 여기** — gitignored 아님) |

## For AI Agents

### Working In This Directory

- **`POST /verify` 의 요청·응답 형식을 바꾸지 말 것.** backend `AiVerificationClient` 가
  이 계약에 의존한다. 필드 이름 하나만 바꿔도 backend가 깨진다.
- **`gps.py` 는 backend `GpsVerificationEvaluator` 와 같은 답을 내야 한다.**
  갈라지면 같은 사용자가 한쪽에서는 통과하고 다른 쪽에서는 실패한다.
  `tests/test_gps.py` 가 경계값과 반올림 순서를 지킨다.
- **모델 호출은 LangChain을 거친다.** `anthropic` SDK를 직접 부르지 말 것
  (예외 타입 import는 예외). 프로바이더를 바꾸려면 `Verifier` ABC를 구현해
  `main.py` 에서 주입한다.
- **판정 실패를 `passed=false` 로 내리지 말 것.** 모델이 스키마대로 답하지 않거나
  업스트림이 실패한 것은 "기준 미달"과 다른 일이다. `VerdictUnavailableError` → 502.
- **모델에게 나가는 문구는 `system`·사용자 메시지 텍스트만이 아니다.** `PhotoVerdict`의
  필드 `description`과 도구 자체의 `description`(전에는 클래스 docstring이었다)도
  그대로 모델에 실려 간다. 문구를 고치려면 `policies/verification.yaml`만 고쳐라 —
  `schemas.py::PhotoVerdict`의 docstring은 이제 모델에 안 가지만, 헷갈리기 쉬우니
  거기에 실제 지시문을 적지 말 것.
- 이 서비스는 무인증이다 (내부망 전제). 인증·소유권 검증·중복 차단은 backend의 몫이다.

### Testing Requirements

```bash
python -m pytest tests -q
```

네트워크 없이 돈다. 모델 호출은 `ChatAnthropic._acreate` 를 가로채 검증한다
(`tests/test_langchain_chain.py`). `tests/test_prompt_policy.py`는 모델에게 나가는
문구 전체(위 네 갈래)를 골든 스냅샷으로 고정한다.

**이 골든이 깨졌을 때 원인이 둘로 갈리고, 대응은 정반대다.**
`policies/verification.yaml`을 **의도적으로 튜닝했다면** 정상이다 —
`UPDATE_PROMPT_GOLDEN=1 pytest tests/test_prompt_policy.py`로 갱신하고, **그 diff를
같은 커밋·리뷰에 포함**해라. 반대로 정책 파일을 **안 건드렸는데** 깨졌다면 그건
코드 변경(`schemas.py`·`policy.py` 등)이 프롬프트를 몰래 바꿨다는 **사고 신호**다 —
이땐 갱신하지 말고 원인부터 찾아라. "골든 깨지면 갱신"으로만 알고 있으면 사고를
덮는 버튼이 된다.

프롬프트 *품질* 평가(사진이 실제로 잘 걸러지는가)는 단위 테스트가 아니라
`batch_test.sh` + `samples/` 로 따로 한다.

### Common Patterns

- 판정 결과는 Pydantic 모델로 돌려준다. 실패도 **에러가 아니라 결과**다
  (`passed=false`) — 흐름 제어는 호출자가 정한다.
- 새 카테고리를 늘릴 땐 `schemas.py::Category` 와 `policies/verification.yaml::categories` 를
  **함께** 고친다. 한쪽만 고치면 `policy.py::require_category_coverage` 가 기동을 막는다
  (런타임 500 대신 기동 실패로 앞당긴 것 — 조용히 넘어가지 않는다).

## Dependencies

### Internal
- `../backend/` 가 `POST /verify` 를 호출한다. 단독 엔드포인트는 앱이 직접 부를 수 있다.
- 어느 쪽으로도 backend·frontend를 호출하지 않는다.

### External
- FastAPI · uvicorn · Pydantic v2
- LangChain (`langchain-anthropic`, `langchain-core`) — `anthropic` SDK는 여기에 딸려 온다
- Pillow (매직넘버로 이미지 형식 검증)

## 관련 문서

- API 계약: `../docs/api/AI_SERVICE_SPEC.md`
- 실행·튜닝 방법: `README.md`

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
