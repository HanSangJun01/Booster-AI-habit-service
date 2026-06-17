package com.booster.team.dto;

import com.booster.team.domain.Team;
import com.booster.team.domain.TeamResult;
import lombok.Builder;
import lombok.Getter;

import java.math.BigDecimal;

@Getter
@Builder
public class TeamResponse {

    private Long id;
    private Long challengeId;
    private String name;
    private BigDecimal participationRate;
    private TeamResult result;
    private int initialMemberCount;

    public static TeamResponse from(Team team) {
        return TeamResponse.builder()
                .id(team.getId())
                .challengeId(team.getChallengeId())
                .name(team.getName())
                .participationRate(team.getParticipationRate())
                .result(team.getResult())
                .initialMemberCount(team.getInitialMemberCount())
                .build();
    }
}
