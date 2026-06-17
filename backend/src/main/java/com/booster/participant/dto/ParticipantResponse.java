package com.booster.participant.dto;

import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class ParticipantResponse {

    private Long id;
    private Long challengeId;
    private Long userId;
    private Long teamId;
    private String personalStatement;
    private ParticipantStatus status;
    private LocalDateTime joinedAt;
    private LocalDateTime approvedAt;

    public static ParticipantResponse from(ChallengeParticipant p) {
        return ParticipantResponse.builder()
                .id(p.getId())
                .challengeId(p.getChallenge().getId())
                .userId(p.getUserId())
                .teamId(p.getTeamId())
                .personalStatement(p.getPersonalStatement())
                .status(p.getStatus())
                .joinedAt(p.getJoinedAt())
                .approvedAt(p.getApprovedAt())
                .build();
    }
}
