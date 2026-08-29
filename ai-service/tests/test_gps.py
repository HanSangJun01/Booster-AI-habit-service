"""GPS 판정이 backend `GpsVerificationEvaluator` 와 같은 답을 내는지.

backend를 고칠 수 없으므로 두 구현이 갈라지면 같은 사용자가 앱에서는 통과하고
서버에서는 실패하는 상황이 된다. 여기서 막는다.
"""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

import gps  # noqa: E402


def test_same_point_is_zero():
    assert gps.haversine_distance_meters(37.5665, 126.9780, 37.5665, 126.9780) == 0.0


def test_one_degree_of_latitude_is_about_111km():
    """위도 1도 ≈ 111.19km (지구 반지름 6_371_000m 기준). backend와 같은 상수."""
    distance = gps.haversine_distance_meters(0.0, 0.0, 1.0, 0.0)
    assert 111_100 < distance < 111_300


def test_known_pair_seoul_city_hall_to_gwanghwamun():
    """서울시청 ↔ 광화문 약 1.0km. 자릿수가 어긋나면 여기서 잡힌다."""
    distance = gps.haversine_distance_meters(37.5665, 126.9780, 37.5759, 126.9769)
    assert 1_000 < distance < 1_100


def test_boundary_distance_equals_radius_passes():
    """거리 == 반경은 통과. backend가 `distance <= radius` 라서 경계는 성공이다."""
    lat1, lng1 = 37.5665, 126.9780
    lat2, lng2 = 37.5675, 126.9780
    distance = gps.haversine_distance_meters(lat1, lng1, lat2, lng2)
    radius = int(distance) + 1  # 반올림 없이 거리보다 큰 정수 반경
    assert gps.is_within_radius(lat1, lng1, radius, lat2, lng2) is True
    assert gps.is_within_radius(lat1, lng1, int(distance) - 1, lat2, lng2) is False


def test_distance_is_symmetric():
    a = gps.haversine_distance_meters(37.5665, 126.9780, 35.1796, 129.0756)
    b = gps.haversine_distance_meters(35.1796, 129.0756, 37.5665, 126.9780)
    assert a == pytest.approx(b)


@pytest.mark.parametrize(
    "raw,expected",
    [
        (123.454, 123.45),
        (123.455, 123.46),  # HALF_UP — backend BigDecimal.setScale(2, HALF_UP)와 동일
        (0.0, 0.0),
    ],
)
def test_round_distance_matches_backend_scale(raw, expected):
    assert gps.round_distance_meters(raw) == expected


def test_rounding_never_changes_the_verdict():
    """판정은 반올림 전 거리로 한다.

    거리가 50.004m이고 반경이 50m면 backend는 실패다(50.004 > 50). 반올림한
    50.00을 비교했다면 통과가 되어 답이 갈린다.
    """
    lat1, lng1 = 37.5665, 126.9780
    # 반경 50m 바로 바깥의 점을 찾는다.
    lat2 = lat1
    lng2 = lng1
    step = 0.0000001
    while gps.haversine_distance_meters(lat1, lng1, lat2, lng2) <= 50.0:
        lat2 += step
    distance = gps.haversine_distance_meters(lat1, lng1, lat2, lng2)

    assert distance > 50.0
    assert gps.round_distance_meters(distance) == 50.0  # 반올림하면 50.00
    assert gps.is_within_radius(lat1, lng1, 50, lat2, lng2) is False
