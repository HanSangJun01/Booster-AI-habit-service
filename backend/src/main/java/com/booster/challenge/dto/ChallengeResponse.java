package com.booster.challenge.dto;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.domain.VerificationType;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class ChallengeResponse {

    private Long id;
    private String category;
    private String title;
    private String description;
    private VerificationType verificationType;
    private int durationDays;
    private long depositCoins;
    private ChallengeVisibility visibility;
    private ApprovalType approvalType;
    private ChallengeStatus status;
    private String inviteCode;
    private int maxParticipants;
    private LocalDateTime startedAt;
    private LocalDateTime endedAt;
    private Long createdBy;
    private LocalDateTime createdAt;

    /**
     * 요청자가 이 챌린지에 참여 중인지.
     *
     * <p>없을 때 클라이언트는 이미 참가한 챌린지를 탐색 목록에서 계속 보여주고, 눌렀을 때만 409 를
     * 받았다. 앱에서 걸러내는 건 두 가지 이유로 불가능하다 — (1) 남이 만든 챌린지에 참가했는지
     * 서버가 알려주지 않으면 판정할 수 없고, (2) 서버가 20개를 준 페이지에서 앱이 3개를 숨기면
     * 17개가 되어 페이징 경계가 깨진다.
     *
     * <p>목록에서 제외하지 않고 플래그로 내려서 "참여 중"으로 표시할 수 있게 한다.
     */
    private boolean joined;

    public static ChallengeResponse from(Challenge c) {
        return from(c, false);
    }

    public static ChallengeResponse from(Challenge c, boolean joined) {
        return ChallengeResponse.builder()
                .joined(joined)
                .id(c.getId())
                .category(c.getCategory())
                .title(c.getTitle())
                .description(c.getDescription())
                .verificationType(c.getVerificationType())
                .durationDays(c.getDurationDays())
                .depositCoins(c.getDepositCoins())
                .visibility(c.getVisibility())
                .approvalType(c.getApprovalType())
                .status(c.getStatus())
                .inviteCode(c.getInviteCode())
                .maxParticipants(c.getMaxParticipants())
                .startedAt(c.getStartedAt())
                .endedAt(c.getEndedAt())
                .createdBy(c.getCreatedBy())
                .createdAt(c.getCreatedAt())
                .build();
    }
}
