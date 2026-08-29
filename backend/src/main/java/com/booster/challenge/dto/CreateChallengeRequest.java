package com.booster.challenge.dto;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.domain.VerificationType;
import jakarta.validation.constraints.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class CreateChallengeRequest {

    @NotBlank
    private String category;

    @NotBlank
    @Size(max = 200)
    private String title;

    private String description;

    @NotNull
    private VerificationType verificationType;

    @Min(1)
    private int durationDays;

    @Min(0)
    private long depositCoins;

    @NotNull
    private ChallengeVisibility visibility;

    @NotNull
    private ApprovalType approvalType;

    // [기획서 확정] "10명이 채워지면 서버가 랜덤으로 5:5 팀을 구성" — 팀 편성이 10명 기준이므로
    // 정원도 10 고정이다. 과거 @Min(2)는 정원 4·6·8 챌린지를 만들 수 있게 해, 정원을 채워도
    // 팀이 편성되지 않아 아무도 인증할 수 없는 좀비 챌린지를 만들었다.
    @Min(value = 10, message = "정원은 10명 고정입니다.")
    @Max(value = 10, message = "정원은 10명 고정입니다.")
    private int maxParticipants = 10;

    // ── 방장의 인증 기준 위치 ────────────────────────────────────────────────
    // 챌린지를 만들면 방장은 곧바로 CONFIRMED 참가자가 되므로 인증 위치가 필요하다.
    // 생략하면 서버가 방장의 개인 인증 위치(GET /api/users/me/location)를 재사용한다.
    // 둘 다 없으면 400 으로 거절한다(위치 없이 참가자를 만들면 인증이 영영 불가능해진다).

    @DecimalMin("-90.0") @DecimalMax("90.0")
    private Double gpsLat;

    @DecimalMin("-180.0") @DecimalMax("180.0")
    private Double gpsLng;

    @Positive
    private Integer gpsRadiusMeters;

    @Size(max = 200)
    private String gpsPlaceName;

    @Size(max = 500)
    private String personalStatement;

    /** 요청에 좌표·반경이 모두 들어왔는지. 하나라도 빠지면 개인 위치로 폴백한다. */
    public boolean hasExplicitGps() {
        return gpsLat != null && gpsLng != null && gpsRadiusMeters != null;
    }
}
