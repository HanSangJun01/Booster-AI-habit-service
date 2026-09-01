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
import com.booster.weeklygoal.domain.EvaluationResult;
import com.booster.challenge.domain.VerificationType;
import java.util.EnumSet;
import java.util.Set;

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
    @Value("${booster.weekly.late-rescue-price}")
    private long lateRescuePrice;

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

        // 구제 대기 건이 있으면 앱이 "구매하고 지킬까요?" 팝업을 띄울 수 있도록 함께 내려준다.
        WeeklyEvaluation pendingRescue = evaluationRepository
                .findFirstByUserIdAndResultOrderByWeekStartDesc(userId, EvaluationResult.PENDING_RESCUE)
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
                location.getVerificationType().name(),
                location.getCategory(),
                lastWeekResult,
                pendingRescue != null ? pendingRescue.getWeekStart() : null,
                pendingRescue != null ? pendingRescue.getRescueDeadline() : null,
                lateRescuePrice);
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
    public WeeklyGoalResponse reserveTarget(Long userId, int targetDays,
                                            VerificationType verificationType, String category) {
        PersonalLocation location = locationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.badRequest(
                        "LOCATION_NOT_REGISTERED", "개인 GPS 위치를 먼저 등록하세요."));
        location.reserveWeeklyTarget(targetDays);
        if (verificationType != null) {
            if (!SUPPORTED_VERIFICATION_TYPES.contains(verificationType)) {
                throw BusinessException.badRequest("UNSUPPORTED_VERIFICATION_TYPE",
                        "인증 방식은 위치+사진(GPS_PHOTO_AI)만 지원합니다: " + verificationType);
            }
            location.changeVerificationType(verificationType);
        }
        if (category != null) {
            location.changeCategory(category);
        }
        locationRepository.flush();
        return getStatus(userId);
    }

    /**
     * 개인 트랙이 지원하는 인증 방식. 팀 챌린지와 동일하게 "위치+사진" 하나로 고정한다.
     *
     * <p>[2026-09 확정] 위치만·사진만은 우회가 쉬워 인증으로서 신뢰가 낮았다. 이미 GPS 나 AI 로
     * 저장돼 있는 사용자의 값은 건드리지 않고, 새로 바꾸는 것만 막는다.
     */
    private static final Set<VerificationType> SUPPORTED_VERIFICATION_TYPES =
            EnumSet.of(VerificationType.GPS_PHOTO_AI);
}
