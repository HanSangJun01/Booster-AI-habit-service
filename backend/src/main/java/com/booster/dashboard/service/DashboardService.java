package com.booster.dashboard.service;

import com.booster.dashboard.dto.DashboardResponse;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.domain.PersonalCheckInStatus;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.shared.common.BusinessException;
import com.booster.streak.domain.Streak;
import com.booster.streak.repository.StreakRepository;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.List;

@Service
@RequiredArgsConstructor
public class DashboardService {

    private final UserRepository userRepository;
    private final StreakRepository streakRepository;
    private final PersonalCheckInRepository personalCheckInRepository;
    private final Clock clock;

    @Transactional(readOnly = true)
    public DashboardResponse getHome(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));

        Streak streak = streakRepository.findById(userId).orElseGet(() -> Streak.init(userId));
        LocalDate today = LocalDate.now(clock);

        String todayStatus = personalCheckInRepository.findByUserIdAndDate(userId, today)
                .map(c -> c.getStatus().name())
                .orElse("NOT_CHECKED");

        // 이번 주(월~일, ISO) SUCCESS 일수
        LocalDate weekStart = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate weekEnd = weekStart.plusDays(6);
        long weeklySuccessCount = personalCheckInRepository.countByUserIdAndStatusAndDateBetween(
                userId, PersonalCheckInStatus.SUCCESS, weekStart, weekEnd);

        // 이번 달 캘린더(레코드 있는 날짜만; 없으면 클라이언트가 NOT_CHECKED로 간주)
        LocalDate monthStart = today.withDayOfMonth(1);
        LocalDate monthEnd = today.withDayOfMonth(today.lengthOfMonth());
        List<DashboardResponse.CalendarDay> days = personalCheckInRepository
                .findByUserIdAndDateBetween(userId, monthStart, monthEnd).stream()
                .sorted(java.util.Comparator.comparing(PersonalCheckIn::getDate))
                .map(c -> new DashboardResponse.CalendarDay(c.getDate(), c.getStatus().name()))
                .toList();

        return new DashboardResponse(
                user.getCoinBalance(),
                new DashboardResponse.StreakInfo(streak.getCurrentStreak(), streak.getMaxStreak()),
                weeklySuccessCount,
                todayStatus,
                new DashboardResponse.CalendarInfo(today.getYear(), today.getMonthValue(), days));
    }
}
