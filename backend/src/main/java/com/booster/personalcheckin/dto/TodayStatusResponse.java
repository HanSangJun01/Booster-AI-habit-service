package com.booster.personalcheckin.dto;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/** 오늘 인증 상태. 레코드가 없으면 status = "NOT_CHECKED". */
public record TodayStatusResponse(
        LocalDate date,
        String status,
        OffsetDateTime verifiedAt
) {
}
