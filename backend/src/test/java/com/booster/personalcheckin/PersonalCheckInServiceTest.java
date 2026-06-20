package com.booster.personalcheckin;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.personalcheckin.domain.PersonalCheckInStatus;
import com.booster.personalcheckin.dto.CheckInResponse;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personalcheckin.service.PersonalCheckInService;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.service.PersonalLocationService;
import com.booster.shared.common.BusinessException;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
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

@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
@Transactional
class PersonalCheckInServiceTest {

    @Autowired AuthService authService;
    @Autowired PersonalLocationService personalLocationService;
    @Autowired PersonalCheckInService personalCheckInService;
    @Autowired PersonalCheckInRepository personalCheckInRepository;
    @Autowired MutableClock clock;

    private static final AtomicInteger SEQ = new AtomicInteger();

    private Long newUserWithLocation() {
        String email = "p" + SEQ.incrementAndGet() + "@test.com";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        personalLocationService.register(userId, new LocationRequest(37.0, 127.0, 100, "home"));
        return userId;
    }

    @Test
    void gpsSuccess_incrementsStreak() {
        Long userId = newUserWithLocation();
        clock.setDate(LocalDate.of(2035, 3, 2));

        CheckInResponse resp = personalCheckInService.checkIn(userId, 37.0, 127.0);

        assertThat(resp.status()).isEqualTo(PersonalCheckInStatus.SUCCESS);
        assertThat(resp.currentStreak()).isEqualTo(1);
        assertThat(resp.rewardGranted()).isFalse();
        assertThat(resp.coinBalance()).isEqualTo(500L); // 가입 보너스만
    }

    @Test
    void sevenDayStreak_grantsRewardCoins() {
        Long userId = newUserWithLocation();
        LocalDate start = LocalDate.of(2035, 3, 5);

        CheckInResponse resp = null;
        for (int i = 0; i < 7; i++) {
            clock.setDate(start.plusDays(i));
            resp = personalCheckInService.checkIn(userId, 37.0, 127.0);
        }

        assertThat(resp.currentStreak()).isEqualTo(7);
        assertThat(resp.rewardGranted()).isTrue();
        assertThat(resp.coinBalance()).isEqualTo(600L); // 500 + 100
    }

    @Test
    void duplicateSameDay_returns409() {
        Long userId = newUserWithLocation();
        clock.setDate(LocalDate.of(2035, 3, 10));
        personalCheckInService.checkIn(userId, 37.0, 127.0);

        assertThatThrownBy(() -> personalCheckInService.checkIn(userId, 37.0, 127.0))
                .isInstanceOf(BusinessException.class)
                .satisfies(e -> assertThat(((BusinessException) e).getCode()).isEqualTo("DUPLICATE_CHECK_IN"));
    }

    @Test
    void outOfRange_throwsAndCreatesNoRecord() {
        Long userId = newUserWithLocation();
        LocalDate day = LocalDate.of(2035, 3, 12);
        clock.setDate(day);

        assertThatThrownBy(() -> personalCheckInService.checkIn(userId, 40.0, 130.0))
                .isInstanceOf(BusinessException.class)
                .satisfies(e -> assertThat(((BusinessException) e).getCode()).isEqualTo("GPS_OUT_OF_RANGE"));

        assertThat(personalCheckInRepository.existsByUserIdAndDate(userId, day)).isFalse();
    }
}
