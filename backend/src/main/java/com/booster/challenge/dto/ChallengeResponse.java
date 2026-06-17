package com.booster.challenge.dto;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
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
    private String verificationMethod;
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

    public static ChallengeResponse from(Challenge c) {
        return ChallengeResponse.builder()
                .id(c.getId())
                .category(c.getCategory())
                .title(c.getTitle())
                .description(c.getDescription())
                .verificationMethod(c.getVerificationMethod())
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
