"""사진 판정 — LangChain 기반 오케스트레이션.

## 무엇이 바뀌었나

예전엔 `anthropic` SDK를 직접 불러 응답 텍스트를 손으로 파싱했다. 그 구조에는
조용한 결함이 하나 있었다 — 모델이 JSON 형식을 어기면 예외가 아니라
`passed=False` 로 폴백해서, **모델이 형식을 틀린 것과 실제로 인증을 거절한 것을
호출자가 구분할 수 없었다.** 사용자는 멀쩡한 사진을 올리고 거절당한다.

LangChain의 structured output은 `PhotoVerdict` 스키마를 도구 정의로 바꿔
모델이 반드시 그 모양으로 답하게 만든다. 그래도 결과를 못 받으면 이제
[`VerdictUnavailableError`] 를 던지고, `main.py` 가 이를 502로 바꾼다.
502는 backend `AiVerificationClient` 가 재시도 가능한 실패(`AI_VERIFICATION_502`)로
번역하는 코드라, 거짓 거절 대신 재시도가 된다.

## 갈아끼우는 자리

[`Verifier`] 는 그대로 남는다. 프로바이더를 바꾸려면 이 ABC를 구현해
`main.py` 에서 주입하면 되고, 테스트도 같은 방법으로 가짜 판정기를 넣는다.
"""

import base64
from abc import ABC, abstractmethod

# langchain-anthropic이 끌어오는 SDK. 예외 타입만 쓴다 — 호출은 LangChain이 한다.
from anthropic import APIError
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate

import prompts
from schemas import Category, PhotoVerdict, VerificationResult


class VerdictUnavailableError(RuntimeError):
    """모델에서 판정을 받지 못했다. **인증 거절이 아니라 판정 실패다.**

    - 모델이 스키마대로 답하지 않았거나
    - 업스트림(Anthropic) 호출 자체가 실패했거나

    어느 쪽이든 "이 사진은 기준 미달"과는 다른 일이다. 이걸 `passed=false` 로
    내리면 멀쩡한 사진을 올린 사용자가 반려당한다.
    """


class Verifier(ABC):
    @abstractmethod
    async def verify(
        self,
        image_bytes: bytes,
        media_type: str,
        category: Category,
    ) -> VerificationResult:
        ...


# 이미지·기준·시스템 문구를 전부 **변수**로 넣는다. 프롬프트 텍스트를 템플릿에
# 직접 박으면 나중에 중괄호가 하나 섞이는 순간 임포트 시점에 터진다 —
# 변수로 넘긴 값은 다시 템플릿으로 해석되지 않아 그 사고가 없다.
_PROMPT = ChatPromptTemplate.from_messages(
    [
        ("system", "{system}"),
        (
            "human",
            [
                {"type": "image", "base64": "{image_b64}", "mime_type": "{media_type}"},
                {"type": "text", "text": "{instruction}"},
            ],
        ),
    ]
)


class LangChainVerifier(Verifier):
    """`ChatPromptTemplate | ChatAnthropic.with_structured_output` 체인."""

    def __init__(
        self,
        api_key: str,
        model: str,
        max_tokens: int = 512,
        # 30.0이 아니라 25.0이다. backend `AiVerificationClient` 도 30초에 끊으므로
        # 같은 값이면 어느 쪽이 먼저 터질지가 경합이고, backend가 먼저 끊으면
        # "AI 판정 실패" 사유가 남지 않는다. 안쪽인 여기가 먼저 끊어져야
        # `VerdictUnavailableError` → 502 → 재시도 가능한 실패로 번역된다.
        # 실제 운영값은 `config.ANTHROPIC_TIMEOUT_SECONDS` 로 넘어온다.
        timeout: float = 25.0,
    ) -> None:
        self.model = model
        self.llm = ChatAnthropic(
            model=model,
            max_tokens=max_tokens,
            api_key=api_key,
            timeout=timeout,
        )
        # include_raw=True — 파싱 실패를 `parsing_error` 로 손에 쥐기 위해서다.
        # 기본값이면 LangChain 예외가 그대로 올라와, 여기서 도메인 예외로
        # 바꿔 담으며 사유를 붙일 자리가 없다.
        self._chain = _PROMPT | self.llm.with_structured_output(
            PhotoVerdict, include_raw=True
        )

    async def verify(
        self,
        image_bytes: bytes,
        media_type: str,
        category: Category,
    ) -> VerificationResult:
        image_b64 = base64.standard_b64encode(image_bytes).decode("ascii")
        try:
            result = await self._chain.ainvoke(
                {
                    "system": prompts.SYSTEM_PROMPT,
                    "instruction": prompts.build_instruction(category),
                    "image_b64": image_b64,
                    "media_type": media_type,
                }
            )
        except APIError as exc:
            # 인증 실패·과부하·타임아웃 등 업스트림 사정. 스택트레이스를 500으로
            # 흘리지 않고 판정 실패로 정리한다.
            raise VerdictUnavailableError(f"업스트림 호출 실패: {exc}") from exc

        verdict = result.get("parsed")
        error = result.get("parsing_error")
        if verdict is None:
            raise VerdictUnavailableError(
                f"구조화된 판정을 받지 못함: {error}"
            )

        return VerificationResult(
            passed=verdict.passed,
            confidence_score=verdict.confidence_score,
            detected_labels=list(verdict.detected_labels),
            model_name=self.model,
            reason=verdict.reason,
            raw_response=verdict.model_dump(),
        )
