"""악용 방어층 회귀 테스트 — 인증 가드·레이트리밋·EXIF 사전검사·보존 purge.

이 파일이 지키는 방어선:

1. `AI_SERVICE_API_KEY` 가 설정되면 `/verify*` 는 `X-API-Key` 없이 401 —
   ai-service 가 "Anthropic 키의 공짜 프록시"가 되는 것을 막는 층.
2. 키 미설정(무인증) 트래픽은 IP당 분당 상한(429) — 시크릿 없이 노출돼도
   비용 폭주를 막는 마지막 둑.
3. EXIF 촬영시각이 오래된 사진은 모델을 부르지 않고 반려 —
   "옛날 사진 재사용"의 가장 게으른 형태 차단.
4. 보존 기간이 지난 저장 이미지는 purge — 개인정보 무기한 보관 금지.

모델 호출은 전부 FakeVerifier 로 대체한다. 네트워크는 타지 않는다.
"""
import io
import os
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

import config  # noqa: E402
import main  # noqa: E402
from schemas import VerificationResult  # noqa: E402
from storage import LocalStorage  # noqa: E402
from verifier import Verifier  # noqa: E402


class FakeVerifier(Verifier):
    def __init__(self):
        self.calls = 0

    async def verify(self, image_bytes, media_type, category):
        self.calls += 1
        return VerificationResult(
            passed=True,
            confidence_score=0.9,
            detected_labels=["fake"],
            model_name="fake-model",
            reason="fake",
            raw_response={"passed": True},
        )


class TmpStorage:
    def __init__(self, tmp_path):
        self.tmp_path = tmp_path

    async def save(self, key, content):
        path = self.tmp_path / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return key


def _png_bytes() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (8, 8), "white").save(buf, format="PNG")
    return buf.getvalue()


def _jpeg_with_exif_datetime(taken_at: datetime) -> bytes:
    """EXIF DateTime(306) 을 박은 JPEG. `_exif_taken_at` 의 폴백 경로를 탄다."""
    img = Image.new("RGB", (8, 8), "white")
    exif = img.getexif()
    exif[306] = taken_at.strftime("%Y:%m:%d %H:%M:%S")  # DateTime
    buf = io.BytesIO()
    img.save(buf, format="JPEG", exif=exif)
    return buf.getvalue()


@pytest.fixture
def harness(monkeypatch, tmp_path):
    """Verifier·Storage 를 스왑하고 리밋 상태를 격리한 클라이언트."""
    fake = FakeVerifier()
    monkeypatch.setattr(main, "verifier", fake)
    monkeypatch.setattr(main, "storage", TmpStorage(tmp_path))
    # 테스트 간 리밋 상태 공유 방지 — 매번 새 리미터.
    monkeypatch.setattr(main, "_limiter", main.SlidingWindowLimiter(0))
    return TestClient(main.app), fake, monkeypatch


def _post_photo(client, image_bytes: bytes, headers: dict | None = None):
    return client.post(
        "/verify/photo",
        data={"category": "EXERCISE"},
        files={"image": ("photo.png", image_bytes, "image/png")},
        headers=headers or {},
    )


# ── 1. 공유 시크릿 ──────────────────────────────────────────────────────────

def test_verify_requires_api_key_when_configured(harness):
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "AI_SERVICE_API_KEY", "topsecret")

    resp = _post_photo(client, _png_bytes())
    assert resp.status_code == 401
    assert fake.calls == 0  # 모델은커녕 판정 흐름 자체에 못 들어간다


def test_verify_rejects_wrong_api_key(harness):
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "AI_SERVICE_API_KEY", "topsecret")

    resp = _post_photo(client, _png_bytes(), headers={"X-API-Key": "wrong"})
    assert resp.status_code == 401
    assert fake.calls == 0


def test_verify_accepts_correct_api_key(harness):
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "AI_SERVICE_API_KEY", "topsecret")

    resp = _post_photo(client, _png_bytes(), headers={"X-API-Key": "topsecret"})
    assert resp.status_code == 200
    assert fake.calls == 1


def test_gps_endpoint_is_guarded_too(harness):
    """가드는 사진뿐 아니라 판정 엔드포인트 전체에 걸린다."""
    client, _, monkeypatch = harness
    monkeypatch.setattr(config, "AI_SERVICE_API_KEY", "topsecret")

    resp = client.post("/verify/gps", json={
        "target_lat": 37.0, "target_lng": 127.0, "radius_meters": 100,
        "submitted_lat": 37.0, "submitted_lng": 127.0,
    })
    assert resp.status_code == 401


def test_health_stays_open_without_key(harness):
    """/health 는 docker healthcheck·batch_test 사전점검용이라 인증을 안 건다."""
    client, _, monkeypatch = harness
    monkeypatch.setattr(config, "AI_SERVICE_API_KEY", "topsecret")

    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["auth_required"] is True


