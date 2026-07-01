package com.booster.recovery;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.domain.PersonalCheckInStatus;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personalcheckin.dto.CheckInResponse;
import com.booster.personalcheckin.service.PersonalCheckInService;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.service.PersonalLocationService;
import com.booster.recovery.domain.RecoveryMission;
import com.booster.recovery.repository.RecoveryMissionRepository;
import com.booster.recovery.service.RecoveryService;
import com.booster.shared.common.BusinessException;
import com.booster.streak.repository.StreakRepository;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
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

/**
 * [BS-30 시나리오 고정]
 * - B2: 가입일 off-by-one — 가입일==어제 유저에게 부당하게 복귀 미션 생성.
 * - F2(팀 결정): 복귀 = 그날 인증으로 완전 간주(복귀일 SUCCESS 레코드 생성 + 스트릭 +1),
 *   복귀 대상일의 별도 일반 인증은 불가. 무한 복귀 루프/순서 의존(F7) 없음.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
@Transactional
class RecoveryScenarioBugTest {

    @Autowired AuthService authService;
    @Autowired PersonalLocationService personalLocationService;
    @Autowired RecoveryService recoveryService;
    @Autowired PersonalCheckInService personalCheckInService;
    @Autowired PersonalCheckInRepository personalCheckInRepository;
    @Autowired RecoveryMissionRepository recoveryMissionRepository;
    @Autowired StreakRepository streakRepository;
    @Autowired MutableClock clock;
    @PersistenceContext EntityManager em;

    private static final AtomicInteger SEQ = new AtomicInteger();

    private Long newUserWithLocation(String prefix) {
        String email = prefix + SEQ.incrementAndGet() + "@test.com";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        personalLocationService.register(userId, new LocationRequest(37.0, 127.0, 100, "home"));
        return userId;
    }

    /**
     * joinedAt은 @CreationTimestamp라 실제 벽시계(약 2026)로 박힌다. 테스트 clock(2035)에선
     * 항상 "과거 가입"이라 off-by-one을 재현할 수 없으므로, 네이티브 UPDATE로 가입일을
     * 지정 날짜(KST 정오)로 강제 세팅한 뒤 영속성 컨텍스트를 비워 재조회되게 한다.
     */
    private void forceJoinedAt(Long userId, LocalDate date) {
        OffsetDateTime ts = date.atTime(12, 0).atZone(MutableClock.KST).toOffsetDateTime();
        em.flush();
        em.createNativeQuery("UPDATE users SET joined_at = :ts WHERE id = :id")
                .setParameter("ts", ts)
                .setParameter("id", userId)
                .executeUpdate();
        em.clear();
    }

    /**
     * [B2] 가입일 == 어제 인 유저가 어제 미인증인 상태.
     * 명세: "어제 이전 가입자만 대상, 가입일 당일 미인증은 책임 없음".
     * 기대: generatePendingForYesterday() 호출 시 이 유저에겐 RECOVERY_PENDING이 생성되지 않아야 한다.
     * 현재: isAfter(yesterday)만 스킵 → 가입일==어제 유저는 스킵 안 됨 → 복귀미션+페널티 생성 (RED).
     */
    @Test
    void joinedYesterday_shouldNotGetRecoveryPending() {
        Long userId = newUserWithLocation("b2-");
        LocalDate today = LocalDate.of(2035, 6, 11); // TestClockConfig 기본값
        LocalDate yesterday = today.minusDays(1);
        clock.setDate(today);

        forceJoinedAt(userId, yesterday); // 가입일을 '어제'로 강제

        recoveryService.generatePendingForYesterday();

        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, yesterday))
                .as("가입일 당일(=어제) 미인증은 책임 대상이 아니므로 복귀 미션이 생성되면 안 된다")
                .isEmpty();
    }

    /**
     * [F2 — 팀 결정: 복귀 당일 일반 인증 불가 / 복귀 = 그날 인증으로 완전 간주]
     * 복귀 수행 시: (1) 미인증일 SUCCESS 보정, (2) 복귀일(오늘)도 SUCCESS 레코드 생성(그날 인증 간주),
     * (3) 복귀일의 별도 일반 인증은 차단된다.
     */
    @Test
    void recovery_countsAsTodayCheckIn_andBlocksSeparateCheckIn() {
        Long userId = newUserWithLocation("f2-");
        LocalDate day = LocalDate.of(2035, 7, 10); // 복귀 수행일 D
        LocalDate missed = day.minusDays(1);       // D-1 미인증

        clock.setDate(day);
        PersonalCheckIn pending = personalCheckInRepository.save(
                PersonalCheckIn.recoveryPending(userId, missed));
        OffsetDateTime deadline = day.atTime(23, 59, 59).atZone(MutableClock.KST).toOffsetDateTime();
        em.persist(RecoveryMission.createPending(userId, pending.getId(), deadline));
        em.flush();

        recoveryService.performRecovery(userId, 37.0, 127.0);

        // (1) 미인증일(D-1)은 SUCCESS로 보정
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, missed).orElseThrow().getStatus())
                .isEqualTo(PersonalCheckInStatus.SUCCESS);
        // (2) 복귀일(D)도 SUCCESS 레코드로 남는다(그날 인증으로 간주)
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, day).orElseThrow().getStatus())
                .as("복귀는 복귀일(D)의 인증으로 간주되어 D 레코드가 SUCCESS여야 한다")
                .isEqualTo(PersonalCheckInStatus.SUCCESS);
        // (3) 복귀일의 별도 일반 인증은 차단
        assertThatThrownBy(() -> personalCheckInService.checkIn(userId, 37.0, 127.0))
                .as("복귀 대상일에는 별도 일반 인증이 불가해야 한다")
                .isInstanceOf(BusinessException.class)
                .satisfies(e -> assertThat(((BusinessException) e).getCode()).isEqualTo("RECOVERY_DAY_NO_CHECKIN"));
    }

    /**
     * [F2/F7] 복귀가 복귀일을 '인증'으로 닫으므로, 그날이 다음날 다시 미인증으로 잡히는
     * 무한 복귀 루프가 없고, 복귀일 스트릭이 정상 연속으로 이어진다.
     * D1~D6 인증(streak 6) → D7 미인증 → D8 복귀(D7 보정 + D8 인증 간주, streak 7) →
     * D9 스케줄러는 D8을 미인증으로 잡지 않음 → D9 일반 인증 정상(streak 8).
     */
    @Test
    void recoveryClosesRecoveryDay_noInfiniteChain_streakContinues() {
        Long userId = newUserWithLocation("f7-");
        LocalDate d1 = LocalDate.of(2035, 3, 1);

        for (int i = 0; i < 6; i++) { // D1~D6 → streak 6
            clock.setDate(d1.plusDays(i));
            personalCheckInService.checkIn(userId, 37.0, 127.0);
        }

        // D7 미인증. D8: 스케줄러가 D7 복귀 미션 생성 → D8 복귀 수행
        LocalDate d8 = d1.plusDays(7);
        clock.setDate(d8);
        recoveryService.generatePendingForYesterday();
        recoveryService.performRecovery(userId, 37.0, 127.0);

        // 복귀일 D8은 SUCCESS로 닫히고 streak는 7로 이어진다
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, d8).orElseThrow().getStatus())
                .isEqualTo(PersonalCheckInStatus.SUCCESS);
        assertThat(streakRepository.findById(userId).orElseThrow().getCurrentStreak()).isEqualTo(7);

        // D9: 스케줄러가 D8을 미인증으로 잡지 않아야 한다(무한 루프 없음) → D8 PENDING 미션 없음
        LocalDate d9 = d1.plusDays(8);
        clock.setDate(d9);
        recoveryService.generatePendingForYesterday();
        assertThat(recoveryMissionRepository.findFirstByUserIdAndStatusOrderByDeadlineAtAsc(
                userId, com.booster.recovery.domain.RecoveryStatus.PENDING))
                .as("복귀로 닫힌 D8은 다시 미인증 복귀 대상이 되면 안 된다")
                .isEmpty();

        // D9 일반 인증은 정상 허용되고 streak가 8로 이어진다
        CheckInResponse d9resp = personalCheckInService.checkIn(userId, 37.0, 127.0);
        assertThat(d9resp.status()).isEqualTo(PersonalCheckInStatus.SUCCESS);
        assertThat(d9resp.currentStreak()).isEqualTo(8);
    }
}
