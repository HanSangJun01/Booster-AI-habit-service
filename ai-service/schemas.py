from enum import Enum

from pydantic import BaseModel, ConfigDict, Field

from policy import POLICY


class Category(str, Enum):
    """AI 사진 판정이 아는 카테고리. 이 둘 외의 값은 422다."""

    EXERCISE = "EXERCISE"
    STUDY = "STUDY"


# 여기가 카테고리를 늘리는 자리이므로, 정책 파일이 따라왔는지도 여기서 본다.
# 값만 추가하고 `policies/verification.yaml` 을 빠뜨리면 예전엔 그 카테고리로 첫
# 요청이 올 때 500이 났다. 이제는 임포트가 실패해 배포가 먼저 멈춘다.
POLICY.require_category_coverage({c.value for c in Category})


class VerificationType(str, Enum):
    """인증 방식. backend `challenges.verification_type` 중 지원되는 3종.

    `PHOTO`·`GPS_PHOTO`는 backend 체크인이 처리하지 못해 400으로 거절하는 값이라
    여기서도 받지 않는다 — 좀비 챌린지를 만들지 않기 위한 같은 제약이다.
    """

    GPS = "GPS"
    AI = "AI"
    GPS_PHOTO_AI = "GPS_PHOTO_AI"


class DecisionStatus(str, Enum):
    """판정 확정 여부. backend `verification_decisions.decision_status` 와 같은 값."""

    PENDING = "PENDING"
    CONFIRMED = "CONFIRMED"


#: backend `ChallengeCheckInService` 가 쓰는 실패 사유 문자열. 값까지 맞춘다.
FAILURE_GPS_OUT_OF_RADIUS = "GPS_OUT_OF_RADIUS"
FAILURE_AI_REJECTED = "AI_REJECTED"


class PhotoVerdict(BaseModel):
    """LLM이 채워야 하는 판정 결과. **이 docstring은 모델에게 가지 않는다.**

    이 클래스가 만드는 도구 스키마는 통째로 프롬프트다 — 필드 description도,
    도구 자체의 description도 모델이 읽는다. 그래서 문구는 전부
    `policies/verification.yaml` 에 있고 여기서는 주입만 한다.

    `json_schema_extra` 로 도구 설명을 덮어쓰는 이유가 이것이다. 이게 없으면
    pydantic이 **이 docstring을** 도구 설명으로 써버려서, 개발자에게 코드를
    설명하려고 쓴 문장이 그대로 판정 프롬프트가 된다. 실제로 그런 상태였다.
    이제 여기에 무엇을 쓰든 판정에 영향이 없다.
    """

    # 도구 설명을 정책 파일 값으로 덮어쓴다. 덮어쓰지 않으면 위 docstring이
    # 모델에게 간다 — 이 한 줄이 그 사고를 구조적으로 막는다.
    model_config = ConfigDict(
        json_schema_extra={"description": POLICY.output_description}
    )

    passed: bool = Field(description=POLICY.field_description("passed"))
    confidence_score: float = Field(
        ge=0.0, le=1.0, description=POLICY.field_description("confidence_score")
    )
    detected_labels: list[str] = Field(
        default_factory=list, description=POLICY.field_description("detected_labels")
    )
    reason: str = Field(description=POLICY.field_description("reason"))


class VerificationResult(BaseModel):
    """사진 판정 응답. **backend `AiServiceVerdict` 가 그대로 역직렬화하는 계약이다.**

    필드 이름을 바꾸면 backend가 깨진다. 이번 작업에서 backend는 수정하지 않으므로
    기존 필드와 순서를 유지한다.
    """

    passed: bool
    confidence_score: float = Field(ge=0.0, le=1.0)
    detected_labels: list[str]
    model_name: str
    reason: str
    storage_key: str | None = None
    raw_response: dict | None = None


class GpsVerificationRequest(BaseModel):
    """GPS 판정 입력.

    좌표 범위는 backend `LocationRequest` 의 `@DecimalMin/@DecimalMax`,
    반경은 `@Positive` 및 DB `CHECK (radius_meters > 0)` 와 같은 제약이다.
    """

    target_lat: float = Field(ge=-90.0, le=90.0, description="등록된 위치의 위도")
    target_lng: float = Field(ge=-180.0, le=180.0, description="등록된 위치의 경도")
    radius_meters: int = Field(gt=0, description="허용 반경(m)")
    submitted_lat: float = Field(ge=-90.0, le=90.0, description="인증 시도 위도")
    submitted_lng: float = Field(ge=-180.0, le=180.0, description="인증 시도 경도")


class GpsVerificationResult(BaseModel):
    """GPS 판정 결과.

    backend `gps_verification_results` 한 행에 대응한다. 실패는 에러가 아니라
    **판정 결과**이므로 200으로 내려간다(`passed=false`).
    """

    passed: bool
    distance_meters: float
    radius_meters: int
    target_lat: float
    target_lng: float
    submitted_lat: float
    submitted_lng: float
    failure_reason: str | None = None


class CheckInVerificationResult(BaseModel):
    """인증 방식에 따라 GPS·사진을 묶어 낸 최종 판정.

    backend `ChallengeCheckInService.recordCheckIn` +
    `finalizeDecisionAfterAi` 가 두 번의 호출에 나눠 하던 판정을 한 번에 한다.
    `decision_status`는 항상 `CONFIRMED`다 — 사진까지 이 요청 안에서 받으므로
    유보할 이유가 없다. (PENDING은 backend가 두 단계로 나눠 부를 때만 생긴다.)
    """

    verification_type: VerificationType
    decision_status: DecisionStatus
    final_passed: bool
    failure_reason: str | None = None
    gps: GpsVerificationResult | None = None
    ai: VerificationResult | None = None
