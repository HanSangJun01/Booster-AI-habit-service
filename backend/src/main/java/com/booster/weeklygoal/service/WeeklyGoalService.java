package com.booster.weeklygoal.service;

import com.booster.personalcheckin.domain.PersonalCheckInStatus;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.shared.common.BusinessException;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import com.booster.weeklygoal.domain.WeeklyEvaluation;
import com.booster.weeklygoal.dto.WeeklyGoalResponse;
import com.booster.weeklygoal.repository.WeeklyEvaluationRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;
import org.springframework.beans.factory.annotation.Value;

/** 주간 목표 조회 · 변경 예약. */
@Service
@RequiredArgsConstructor
public class WeeklyGoalService {

    private final PersonalLocationRepository locationRepository;
    private final PersonalCheckInRepository checkInRepository;
    private final WeeklyEvaluationRepository evaluationRepository;
    private final UserRepository userRepository;
    private final Clock clock;

    @Value("${booster.weekly.ticket-price}")
    private long ticketPrice;

    @Transactional(readOnly = true)
    public WeeklyGoalResponse getStatus(Long userId) {
        LocalDate today = LocalDate.now(clock);
        LocalDate weekStart = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));

        PersonalLocation location = locationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.badRequest(
                        "LOCATION_NOT_REGISTERED", "개인 GPS 위치를 먼저 등록하세요."));
        User user = userRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));

        int successCount = (int) checkInRepository.countByUserIdAndStatusAndDateBetween(
                userId, PersonalCheckInStatus.SUCCESS, weekStart, weekStart.plusDays(6));

        // 오늘 포함, 이번 주에 남은 날수 (월요일이면 7, 일요일이면 1)
        int remainingDays = (int) ChronoUnit.DAYS.between(today, weekStart.plusDays(7));

        String lastWeekResult = evaluationRepository.findFirstByUserIdOrderByWeekStartDesc(userId)
                .map(WeeklyEvaluation::getResult)
                .map(Enum::name)
                .orElse(null);

        return new WeeklyGoalResponse(
                weekStart,
                location.getWeeklyTargetDays(),
                location.getPendingTargetDays(),
                successCount,
                remainingDays,
                user.getRecoveryTickets(),
                user.getFreeRecoveryTickets(),
                user.getPaidRecoveryTickets(),
                ticketPrice,
                user.getCoinBalance(),
                lastWeekResult);
    }

    /**
     * 목표 변경을 예약한다. <b>다음 달 1일</b>에 반영된다.
     *
     * <p>즉시 반영하면 주 중간에 목표를 낮춰 그 주 채점을 통과할 수 있다. 반영 주기를 월 1회로
     * 두면 회피가 불가능하고, 목표가 자주 흔들리지 않아 스트릭의 의미도 유지된다.
     *
     * @return 예약 반영 후의 현황
     */
    @Transactional
    public WeeklyGoalResponse reserveTarget(Long userId, int targetDays) {
        PersonalLocation location = locationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.badRequest(
                        "LOCATION_NOT_REGISTERED", "개인 GPS 위치를 먼저 등록하세요."));
        location.reserveWeeklyTarget(targetDays);
        locationRepository.flush();
        return getStatus(userId);
    }
}
