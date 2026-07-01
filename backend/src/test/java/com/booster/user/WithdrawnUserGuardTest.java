package com.booster.user;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personalcheckin.service.PersonalCheckInService;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.service.PersonalLocationService;
import com.booster.recovery.domain.RecoveryMission;
import com.booster.recovery.repository.RecoveryMissionRepository;
import com.booster.recovery.service.RecoveryService;
import com.booster.shared.common.BusinessException;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
import com.booster.user.service.UserService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * [BS-30 버그 고정] B3 — 탈퇴(soft delete) 후 활성 가드 누락.
 *
 * 근거: UserService.withdraw는 active=false로만 만든다. 그러나
 * PersonalCheckInService.checkIn / RecoveryService.performRecovery 어디에도 active 검사가 없다
 * (UserRepository.existsByIdAndActiveTrue는 선언만 되고 미사용). → 탈퇴 유저가 그대로 인증/복귀 가능.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
@Transactional
class WithdrawnUserGuardTest {

    @Autowired AuthService authService;
    @Autowired UserService userService;
    @Autowired PersonalLocationService personalLocationService;
    @Autowired PersonalCheckInService personalCheckInService;
    @Autowired RecoveryService recoveryService;
    @Autowired PersonalCheckInRepository personalCheckInRepository;
    @Autowired RecoveryMissionRepository recoveryMissionRepository;
    @Autowired MutableClock clock;

    private static final AtomicInteger SEQ = new AtomicInteger();

    private Long newUserWithLocation() {
        String email = "b3-" + SEQ.incrementAndGet() + "@test.com";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        personalLocationService.register(userId, new LocationRequest(37.0, 127.0, 100, "home"));
        return userId;
    }

    /**
     * [B3] 유저 탈퇴 후 같은 유저로 checkIn 시도.
     * 기대: 비활성 계정이므로 BusinessException으로 거부되어야 한다.
     * 현재: active 검사가 없어 정상 인증 성공 → 예외 미발생 (RED).
     */
    @Test
    void withdrawnUser_cannotCheckIn() {
        Long userId = newUserWithLocation();
        clock.setDate(LocalDate.of(2035, 5, 2));

        userService.withdraw(userId);

        assertThatThrownBy(() -> personalCheckInService.checkIn(userId, 37.0, 127.0))
                .as("탈퇴(비활성) 계정의 출석 인증은 거부되어야 한다")
                .isInstanceOf(BusinessException.class);
    }

    /**
     * [BS-30 F11] 탈퇴 유저가 코인 내역 조회 시도 → 거부되어야 한다(마이페이지와 동일 가드).
     */
    @Test
    void withdrawnUser_cannotReadCoinHistory() {
        Long userId = newUserWithLocation();
        userService.withdraw(userId);

        assertThatThrownBy(() -> userService.getCoinHistory(
                userId, org.springframework.data.domain.PageRequest.of(0, 20)))
                .as("탈퇴 계정의 코인 내역 조회는 거부되어야 한다")
                .isInstanceOf(BusinessException.class);
    }

    /**
     * [BS-30 7차 F3] 탈퇴 유저가 위치 수정 시도 → 거부되어야 한다.
     */
    @Test
    void withdrawnUser_cannotUpdateLocation() {
        Long userId = newUserWithLocation();
        userService.withdraw(userId);

        assertThatThrownBy(() -> personalLocationService.update(
                userId, new LocationRequest(37.0, 127.0, 100, "x")))
                .as("탈퇴 계정의 위치 수정은 거부되어야 한다")
                .isInstanceOf(BusinessException.class);
    }

    /**
     * [BS-30 7차 F3] 탈퇴 유저가 위치 최초 등록 시도 → 거부되어야 한다.
     */
    @Test
    void withdrawnUser_cannotRegisterLocation() {
        String email = "b3reg-" + SEQ.incrementAndGet() + "@test.com";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        userService.withdraw(userId);

        assertThatThrownBy(() -> personalLocationService.register(
                userId, new LocationRequest(37.0, 127.0, 100, "home")))
                .as("탈퇴 계정의 위치 등록은 거부되어야 한다")
                .isInstanceOf(BusinessException.class);
    }

    /**
     * [B3] 복귀 미션 보유 유저가 탈퇴 후 performRecovery 시도.
     * 기대: 비활성 계정이므로 BusinessException으로 거부되어야 한다.
     * 현재: active 검사가 없어 복귀가 정상 수행됨 → 예외 미발생 (RED).
     */
    @Test
    void withdrawnUser_cannotPerformRecovery() {
        Long userId = newUserWithLocation();
        LocalDate today = LocalDate.of(2035, 5, 10);
        clock.setDate(today);

        // 대기 중 복귀 미션 세팅
        PersonalCheckIn pending = personalCheckInRepository.save(
                PersonalCheckIn.recoveryPending(userId, today.minusDays(1)));
        OffsetDateTime deadline = today.atTime(23, 59, 59).atZone(MutableClock.KST).toOffsetDateTime();
        recoveryMissionRepository.save(
                RecoveryMission.createPending(userId, pending.getId(), deadline));

        userService.withdraw(userId);

        assertThatThrownBy(() -> recoveryService.performRecovery(userId, 37.0, 127.0))
                .as("탈퇴(비활성) 계정의 복귀 미션 수행은 거부되어야 한다")
                .isInstanceOf(BusinessException.class);
    }
}
