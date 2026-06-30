package com.booster.concurrency;

import com.booster.coin.domain.CoinTransactionReason;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.recovery.domain.RecoveryMission;
import com.booster.recovery.domain.RecoveryStatus;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [C2] 동시 performRecovery 이중 처리.
 *
 * <p>{@code RecoveryService.performRecovery} 는 PENDING 미션을 <b>락 없이</b> 조회하고
 * PENDING→COMPLETED 전이를 보호하지 않는다. 동시 2건이 같은 미션을 잡으면 둘 다 성공 처리되어
 * 코인 -50 이 2번(-100), 출석 +2, RECOVERY_SUCCESS 거래 2행이 생긴다.
 *
 * <p>올바른 동작: 정확히 1건만 성공, 다른 1건은 거부(이미 처리됨/충돌). 따라서 RECOVERY_SUCCESS
 * 거래는 1행, 총 차감 50(잔액 450)이어야 한다. 버그면 2행/잔액 400 → RED.
 */
@Import(TestClockConfig.class)
class C2ConcurrentRecoveryTest extends ConcurrencyTestBase {

    @Autowired MutableClock clock;

    @Test
    @DisplayName("동시 performRecovery 2건: 복귀 성공은 정확히 1회만 처리되어야 한다(-50, 거래 1행)")
    void concurrentPerformRecovery_mustProcessExactlyOnce() throws Exception {
        clock.setDate(LocalDate.of(2035, 6, 11));
        Long userId = newUserWithLocation("c2-");
        LocalDate today = LocalDate.now(clock);
        LocalDate yesterday = today.minusDays(1);

        // 어제 미인증 → RECOVERY_PENDING + 복귀 미션(deadline 미래)
        PersonalCheckIn pending = personalCheckInRepository.save(
                PersonalCheckIn.recoveryPending(userId, yesterday));
        OffsetDateTime deadline = today.atTime(23, 59, 59).atZone(MutableClock.KST).toOffsetDateTime();
        recoveryMissionRepository.save(RecoveryMission.createPending(userId, pending.getId(), deadline));

        // 동시에 복귀 수행 2건
        runConcurrently(List.of(
                () -> recoveryService.performRecovery(userId, LAT, LNG),
                () -> recoveryService.performRecovery(userId, LAT, LNG)));

        long successTx = countTxOfType(userId, CoinTransactionReason.RECOVERY_SUCCESS);
        long balance = coinService.getBalance(userId);
        int attendance = userRepository.findById(userId).orElseThrow().getTotalAttendance();
        long completedMissions = recoveryMissionRepository
                .findByStatusAndDeadlineAtLessThanEqual(RecoveryStatus.COMPLETED, deadline.plusYears(100))
                .stream().filter(m -> m.getUserId().equals(userId)).count();

        assertThat(successTx)
                .as("RECOVERY_SUCCESS 코인 거래는 정확히 1행이어야 한다(이중 처리 금지). 실제=%d", successTx)
                .isEqualTo(1);
        assertThat(balance)
                .as("복귀 성공 차감은 -50 한 번뿐 → 잔액 450. 실제=%d", balance)
                .isEqualTo(450);
        assertThat(attendance)
                .as("복귀 성공은 출석 +1 한 번뿐. 실제=%d", attendance)
                .isEqualTo(1);
        assertThat(completedMissions)
                .as("COMPLETED 미션은 1건이어야 한다. 실제=%d", completedMissions)
                .isEqualTo(1);
    }
}
