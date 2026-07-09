package com.booster.participant.dto;

import jakarta.validation.constraints.NotNull;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class ParticipationRequest {

    private String personalStatement;

    @NotNull
    private Double gpsLat;

    @NotNull
    private Double gpsLng;

    @NotNull
    private Integer gpsRadiusMeters;

    private String gpsPlaceName;
}
