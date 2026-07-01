package com.booster.concurrency;

import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.recovery.domain.RecoveryMission;
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
 * [C5 → F2 재정의] 복귀일 동시 checkIn+performRecovery.
 *
 * <p>F2(팀 결정: 복귀 당일 별도 인증 불가) 이후, 오늘이 복귀 대상일이면 일반 checkIn 은 차단되고
 * 복귀만 '그날 인증'으로 반영된다. 따라서 checkIn 과 performRecovery 를 동시에 던져도 이중 카운트나
 * streak 소실 없이 결과가 결정적으로 복귀 1건(streak 5→6)이어야 한다.
 * (User 행 비관락으로 사용자 단위 직렬화 + 복귀일 인증 차단이 함께 보장.)
 */
@Import(TestClockConfig.class)
class C5StreakLostUpdateTest extends ConcurrencyTestBase {

    @Autowired MutableClock clock;

    private void forceStreak(Long userId, int value) {
        inTransaction(() -> em.createNativeQuery(
                        "UPDATE streaks SET current_streak = :v, max_streak = :v WHERE user_id = :id")
                .setParameter("v", value)
                .setParameter("id", userId)
                .executeUpdate());
    }

    @Test
    @DisplayName("복귀일 동시 checkIn+performRecovery: 일반 인증은 차단되고 복귀만 반영 → streak 항상 6(이중카운트/소실 없음)")
    void concurrentCheckInAndRecovery_onRecoveryDay_recoveryWinsCheckInBlocked() throws Exception {
        int iterations = 20;
        List<Integer> observed = new java.util.ArrayList<>();

        for (int i = 0; i < iterations; i++) {
            clock.setDate(LocalDate.of(2035, 6, 11));
            Long userId = newUserWithLocation("c5-");
            LocalDate today = LocalDate.now(clock);
            LocalDate yesterday = today.minusDays(1);

            forceStreak(userId, 5);

            // 어제 미인증 → 복귀 미션(deadline=오늘 23:59:59) → 오늘은 '복귀 대상일'
            PersonalCheckIn pending = personalCheckInRepository.save(
                    PersonalCheckIn.recoveryPending(userId, yesterday));
            OffsetDateTime deadline = today.atTime(23, 59, 59).atZone(MutableClock.KST).toOffsetDateTime();
            recoveryMissionRepository.save(RecoveryMission.createPending(userId, pending.getId(), deadline));

            // 동시: 오늘 일반 인증(F2로 차단됨) || 복귀 수행(그날 인증으로 간주, streak 5→6)
            runConcurrently(List.of(
                    () -> personalCheckInService.checkIn(userId, LAT, LNG),
                    () -> recoveryService.performRecovery(userId, LAT, LNG)));

            observed.add(streakRepository.findById(userId).orElseThrow().getCurrentStreak());
        }

        assertThat(observed)
                .as("복귀일엔 일반 인증이 차단되어 복귀만 반영(5→6). 이중 카운트(7)나 소실(5) 없이 항상 6. 관측=%s", observed)
                .containsOnly(6);
    }
}
