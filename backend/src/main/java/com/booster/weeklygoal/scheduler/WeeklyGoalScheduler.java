package com.booster.weeklygoal.scheduler;

import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import com.booster.weeklygoal.service.RecoveryTicketService;
import com.booster.weeklygoal.service.WeeklyEvaluationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.LocalDate;

/**
 * 주간 목표 스케줄러.
 *
 * <pre>
 *   매주 월 00:01 KST — 지난주(월~일) 채점
 *   매월  1일 00:05 KST — 무료 구제권 1개 지급 + 예약된 목표 변경 반영
 * </pre>
 *
 * <p>★실행 순서: 1일이 월요일인 경우 채점(00:01)이 지급(00:05)보다 먼저 돈다. 지난달의 마지막
 * 주는 <b>지난달 구제권</b>으로 판정되고, 그 뒤에 새 달 구제권이 충전된다.
 *
 * <p>각 사용자 처리는 서비스의 {@code REQUIRES_NEW} 트랜잭션이라 한 명이 실패해도 나머지가
 * 계속 진행된다. 스케줄러 자체는 트랜잭션을 열지 않는다.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class WeeklyGoalScheduler {

    private final WeeklyEvaluationService weeklyEvaluationService;
    private final RecoveryTicketService recoveryTicketService;
    private final UserRepository userRepository;
    private final Clock clock;

    @Scheduled(cron = "0 1 0 * * MON", zone = "Asia/Seoul")
    public void evaluateLastWeek() {
        LocalDate weekStart = weeklyEvaluationService.lastWeekStart();
        log.info("[WeeklyGoalScheduler] evaluating week {} ~ {}", weekStart, weekStart.plusDays(6));

        int evaluated = 0;
        int failed = 0;
        for (User user : userRepository.findAllByActiveTrue()) {
            try {
                if (weeklyEvaluationService.evaluateUser(user.getId(), weekStart) != null) {
                    evaluated++;
                }
            } catch (RuntimeException e) {
                failed++;
                log.error("[WeeklyGoalScheduler] evaluation failed: userId={}", user.getId(), e);
            }
        }
        log.info("[WeeklyGoalScheduler] done. evaluated={}, failed={}", evaluated, failed);
    }

    @Scheduled(cron = "0 5 0 1 * *", zone = "Asia/Seoul")
    public void runMonthly() {
        LocalDate monthStart = LocalDate.now(clock).withDayOfMonth(1);
        log.info("[WeeklyGoalScheduler] monthly run (free ticket + target change) for {}", monthStart);

        int granted = 0;
        for (User user : userRepository.findAllByActiveTrue()) {
            try {
                if (recoveryTicketService.runMonthly(user.getId(), monthStart)) {
                    granted++;
                }
            } catch (RuntimeException e) {
                log.error("[WeeklyGoalScheduler] ticket grant failed: userId={}", user.getId(), e);
            }
        }
        log.info("[WeeklyGoalScheduler] tickets granted to {} users", granted);
    }
}
