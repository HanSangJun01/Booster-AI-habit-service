package com.booster.weeklygoal;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import com.booster.personalcheckin.service.PersonalCheckInService;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.service.PersonalLocationService;
import com.booster.shared.common.BusinessException;
import com.booster.streak.repository.StreakRepository;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
import com.booster.user.repository.UserRepository;
import com.booster.weeklygoal.domain.EvaluationResult;
import com.booster.weeklygoal.service.RecoveryTicketService;
import com.booster.weeklygoal.service.WeeklyEvaluationService;
import com.booster.weeklygoal.service.WeeklyGoalService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import com.booster.personalcheckin.dto.CheckInResponse;
import com.booster.weeklygoal.dto.WeeklyGoalResponse;

/**
 * [주간 목표 모델] 주간 채점 · 구제권 회귀 테스트.
 *
 * <p>과거 복귀 미션 모델의 테스트(RecoveryServiceTest / RecoveryScenarioBugTest /
 * StreakContinuityScenarioTest)를 대체한다. 검증 대상이 "하루 단위 복귀"에서
 * "주 단위 채점 + 구제권"으로 바뀌었기 때문이다.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
@Transactional
class WeeklyEvaluationServiceTest {

    /** 평가 대상 주: 2035-06-04(월) ~ 06-10(일). 테스트 시계 기본값은 그다음 월요일(06-11). */
    private static final LocalDate WEEK = LocalDate.of(2035, 6, 4);

    @Autowired AuthService authService;
    @Autowired PersonalLocationService personalLocationService;
    @Autowired PersonalCheckInService personalCheckInService;
    @Autowired WeeklyEvaluationService weeklyEvaluationService;
    @Autowired WeeklyGoalService weeklyGoalService;
    @Autowired RecoveryTicketService recoveryTicketService;
    @Autowired CoinService coinService;
    @Autowired UserRepository userRepository;
    @Autowired StreakRepository streakRepository;
    @Autowired MutableClock clock;

    private static final AtomicInteger SEQ = new AtomicInteger();

    /** 목표 기본값 3회. 가입 보너스 500코인, 구제권 1개로 시작한다. */
    private Long newUser() {
        String email = "wk-" + SEQ.incrementAndGet() + "@test.com";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        personalLocationService.register(userId, new LocationRequest(37.0, 127.0, 100, "home"));
        return userId;
    }

    /** 기준 주의 n번째 날(0=월)에 인증한다. */
    private void checkInOnDay(Long userId, int dayOffset) {
        clock.setDate(WEEK.plusDays(dayOffset));
        personalCheckInService.checkIn(userId, 37.0, 127.0);
    }

    private int streakOf(Long userId) {
        return streakRepository.findById(userId).orElseThrow().getCurrentStreak();
    }

    private long coinsOf(Long userId) {
        return userRepository.findById(userId).orElseThrow().getCoinBalance();
    }

    private int ticketsOf(Long userId) {
        return userRepository.findById(userId).orElseThrow().getRecoveryTickets();
    }

    private int freeOf(Long userId) {
        return userRepository.findById(userId).orElseThrow().getFreeRecoveryTickets();
    }

    private int paidOf(Long userId) {
        return userRepository.findById(userId).orElseThrow().getPaidRecoveryTickets();
    }

    // ────────────────────────── 채점 ──────────────────────────

    @Test
    @DisplayName("목표 달성: 스트릭 유지 + 마일스톤 보상 지급")
    void achieved_keepsStreakAndGrantsMilestoneReward() {
        Long userId = newUser();
        for (int d = 0; d < 7; d++) {   // 목표 3회인데 7회 인증
            checkInOnDay(userId, d);
        }

        EvaluationResult result = weeklyEvaluationService.evaluateUser(userId, WEEK);

        assertThat(result).isEqualTo(EvaluationResult.ACHIEVED);
        assertThat(streakOf(userId)).isEqualTo(7);
        assertThat(coinsOf(userId))
                .as("마일스톤 보상은 7번째 인증 시점에 이미 지급됐다 (가입 500 + 100)")
                .isEqualTo(600L);
        assertThat(ticketsOf(userId)).as("달성했으므로 구제권은 소모되지 않는다").isEqualTo(1);
    }

    @Test
    @DisplayName("미달 + 구제권 있음: 구제권 1개 소모, 스트릭 유지, 코인 차감 없음")
    void shortOfTarget_withTicket_isRescued() {
        Long userId = newUser();
        checkInOnDay(userId, 0);
        checkInOnDay(userId, 2);        // 2/3 미달

        EvaluationResult result = weeklyEvaluationService.evaluateUser(userId, WEEK);

        assertThat(result).isEqualTo(EvaluationResult.RESCUED);
        assertThat(streakOf(userId)).as("스트릭은 지켜진다").isEqualTo(2);
        assertThat(coinsOf(userId)).as("구제 자체에는 코인이 들지 않는다").isEqualTo(500L);
        assertThat(ticketsOf(userId)).as("구제권 1개 소모").isZero();
    }

    @Test
    @DisplayName("미달 + 구제권 없음: 즉시 실패가 아니라 구제 대기 (스트릭·코인 그대로)")
    void shortOfTarget_withoutTicket_entersPendingRescue() {
        Long userId = newUser();
        userRepository.findById(userId).orElseThrow().consumeRecoveryTicket();  // 구제권 소진
        checkInOnDay(userId, 0);
        checkInOnDay(userId, 2);        // 2/3 미달

        EvaluationResult result = weeklyEvaluationService.evaluateUser(userId, WEEK);

        assertThat(result).isEqualTo(EvaluationResult.PENDING_RESCUE);
        assertThat(streakOf(userId)).as("아직 확정 전이므로 스트릭은 그대로").isEqualTo(2);
        assertThat(coinsOf(userId)).as("아직 아무것도 차감하지 않는다").isEqualTo(500L);

        WeeklyGoalResponse status = weeklyGoalService.getStatus(userId);
        assertThat(status.pendingRescueWeek()).as("앱이 안내 팝업을 띄울 수 있게 노출").isEqualTo(WEEK);
        assertThat(status.rescueDeadline()).isNotNull();
        assertThat(status.lateRescuePrice()).isEqualTo(1200L);
    }

    @Test
    @DisplayName("구제 기한 경과: 그때서야 스트릭 0 + 코인 차감으로 확정된다")
    void rescueDeadlinePassed_confirmsFailure() {
        Long userId = newUser();
        userRepository.findById(userId).orElseThrow().consumeRecoveryTicket();
        checkInOnDay(userId, 0);        // 1/3 미달
        clock.setDate(WEEK.plusDays(7));                       // 채점일(다음 주 월요일)
        weeklyEvaluationService.evaluateUser(userId, WEEK);

        clock.setDate(WEEK.plusDays(7 + 3));                   // 유예 2일이 지난 시점
        int expired = weeklyEvaluationService.expireOverdueRescues();

        assertThat(expired).isEqualTo(1);
        assertThat(streakOf(userId)).as("이 시점에 비로소 초기화").isZero();
        assertThat(coinsOf(userId)).as("이 시점에 비로소 벌금 500 차감").isZero();
    }

    @Test
    @DisplayName("사후 구매: 기한 내 구매하면 구제되고 스트릭이 지켜진다")
    void lateRescuePurchase_savesStreak() {
        Long userId = newUser();
        userRepository.findById(userId).orElseThrow().consumeRecoveryTicket();
        coinService.grant(userId, 1000L, CoinTransactionReason.STREAK_REWARD, null);  // 1500
        checkInOnDay(userId, 0);
        checkInOnDay(userId, 2);        // 2/3 미달
        clock.setDate(WEEK.plusDays(7));
        weeklyEvaluationService.evaluateUser(userId, WEEK);

        recoveryTicketService.purchaseLateRescue(userId);

        assertThat(streakOf(userId)).as("스트릭 유지").isEqualTo(2);
        assertThat(coinsOf(userId)).as("사후 구매가 1200 차감 (1500 → 300)").isEqualTo(300L);
        assertThat(weeklyGoalService.getStatus(userId).pendingRescueWeek())
                .as("대기 상태 해소").isNull();

        // 확정된 뒤에는 만료 처리 대상이 아니다
        clock.setDate(WEEK.plusDays(7 + 3));
        assertThat(weeklyEvaluationService.expireOverdueRescues()).isZero();
        assertThat(coinsOf(userId)).as("벌금이 추가로 부과되면 안 된다").isEqualTo(300L);
    }

    @Test
    @DisplayName("사후 구매: 기한이 지나면 거절된다")
    void lateRescuePurchase_afterDeadline_isRejected() {
        Long userId = newUser();
        userRepository.findById(userId).orElseThrow().consumeRecoveryTicket();
        coinService.grant(userId, 1000L, CoinTransactionReason.STREAK_REWARD, null);
        checkInOnDay(userId, 0);
        clock.setDate(WEEK.plusDays(7));
        weeklyEvaluationService.evaluateUser(userId, WEEK);

        clock.setDate(WEEK.plusDays(7 + 3));   // 기한 경과

        assertThatThrownBy(() -> recoveryTicketService.purchaseLateRescue(userId))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    @DisplayName("사후 구매: 대기 중인 건이 없으면 거절된다")
    void lateRescuePurchase_withoutPending_isRejected() {
        Long userId = newUser();
        coinService.grant(userId, 1000L, CoinTransactionReason.STREAK_REWARD, null);

        assertThatThrownBy(() -> recoveryTicketService.purchaseLateRescue(userId))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    @DisplayName("마일스톤 보상은 7번째 인증 순간에 지급된다 (채점을 기다리지 않는다)")
    void milestoneReward_isGrantedAtCheckInMoment() {
        Long userId = newUser();
        for (int d = 0; d < 6; d++) {
            checkInOnDay(userId, d);
        }
        assertThat(coinsOf(userId)).as("6회까지는 보상 없음").isEqualTo(500L);

        CheckInResponse seventh = null;
        clock.setDate(WEEK.plusDays(6));
        seventh = personalCheckInService.checkIn(userId, 37.0, 127.0);

        assertThat(seventh.rewardGranted()).as("7번째 인증 응답에 즉시 반영").isTrue();
        assertThat(seventh.coinBalance()).isEqualTo(600L);
        assertThat(coinsOf(userId)).as("채점 전에 이미 지급됨").isEqualTo(600L);
    }

    @Test
    @DisplayName("멱등: 같은 주를 두 번 채점해도 한 번만 반영된다")
    void evaluatingSameWeekTwice_isIdempotent() {
        Long userId = newUser();
        userRepository.findById(userId).orElseThrow().consumeRecoveryTicket();
        checkInOnDay(userId, 0);        // 1/3 미달

        weeklyEvaluationService.evaluateUser(userId, WEEK);
        long afterFirst = coinsOf(userId);

        EvaluationResult second = weeklyEvaluationService.evaluateUser(userId, WEEK);

        assertThat(second).as("이미 채점된 주는 건너뛴다").isNull();
        assertThat(coinsOf(userId)).as("벌금이 두 번 부과되면 안 된다").isEqualTo(afterFirst);
    }

    // ────────────────────────── 구제권 ──────────────────────────

    @Test
    @DisplayName("구제권 구매: 코인 800 차감, 보유 +1")
    void purchaseTicket_deductsCoinsAndAddsTicket() {
        Long userId = newUser();
        coinService.grant(userId, 1000L, CoinTransactionReason.STREAK_REWARD, null); // 500 + 1000

        int tickets = recoveryTicketService.purchase(userId);

        assertThat(tickets).isEqualTo(2);
        assertThat(coinsOf(userId)).isEqualTo(700L);   // 1500 - 800
    }

    @Test
    @DisplayName("구제권 구매: 잔액 부족이면 거절된다")
    void purchaseTicket_insufficientCoins_isRejected() {
        Long userId = newUser();   // 가입 보너스 500 < 가격 800

        assertThatThrownBy(() -> recoveryTicketService.purchase(userId))
                .as("잔액이 모자라면 클램핑 없이 거절되어야 한다")
                .isInstanceOf(RuntimeException.class);
        assertThat(coinsOf(userId)).as("실패 시 코인이 깎이면 안 된다").isEqualTo(500L);
    }

    @Test
    @DisplayName("무료 구제권 월 지급은 같은 달에 두 번 지급되지 않는다")
    void monthlyGrant_isIdempotentWithinMonth() {
        Long userId = newUser();
        LocalDate month = LocalDate.of(2035, 6, 1);

        assertThat(recoveryTicketService.runMonthly(userId, month)).isTrue();
        assertThat(recoveryTicketService.runMonthly(userId, month))
                .as("같은 달 재실행은 무시된다").isFalse();
        assertThat(ticketsOf(userId)).isEqualTo(1);
    }

    @Test
    @DisplayName("무료분만 소멸하고 코인으로 산 구제권은 살아남는다")
    void monthlyGrant_resetsFreeButKeepsPaid() {
        Long userId = newUser();
        coinService.grant(userId, 1000L, CoinTransactionReason.STREAK_REWARD, null);
        recoveryTicketService.purchase(userId);                 // 무료1 + 구매1 = 2

        recoveryTicketService.runMonthly(userId, LocalDate.of(2035, 7, 1));

        assertThat(freeOf(userId)).as("무료분은 1개로 재설정").isEqualTo(1);
        assertThat(paidOf(userId)).as("코인으로 산 것은 소멸하지 않는다").isEqualTo(1);
        assertThat(ticketsOf(userId)).isEqualTo(2);
    }

    @Test
    @DisplayName("구제는 무료분을 먼저 소모한다 (무료분이 월말에 사라지므로)")
    void rescue_consumesFreeTicketFirst() {
        Long userId = newUser();
        coinService.grant(userId, 1000L, CoinTransactionReason.STREAK_REWARD, null);
        recoveryTicketService.purchase(userId);                 // 무료1 + 구매1
        checkInOnDay(userId, 0);                                // 1/3 미달

        weeklyEvaluationService.evaluateUser(userId, WEEK);

        assertThat(freeOf(userId)).as("무료분이 먼저 쓰인다").isZero();
        assertThat(paidOf(userId)).as("구매분은 남는다").isEqualTo(1);
    }

    // ────────────────────────── 목표 변경 ──────────────────────────

    @Test
    @DisplayName("목표 변경은 예약만 되고 다음 달 1일에 반영된다")
    void targetChange_isReservedAndAppliedOnFirstOfMonth() {
        Long userId = newUser();
        checkInOnDay(userId, 0);
        checkInOnDay(userId, 2);
        checkInOnDay(userId, 4);        // 3/3 달성

        weeklyGoalService.reserveTarget(userId, 5, null);

        assertThat(weeklyGoalService.getStatus(userId).targetDays())
                .as("진행 중인 주의 기준은 그대로 3이어야 한다(주 중간 하향으로 통과하는 회피 차단)")
                .isEqualTo(3);
        assertThat(weeklyGoalService.getStatus(userId).pendingTargetDays()).isEqualTo(5);

        EvaluationResult result = weeklyEvaluationService.evaluateUser(userId, WEEK);
        assertThat(result).as("이번 주는 예전 목표(3) 기준으로 달성 판정").isEqualTo(EvaluationResult.ACHIEVED);
        assertThat(weeklyGoalService.getStatus(userId).targetDays())
                .as("주간 채점만으로는 목표가 바뀌지 않는다").isEqualTo(3);

        recoveryTicketService.runMonthly(userId, LocalDate.of(2035, 7, 1));

        assertThat(weeklyGoalService.getStatus(userId).targetDays())
                .as("월초 처리에서 예약 목표가 반영된다").isEqualTo(5);
        assertThat(weeklyGoalService.getStatus(userId).pendingTargetDays()).isNull();
    }
}
