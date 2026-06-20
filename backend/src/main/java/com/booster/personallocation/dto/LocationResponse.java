package com.booster.personallocation.dto;

import com.booster.personallocation.domain.PersonalLocation;

import java.time.OffsetDateTime;

public record LocationResponse(
        Long userId,
        double lat,
        double lng,
        int radiusMeters,
        String placeName,
        OffsetDateTime updatedAt
) {
    public static LocationResponse from(PersonalLocation location) {
        return new LocationResponse(
                location.getUserId(),
                location.getLat(),
                location.getLng(),
                location.getRadiusMeters(),
                location.getPlaceName(),
                location.getUpdatedAt());
    }
}
