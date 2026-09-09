package com.booster.personallocation.dto;

import com.booster.personallocation.domain.PersonalLocation;

import java.time.OffsetDateTime;

/**
 * 인증 기준 위치.
 *
 * <p>{@code lat}/{@code lng}/{@code radiusMeters} 는 <b>지금 인증에 쓰이는</b> 값이고,
 * {@code pending*} 은 다음 달 1일부터 적용될 예약 값이다. 변경(PUT)은 즉시 반영되지 않고
 * 예약으로 들어가므로, 앱은 두 값을 함께 보여줘야 사용자가 "바꿨는데 왜 그대로지?" 하지 않는다.
 *
 * @param pendingLat          예약된 위도(없으면 null)
 * @param pendingLng          예약된 경도
 * @param pendingRadiusMeters 예약된 반경(m)
 * @param pendingPlaceName    예약된 장소 이름
 */
public record LocationResponse(
        Long userId,
        double lat,
        double lng,
        int radiusMeters,
        String placeName,
        Double pendingLat,
        Double pendingLng,
        Integer pendingRadiusMeters,
        String pendingPlaceName,
        OffsetDateTime updatedAt
) {
    public static LocationResponse from(PersonalLocation location) {
        return new LocationResponse(
                location.getUserId(),
                location.getLat(),
                location.getLng(),
                location.getRadiusMeters(),
                location.getPlaceName(),
                location.getPendingLat(),
                location.getPendingLng(),
                location.getPendingRadiusMeters(),
                location.getPendingPlaceName(),
                location.getUpdatedAt());
    }
}
