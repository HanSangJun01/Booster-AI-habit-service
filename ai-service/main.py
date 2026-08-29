"""Booster 인증 서비스 API.

## 두 갈래의 사용처

1. **backend 경유** — `POST /verify` 는 Spring `AiVerificationClient` 가 부르는
   기존 계약이다. 요청·응답 모양을 바꾸면 backend가 깨진다(이번 작업에서 backend는
   수정하지 않는다).
2. **ai-service 단독** — `POST /verify/gps` · `POST /verify/photo` ·
   `POST /verify/check-in` 은 Spring을 거치지 않고 판정만 받아 가는 경로다.
   GPS 판정을 backend에서 옮겨왔으므로(`gps.py`) 판정에 DB가 필요 없다.

## 단독 경로가 하지 않는 일

**판정만 한다.** 인증·소유권 확인, 중복 인증 차단, 체크인 레코드 생성,
스트릭·코인 지급은 전부 backend의 몫이고 여기엔 저장소가 없다. 그래서
`/verify/check-in` 은 "이 좌표와 이 사진이 기준을 통과하는가"에만 답한다.
"""

import io
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from PIL import Image, UnidentifiedImageError

import config
import gps
from schemas import (
    FAILURE_AI_REJECTED,
    FAILURE_GPS_OUT_OF_RADIUS,
    Category,
    CheckInVerificationResult,
    DecisionStatus,
    GpsVerificationRequest,
    GpsVerificationResult,
    VerificationResult,
    VerificationType,
)
from storage import LocalStorage
from verifier import LangChainVerifier, VerdictUnavailableError

app = FastAPI(title="Booster AI Verification Service")

storage = LocalStorage(config.STORAGE_DIR)
verifier = LangChainVerifier(
    api_key=config.ANTHROPIC_API_KEY,
    model=config.ANTHROPIC_MODEL,
    max_tokens=config.ANTHROPIC_MAX_TOKENS,
    timeout=config.ANTHROPIC_TIMEOUT_SECONDS,
)


@app.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "model": config.ANTHROPIC_MODEL,
        "api_key_present": bool(config.ANTHROPIC_API_KEY),
        "orchestrator": "langchain",
        # timeout·categories는 .env로만 바뀌는 값이라 재기동 없인 눈으로 확인할 길이
        # 없다 — 배포 직후 "설정이 실제로 먹었는가"를 실 판정 없이 확인하기 위함.
        "categories": [c.value for c in Category],
        "anthropic_timeout_seconds": config.ANTHROPIC_TIMEOUT_SECONDS,
    }


@app.post("/verify/gps", response_model=GpsVerificationResult)
async def verify_gps(request: GpsVerificationRequest) -> GpsVerificationResult:
    """GPS 반경 판정. Spring을 거치지 않는다.

    **반경 밖은 에러가 아니라 판정 결과다** — 200에 `passed=false` 로 답한다.
    backend A축은 같은 상황을 400 `GPS_OUT_OF_RANGE` 로 끊지만, 그건 체크인
    레코드를 만들지 않으려는 흐름 제어이지 판정의 성패가 아니다.
    """
    return _evaluate_gps(request)


@app.post("/verify/photo", response_model=VerificationResult)
async def verify_photo(
    category: Category = Form(...),
    image: UploadFile = File(...),
) -> VerificationResult:
    """사진 AI 판정. 이미지를 저장하고 LangChain 체인으로 판정한다."""
    content = await _read_image(image)
    media_type = _require_media_type(content)
    storage_key = await _store(content, media_type, category)

    result = await _run_verifier(content, media_type, category)
    result.storage_key = storage_key
    return result


@app.post("/verify", response_model=VerificationResult)
async def verify(
    category: Category = Form(...),
    image: UploadFile = File(...),
) -> VerificationResult:
    """`/verify/photo` 와 같다. backend `AiVerificationClient` 가 부르는 경로."""
    return await verify_photo(category=category, image=image)


@app.post("/verify/check-in", response_model=CheckInVerificationResult)
async def verify_check_in(
    verification_type: str = Form(...),
    category: Category | None = Form(None),
    image: UploadFile | None = File(None),
    target_lat: float | None = Form(None),
    target_lng: float | None = Form(None),
    radius_meters: int | None = Form(None),
    submitted_lat: float | None = Form(None),
    submitted_lng: float | None = Form(None),
) -> CheckInVerificationResult:
    """인증 방식 하나로 GPS·사진을 묶어 최종 판정까지 낸다.

    backend가 체크인과 사진 업로드 두 번에 나눠 하던 판정을 한 번에 한다.
    최종 규칙은 backend `finalizeDecisionAfterAi` 와 같다:

    | verification_type | 최종 판정 |
    |---|---|
    | `GPS` | gps_passed |
    | `AI` | ai_passed (GPS를 보지 않는다) |
    | `GPS_PHOTO_AI` | gps_passed AND ai_passed |
    """
    vtype = _require_verification_type(verification_type)
    needs_gps = vtype in (VerificationType.GPS, VerificationType.GPS_PHOTO_AI)
    needs_ai = vtype in (VerificationType.AI, VerificationType.GPS_PHOTO_AI)

    gps_result: GpsVerificationResult | None = None
    if needs_gps:
        gps_result = _evaluate_gps(
            _require_gps_fields(
                vtype, target_lat, target_lng, radius_meters, submitted_lat, submitted_lng
            )
        )

    ai_result: VerificationResult | None = None
    if needs_ai:
        if image is None or category is None:
            raise HTTPException(
                400, f"{vtype.value} 인증에는 image와 category가 필요함"
            )
        content = await _read_image(image)
        media_type = _require_media_type(content)
        storage_key = await _store(content, media_type, category)
        ai_result = await _run_verifier(content, media_type, category)
        ai_result.storage_key = storage_key

    # backend는 AI 타입에서 GPS를 아예 보지 않으므로 gps_passed를 참으로 고정한다.
    gps_passed = gps_result.passed if gps_result is not None else True
    ai_passed = ai_result.passed if ai_result is not None else True
    final_passed = gps_passed and ai_passed

    if final_passed:
        failure_reason = None
    elif not gps_passed:
        failure_reason = FAILURE_GPS_OUT_OF_RADIUS
    else:
        failure_reason = FAILURE_AI_REJECTED

    return CheckInVerificationResult(
        verification_type=vtype,
        decision_status=DecisionStatus.CONFIRMED,
        final_passed=final_passed,
        failure_reason=failure_reason,
        gps=gps_result,
        ai=ai_result,
    )


