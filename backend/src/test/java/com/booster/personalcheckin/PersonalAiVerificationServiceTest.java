package com.booster.personalcheckin;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.challenge.domain.VerificationType;
import com.booster.challengecheckin.dto.AiServiceVerdict;
import com.booster.challengecheckin.service.AiVerificationClient;
import com.booster.personalcheckin.domain.PersonalCheckInStatus;
import com.booster.personalcheckin.dto.CheckInResponse;
import com.booster.personalcheckin.dto.PersonalAiVerificationResponse;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personalcheckin.service.PersonalAiVerificationService;
import com.booster.personalcheckin.service.PersonalCheckInService;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.service.PersonalLocationService;
import com.booster.shared.common.BusinessException;
import com.booster.streak.repository.StreakRepository;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
import com.booster.user.repository.UserRepository;
import com.booster.weeklygoal.service.WeeklyGoalService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;

/**
 * [개인 AI 인증] 개인 습관에도 GPS / AI / GPS+AI 를 고를 수 있게 한 흐름의 회귀 테스트.
 *
 * <p>ai-service 는 외부 프로세스이므로 {@link AiVerificationClient} 를 mocking 한다.
 * 검증 대상은 "판정 결과에 따라 체크인·스트릭·보상이 어떻게 확정되는가" 다.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
@Transactional
class PersonalAiVerificationServiceTest {

    @Autowired AuthService authService;
    @Autowired PersonalLocationService personalLocationService;
    @Autowired PersonalCheckInService personalCheckInService;
    @Autowired PersonalAiVerificationService aiVerificationService;
    @Autowired WeeklyGoalService weeklyGoalService;
    @Autowired PersonalCheckInRepository checkInRepository;
    @Autowired StreakRepository streakRepository;
    @Autowired UserRepository userRepository;
    @Autowired MutableClock clock;

    @MockBean AiVerificationClient aiVerificationClient;

    private static final AtomicInteger SEQ = new AtomicInteger();
    private static final double LAT = 37.5;
    private static final double LNG = 127.0;

    @BeforeEach
    void setUp() {
        clock.setDate(LocalDate.of(2035, 6, 4));
    }

    /** AI 인증 방식으로 설정된 사용자. */
    private Long newAiUser(VerificationType type) {
        String email = "pai-" + SEQ.incrementAndGet() + "@test.com";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        personalLocationService.register(userId, new LocationRequest(LAT, LNG, 100, "home"));
        weeklyGoalService.reserveTarget(userId, 3, type);
        return userId;
    }

    private MockMultipartFile photo() {
        return new MockMultipartFile("image", "run.jpg", "image/jpeg", new byte[]{1, 2, 3});
    }

    private void stubVerdict(boolean passed, String reason) {
        Mockito.when(aiVerificationClient.verify(anyString(), any(), anyString(), any()))
                .thenReturn(new AiServiceVerdict(passed, new BigDecimal("0.8700"),
                        List.of("러닝화", "야외"), "claude-haiku-4-5", reason, "exercise/x.jpg", null));
    }

    private int streakOf(Long userId) {
        return streakRepository.findById(userId).orElseThrow().getCurrentStreak();
    }

    // ────────────────────────── 체크인 단계 ──────────────────────────

    @Test
    @DisplayName("AI 목표: 체크인은 PENDING 으로 남고 checkInId 를 돌려준다")
    void aiGoal_checkInStaysPending() {
        Long userId = newAiUser(VerificationType.AI);

        CheckInResponse resp = personalCheckInService.checkIn(userId, LAT, LNG);

        assertThat(resp.status()).isEqualTo(PersonalCheckInStatus.PENDING);
        assertThat(resp.checkInId()).as("사진 업로드 2단계 호출의 입력").isNotNull();
        assertThat(streakOf(userId)).as("확정 전이므로 스트릭은 아직 안 오른다").isZero();
    }

    @Test
    @DisplayName("AI 목표: GPS 는 보지 않는다 — 반경 밖이어도 체크인이 만들어진다")
    void aiOnlyGoal_ignoresGps() {
        Long userId = newAiUser(VerificationType.AI);

        CheckInResponse resp = personalCheckInService.checkIn(userId, 38.5, 128.0);  // 한참 밖

        assertThat(resp.status()).isEqualTo(PersonalCheckInStatus.PENDING);
    }

    @Test
    @DisplayName("GPS+AI 목표: GPS 부터 통과해야 한다 — 반경 밖이면 400")
    void gpsAndAiGoal_rejectsOutOfRangeBeforePhoto() {
        Long userId = newAiUser(VerificationType.GPS_PHOTO_AI);

        assertThatThrownBy(() -> personalCheckInService.checkIn(userId, 38.5, 128.0))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("떨어져 있습니다");
    }

    @Test
    @DisplayName("PENDING 중에는 같은 날 다시 체크인할 수 없다")
    void pendingCheckIn_blocksDuplicate() {
        Long userId = newAiUser(VerificationType.AI);
        personalCheckInService.checkIn(userId, LAT, LNG);

        assertThatThrownBy(() -> personalCheckInService.checkIn(userId, LAT, LNG))
                .isInstanceOf(BusinessException.class);
    }

    // ────────────────────────── AI 판정 단계 ──────────────────────────

    @Test
    @DisplayName("AI 통과: 체크인이 확정되고 스트릭이 오른다")
    void aiPassed_confirmsCheckInAndRaisesStreak() {
        Long userId = newAiUser(VerificationType.AI);
        Long checkInId = personalCheckInService.checkIn(userId, LAT, LNG).checkInId();
        stubVerdict(true, "러닝화를 신고 야외에서 달리는 모습");

        PersonalAiVerificationResponse resp =
                aiVerificationService.verifyAndSave(userId, checkInId, "EXERCISE", photo());

        assertThat(resp.passed()).isTrue();
        assertThat(resp.currentStreak()).isEqualTo(1);
        assertThat(checkInRepository.findById(checkInId).orElseThrow().isSuccess()).isTrue();
        assertThat(streakOf(userId)).isEqualTo(1);
    }

    @Test
    @DisplayName("AI 거절: 사유를 돌려주고 그날을 '안 한 날'로 되돌려 재시도할 수 있게 한다")
    void aiRejected_returnsReasonAndAllowsRetry() {
        Long userId = newAiUser(VerificationType.AI);
        Long checkInId = personalCheckInService.checkIn(userId, LAT, LNG).checkInId();
        stubVerdict(false, "운동복만 입은 정지 셀카로 보입니다");

        PersonalAiVerificationResponse resp =
                aiVerificationService.verifyAndSave(userId, checkInId, "EXERCISE", photo());

        assertThat(resp.passed()).isFalse();
        assertThat(resp.reason()).contains("정지 셀카");
        assertThat(streakOf(userId)).as("거절이면 스트릭이 오르지 않는다").isZero();
        assertThat(checkInRepository.findById(checkInId))
                .as("PENDING 이 하루를 점유하지 않도록 제거된다").isEmpty();

        // 다시 시도할 수 있어야 한다
        assertThat(personalCheckInService.checkIn(userId, LAT, LNG).status())
                .isEqualTo(PersonalCheckInStatus.PENDING);
    }

    @Test
    @DisplayName("확정된 체크인에 사진을 다시 올릴 수 없다")
    void confirmedCheckIn_rejectsSecondPhoto() {
        Long userId = newAiUser(VerificationType.AI);
        Long checkInId = personalCheckInService.checkIn(userId, LAT, LNG).checkInId();
        stubVerdict(true, "ok");
        aiVerificationService.verifyAndSave(userId, checkInId, "EXERCISE", photo());

        assertThatThrownBy(() ->
                aiVerificationService.verifyAndSave(userId, checkInId, "EXERCISE", photo()))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    @DisplayName("남의 체크인에는 사진을 올릴 수 없다")
    void otherUsersCheckIn_isForbidden() {
        Long owner = newAiUser(VerificationType.AI);
        Long intruder = newAiUser(VerificationType.AI);
        Long checkInId = personalCheckInService.checkIn(owner, LAT, LNG).checkInId();

        assertThatThrownBy(() ->
                aiVerificationService.verifyAndSave(intruder, checkInId, "EXERCISE", photo()))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    @DisplayName("GPS 목표는 예전처럼 체크인 즉시 확정된다")
    void gpsGoal_confirmsImmediately() {
        Long userId = newAiUser(VerificationType.GPS);

        CheckInResponse resp = personalCheckInService.checkIn(userId, LAT, LNG);

        assertThat(resp.status()).isEqualTo(PersonalCheckInStatus.SUCCESS);
        assertThat(streakOf(userId)).isEqualTo(1);
    }
}
