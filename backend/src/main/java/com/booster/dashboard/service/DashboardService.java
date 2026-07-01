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

        LocalDate weekStart = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate weekEnd = weekStart.plusDays(6);
        LocalDate monthStart = today.withDayOfMonth(1);
        LocalDate monthEnd = today.withDayOfMonth(today.lengthOfMonth());

        // [BS-30 최적화 ③] 오늘 상태 / 주간 성공수 / 월 캘린더를 3개 쿼리로 나눠 치던 것을,
        // 주·월을 아우르는 합집합 범위 [min(monthStart,weekStart), max(monthEnd,weekEnd)] 1회 조회 후
        // 메모리에서 계산한다(주가 두 달에 걸쳐도 각 범위로 정확히 분리).
        LocalDate from = monthStart.isBefore(weekStart) ? monthStart : weekStart;
        LocalDate to = monthEnd.isAfter(weekEnd) ? monthEnd : weekEnd;
        List<PersonalCheckIn> checkIns =
                personalCheckInRepository.findByUserIdAndDateBetween(userId, from, to);

        String todayStatus = checkIns.stream()
                .filter(c -> c.getDate().isEqual(today))
                .map(c -> c.getStatus().name())
                .findFirst()
                .orElse("NOT_CHECKED");

        // 이번 주(월~일, ISO) SUCCESS 일수
        long weeklySuccessCount = checkIns.stream()
                .filter(c -> c.getStatus() == PersonalCheckInStatus.SUCCESS)
                .filter(c -> !c.getDate().isBefore(weekStart) && !c.getDate().isAfter(weekEnd))
                .count();

        // 이번 달 캘린더(레코드 있는 날짜만; 없으면 클라이언트가 NOT_CHECKED로 간주)
        List<DashboardResponse.CalendarDay> days = checkIns.stream()
                .filter(c -> !c.getDate().isBefore(monthStart) && !c.getDate().isAfter(monthEnd))
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
