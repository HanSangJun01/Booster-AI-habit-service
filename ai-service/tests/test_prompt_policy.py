"""프롬프트 회귀 감시 — **모델에게 나가는 문구 전체를 골든 파일로 고정한다.**

## 왜 이 테스트가 있나

판정 프롬프트는 한 곳에 있지 않다. 실제로 모델에게 나가는 문구는 네 갈래다:

1. `system` — 판별기 역할·판단 원칙
2. 사용자 메시지의 텍스트 블록 — 카테고리별 판정 기준
3. `tools[].input_schema.properties[].description` — 필드별 출력 지시
4. `tools[].description` — 도구 자체의 설명

3번과 4번이 함정이다. 둘 다 `schemas.py` 의 평범한 파이썬 코드처럼 생겼다.
특히 4번은 클래스 **docstring** 이었어서, 코드를 설명하려고 쓴 문장이 판정
프롬프트로 나가고 있었다. 실제로 리팩터링 중에 그 docstring 을 고쳤다가
라이브 프롬프트를 바꾼 사고가 있었고, 그때 이 사실을 발견했다.

사람의 주의력으로는 못 막는다. 그래서 payload 전체를 스냅샷으로 박아둔다.

## 골든이 깨졌을 때 무엇을 해야 하나

**실패는 두 가지 중 하나다. 이걸 구분하는 게 사람의 일이다.**

- **정책을 일부러 튜닝했다** (`policies/verification.yaml` 을 고쳤거나 카테고리를
  추가했다) → 정상이다. 아래 명령으로 골든을 갱신하고, **갱신된 diff 를
  커밋에 포함해 리뷰어가 프롬프트 변경을 눈으로 보게 하라.**

  ```
  UPDATE_PROMPT_GOLDEN=1 .venv/bin/python -m pytest tests/test_prompt_policy.py
  ```

- **정책 파일을 안 고쳤는데 깨졌다** → 사고다. 코드 변경이 프롬프트를 바꿨다는
  뜻이다. docstring 을 손봤거나, Field 를 건드렸거나, 스키마 구조가 바뀌었다.
  골든을 갱신하지 말고 **왜 바뀌었는지 먼저 밝혀라.**

네트워크는 타지 않는다. `ChatAnthropic._acreate` 를 가로채 실제로 조립된
payload 를 붙잡는다 — 이 테스트가 보는 것은 "우리 코드가 만들려던 것"이 아니라
"실제로 나가는 것"이다.
"""

import asyncio
import difflib
import json
import os
import sys
from pathlib import Path

import pytest
from anthropic.types import Message, ToolUseBlock, Usage

sys.path.insert(0, str(Path(__file__).parent.parent))

import prompts  # noqa: E402
from schemas import Category, PhotoVerdict  # noqa: E402
from verifier import LangChainVerifier  # noqa: E402

GOLDEN_PATH = Path(__file__).parent / "golden" / "prompt_payload.json"
UPDATE_ENV = "UPDATE_PROMPT_GOLDEN"
UPDATE_CMD = (
    f"{UPDATE_ENV}=1 .venv/bin/python -m pytest tests/test_prompt_policy.py"
)

# 이미지 바이트는 프롬프트가 아니다. 스냅샷에서 빼려고 고정값을 쓴다.
_IMAGE = b"\x89PNG\r\n\x1a\n golden fixture"


class _FakeRawResponse:
    def __init__(self, message: Message) -> None:
        self._message = message

    def parse(self) -> Message:
        return self._message


def _tool_use_response() -> Message:
    return Message(
        id="msg_golden",
        type="message",
        role="assistant",
        model="claude-haiku-4-5",
        stop_reason="tool_use",
        usage=Usage(input_tokens=1, output_tokens=1),
        content=[
            ToolUseBlock(
                id="tu_1",
                type="tool_use",
                name="PhotoVerdict",
                input={
                    "passed": True,
                    "confidence_score": 0.5,
                    "detected_labels": [],
                    "reason": "골든 픽스처",
                },
            )
        ],
    )


def _capture(category: Category) -> dict:
    """한 카테고리로 판정을 돌려 실제 조립된 요청 payload 를 붙잡는다."""
    captured: dict = {}

    async def _acreate(payload: dict):
        captured.update(payload)
        return _FakeRawResponse(_tool_use_response())

    verifier = LangChainVerifier(api_key="sk-fake", model="claude-haiku-4-5")
    verifier.llm._acreate = _acreate
    asyncio.run(verifier.verify(_IMAGE, "image/png", category))
    return captured


def _prompt_surface() -> dict:
    """모델에게 나가는 문구만 추린다.

    모델 이름·max_tokens·이미지 바이트는 뺀다 — 프롬프트가 아니라 설정이고,
    환경에 따라 달라져서 넣으면 골든이 헛되이 깨진다.
    """
    per_category = {c.value: _capture(c) for c in Category}
    # tools·tool_choice 는 카테고리와 무관하다. 정말 그런지도 여기서 확인한다.
    first = per_category[next(iter(per_category))]
    for name, payload in per_category.items():
        assert payload["tools"] == first["tools"], f"{name}: 도구 정의가 카테고리마다 다르다"
        assert payload["system"] == first["system"], f"{name}: system 이 카테고리마다 다르다"

    return {
        "system": first["system"],
        "tool_choice": first["tool_choice"],
        "tools": first["tools"],
        "instructions": {
            name: next(
                b["text"] for b in payload["messages"][0]["content"] if b["type"] == "text"
            )
            for name, payload in per_category.items()
        },
    }