# ── 2. 레이트리밋 ──────────────────────────────────────────────────────────

def test_unauthenticated_traffic_is_rate_limited(harness):
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "AI_SERVICE_API_KEY", "")  # 무인증 모드
    monkeypatch.setattr(main, "_limiter", main.SlidingWindowLimiter(2))

    png = _png_bytes()
    assert _post_photo(client, png).status_code == 200
    assert _post_photo(client, png).status_code == 200
    resp = _post_photo(client, png)
    assert resp.status_code == 429
    assert fake.calls == 2  # 세 번째는 모델 호출 비용이 나가기 전에 막힌다


def test_authenticated_traffic_skips_rate_limit(harness):
    """유효한 키를 낸 내부 트래픽(backend)은 리밋 면제 — 정상 부하를 막지 않는다."""
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "AI_SERVICE_API_KEY", "topsecret")
    monkeypatch.setattr(main, "_limiter", main.SlidingWindowLimiter(1))

    png = _png_bytes()
    headers = {"X-API-Key": "topsecret"}
    for _ in range(3):
        assert _post_photo(client, png, headers=headers).status_code == 200
    assert fake.calls == 3


def test_sliding_window_limiter_recovers_after_window():
    limiter = main.SlidingWindowLimiter(1)
    assert limiter.allow("1.2.3.4") is True
    assert limiter.allow("1.2.3.4") is False
    # 61초 전에 찍힌 것처럼 창을 되감아 회복을 확인한다.
    limiter._hits["1.2.3.4"][0] -= 61.0
    assert limiter.allow("1.2.3.4") is True


# ── 3. EXIF 촬영시각 사전검사 ───────────────────────────────────────────────

def test_stale_exif_photo_rejected_without_model_call(harness):
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "MAX_PHOTO_AGE_HOURS", 48)

    old = _jpeg_with_exif_datetime(datetime.now() - timedelta(days=30))
    resp = _post_photo(client, old)

    assert resp.status_code == 200  # 반려는 에러가 아니라 판정 결과다
    body = resp.json()
    assert body["passed"] is False
    assert body["model_name"] == "exif-precheck"
    assert "stale_photo_exif" in body["detected_labels"]
    assert fake.calls == 0  # 모델 호출 비용 없이 걸러졌다


def test_fresh_exif_photo_goes_to_model(harness):
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "MAX_PHOTO_AGE_HOURS", 48)

    fresh = _jpeg_with_exif_datetime(datetime.now() - timedelta(hours=1))
    resp = _post_photo(client, fresh)
    assert resp.status_code == 200
    assert resp.json()["passed"] is True
    assert fake.calls == 1


def test_photo_without_exif_goes_to_model(harness):
    """EXIF 없음은 거절 사유가 아니다 — 메신저·스크린샷이 EXIF 를 벗겨낸다."""
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "MAX_PHOTO_AGE_HOURS", 48)

    resp = _post_photo(client, _png_bytes())
    assert resp.status_code == 200
    assert fake.calls == 1


def test_exif_check_disabled_when_zero(harness):
    client, fake, monkeypatch = harness
    monkeypatch.setattr(config, "MAX_PHOTO_AGE_HOURS", 0)

    old = _jpeg_with_exif_datetime(datetime.now() - timedelta(days=365))
    resp = _post_photo(client, old)
    assert resp.status_code == 200
    assert fake.calls == 1


# ── 4. 저장 이미지 보존 purge ───────────────────────────────────────────────

def test_purge_removes_only_expired_files(tmp_path):
    storage = LocalStorage(tmp_path / "storage")
    old_file = storage.base_dir / "exercise/20200101/old.jpg"
    new_file = storage.base_dir / "exercise/20990101/new.jpg"
    for f in (old_file, new_file):
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(b"x")
    expired = time.time() - 31 * 86400
    os.utime(old_file, (expired, expired))

    removed = storage.purge_older_than(30)

    assert removed == 1
    assert not old_file.exists()
    assert new_file.exists()


def test_purge_disabled_when_zero_days(tmp_path):
    storage = LocalStorage(tmp_path / "storage")
    f = storage.base_dir / "a.jpg"
    f.write_bytes(b"x")
    ancient = time.time() - 999 * 86400
    os.utime(f, (ancient, ancient))

    assert storage.purge_older_than(0) == 0
    assert f.exists()


# ── 5. 판정 감사 — 정책 해시 각인 ──────────────────────────────────────────

def test_health_exposes_policy_sha256(harness):
    client, _, _ = harness
    body = client.get("/health").json()
    assert len(body["policy_sha256"]) == 64
    int(body["policy_sha256"], 16)  # hex 인가
