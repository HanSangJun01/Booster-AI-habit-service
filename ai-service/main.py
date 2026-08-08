import io
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from PIL import Image, UnidentifiedImageError

import config
from schemas import Category, VerificationResult
from storage import LocalStorage
from verifier import AnthropicVerifier

app = FastAPI(title="Booster AI Verification Service")

storage = LocalStorage(config.STORAGE_DIR)
verifier = AnthropicVerifier(
    api_key=config.ANTHROPIC_API_KEY,
    model=config.ANTHROPIC_MODEL,
)


@app.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "model": config.ANTHROPIC_MODEL,
        "api_key_present": bool(config.ANTHROPIC_API_KEY),
    }


@app.post("/verify", response_model=VerificationResult)
async def verify(
    category: Category = Form(...),
    image: UploadFile = File(...),
) -> VerificationResult:
    content = await image.read()
    if len(content) > config.MAX_IMAGE_BYTES:
        raise HTTPException(413, "이미지 크기가 10MB를 초과함")

    media_type = _sniff_media_type(content)
    if media_type is None:
        raise HTTPException(415, "지원하지 않는 이미지 형식 (JPEG/PNG/WebP만 허용)")

    ext = media_type.split("/")[1]
    key = f"{category.value.lower()}/{datetime.now(timezone.utc):%Y%m%d}/{uuid.uuid4().hex}.{ext}"
    storage_key = await storage.save(key, content)

    result = await verifier.verify(content, media_type, category)
    result.storage_key = storage_key
    return result


_ALLOWED_MEDIA = {
    "JPEG": "image/jpeg",
    "PNG": "image/png",
    "WEBP": "image/webp",
}


def _sniff_media_type(content: bytes) -> str | None:
    try:
        with Image.open(io.BytesIO(content)) as img:
            fmt = img.format or ""
            img.verify()
    except (UnidentifiedImageError, OSError):
        return None
    return _ALLOWED_MEDIA.get(fmt)
