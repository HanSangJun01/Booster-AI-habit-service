"""config.py 상수가 실제로 배선되는지에 대한 회귀 방어.

`config.py`가 값을 갖고 있는 것과 그 값이 실제로 쓰이는 것은 다른 문제다.
main.py나 verifier.py가 여전히 하드코딩된 숫자를 쓰면 `.env`로 아무것도
바꿀 수 없다 — 이 파일은 그 배선이 실제로 이어졌는지만 본다.
"""
import io
import sys
from pathlib import Path

from fastapi.testclient import TestClient
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

import config  # noqa: E402
import main  # noqa: E402
from verifier import LangChainVerifier  # noqa: E402


def _png_bytes(size=(10, 10)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, (255, 0, 0)).save(buf, format="PNG")
    return buf.getvalue()


def test_413_message_follows_max_image_mb_config(monkeypatch):
    """MAX_IMAGE_MB를 5로 낮추면 413 메시지도 "5MB"로 바뀌어야 한다.

    상수만 바꾸고 메시지는 여전히 "10MB"라고 말하면 사용자에게 거짓을
    알리는 것이다 — main.py가 메시지를 리터럴이 아니라 config에서
    조립하는지를 여기서 확인한다.
    """
    monkeypatch.setattr(config, "MAX_IMAGE_MB", 5)
    monkeypatch.setattr(config, "MAX_IMAGE_BYTES", 5 * 1024 * 1024)

    tc = TestClient(main.app)
    payload = _png_bytes() + (b"\x00" * (5 * 1024 * 1024 + 1))
    resp = tc.post(
        "/verify/photo",
        data={"category": "EXERCISE"},
        files={"image": ("big.png", payload, "image/png")},
    )

    assert resp.status_code == 413, resp.text
    detail = resp.json()["detail"]
    assert "5MB" in detail
    assert "10MB" not in detail


def test_app_verifier_uses_configured_max_tokens_and_timeout():
    """main.py가 만드는 전역 verifier가 config 값을 실제로 물고 있는가."""
    assert main.verifier.llm.max_tokens == config.ANTHROPIC_MAX_TOKENS
    assert main.verifier.llm.default_request_timeout == config.ANTHROPIC_TIMEOUT_SECONDS


def test_langchain_verifier_passes_max_tokens_and_timeout_to_chat_anthropic():
    """`LangChainVerifier` 자체가 인자를 `ChatAnthropic`에 그대로 넘기는가.

    위 테스트가 main.py 배선을 보장한다면, 이건 verifier.py 쪽 계약이다 —
    둘 중 하나만 지키고 다른 하나가 깨지는 걸 따로 잡기 위해 나눈다.
    """
    verifier = LangChainVerifier(
        api_key="sk-fake", model="claude-haiku-4-5", max_tokens=111, timeout=3.5
    )
    assert verifier.llm.max_tokens == 111
    assert verifier.llm.default_request_timeout == 3.5
