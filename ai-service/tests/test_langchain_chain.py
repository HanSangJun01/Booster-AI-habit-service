"""LangChain 체인이 Anthropic으로 내보내는 요청과 받아오는 응답의 배선 검증.

네트워크는 타지 않는다. `ChatAnthropic._acreate` 를 가로채 **실제로 조립된
요청 payload** 를 붙잡고, 도구 호출 응답을 흉내 내 돌려준다. 여기서 보는 것:

- 이미지가 Anthropic 네이티브 블록(`source.type=base64`)으로 변환되는가
- `PhotoVerdict` 스키마가 도구로 강제되는가 (`tool_choice`)
- 도구 인자가 `VerificationResult` 로 정확히 옮겨지는가
- 판정을 못 받으면 거절이 아니라 예외가 되는가
"""
import asyncio
import base64
import sys
from pathlib import Path

import pytest
from anthropic.types import Message, TextBlock, ToolUseBlock, Usage

sys.path.insert(0, str(Path(__file__).parent.parent))

import prompts  # noqa: E402
from schemas import Category  # noqa: E402
from verifier import LangChainVerifier, VerdictUnavailableError  # noqa: E402

_IMAGE = b"\x89PNG\r\n\x1a\n fake bytes"


class _FakeRawResponse:
    """`_aparse` 가 기대하는 최소 인터페이스(`.parse()`)."""

    def __init__(self, message: Message) -> None:
        self._message = message

    def parse(self) -> Message:
        return self._message


def _message(content: list) -> Message:
    return Message(
        id="msg_fake",
        type="message",
        role="assistant",
        model="claude-haiku-4-5",
        content=content,
        stop_reason="tool_use",
        usage=Usage(input_tokens=10, output_tokens=10),
    )


def _install(verifier: LangChainVerifier, response: Message) -> dict:
    """모델 호출을 가로채고, 마지막으로 조립된 payload를 담을 그릇을 돌려준다."""
    captured: dict = {}

    async def _acreate(payload: dict):
        captured.update(payload)
        return _FakeRawResponse(response)

    verifier.llm._acreate = _acreate
    return captured


@pytest.fixture
def verifier() -> LangChainVerifier:
    return LangChainVerifier(api_key="sk-fake", model="claude-haiku-4-5")


def test_request_carries_native_image_block_and_forced_tool(verifier):
    captured = _install(
        verifier,
        _message(
            [
                ToolUseBlock(
                    id="tu_1",
                    type="tool_use",
                    name="PhotoVerdict",
                    input={
                        "passed": True,
                        "confidence_score": 0.83,
                        "detected_labels": ["dumbbell", "gym"],
                        "reason": "덤벨을 들고 있는 장면이 보인다.",
                    },
                )
            ]
        ),
    )

    result = asyncio.run(verifier.verify(_IMAGE, "image/png", Category.EXERCISE))

    # --- 요청: 이미지가 네이티브 블록으로 변환됐는가
    blocks = captured["messages"][0]["content"]
    image_block = next(b for b in blocks if b["type"] == "image")
    assert image_block["source"]["type"] == "base64"
    assert image_block["source"]["media_type"] == "image/png"
    assert image_block["source"]["data"] == base64.standard_b64encode(_IMAGE).decode()

    # 카테고리 기준이 텍스트로 함께 갔는가.
    # 문구 그대로("운동 인증" 등)에 결합하면 프롬프트 튜닝 때마다 테스트가
    # 깨진다 — 정책 소스(prompts.py)가 실제로 만든 값과 같은지만 본다.
    text_block = next(b for b in blocks if b["type"] == "text")
    assert text_block["text"] == prompts.build_instruction(Category.EXERCISE)
    assert captured["system"] == prompts.SYSTEM_PROMPT

    # --- 요청: 스키마가 도구로 강제됐는가
    assert captured["tool_choice"] == {"type": "tool", "name": "PhotoVerdict"}
    tool = next(t for t in captured["tools"] if t["name"] == "PhotoVerdict")
    assert set(tool["input_schema"]["properties"]) == {
        "passed",
        "confidence_score",
        "detected_labels",
        "reason",
    }

    # --- 응답: 도구 인자가 그대로 옮겨졌는가
    assert result.passed is True
    assert result.confidence_score == 0.83
    assert result.detected_labels == ["dumbbell", "gym"]
    assert result.reason == "덤벨을 들고 있는 장면이 보인다."
    assert result.model_name == "claude-haiku-4-5"
    assert result.raw_response["confidence_score"] == 0.83


def test_study_category_sends_study_criteria(verifier):
    captured = _install(
        verifier,
        _message(
            [
                ToolUseBlock(
                    id="tu_1",
                    type="tool_use",
                    name="PhotoVerdict",
                    input={
                        "passed": False,
                        "confidence_score": 0.2,
                        "detected_labels": [],
                        "reason": "책 표지만 보인다.",
                    },
                )
            ]
        ),
    )

    result = asyncio.run(verifier.verify(_IMAGE, "image/jpeg", Category.STUDY))

    text_block = next(
        b for b in captured["messages"][0]["content"] if b["type"] == "text"
    )
    assert text_block["text"] == prompts.build_instruction(Category.STUDY)
    assert result.passed is False


def test_exercise_and_study_receive_different_instructions():
    """카테고리별로 다른 기준이 실제로 전달되는가 — 문구가 아니라 이 사실이 진짜 계약이다.

    위 두 테스트가 '전달된 텍스트 == 정책 소스가 만든 텍스트'만 보장하므로,
    정책 소스 자체가 실수로 카테고리 구분 없이 같은 문구를 내도 안 잡힌다.
    이 테스트가 그 구멍을 막는다.
    """
    assert prompts.build_instruction(Category.EXERCISE) != prompts.build_instruction(
        Category.STUDY
    )


def test_missing_tool_call_raises_instead_of_rejecting(verifier):
    """모델이 도구를 안 쓰고 말로 답한 경우.

    예전 구현은 이걸 `passed=False` 로 폴백해서 **거절과 구분되지 않았다.**
    지금은 예외로 올라가 502가 되고, 사용자는 재시도할 수 있다.
    """
    _install(
        verifier,
        _message([TextBlock(type="text", text="음, 판단하기 어렵네요")]),
    )

    with pytest.raises(VerdictUnavailableError):
        asyncio.run(verifier.verify(_IMAGE, "image/png", Category.EXERCISE))


def test_upstream_api_error_becomes_verdict_unavailable(verifier):
    """업스트림 실패(인증·과부하·타임아웃)도 '거절'이 아니라 판정 실패다."""
    from anthropic import APIStatusError

    class _Resp:
        status_code = 401
        headers: dict = {}
        request = None

    async def _acreate(payload):
        raise APIStatusError(
            "API key is invalid.",
            response=_Resp(),  # type: ignore[arg-type]
            body=None,
        )

    verifier.llm._acreate = _acreate

    with pytest.raises(VerdictUnavailableError) as excinfo:
        asyncio.run(verifier.verify(_IMAGE, "image/png", Category.EXERCISE))
    assert "업스트림" in str(excinfo.value)
