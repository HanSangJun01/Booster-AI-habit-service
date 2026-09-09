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

import asyncio
import io
import logging
import secrets
import time
import uuid
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from PIL import ExifTags, Image, UnidentifiedImageError

import config
import gps
from policy import POLICY
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

logger = logging.getLogger("ai-service")


class SlidingWindowLimiter:
    """IP당 분당 요청 상한. 프로세스 메모리 기반 — 단일 워커 전제다.

    판정 한 건이 실제 과금되는 모델 호출이므로, 인증과 **별개로** 상한을 둔다.
    시크릿이 새거나 미설정인 채 노출돼도 폭주 비용을 막는 마지막 둑이다.
    """

    def __init__(self, limit_per_minute: int) -> None:
        self.limit = limit_per_minute
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        if self.limit <= 0:
            return True
        now = time.monotonic()
        window = self._hits[key]
        while window and now - window[0] > 60.0:
            window.popleft()
        if len(window) >= self.limit:
            return False
        window.append(now)
        # 임의 IP를 무한히 기억하면 그 자체가 메모리 DoS 벡터다. 가끔 비운다.
        if len(self._hits) > 10_000:
            for k in [k for k, v in self._hits.items() if not v]:
                del self._hits[k]
        return True


_limiter = SlidingWindowLimiter(config.RATE_LIMIT_PER_MINUTE)


async def _guard_verify(
    request: Request,
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
) -> None:
    """판정 엔드포인트 공용 가드 — 시크릿 검사 + 레이트리밋.

    - `AI_SERVICE_API_KEY` 가 설정돼 있으면 `X-API-Key` 일치가 필수(401).
      비교는 타이밍 공격을 피해 `secrets.compare_digest` 로 한다.
    - 유효한 키를 낸 요청(backend)은 레이트리밋을 건너뛴다 — 리밋의 목적은
      무인증 폭주 차단이지 내부 트래픽 스로틀이 아니다.
    - 키가 미설정(로컬 개발)이면 전 요청이 무인증이므로 리밋만 적용된다.
    """
    if config.AI_SERVICE_API_KEY:
        if x_api_key is None or not secrets.compare_digest(
            x_api_key, config.AI_SERVICE_API_KEY
        ):
            raise HTTPException(401, "X-API-Key가 없거나 일치하지 않음")
        return  # 인증된 내부 트래픽 — 리밋 면제
    client_ip = request.client.host if request.client else "unknown"
    if not _limiter.allow(client_ip):
        raise HTTPException(429, "요청이 너무 잦음 — 잠시 후 다시 시도")


async def _retention_loop() -> None:
    """기동 직후 1회 + 24시간마다 보존 기간 지난 인증 사진을 지운다."""
    while True:
        await asyncio.to_thread(
            storage.purge_older_than, config.STORAGE_RETENTION_DAYS
        )
        await asyncio.sleep(86400)


@asynccontextmanager
async def _lifespan(app: FastAPI):
    # 어떤 정책으로 뜨는지 기동 로그에 박는다 — 볼륨 마운트로 기준이 갈리는
    # 구조라, 이 한 줄이 "그때 무슨 기준이었나"를 되짚는 시작점이다.
    logger.info("판정 정책 로드: %s (sha256=%s)", POLICY.path, POLICY.sha256)
    if not config.AI_SERVICE_API_KEY:
        logger.warning(
            "AI_SERVICE_API_KEY 미설정 — /verify* 가 무인증으로 열려 있다. "
            "로컬 개발 외에는 반드시 설정하라."
        )
    retention = asyncio.create_task(_retention_loop())
    try:
        yield
    finally:
        retention.cancel()


app = FastAPI(title="Booster AI Verification Service", lifespan=_lifespan)

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
        # 판정 감사용 — 지금 어떤 정책 파일로 판정 중인지. 볼륨 교체가 실제로
        # 먹었는지를 실 판정 없이 확인하는 용도이기도 하다.
        "policy_sha256": POLICY.sha256,
        "auth_required": bool(config.AI_SERVICE_API_KEY),
        "rate_limit_per_minute": config.RATE_LIMIT_PER_MINUTE,
        "storage_retention_days": config.STORAGE_RETENTION_DAYS,
        "max_photo_age_hours": config.MAX_PHOTO_AGE_HOURS,
    }


