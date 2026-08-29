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

    /**
     * 신청자 닉네임.
     *
     * <p>방장이 승인 화면에서 신청자를 알아보려면 이것이 필요하다. 없으면 앱이
     * {@code "참가자 #12"}처럼 userId로만 표시해서 누구인지 알 수 없다.
     *
     * <p>참가자 목록·승인 응답에서만 채워지고, 그 밖의 경로에서는 null이다.
     */
    private String nickname;

    private String personalStatement;
    private ParticipantStatus status;
    private LocalDateTime joinedAt;
    private LocalDateTime approvedAt;

    public static ParticipantResponse from(ChallengeParticipant p) {
        return from(p, null);
    }

    public static ParticipantResponse from(ChallengeParticipant p, String nickname) {
        return ParticipantResponse.builder()
                .id(p.getId())
                .challengeId(p.getChallenge().getId())
                .userId(p.getUserId())
                .teamId(p.getTeamId())
                .nickname(nickname)
                .personalStatement(p.getPersonalStatement())
                .status(p.getStatus())
                .joinedAt(p.getJoinedAt())
                .approvedAt(p.getApprovedAt())
                .build();
    }
}
