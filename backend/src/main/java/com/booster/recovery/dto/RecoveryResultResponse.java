package com.booster.recovery.dto;

import com.booster.recovery.domain.RecoveryStatus;

import java.time.OffsetDateTime;

public record RecoveryResultResponse(
        Long recoveryMissionId,
        RecoveryStatus status,
        OffsetDateTime completedAt,
        int currentStreak,
        long coinBalance,
        long chargedAmount
) {
}
