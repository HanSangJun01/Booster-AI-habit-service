package com.booster.recovery;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.domain.PersonalCheckInStatus;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.service.PersonalLocationService;
import com.booster.recovery.domain.RecoveryMission;
import com.booster.recovery.domain.RecoveryStatus;
import com.booster.recovery.dto.RecoveryResultResponse;
import com.booster.recovery.repository.RecoveryMissionRepository;
import com.booster.recovery.service.RecoveryService;
import com.booster.shared.common.BusinessException;
import com.booster.streak.domain.Streak;
import com.booster.streak.repository.StreakRepository;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
@Transactional
class RecoveryServiceTest {

    @Autowired AuthService authService;
    @Autowired PersonalLocationService personalLocationService;
    @Autowired RecoveryService recoveryService;
    @Autowired CoinService coinService;
    @Autowired PersonalCheckInRepository personalCheckInRepository;
    @Autowired RecoveryMissionRepository recoveryMissionRepository;
    @Autowired StreakRepository streakRepository;
    @Autowired MutableClock clock;

    private static final AtomicInteger SEQ = new AtomicInteger();

    private Long newUserWithLocation() {
        String email = "r" + SEQ.incrementAndGet() + "@test.com";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        personalLocationService.register(userId, new LocationRequest(37.0, 127.0, 100, "home"));
        return userId;
    }

    private void setStreak(Long userId, int value) {
        Streak streak = streakRepository.findById(userId).orElseThrow();
        for (int i = 0; i < value; i++) {
            streak.recordSuccess(LocalDate.of(2035, 1, 1).plusDays(i));
        }
    }

    private Long createPendingMission(Long userId, LocalDate missedDate, OffsetDateTime deadline) {
        PersonalCheckIn pending = personalCheckInRepository.save(
                PersonalCheckIn.recoveryPending(userId, missedDate));
        RecoveryMission mission = recoveryMissionRepository.save(
                RecoveryMission.createPending(userId, pending.getId(), deadline));
        return mission.getId();
    }

    @Test
    void performRecovery_success_keepsStreakAndCharges50() {
        Long userId = newUserWithLocation();
        setStreak(userId, 3);
        LocalDate today = LocalDate.of(2035, 4, 10);
        clock.setDate(today);
        OffsetDateTime deadline = today.atTime(23, 59, 59).atZone(MutableClock.KST).toOffsetDateTime();
        createPendingMission(userId, today.minusDays(1), deadline);

        RecoveryResultResponse resp = recoveryService.performRecovery(userId, 37.0, 127.0);

        assertThat(resp.status()).isEqualTo(RecoveryStatus.COMPLETED);
        assertThat(resp.chargedAmount()).isEqualTo(50L);
        assertThat(resp.coinBalance()).isEqualTo(450L); // 500 - 50
        assertThat(resp.currentStreak()).isEqualTo(3);   // 스트릭 유지
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, today.minusDays(1))
                .orElseThrow().getStatus()).isEqualTo(PersonalCheckInStatus.SUCCESS);
    }

    @Test
    void expireOverdue_failsAndResetsStreakAndCharges100() {
        Long userId = newUserWithLocation();
        setStreak(userId, 5);
        LocalDate today = LocalDate.of(2035, 4, 15);
        clock.setDate(today);
        OffsetDateTime pastDeadline = today.minusDays(1).atTime(23, 59, 59)
                .atZone(MutableClock.KST).toOffsetDateTime();
        Long missionId = createPendingMission(userId, today.minusDays(2), pastDeadline);

        int expired = recoveryService.expireOverdueMissions();

        assertThat(expired).isGreaterThanOrEqualTo(1);
        assertThat(recoveryMissionRepository.findById(missionId).orElseThrow().getStatus())
                .isEqualTo(RecoveryStatus.FAILED);
        assertThat(coinService.getBalance(userId)).isEqualTo(400L); // 500 - 100
        assertThat(streakRepository.findById(userId).orElseThrow().getCurrentStreak()).isZero();
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, today.minusDays(2))
                .orElseThrow().getStatus()).isEqualTo(PersonalCheckInStatus.FAILED);
    }

    @Test
    void failurePenalty_clampedToBalance() {
        Long userId = newUserWithLocation();
        coinService.charge(userId, 470, CoinTransactionReason.RECOVERY_SUCCESS, null); // 잔액 30으로
        assertThat(coinService.getBalance(userId)).isEqualTo(30L);

        LocalDate today = LocalDate.of(2035, 4, 20);
        clock.setDate(today);
        OffsetDateTime pastDeadline = today.minusDays(1).atTime(23, 59, 59)
                .atZone(MutableClock.KST).toOffsetDateTime();
        createPendingMission(userId, today.minusDays(2), pastDeadline);

        recoveryService.expireOverdueMissions();

        assertThat(coinService.getBalance(userId)).isZero(); // -100 클램핑 → 0 (실차감 -30)
    }

    @Test
    void performRecovery_noPendingMission_returns404() {
        Long userId = newUserWithLocation();
        clock.setDate(LocalDate.of(2035, 4, 25));

        assertThatThrownBy(() -> recoveryService.performRecovery(userId, 37.0, 127.0))
                .isInstanceOf(BusinessException.class)
                .satisfies(e -> assertThat(((BusinessException) e).getCode()).isEqualTo("NO_RECOVERY_MISSION"));
    }

    @Test
    void generatePendingForYesterday_createsRecoveryPending_idempotent() {
        Long userId = newUserWithLocation();
        LocalDate today = LocalDate.of(2035, 6, 11);
        LocalDate yesterday = today.minusDays(1);
        clock.setDate(today);

        recoveryService.generatePendingForYesterday();
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, yesterday).orElseThrow()
                .getStatus()).isEqualTo(PersonalCheckInStatus.RECOVERY_PENDING);
        assertThat(recoveryMissionRepository
                .findFirstByUserIdAndStatusOrderByDeadlineAtAsc(userId, RecoveryStatus.PENDING))
                .isPresent();

        // 재실행 시 중복 생성 없음(멱등)
        recoveryService.generatePendingForYesterday();
        assertThat(personalCheckInRepository.findByUserIdAndDateBetween(userId, yesterday, yesterday))
                .hasSize(1);
    }
}
