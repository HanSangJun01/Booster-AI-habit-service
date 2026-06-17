package com.booster.settlement.dto;

import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class SettlementResultResponse {

    private Long challengeId;
    private SettlementStatus status;
    private boolean draw;
    private Long winnerTeamId;
    private Long loserTeamId;
    private long totalPool;
    private long perWinnerPayout;
    private LocalDateTime computedAt;

    public static SettlementResultResponse from(Settlement s) {
        return SettlementResultResponse.builder()
                .challengeId(s.getChallengeId())
                .status(s.getStatus())
                .draw(s.isDraw())
                .winnerTeamId(s.getWinnerTeamId())
                .loserTeamId(s.getLoserTeamId())
                .totalPool(s.getTotalPool())
                .perWinnerPayout(s.getPerWinnerPayout())
                .computedAt(s.getComputedAt())
                .build();
    }
}
