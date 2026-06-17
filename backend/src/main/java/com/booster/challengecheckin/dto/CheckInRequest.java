package com.booster.challengecheckin.dto;

import jakarta.validation.constraints.NotNull;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class CheckInRequest {

    @NotNull
    private Double currentLat;

    @NotNull
    private Double currentLng;
}
