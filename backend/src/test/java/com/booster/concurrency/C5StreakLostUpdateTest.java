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
 * [C5] Streak lost update.
 *
 * <p>Streak 엔티티에는 {@code @Version} 이 없고, checkIn 과 performRecovery 모두 Streak 를
 * <b>락 없이</b> 로드/수정한다. 동시에:
 * <ul>
 *   <li>T1 = 일반 checkIn(오늘) → {@code recordSuccess} → currentStreak 5→6</li>
 *   <li>T2 = performRecovery(어제 미션) → {@code keepAlive} → lastSuccessDate 만 갱신하지만,
 *       Hibernate 전체갱신이 자신이 읽은 current_streak(5)을 그대로 다시 써서 T1 의 +1 을 덮어쓸 수 있다.</li>
 * </ul>
 *
 * <p>의미상 "체크인의 +1 은 소실되면 안 된다" → 최종 current_streak == 6 이어야 한다.
 * lost update 면 5 로 남는다. 비결정적이므로 신규 유저로 다수 라운드를 돌려, 한 번이라도
 * 소실되면 RED. 환경에 따라 재현이 불안정하면 보고서에 명시한다.
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
    @DisplayName("동시 checkIn(+1)과 performRecovery(keepAlive)에서 체크인의 streak +1 이 소실되면 안 된다")
    void checkInIncrementMustSurvive_concurrentRecoveryKeepAlive() throws Exception {
        int iterations = 30;
        int lostUpdates = 0;
        List<Integer> observed = new java.util.ArrayList<>();

        for (int i = 0; i < iterations; i++) {
            clock.setDate(LocalDate.of(2035, 6, 11));
            Long userId = newUserWithLocation("c5-");
            LocalDate today = LocalDate.now(clock);
            LocalDate yesterday = today.minusDays(1);

            forceStreak(userId, 5);

            // 어제 미인증 → 복귀 미션(deadline 미래)
            PersonalCheckIn pending = personalCheckInRepository.save(
                    PersonalCheckIn.recoveryPending(userId, yesterday));
            OffsetDateTime deadline = today.atTime(23, 59, 59).atZone(MutableClock.KST).toOffsetDateTime();
            recoveryMissionRepository.save(RecoveryMission.createPending(userId, pending.getId(), deadline));

            // 동시: 오늘 일반 인증(+1 → 6) || 어제 복귀 수행(keepAlive, current 유지)
            runConcurrently(List.of(
                    () -> personalCheckInService.checkIn(userId, LAT, LNG),
                    () -> recoveryService.performRecovery(userId, LAT, LNG)));

            int finalStreak = streakRepository.findById(userId).orElseThrow().getCurrentStreak();
            observed.add(finalStreak);
            if (finalStreak != 6) {
                lostUpdates++;
            }
        }

        assertThat(lostUpdates)
                .as("체크인의 +1(5→6)이 동시 performRecovery(keepAlive)의 무락 전체갱신으로 소실된 라운드 수가 0이어야 한다. "
                        + "라운드별 관측 current_streak=%s", observed)
                .isZero();
    }
}
