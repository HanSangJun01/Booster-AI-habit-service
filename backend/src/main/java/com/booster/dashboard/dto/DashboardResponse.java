package com.booster.dashboard.dto;

import java.time.LocalDate;
import java.util.List;

/** 홈 대시보드 단일 응답. bs-25 Phase 4. */
public record DashboardResponse(
        long coinBalance,
        StreakInfo streak,
        long weeklySuccessCount,
        String todayStatus,
        CalendarInfo calendar
) {
    public record StreakInfo(int current, int max) {
    }

    public record CalendarInfo(int year, int month, List<CalendarDay> days) {
    }

    public record CalendarDay(LocalDate date, String status) {
    }
}
