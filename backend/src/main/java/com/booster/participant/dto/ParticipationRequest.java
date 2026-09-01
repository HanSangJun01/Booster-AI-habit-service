package com.booster.participant.dto;

import com.booster.shared.common.GpsPolicy;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class ParticipationRequest {

    @Size(max = 500)
    private String personalStatement;

    @NotNull
    @DecimalMin("-90.0") @DecimalMax("90.0")
    private Double gpsLat;

    @NotNull
    @DecimalMin("-180.0") @DecimalMax("180.0")
    private Double gpsLng;

    // 범위 검증이 없던 시절엔 음수·0 반경이 그대로 저장돼, 400 대신 나중에 409(DATA_CONFLICT)로
    // 터졌다. 개인 위치·챌린지 생성과 같은 상·하한을 적용한다.
    @NotNull
    @Min(value = GpsPolicy.MIN_RADIUS_METERS, message = GpsPolicy.RADIUS_MESSAGE)
    @Max(value = GpsPolicy.MAX_RADIUS_METERS, message = GpsPolicy.RADIUS_MESSAGE)
    private Integer gpsRadiusMeters;

    @Size(max = 200)
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
