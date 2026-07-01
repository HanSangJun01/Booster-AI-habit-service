package com.booster.dashboard;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.dashboard.dto.DashboardResponse;
import com.booster.dashboard.service.DashboardService;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
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

/**
 * 대시보드 홈 응답의 정확성을 고정한다. 특히 이번 주(월~일)가 두 달에 걸치는 경계에서
 * 주간 성공수(week)와 캘린더(month)가 각자 올바른 범위로 계산되는지 검증한다.
 * (BS-30 최적화 ③ — 쿼리 5→3 리팩터 전/후 동작 불변 보장용 안전망)
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
@Transactional
class DashboardServiceTest {

    @Autowired AuthService authService;
    @Autowired DashboardService dashboardService;
    @Autowired PersonalCheckInRepository personalCheckInRepository;
    @Autowired MutableClock clock;

    private static final AtomicInteger SEQ = new AtomicInteger();

    private Long newUser() {
        String email = "dash-" + SEQ.incrementAndGet() + "@test.com";
        return authService.signup(new SignupRequest(email, "password1234", "u")).userId();
    }

    private void saveSuccess(Long userId, LocalDate date) {
        personalCheckInRepository.save(
                PersonalCheckIn.success(userId, date, OffsetDateTime.now(clock)));
    }

    /**
     * today=2035-08-01(수) → 이번 주 월요일=2035-07-30(전달), 주 종료=2035-08-05.
     * - 07-30: 이번 주 O / 8월 캘린더 X
     * - 08-01: 오늘 / 이번 주 O / 8월 캘린더 O
     * - 08-20: 이번 주 X / 8월 캘린더 O
     */
    @Test
    void home_weekSpanningMonthBoundary_computesWeekAndCalendarSeparately() {
        Long userId = newUser();
        LocalDate today = LocalDate.of(2035, 8, 1);
        clock.setDate(today);

        saveSuccess(userId, LocalDate.of(2035, 7, 30));
        saveSuccess(userId, today);
        saveSuccess(userId, LocalDate.of(2035, 8, 20));

        DashboardResponse home = dashboardService.getHome(userId);

        assertThat(home.coinBalance()).isEqualTo(500L);
        assertThat(home.todayStatus())
                .as("오늘(08-01) 상태는 SUCCESS")
                .isEqualTo("SUCCESS");
        assertThat(home.weeklySuccessCount())
                .as("이번 주(07-30~08-05) 성공수 = 07-30 + 08-01 = 2 (전달 날짜 포함)")
                .isEqualTo(2L);
        assertThat(home.calendar().year()).isEqualTo(2035);
        assertThat(home.calendar().month()).isEqualTo(8);
        assertThat(home.calendar().days())
                .as("8월 캘린더는 8월 레코드만(07-30 제외) → 08-01, 08-20")
                .extracting(DashboardResponse.CalendarDay::date)
                .containsExactly(LocalDate.of(2035, 8, 1), LocalDate.of(2035, 8, 20));
    }

    @Test
    void home_noCheckInToday_todayStatusNotChecked() {
        Long userId = newUser();
        clock.setDate(LocalDate.of(2035, 9, 15));

        DashboardResponse home = dashboardService.getHome(userId);

        assertThat(home.todayStatus()).isEqualTo("NOT_CHECKED");
        assertThat(home.weeklySuccessCount()).isZero();
        assertThat(home.calendar().days()).isEmpty();
        assertThat(home.streak().current()).isZero();
    }
}
