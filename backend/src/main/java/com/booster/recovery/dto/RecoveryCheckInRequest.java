package com.booster.recovery.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

public record RecoveryCheckInRequest(
        @NotNull(message = "위도는 필수입니다.")
        @DecimalMin(value = "-90.0") @DecimalMax(value = "90.0")
        Double lat,

        @NotNull(message = "경도는 필수입니다.")
        @DecimalMin(value = "-180.0") @DecimalMax(value = "180.0")
        Double lng
) {
}