def _dump(surface: dict) -> str:
    return json.dumps(surface, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def test_prompt_payload_matches_golden():
    """모델에게 나가는 문구 전체가 골든과 같은가."""
    surface = _prompt_surface()
    actual = _dump(surface)

    if os.environ.get(UPDATE_ENV):
        GOLDEN_PATH.parent.mkdir(parents=True, exist_ok=True)
        GOLDEN_PATH.write_text(actual, encoding="utf-8")
        pytest.skip(f"골든 갱신함: {GOLDEN_PATH} — 이 diff 를 커밋에 포함하라")

    if not GOLDEN_PATH.exists():
        pytest.fail(
            f"골든 파일이 없다: {GOLDEN_PATH}\n"
            f"처음 만드는 것이라면: {UPDATE_CMD}"
        )

    expected = GOLDEN_PATH.read_text(encoding="utf-8")
    if actual == expected:
        return

    diff = "\n".join(
        difflib.unified_diff(
            expected.splitlines(),
            actual.splitlines(),
            fromfile="golden (커밋된 프롬프트)",
            tofile="actual (지금 나가는 프롬프트)",
            lineterm="",
        )
    )
    pytest.fail(
        "모델에게 나가는 프롬프트가 골든과 다르다.\n"
        "\n"
        f"{diff}\n"
        "\n"
        "── 무엇을 해야 하나 ─────────────────────────────────────────\n"
        "policies/verification.yaml 을 일부러 고쳤거나 카테고리를 추가했다면\n"
        "정상이다. 골든을 갱신하고 그 diff 를 커밋에 포함해라:\n"
        f"    {UPDATE_CMD}\n"
        "\n"
        "정책 파일을 안 고쳤는데 이게 깨졌다면 사고다. 코드 변경이 프롬프트를\n"
        "바꿨다는 뜻이다 (docstring 수정, Field 변경, 스키마 구조 변화 등).\n"
        "골든을 갱신하지 말고 왜 바뀌었는지 먼저 밝혀라.\n"
        "────────────────────────────────────────────────────────────"
    )


def test_class_docstring_does_not_reach_the_model():
    """`PhotoVerdict` 의 docstring 이 프롬프트로 새지 않는가.

    이게 이 파일이 생긴 계기다. 예전엔 이 docstring 이 그대로
    `tools[].description` 으로 나갔다. 지금은 `json_schema_extra` 가 정책
    파일 값으로 덮어쓴다. 그 덮어쓰기가 사라지면 여기서 잡힌다.
    """
    payload = _capture(Category.EXERCISE)
    tool = next(t for t in payload["tools"] if t["name"] == "PhotoVerdict")

    docstring = PhotoVerdict.__doc__ or ""
    assert docstring.strip(), "docstring 이 비었다 — 이 테스트가 의미를 잃는다"

    # 첫 줄만 봐도 충분하다. 통째로 비교하면 docstring 을 조금만 고쳐도 통과해버린다.
    first_line = docstring.strip().splitlines()[0]
    blob = json.dumps(payload, ensure_ascii=False)
    assert first_line not in blob, (
        f"PhotoVerdict 의 docstring 이 모델에게 가고 있다: {first_line!r}\n"
        "schemas.py 의 `model_config = ConfigDict(json_schema_extra=...)` 가 "
        "사라졌거나 무력화됐다. 도구 설명은 "
        "policies/verification.yaml::output_description 에서 와야 한다."
    )


def test_tool_description_comes_from_policy_file():
    """도구 설명이 정책 파일 값과 정확히 같은가."""
    from policy import POLICY

    payload = _capture(Category.STUDY)
    tool = next(t for t in payload["tools"] if t["name"] == "PhotoVerdict")
    assert tool["description"] == POLICY.output_description


def test_field_descriptions_come_from_policy_file():
    """필드별 출력 지시가 정책 파일 값과 정확히 같은가.

    `Field(description=...)` 는 코드처럼 보이지만 프롬프트다. 누가 여기에
    문구를 직접 박아 넣으면 정책 파일과 어긋나고, 그때 잡는다.
    """
    from policy import POLICY

    payload = _capture(Category.EXERCISE)
    tool = next(t for t in payload["tools"] if t["name"] == "PhotoVerdict")
    properties = tool["input_schema"]["properties"]

    assert set(properties) == set(POLICY.output_fields), (
        "도구 스키마의 필드와 정책 파일의 output_fields 가 어긋난다: "
        f"스키마={sorted(properties)} 정책={sorted(POLICY.output_fields)}"
    )
    for name, prop in properties.items():
        assert prop.get("description") == POLICY.output_fields[name], (
            f"'{name}' 필드 설명이 정책 파일과 다르다: "
            f"스키마={prop.get('description')!r} 정책={POLICY.output_fields[name]!r}"
        )


def test_every_category_sends_its_own_criteria():
    """카테고리마다 서로 다른 기준이 실제로 나가는가.

    `build_instruction` 이 카테고리를 무시하고 같은 문구를 돌려주는 사고를 잡는다.
    """
    from policy import POLICY

    texts = {}
    for category in Category:
        payload = _capture(category)
        texts[category.value] = next(
            b["text"] for b in payload["messages"][0]["content"] if b["type"] == "text"
        )
        assert POLICY.criteria(category.value) in texts[category.value]
        assert texts[category.value] == prompts.build_instruction(category)

    assert len(set(texts.values())) == len(texts), f"카테고리별 기준이 겹친다: {list(texts)}"
