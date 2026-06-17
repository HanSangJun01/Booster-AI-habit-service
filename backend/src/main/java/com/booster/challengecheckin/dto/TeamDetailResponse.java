package com.booster.challengecheckin.dto;

import lombok.Builder;
import lombok.Getter;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Getter
@Builder
public class TeamDetailResponse {

    private TeamInfo myTeam;
    private TeamInfo opponentTeam;
    private Integer challengeDay;
    private int totalDays;
    private LocalDate today;

    public record TeamInfo(
            Long teamId,
            String teamName,
            BigDecimal participationRate,
            int todayCheckedInCount,
            int totalMemberCount,
            List<TeamMemberCheckInStatus> members
    ) {}
}
