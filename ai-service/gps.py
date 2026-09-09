"""GPS 반경 판정.

backend `com.booster.shared.gps.GpsVerificationEvaluator` 를 그대로 옮긴 것이다.
backend 코드는 이번 작업에서 건드리지 않으므로, 같은 판정을 ai-service 안에서
독립적으로 낼 수 있도록 동일한 공식을 다시 구현한다.

**두 구현이 같은 답을 내야 한다.** 옮기면서 지킨 것들:

- 지구 반지름 상수 `6_371_000.0` m (backend와 동일)
- Haversine 공식 (`2 * atan2(sqrt(a), sqrt(1-a))`)
- 판정은 **반올림하지 않은 거리**로 한다 — `distance <= radius`
- 보고용 거리만 소수 둘째 자리로 반올림한다 (backend가 결과를 저장하는
  `gps_verification_results.distance_meters` 가 `NUMERIC(10, 2)` 라서,
  같은 값이 보이도록 `BigDecimal.setScale(2, HALF_UP)` 를 맞춘다)

경계값(거리 == 반경)은 backend와 같이 **통과**다.
"""

from __future__ import annotations

import math
from decimal import ROUND_HALF_UP, Decimal

EARTH_RADIUS_METERS = 6_371_000.0


def haversine_distance_meters(
    lat1: float, lng1: float, lat2: float, lng2: float
) -> float:
    """두 좌표 사이의 대권 거리(m)."""
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (
        math.sin(d_lat / 2) * math.sin(d_lat / 2)
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lng / 2)
        * math.sin(d_lng / 2)
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return EARTH_RADIUS_METERS * c


def is_within_radius(
    registered_lat: float,
    registered_lng: float,
    radius_meters: int,
    current_lat: float,
    current_lng: float,
) -> bool:
    """등록 좌표 반경 안인지. 경계값 포함(<=)."""
    distance = haversine_distance_meters(
        registered_lat, registered_lng, current_lat, current_lng
    )
    return distance <= radius_meters


def round_distance_meters(distance: float) -> float:
    """보고용 반올림. backend가 DB에 저장하는 자릿수(NUMERIC(10,2))와 맞춘다."""
    return float(
        Decimal(str(distance)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    )
