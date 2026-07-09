package com.booster.personalcheckin;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.personalcheckin.dto.CheckInResponse;
import com.booster.personalcheckin.service.PersonalCheckInService;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.service.PersonalLocationService;
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

/**
 * [BS-30 버그 고정] B1 — 스트릭 연속성 미강제.
 *
 * 근거: Streak.recordSuccess(streak/domain/Streak.java:54-60)가 lastSuccessDate를
 * 검사하지 않고 무조건 currentStreak += 1 한다. PersonalCheckInService.checkIn은
 * 갭(미인증일)을 조회/판단하지 않는다 → 하루를 건너뛰어도 스트릭이 끊기지 않는다.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
@Transactional
class StreakContinuityScenarioTest {

    @Autowired AuthService authService;
    @Autowired PersonalLocationService personalLocationService;
    @Autowired PersonalCheckInService personalCheckInService;
    @Autowired MutableClock clock;

    private static final AtomicInteger SEQ = new AtomicInteger();

    private Long newUserWithLocation() {
        String email = "b1-" + SEQ.incrementAndGet() + "@test.com";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        personalLocationService.register(userId, new LocationRequest(37.0, 127.0, 100, "home"));
        return userId;
    }

    /**
     * [B1] D일 체크인 → D+1 미인증(하루 건너뜀) → D+2 체크인.
     * 기대: 연속이 끊겼으므로 D+2의 currentStreak == 1.
     * 현재: 갭을 무시하고 +1 → currentStreak == 2 (RED).
     */
    @Test
    void gapDay_breaksStreak_currentStreakResetsToOne() {
        Long userId = newUserWithLocation();
        LocalDate d = LocalDate.of(2035, 3, 2);

        clock.setDate(d);
        CheckInResponse first = personalCheckInService.checkIn(userId, 37.0, 127.0);
        assertThat(first.currentStreak()).isEqualTo(1);

        // D+1 (2035-03-03)은 의도적으로 미인증 → 연속 끊김

        clock.setDate(d.plusDays(2)); // D+2 (2035-03-04)
        CheckInResponse afterGap = personalCheckInService.checkIn(userId, 37.0, 127.0);

        assertThat(afterGap.currentStreak())
                .as("하루 건너뛴 뒤 복귀하면 스트릭은 1로 새로 시작해야 한다(연속성). 현재는 2로 누적됨")
                .isEqualTo(1);
    }

    /**
     * [B1 보너스] 갭으로 끊긴 스트릭이 부당하게 7일 마일스톤 보상을 받지 않아야 한다.
     * 시나리오: D..D+5 6일 연속 체크인(streak 6) → D+6 미인증 → D+7 체크인.
     * 기대: 갭으로 streak가 1로 리셋되므로 7일 마일스톤 미도달 → 보상 없음(잔액 500 유지).
     * 현재: 갭 무시로 streak가 7 도달 → 100코인 부당 지급(rewardGranted=true, 잔액 600) (RED).
     */
    @Test
    void gapBrokenStreak_doesNotGrantSevenDayMilestoneReward() {
        Long userId = newUserWithLocation();
        LocalDate start = LocalDate.of(2035, 3, 10);

        for (int i = 0; i < 6; i++) { // D..D+5: 6일 연속
            clock.setDate(start.plusDays(i));
            personalCheckInService.checkIn(userId, 37.0, 127.0);
        }

        // D+6 (start+6)은 미인증 → 연속 끊김

        clock.setDate(start.plusDays(7)); // D+7 복귀 체크인
        CheckInResponse afterGap = personalCheckInService.checkIn(userId, 37.0, 127.0);

        assertThat(afterGap.rewardGranted())
                .as("갭으로 끊긴 스트릭은 7일 마일스톤에 도달할 수 없으므로 보상이 지급되면 안 된다")
                .isFalse();
        assertThat(afterGap.coinBalance())
                .as("부당 마일스톤 보상(+100)이 지급되면 안 됨 → 가입보너스 500 유지")
                .isEqualTo(500L);
    }
}