@app.post(
    "/verify/gps",
    response_model=GpsVerificationResult,
    dependencies=[Depends(_guard_verify)],
)
async def verify_gps(request: GpsVerificationRequest) -> GpsVerificationResult:
    """GPS 반경 판정. Spring을 거치지 않는다.

    **반경 밖은 에러가 아니라 판정 결과다** — 200에 `passed=false` 로 답한다.
    backend A축은 같은 상황을 400 `GPS_OUT_OF_RANGE` 로 끊지만, 그건 체크인
    레코드를 만들지 않으려는 흐름 제어이지 판정의 성패가 아니다.
    """
    return _evaluate_gps(request)


@app.post(
    "/verify/photo",
    response_model=VerificationResult,
    dependencies=[Depends(_guard_verify)],
)
async def verify_photo(
    category: Category = Form(...),
    image: UploadFile = File(...),
) -> VerificationResult:
    """사진 AI 판정. 이미지를 저장하고 LangChain 체인으로 판정한다."""
    content = await _read_image(image)
    media_type = _require_media_type(content)
    storage_key = await _store(content, media_type, category)

    result = await _precheck_or_verify(content, media_type, category)
    result.storage_key = storage_key
    return result


@app.post(
    "/verify",
    response_model=VerificationResult,
    dependencies=[Depends(_guard_verify)],
)
async def verify(
    category: Category = Form(...),
    image: UploadFile = File(...),
) -> VerificationResult:
    """`/verify/photo` 와 같다. backend `AiVerificationClient` 가 부르는 경로."""
    return await verify_photo(category=category, image=image)


@app.post(
    "/verify/check-in",
    response_model=CheckInVerificationResult,
    dependencies=[Depends(_guard_verify)],
)
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
        ai_result = await _precheck_or_verify(content, media_type, category)
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


#: EXIF 촬영시각 포맷. 타임존 정보가 없다 — 그래서 비교 임계값을 넉넉히 잡는다.
_EXIF_DATETIME_FORMAT = "%Y:%m:%d %H:%M:%S"


def _exif_taken_at(content: bytes) -> datetime | None:
    """EXIF 촬영시각(DateTimeOriginal, 없으면 DateTime). 못 읽으면 None.

    EXIF 는 클라이언트가 통제하는 데이터라 **없다고 거절할 수는 없다**
    (메신저·스크린샷·일부 카메라 앱이 벗겨낸다). 있는데 오래됐을 때만 잡는다 —
    "옛날 사진 재사용"의 가장 게으른 형태를 모델 호출 비용 없이 걸러내는 층이다.
    """
    try:
        with Image.open(io.BytesIO(content)) as img:
            exif = img.getexif()
            raw = exif.get_ifd(ExifTags.IFD.Exif).get(
                ExifTags.Base.DateTimeOriginal
            ) or exif.get(ExifTags.Base.DateTime)
    except (UnidentifiedImageError, OSError, KeyError):
        return None
    if not raw:
        return None
    try:
        return datetime.strptime(str(raw).strip(), _EXIF_DATETIME_FORMAT)
    except ValueError:
        return None


async def _precheck_or_verify(
    content: bytes, media_type: str, category: Category
) -> VerificationResult:
    """모델을 부르기 전 코드로 걸러낼 수 있는 반려를 먼저 처리한다.

    지금 걸러내는 것은 EXIF 촬영시각이 오래된 사진 하나다. 모델은 "운동으로
    보이는가"만 알지 "오늘 찍었는가"는 원리적으로 모른다 — 최근성은 코드의 몫.
    반려는 판정 실패(502)가 아니라 **판정 결과**이므로 200 `passed=false` 다.
    """
    taken_at = _exif_taken_at(content)
    if taken_at is not None and config.MAX_PHOTO_AGE_HOURS > 0:
        age_hours = (datetime.now() - taken_at).total_seconds() / 3600
        if age_hours > config.MAX_PHOTO_AGE_HOURS:
            return VerificationResult(
                passed=False,
                confidence_score=1.0,
                detected_labels=["stale_photo_exif"],
                model_name="exif-precheck",
                reason=(
                    f"사진의 촬영 시각(EXIF)이 약 {age_hours:.0f}시간 전으로, "
                    f"허용 한도({config.MAX_PHOTO_AGE_HOURS}시간)를 초과함. "
                    f"오늘 촬영한 사진으로 다시 인증 필요."
                ),
                raw_response={
                    "precheck": "stale_exif",
                    "exif_taken_at": taken_at.isoformat(),
                    "policy_sha256": POLICY.sha256,
                },
            )
    return await _run_verifier(content, media_type, category)


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
