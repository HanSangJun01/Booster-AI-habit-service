package com.booster.challenge.dto;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.domain.VerificationType;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;

@Getter
@Builder
public class ChallengeDetailResponse {

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
    private long confirmedCount;
    private Integer currentDay;
    private LocalDateTime startedAt;
    private LocalDateTime endedAt;
    private Long createdBy;
    private LocalDateTime createdAt;

    public static ChallengeDetailResponse from(Challenge c, long confirmedCount) {
        Integer currentDay = null;
        if (c.getStartedAt() != null) {
            currentDay = (int) ChronoUnit.DAYS.between(
                    c.getStartedAt().toLocalDate(), LocalDate.now()) + 1;
        }
        return ChallengeDetailResponse.builder()
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
                .confirmedCount(confirmedCount)
                .currentDay(currentDay)
                .startedAt(c.getStartedAt())
                .endedAt(c.getEndedAt())
                .createdBy(c.getCreatedBy())
                .createdAt(c.getCreatedAt())
                .build();
    }
}
