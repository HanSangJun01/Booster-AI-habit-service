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

    /**
     * 참가 직후의 코인 잔액.
     *
     * <p>참가하면 예치금이 빠지는데 응답에 잔액이 없어서, 앱이 화면의 코인을 갱신하지 못했다.
     * 그래서 참가해도 코인이 그대로 보이다가 <b>재로그인해야 줄어드는 것처럼</b> 보였다.
     * 참가 신청 응답에서만 채워지고, 목록·승인 응답에서는 null 이다.
     */
    private Long coinBalance;

    public static ParticipantResponse from(ChallengeParticipant p) {
        return from(p, null, null);
    }

    public static ParticipantResponse from(ChallengeParticipant p, String nickname) {
        return from(p, nickname, null);
    }

    public static ParticipantResponse from(ChallengeParticipant p, String nickname, Long coinBalance) {
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
                .coinBalance(coinBalance)
                .build();
    }
}
