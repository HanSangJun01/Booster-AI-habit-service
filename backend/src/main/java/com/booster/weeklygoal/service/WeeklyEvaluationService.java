package com.booster.weeklygoal.service;

import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import com.booster.personalcheckin.domain.PersonalCheckInStatus;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.shared.common.BusinessException;
import com.booster.streak.domain.Streak;
import com.booster.streak.repository.StreakRepository;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import com.booster.weeklygoal.domain.EvaluationResult;
import com.booster.weeklygoal.domain.WeeklyEvaluation;
import com.booster.weeklygoal.repository.WeeklyEvaluationRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.OffsetDateTime;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.List;

/**
 * 주간 목표 채점.
 *
 * <p>매주 월요일 00:0x 에 지난주(월~일)를 평가한다.
 * <pre>
 *   성공 횟수 &gt;= 목표   → ACHIEVED : 스트릭 유지 (마일스톤 보상은 인증 시점에 이미 지급됨)
 *   미달 + 구제권 있음   → RESCUED  : 구제권 1개 소모, 스트릭 유지, 코인 차감 없음, 보상 없음
 *   미달 + 구제권 없음   → FAILED   : 스트릭 초기화 + 코인 차감
 * </pre>
 *
 * <p>★리셋 책임 단일화: 과거 모델은 스트릭 초기화가 체크인(갭 검사)과 복귀 만료 두 곳에 흩어져
 * 있었다. 새 모델은 초기화가 <b>오직 이 클래스</b>에서만 일어난다.
 *
 * <p>★동시성: 사용자 행을 비관락으로 먼저 잡아 coin/streak 갱신을 사용자 단위로 직렬화한다
 * (BS-30 C1/C5 와 동일한 락 순서 — User → Streak → Coin). 멱등성은
 * {@code UNIQUE(user_id, week_start)} 가 DB 레벨에서 보장한다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class WeeklyEvaluationService {

    private final PersonalCheckInRepository checkInRepository;
    private final PersonalLocationRepository locationRepository;
    private final WeeklyEvaluationRepository evaluationRepository;
    private final StreakRepository streakRepository;
    private final UserRepository userRepository;
    private final CoinService coinService;
    private final Clock clock;

    @Value("${booster.weekly.miss-penalty}")
    private long missPenalty;
    @Value("${booster.weekly.rescue-grace-days}")
    private int rescueGraceDays;

    /** 오늘(KST) 기준 직전 주의 월요일. */
    public LocalDate lastWeekStart() {
        return LocalDate.now(clock)
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                .minusWeeks(1);
    }

    /**
     * 한 사용자의 한 주를 채점한다. 사용자별 트랜잭션이므로 한 명이 실패해도 나머지에 영향이 없다.
     *
     * @return 채점 결과. 대상이 아니어서 건너뛴 경우 null
     */
    @Transactional
    public EvaluationResult evaluateUser(Long userId, LocalDate weekStart) {
        // 1) 멱등 — 이미 채점된 주는 건너뛴다(스케줄러 재실행/다중 인스턴스 대비).
        if (evaluationRepository.existsByUserIdAndWeekStart(userId, weekStart)) {
            return null;
        }

        // 2) 목표는 개인 인증 위치에 붙어 있다. 위치 미등록 = 개인 트랙을 아직 시작하지 않음 → 대상 아님.
        PersonalLocation location = locationRepository.findById(userId).orElse(null);
        if (location == null) {
            return null;
        }

        // 3) User 비관락 — coin/streak 갱신을 사용자 단위로 직렬화하고 active 를 락 상태에서 확인한다.
        User user = userRepository.findByIdForUpdate(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        if (!user.isActive()) {
            return null;
        }

        // 4) 가입한 주는 채점하지 않는다. 수요일에 가입한 사람에게 그 주 목표를 요구할 수 없다.
        //    (과거 모델의 B2 "가입 당일 미인증 면책"과 같은 취지)
        LocalDate joinedDate = user.getJoinedAt().atZoneSameInstant(clock.getZone()).toLocalDate();
        if (!joinedDate.isBefore(weekStart)) {
            return null;
        }

        // 5) 집계
        int targetDays = location.getWeeklyTargetDays();
        int successCount = (int) checkInRepository.countByUserIdAndStatusAndDateBetween(
                userId, PersonalCheckInStatus.SUCCESS, weekStart, weekStart.plusDays(6));

        Streak streak = streakRepository.findById(userId)
                .orElseGet(() -> streakRepository.save(Streak.init(userId)));

        // 6) 판정
        EvaluationResult result;
        OffsetDateTime rescueDeadline = null;
        if (successCount >= targetDays) {
            result = EvaluationResult.ACHIEVED;
        } else if (user.consumeRecoveryTicket()) {
            // 구제: 스트릭만 지킨다. 못 한 인증을 채워주지 않고, 코인도 깎지 않는다.
            result = EvaluationResult.RESCUED;
            log.info("[WeeklyGoal] rescued: userId={}, week={}, {}/{}", userId, weekStart, successCount, targetDays);
        } else {
            // 구제권이 없어도 즉시 실패시키지 않는다. 자동 채점이 새벽에 도는 탓에 사용자는 아무
            // 예고 없이 스트릭 0 + 코인 차감을 맞게 되는데, 오래 쌓은 사용자일수록 그 순간 이탈한다.
            // 기한까지 사후 구매할 기회를 주고, 그 사이 스트릭·코인은 건드리지 않는다.
            result = EvaluationResult.PENDING_RESCUE;
            rescueDeadline = LocalDate.now(clock).plusDays(rescueGraceDays)
                    .atTime(23, 59, 59).atZone(clock.getZone()).toOffsetDateTime();
            log.info("[WeeklyGoal] pending rescue: userId={}, week={}, {}/{}, deadline={}",
                    userId, weekStart, successCount, targetDays, rescueDeadline);
        }

        // 7) 기록 — UNIQUE(user_id, week_start) 위반은 다른 인스턴스가 먼저 처리했다는 뜻이므로 무시한다.
        try {
            evaluationRepository.saveAndFlush(
                    WeeklyEvaluation.of(userId, weekStart, targetDays, successCount, result, rescueDeadline));
        } catch (DataIntegrityViolationException e) {
            log.warn("[WeeklyGoal] concurrent evaluation detected, skipping: userId={}, week={}", userId, weekStart);
            throw e; // 트랜잭션 롤백 → 코인/스트릭 변경도 함께 취소되어 이중 처리되지 않는다
        }

        return result;
    }

    /**
     * 구제 기한이 지난 {@code PENDING_RESCUE} 를 실패로 확정한다.
     *
     * <p>여기서야 비로소 스트릭 초기화와 코인 차감이 일어난다. 채점 시점에는 유예만 걸어두고
     * 아무것도 깎지 않기 때문에, 사용자가 기한 안에 사후 구매하면 손실이 전혀 없다.
     */
    @Transactional
    public int expireOverdueRescues() {
        OffsetDateTime now = OffsetDateTime.now(clock);
        List<WeeklyEvaluation> overdue = evaluationRepository
                .findByResultAndRescueDeadlineLessThanEqual(EvaluationResult.PENDING_RESCUE, now);

        int processed = 0;
        for (WeeklyEvaluation evaluation : overdue) {
            Long userId = evaluation.getUserId();
            // 사용자 행을 잠가 사후 구매와 직렬화한다 — 만료 처리와 구매가 겹쳐도 둘 중 하나만 이긴다.
            User user = userRepository.findByIdForUpdate(userId).orElse(null);
            if (user == null || !evaluation.isPendingRescue()) {
                continue;   // 락 대기 중 사후 구매가 먼저 확정함
            }

            evaluation.markFailed();
            streakRepository.findById(userId).ifPresent(Streak::reset);
            coinService.charge(userId, missPenalty, CoinTransactionReason.WEEKLY_MISS_PENALTY, null);
            processed++;
            log.info("[WeeklyGoal] rescue expired → failed: userId={}, week={}",
                    userId, evaluation.getWeekStart());
        }
        return processed;
    }

}
