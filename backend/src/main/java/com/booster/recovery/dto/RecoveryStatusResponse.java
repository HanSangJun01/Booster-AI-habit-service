package com.booster.recovery.dto;

import java.time.LocalDate;
import java.time.OffsetDateTime;

public record RecoveryStatusResponse(
        boolean hasPendingMission,
        Long recoveryMissionId,
        LocalDate missedDate,
        OffsetDateTime deadlineAt
) {
    public static RecoveryStatusResponse none() {
        return new RecoveryStatusResponse(false, null, null, null);
    }
}
