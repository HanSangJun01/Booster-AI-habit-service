package com.booster.personalcheckin.dto;

import com.booster.personalcheckin.domain.PersonalCheckInStatus;

import java.time.LocalDate;
import java.time.OffsetDateTime;

public record CheckInResponse(
        LocalDate date,
        PersonalCheckInStatus status,
        OffsetDateTime verifiedAt,
        int currentStreak,
        int maxStreak,
        long coinBalance,
        boolean rewardGranted
) {
}