def _evaluate_gps(request: GpsVerificationRequest) -> GpsVerificationResult:
    distance = gps.haversine_distance_meters(
        request.target_lat,
        request.target_lng,
        request.submitted_lat,
        request.submitted_lng,
    )
    # 판정은 반올림 전 거리로 한다 — backend와 같은 순서다.
    passed = distance <= request.radius_meters
    return GpsVerificationResult(
        passed=passed,
        distance_meters=gps.round_distance_meters(distance),
        radius_meters=request.radius_meters,
        target_lat=request.target_lat,
        target_lng=request.target_lng,
        submitted_lat=request.submitted_lat,
        submitted_lng=request.submitted_lng,
        failure_reason=None if passed else FAILURE_GPS_OUT_OF_RADIUS,
    )


def _require_verification_type(raw: str) -> VerificationType:
    try:
        return VerificationType(raw)
    except ValueError:
        # backend도 PHOTO·GPS_PHOTO를 체크인 시점에 400으로 거절한다.
        supported = ", ".join(t.value for t in VerificationType)
        raise HTTPException(
            400, f"지원하지 않는 인증 방식: {raw} (지원: {supported})"
        )


def _require_gps_fields(
    vtype: VerificationType,
    target_lat: float | None,
    target_lng: float | None,
    radius_meters: int | None,
    submitted_lat: float | None,
    submitted_lng: float | None,
) -> GpsVerificationRequest:
    missing = [
        name
        for name, value in (
            ("target_lat", target_lat),
            ("target_lng", target_lng),
            ("radius_meters", radius_meters),
            ("submitted_lat", submitted_lat),
            ("submitted_lng", submitted_lng),
        )
        if value is None
    ]
    if missing:
        raise HTTPException(
            400,
            f"{vtype.value} 인증에는 GPS 필드가 필요함: {', '.join(missing)}",
        )
    return GpsVerificationRequest(
        target_lat=target_lat,
        target_lng=target_lng,
        radius_meters=radius_meters,
        submitted_lat=submitted_lat,
        submitted_lng=submitted_lng,
    )


async def _read_image(image: UploadFile) -> bytes:
    content = await image.read()
    if len(content) > config.MAX_IMAGE_BYTES:
        # 메시지를 상수에서 조립한다 — MAX_IMAGE_MB를 바꿨는데 메시지가
        # "10MB"로 고정돼 있으면 사용자에게 거짓을 알리게 된다.
        raise HTTPException(413, f"이미지 크기가 {config.MAX_IMAGE_MB}MB를 초과함")
    return content


def _require_media_type(content: bytes) -> str:
    media_type = _sniff_media_type(content)
    if media_type is None:
        allowed = "/".join(config.ALLOWED_IMAGE_MEDIA_TYPES)
        raise HTTPException(415, f"지원하지 않는 이미지 형식 ({allowed}만 허용)")
    return media_type


async def _store(content: bytes, media_type: str, category: Category) -> str:
    ext = media_type.split("/")[1]
    key = (
        f"{category.value.lower()}/{datetime.now(timezone.utc):%Y%m%d}/"
        f"{uuid.uuid4().hex}.{ext}"
    )
    return await storage.save(key, content)


async def _run_verifier(
    content: bytes, media_type: str, category: Category
) -> VerificationResult:
    try:
        return await verifier.verify(content, media_type, category)
    except VerdictUnavailableError as exc:
        # 판정을 못 받은 것을 '거절'로 내리면 멀쩡한 사진이 반려된다.
        # 502로 올려 backend가 AI_VERIFICATION_502(재시도 가능)로 번역하게 한다.
        raise HTTPException(502, f"AI 판정 실패: {exc}")


def _sniff_media_type(content: bytes) -> str | None:
    try:
        with Image.open(io.BytesIO(content)) as img:
            fmt = img.format or ""
            img.verify()
    except (UnidentifiedImageError, OSError):
        return None
    return config.ALLOWED_IMAGE_MEDIA_TYPES.get(fmt)
