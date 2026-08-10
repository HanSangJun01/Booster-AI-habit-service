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

    /** 서버 내부 조립용(방장 자동 참가 등). 클라이언트 요청 바인딩과는 무관하다. */
    public static ParticipationRequest of(String personalStatement, Double gpsLat, Double gpsLng,
                                          Integer gpsRadiusMeters, String gpsPlaceName) {
        ParticipationRequest r = new ParticipationRequest();
        r.personalStatement = personalStatement;
        r.gpsLat = gpsLat;
        r.gpsLng = gpsLng;
        r.gpsRadiusMeters = gpsRadiusMeters;
        r.gpsPlaceName = gpsPlaceName;
        return r;
    }
}
