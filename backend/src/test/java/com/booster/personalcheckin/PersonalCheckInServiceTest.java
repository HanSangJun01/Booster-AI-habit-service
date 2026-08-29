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

    /** 마일스톤 보상은 7번째 인증하는 그 순간 지급된다(주간 채점을 기다리지 않는다). */
    @Test
    void sevenCheckIns_grantMilestoneRewardImmediately() {
        Long userId = newUserWithLocation();
        LocalDate start = LocalDate.of(2035, 3, 5);

        CheckInResponse resp = null;
        for (int i = 0; i < 7; i++) {
            clock.setDate(start.plusDays(i));
            resp = personalCheckInService.checkIn(userId, 37.0, 127.0);
        }

        assertThat(resp.currentStreak()).isEqualTo(7);
        assertThat(resp.rewardGranted()).as("7회 도달 즉시 보상").isTrue();
        assertThat(resp.coinBalance()).as("가입 500 + 마일스톤 100").isEqualTo(600L);
    }

    /**
     * [주간 목표 모델] 날짜 갭이 있어도 스트릭은 끊기지 않는다.
     * 주 3회 목표라면 월·수·금 사이의 빈 날은 정상이기 때문이다.
     * (과거 B1 수정이 강제하던 "갭 = 리셋"은 폐기됐고, 리셋은 주간 채점만 수행한다.)
     */
    @Test
    void gapDay_doesNotBreakStreak() {
        Long userId = newUserWithLocation();
        LocalDate d = LocalDate.of(2035, 3, 2);

        clock.setDate(d);
        assertThat(personalCheckInService.checkIn(userId, 37.0, 127.0).currentStreak()).isEqualTo(1);

        clock.setDate(d.plusDays(2)); // 하루 건너뜀
        assertThat(personalCheckInService.checkIn(userId, 37.0, 127.0).currentStreak())
                .as("갭이 있어도 누적된다 — 주간 목표 달성 여부는 주간 채점이 판정한다")
                .isEqualTo(2);
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
