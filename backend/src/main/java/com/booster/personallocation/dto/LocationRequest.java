package com.booster.personallocation.dto;

import com.booster.shared.common.GpsPolicy;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record LocationRequest(
        @NotNull(message = "위도는 필수입니다.")
        @DecimalMin(value = "-90.0") @DecimalMax(value = "90.0")
        Double lat,

        @NotNull(message = "경도는 필수입니다.")
        @DecimalMin(value = "-180.0") @DecimalMax(value = "180.0")
        Double lng,

        @NotNull(message = "반경은 필수입니다.")
        @Min(value = GpsPolicy.MIN_RADIUS_METERS, message = GpsPolicy.RADIUS_MESSAGE)
        @Max(value = GpsPolicy.MAX_RADIUS_METERS, message = GpsPolicy.RADIUS_MESSAGE)
        Integer radiusMeters,

        @Size(max = 200)
        String placeName
) {
}
