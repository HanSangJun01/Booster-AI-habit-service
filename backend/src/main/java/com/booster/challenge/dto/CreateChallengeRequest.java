package com.booster.challenge.dto;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.domain.VerificationType;
import com.booster.shared.common.GpsPolicy;
import jakarta.validation.constraints.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class CreateChallengeRequest {

    /** 앱이 고르는 카테고리는 운동·공부 둘뿐이다(독서는 공부로 합쳤고, 기상은 폐지). */
    @NotBlank
    @Pattern(regexp = "EXERCISE|STUDY", message = "카테고리는 EXERCISE 또는 STUDY 만 가능합니다.")
    private String category;

    /**
     * 챌린지 이름.
     *
     * <p>앱은 더 이상 이름을 입력받지 않는다 — 카테고리만 고르면 서버가
     * "운동 · {방장 닉네임}" 형태로 만들어 준다(ChallengeService 참조).
     * 예전 클라이언트가 보내오면 그 값을 그대로 존중한다.
     */
    @Size(max = 200)
    private String title;

    /**
     * 챌린지 설명(선택).
     *
     * <p>DB 는 TEXT 라 상한이 없고 title 만 200자로 막혀 있어, API 를 직접 호출하면 임의 길이가
     * 그대로 저장됐다. 이 값은 목록 조회 응답({@code ChallengeResponse})에 항목마다 실려 나가므로
     * 길이를 두지 않으면 팀 탐색 응답 하나가 통째로 비대해진다.
     */
    @Size(max = 1000)
    private String description;

    @NotNull
    private VerificationType verificationType;

    /**
     * 챌린지 기간(일). 앱이 고르는 값은 7·14·21·30 뿐이다.
     *
     * <p>[상한 필수] 하한만 있던 시절엔 {@code int} 전 범위가 통과했다. 큰 값으로 만든 방은
     * 정원이 찰 때까지 조용히 있다가, 10명이 채워지는 순간 {@code ChallengeLifecycleService}
     * 가 {@code now.plusDays(durationDays)} 로 종료일을 계산하면서 timestamptz 표현 범위를
     * 넘겨 팀 편성 트랜잭션이 통째로 롤백된다 → 10번째 참가는 500 으로 실패하고 방은 9명에서
     * 영구히 멈춘 채 예치금만 잠긴다. 되살릴 경로가 없으므로 입구에서 막는다.
     * ({@code ParticipationRateCalculator} 의 일자별 집계 루프도 이 값만큼 돈다.)
     */
    @Min(1)
    @Max(value = 365, message = "챌린지 기간은 365일 이하여야 합니다.")
    private int durationDays;

    /**
     * 예치금.
     *
     * <p>하한이 0이던 시절엔 아무것도 걸지 않은 챌린지를 만들 수 있어, 져도 잃을 게
     * 없으니 판이 성립하지 않았다. 신규 가입 지급이 500코인이라 100이면 부담 없이
     * 여러 방에 들어갈 수 있다.
     */
    @Min(value = 100, message = "예치금은 100코인 이상이어야 합니다.")
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

    @Min(value = GpsPolicy.MIN_RADIUS_METERS, message = GpsPolicy.RADIUS_MESSAGE)
    @Max(value = GpsPolicy.MAX_RADIUS_METERS, message = GpsPolicy.RADIUS_MESSAGE)
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
