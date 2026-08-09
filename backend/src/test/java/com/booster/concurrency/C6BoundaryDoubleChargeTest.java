package com.booster.concurrency;

import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.recovery.domain.RecoveryMission;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;

import java.time.Clock;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [C6] 스케줄러 만료(<=) vs 유저 수행(isAfter strict) 경계 불일치 → 코인 이중차감.
 *
 * <p>{@code performRecovery} 는 {@code now.isAfter(deadline)}(strict) 라 deadline==now 면 통과(성공 -50).
 * {@code expireOverdueMissions} 는 {@code deadlineAt <= now}(inclusive) 라 같은 미션을 만료 대상(실패 -100)으로 본다.
 * 양쪽 모두 무락이라, deadline==now 인 순간 동시에 부딪히면 한 미션이 사용자 성공과 스케줄러 실패로
 * <b>동시에</b> 처리되어 -50 과 -100 이 모두 적용(-150) 된다.
 *
 * <p>고정 시계({@link FixedClockConfig})로 now 를 고정하고, 미션 deadline 을 그 instant 와 정확히 동일하게 둔다.
 * 올바른 동작: 한 미션은 둘 중 하나로만 처리 → 총 차감은 50 또는 100. 이중차감(-150)이면 RED.
 * (TestClockConfig 를 함께 import 하지 않으며, FixedClockConfig 의 @Primary Clock 이 우선한다.)
 */
@Import(FixedClockConfig.class)
class C6BoundaryDoubleChargeTest extends ConcurrencyTestBase {

    @Autowired Clock clock; // FixedClockConfig 의 고정 시계

    @Test
    @DisplayName("deadline==now 경계: performRecovery(-50)와 expireOverdueMissions(-100)가 한 미션을 이중차감하면 안 된다")
    void boundaryDeadlineEqualsNow_mustNotDoubleCharge() throws Exception {
        int iterations = 10;
        List<Long> chargedPerRound = new java.util.ArrayList<>();

        for (int i = 0; i < iterations; i++) {
            Long userId = newUserWithLocation("c6-");
            OffsetDateTime nowExact = OffsetDateTime.now(clock);   // == FIXED_INSTANT
            LocalDate missed = LocalDate.now(clock).minusDays(1);

            PersonalCheckIn pending = personalCheckInRepository.save(
                    PersonalCheckIn.recoveryPending(userId, missed));
            // deadline 을 now 와 정확히 동일하게 → 경계 충돌 강제
            recoveryMissionRepository.save(
                    RecoveryMission.createPending(userId, pending.getId(), nowExact));

            // 동시: 사용자 복귀 수행 || 스케줄러 만료
            runConcurrently(List.of(
                    () -> recoveryService.performRecovery(userId, LAT, LNG),
                    () -> recoveryService.expireOverdueMissions()));

            long balance = coinService.getBalance(userId);
            long charged = 500 - balance; // 가입 보너스 500 기준 총 차감액
            chargedPerRound.add(charged);

            assertThat(charged)
                    .as("iteration %d: deadline==now 미션의 총 차감은 50(성공) 또는 100(실패) 중 하나여야 한다. "
                            + "150 이면 한 미션이 성공+실패로 이중차감된 것. 실제 차감=%d", i, charged)
                    .isIn(50L, 100L);
        }
    }
}
