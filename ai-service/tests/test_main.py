"""엔드포인트의 경계 조건 회귀 방어.

모델 호출은 FakeVerifier로 대체하여 네트워크 없이 검증한다.
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
from verifier import Verifier, VerdictUnavailableError  # noqa: E402


class FakeVerifier(Verifier):
    def __init__(self, passed: bool = True, raises: bool = False):
        self.passed = passed
        self.raises = raises
        self.calls = 0

    async def verify(self, image_bytes, media_type, category):
        self.calls += 1
        if self.raises:
            raise VerdictUnavailableError("모델이 도구 호출을 하지 않음")
        return VerificationResult(
            passed=self.passed,
            confidence_score=0.9,
            detected_labels=["fake_label"],
            model_name="fake-model",
            reason="fake reason",
            raw_response={"passed": self.passed},
        )


class TmpStorage:
    def __init__(self, tmp_path):
        self.tmp_path = tmp_path

    async def save(self, key, content):
        path = self.tmp_path / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return key


@pytest.fixture
def make_client(monkeypatch, tmp_path):
    """Verifier와 Storage를 테스트용으로 스왑한 클라이언트를 만든다."""

    def _make(passed: bool = True, raises: bool = False):
        fake = FakeVerifier(passed=passed, raises=raises)
        monkeypatch.setattr(main, "verifier", fake)
        monkeypatch.setattr(main, "storage", TmpStorage(tmp_path))
        return TestClient(main.app), fake

    return _make


@pytest.fixture
def client(make_client):
    return make_client()


def _png_bytes(size=(10, 10)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, (255, 0, 0)).save(buf, format="PNG")
    return buf.getvalue()


def _png_upload(name="ok.png"):
    return {"image": (name, _png_bytes(), "image/png")}


# --------------------------------------------------------------------------
# /verify, /verify/photo — 사진 판정
# --------------------------------------------------------------------------


@pytest.mark.parametrize("path", ["/verify", "/verify/photo"])
def test_photo_rejects_when_content_is_not_a_real_image(client, path):
    """확장자만 이미지고 내용은 텍스트인 경우 → 415. 헤더가 아니라 매직넘버로 판별."""
    tc, _ = client
    fake_bytes = b"this is definitely not an image, even if we call it .jpeg"

    resp = tc.post(
        path,
        data={"category": Category.EXERCISE.value},
        files={"image": ("fake.jpeg", fake_bytes, "image/jpeg")},
    )
    assert resp.status_code == 415, resp.text
    assert "지원하지 않는 이미지 형식" in resp.json()["detail"]


@pytest.mark.parametrize("path", ["/verify", "/verify/photo"])
def test_photo_rejects_over_10mb(client, path):
    """정확히 10MB+1 바이트는 413. 매직넘버는 이미지여도 크기가 먼저 걸린다."""
    tc, _ = client
    payload = _png_bytes() + (b"\x00" * (10 * 1024 * 1024 + 1))

    resp = tc.post(
        path,
        data={"category": Category.EXERCISE.value},
        files={"image": ("big.png", payload, "image/png")},
    )
    assert resp.status_code == 413, resp.text
    assert "10MB" in resp.json()["detail"]


@pytest.mark.parametrize("path", ["/verify", "/verify/photo"])
def test_photo_happy_path(client, path):
    """정상 이미지 → 200, FakeVerifier가 반환한 필드가 응답에 그대로 실린다."""
    tc, fake = client
    resp = tc.post(
        path,
        data={"category": Category.STUDY.value},
        files=_png_upload(),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["passed"] is True
    assert body["confidence_score"] == 0.9
    assert body["model_name"] == "fake-model"
    assert body["storage_key"].startswith("study/")
    assert body["storage_key"].endswith(".png")
    assert fake.calls == 1


def test_photo_rejects_unknown_category(client):
    """ai-service가 모르는 카테고리(WAKE_UP 등)는 422. backend는 이걸 500으로 바꾼다."""
    tc, fake = client
    resp = tc.post(
        "/verify/photo",
        data={"category": "WAKE_UP"},
        files=_png_upload(),
    )
    assert resp.status_code == 422, resp.text
    assert fake.calls == 0


def test_photo_returns_502_when_verdict_unavailable(make_client):
    """판정을 못 받은 것은 '거절'이 아니다 → 502로 올려 재시도 가능하게 한다."""
    tc, _ = make_client(raises=True)
    resp = tc.post(
        "/verify/photo",
        data={"category": Category.EXERCISE.value},
        files=_png_upload(),
    )
    assert resp.status_code == 502, resp.text
    assert "AI 판정 실패" in resp.json()["detail"]


# --------------------------------------------------------------------------
# /verify/gps — GPS 판정
# --------------------------------------------------------------------------

# 서울시청 근처. 약 111m 떨어진 두 점(위도 0.001도 ≈ 111m).
_TARGET = {"target_lat": 37.5665, "target_lng": 126.9780}


def test_gps_within_radius(client):
    tc, _ = client
    resp = tc.post(
        "/verify/gps",
        json={
            **_TARGET,
            "radius_meters": 200,
            "submitted_lat": 37.5675,
            "submitted_lng": 126.9780,
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["passed"] is True
    assert body["failure_reason"] is None
    assert 110 < body["distance_meters"] < 112


def test_gps_out_of_radius_is_a_verdict_not_an_error(client):
    """반경 밖은 200 + passed=false. 400이 아니다."""
    tc, _ = client
    resp = tc.post(
        "/verify/gps",
        json={
            **_TARGET,
            "radius_meters": 50,
            "submitted_lat": 37.5675,
            "submitted_lng": 126.9780,
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["passed"] is False
    assert body["failure_reason"] == "GPS_OUT_OF_RADIUS"


def test_gps_rejects_out_of_range_coordinates(client):
    tc, _ = client
    resp = tc.post(
        "/verify/gps",
        json={
            "target_lat": 91.0,
            "target_lng": 126.9780,
            "radius_meters": 50,
            "submitted_lat": 37.5665,
            "submitted_lng": 126.9780,
        },
    )
    assert resp.status_code == 422, resp.text


def test_gps_rejects_non_positive_radius(client):
    """backend `@Positive` · DB CHECK(radius_meters > 0)와 같은 제약."""
    tc, _ = client
    resp = tc.post(
        "/verify/gps",
        json={**_TARGET, "radius_meters": 0, "submitted_lat": 37.5665, "submitted_lng": 126.9780},
    )
    assert resp.status_code == 422, resp.text


# --------------------------------------------------------------------------
# /verify/check-in — 인증 방식별 최종 판정
# --------------------------------------------------------------------------


def _near():
    return {"submitted_lat": 37.5665, "submitted_lng": 126.9780}


def _far():
    return {"submitted_lat": 37.5765, "submitted_lng": 126.9780}


def _gps_form(**overrides):
    form = {**_TARGET, "radius_meters": 50, **_near()}
    form.update(overrides)
    return form


def test_check_in_gps_only_does_not_call_the_model(client):
    tc, fake = client
    resp = tc.post(
        "/verify/check-in",
        data={"verification_type": "GPS", **_gps_form()},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["final_passed"] is True
    assert body["decision_status"] == "CONFIRMED"
    assert body["ai"] is None
    assert fake.calls == 0


def test_check_in_gps_only_fails_out_of_radius(client):
    tc, _ = client
    resp = tc.post(
        "/verify/check-in",
        data={"verification_type": "GPS", **_gps_form(**_far())},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["final_passed"] is False
    assert body["failure_reason"] == "GPS_OUT_OF_RADIUS"


def test_check_in_ai_only_ignores_gps(client):
    """AI 타입은 GPS를 아예 보지 않는다 — 좌표를 안 줘도 통과한다."""
    tc, fake = client
    resp = tc.post(
        "/verify/check-in",
        data={"verification_type": "AI", "category": Category.EXERCISE.value},
        files=_png_upload(),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["final_passed"] is True
    assert body["gps"] is None
    assert body["ai"]["storage_key"].startswith("exercise/")
    assert fake.calls == 1


def test_check_in_ai_rejected_reports_ai_reason(make_client):
    tc, _ = make_client(passed=False)
    resp = tc.post(
        "/verify/check-in",
        data={"verification_type": "AI", "category": Category.EXERCISE.value},
        files=_png_upload(),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["final_passed"] is False
    assert body["failure_reason"] == "AI_REJECTED"


def test_check_in_combined_requires_both_to_pass(client):
    tc, fake = client
    resp = tc.post(
        "/verify/check-in",
        data={
            "verification_type": "GPS_PHOTO_AI",
            "category": Category.EXERCISE.value,
            **_gps_form(),
        },
        files=_png_upload(),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["final_passed"] is True
    assert body["gps"]["passed"] is True
    assert body["ai"]["passed"] is True
    assert fake.calls == 1


def test_check_in_combined_gps_failure_wins_over_ai(make_client):
    """GPS와 AI가 둘 다 실패하면 사유는 GPS다 — backend와 같은 우선순위."""
    tc, _ = make_client(passed=False)
    resp = tc.post(
        "/verify/check-in",
        data={
            "verification_type": "GPS_PHOTO_AI",
            "category": Category.EXERCISE.value,
            **_gps_form(**_far()),
        },
        files=_png_upload(),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["final_passed"] is False
    assert body["failure_reason"] == "GPS_OUT_OF_RADIUS"


@pytest.mark.parametrize("unsupported", ["PHOTO", "GPS_PHOTO", "SOMETHING_ELSE"])
def test_check_in_rejects_unsupported_verification_type(client, unsupported):
    """backend도 PHOTO·GPS_PHOTO를 체크인 시점에 400으로 거절한다."""
    tc, _ = client
    resp = tc.post(
        "/verify/check-in",
        data={"verification_type": unsupported, **_gps_form()},
    )
    assert resp.status_code == 400, resp.text
    assert "지원하지 않는 인증 방식" in resp.json()["detail"]


def test_check_in_requires_gps_fields_for_gps_type(client):
    tc, _ = client
    resp = tc.post("/verify/check-in", data={"verification_type": "GPS"})
    assert resp.status_code == 400, resp.text
    detail = resp.json()["detail"]
    assert "target_lat" in detail and "radius_meters" in detail


def test_check_in_requires_image_for_ai_type(client):
    tc, _ = client
    resp = tc.post(
        "/verify/check-in",
        data={"verification_type": "AI", "category": Category.EXERCISE.value},
    )
    assert resp.status_code == 400, resp.text
    assert "image와 category가 필요함" in resp.json()["detail"]


def test_health_reports_orchestrator(client):
    tc, _ = client
    body = tc.get("/health").json()
    assert body["status"] == "ok"
    assert body["orchestrator"] == "langchain"
