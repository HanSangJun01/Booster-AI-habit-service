"""
/verify 엔드포인트의 경계 조건 회귀 방어.
Anthropic 호출은 FakeVerifier로 대체하여 네트워크 없이 검증한다.
"""
import io
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from PIL import Image

# ai-service를 sys.path에 추가 (tests/ 아래에서 실행되어도 main을 임포트할 수 있게)
sys.path.insert(0, str(Path(__file__).parent.parent))

import main  # noqa: E402
from schemas import Category, VerificationResult  # noqa: E402
from verifier import Verifier, _parse_json_response  # noqa: E402


class FakeVerifier(Verifier):
    def __init__(self, passed: bool = True):
        self.passed = passed
        self.calls = 0

    async def verify(self, image_bytes, media_type, category):
        self.calls += 1
        return VerificationResult(
            passed=self.passed,
            confidence_score=0.9,
            detected_labels=["fake_label"],
            model_name="fake-model",
            reason="fake reason",
            raw_response={"passed": self.passed},
        )


@pytest.fixture
def client(monkeypatch, tmp_path):
    # Verifier와 Storage를 테스트용으로 스왑
    fake = FakeVerifier(passed=True)
    monkeypatch.setattr(main, "verifier", fake)

    class TmpStorage:
        async def save(self, key, content):
            path = tmp_path / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            return key

    monkeypatch.setattr(main, "storage", TmpStorage())
    return TestClient(main.app), fake


def _png_bytes(size=(10, 10)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, (255, 0, 0)).save(buf, format="PNG")
    return buf.getvalue()


def test_verify_rejects_when_content_is_not_a_real_image(client):
    """확장자만 이미지고 내용은 텍스트인 경우 → 415. Content-Type 헤더가 아니라 매직넘버로 판별."""
    tc, _ = client
    fake_bytes = b"this is definitely not an image, even if we call it .jpeg"

    resp = tc.post(
        "/verify",
        data={"category": Category.EXERCISE.value},
        files={"image": ("fake.jpeg", fake_bytes, "image/jpeg")},
    )
    assert resp.status_code == 415, resp.text
    assert "지원하지 않는 이미지 형식" in resp.json()["detail"]


def test_verify_rejects_over_10mb(client):
    """정확히 10MB+1 바이트는 413. 매직넘버는 이미지여도 크기가 먼저 걸린다."""
    tc, _ = client
    # PNG 헤더로 시작하되 뒤에 무의미한 바이트를 채워 크기만 초과시킨다.
    payload = _png_bytes() + (b"\x00" * (10 * 1024 * 1024 + 1))

    resp = tc.post(
        "/verify",
        data={"category": Category.EXERCISE.value},
        files={"image": ("big.png", payload, "image/png")},
    )
    assert resp.status_code == 413, resp.text
    assert "10MB" in resp.json()["detail"]


def test_verify_happy_path_with_fake_verifier(client):
    """정상 이미지 → 200, FakeVerifier가 반환한 필드가 응답에 그대로 실린다."""
    tc, fake = client
    resp = tc.post(
        "/verify",
        data={"category": Category.STUDY.value},
        files={"image": ("ok.png", _png_bytes(), "image/png")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["passed"] is True
    assert body["confidence_score"] == 0.9
    assert body["model_name"] == "fake-model"
    assert body["storage_key"].startswith("study/")
    assert body["storage_key"].endswith(".png")
    assert fake.calls == 1


def test_parse_json_response_strips_fenced_block():
    """LLM이 ```json ... ``` 로 감싸서 반환해도 파싱해야 한다."""
    text = '```json\n{"passed": true, "confidence_score": 0.7, "detected_labels": [], "reason": "ok"}\n```'
    parsed = _parse_json_response(text)
    assert parsed["passed"] is True
    assert parsed["confidence_score"] == 0.7


def test_parse_json_response_falls_back_when_garbage():
    """완전히 깨진 응답이면 passed=False로 안전하게 폴백해야 한다."""
    parsed = _parse_json_response("이건 JSON이 아니에요 그냥 텍스트")
    assert parsed["passed"] is False
    assert parsed["confidence_score"] == 0.0
    assert parsed["detected_labels"] == []
    assert "파싱 실패" in parsed["reason"]
