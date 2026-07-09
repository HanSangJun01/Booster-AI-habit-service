package com.booster.social.dto;

import lombok.Builder;
import lombok.Getter;

import java.math.BigDecimal;

@Getter
@Builder
public class LeaderboardEntry {

    private int rank;
    private Long userId;
    private Long teamId;
    private String name;
    private long checkInCount;
    private BigDecimal participationRate;
}
