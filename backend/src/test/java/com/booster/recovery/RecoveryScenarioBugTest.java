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
import com.booster.recovery.service.RecoveryService;
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

/**
 * [BS-30 시나리오 고정]
 * - B2 (RED): 가입일 off-by-one — 가입일==어제 유저에게 부당하게 복귀 미션 생성.
 * - B4 (GREEN, 재분류): 복귀는 오늘 레코드를 만들지 않고 오늘 일반 인증은 허용 — A축 계획서 Phase 3 명세상 의도된 동작.
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
     * [B4 — 재분류: 명세상 의도된 동작 / GREEN 특성화 테스트]
     *
     * A축 계획서 Phase 3 명시:
     *   "복귀가 오늘 날짜의 PersonalCheckIn을 생성하지는 않으므로 이중 카운트 없음" +
     *   "복귀 수행일(today) PersonalCheckIn이 없어도 오늘의 일반 인증은 허용".
     *
     * 따라서 복귀 수행 시:
     *   (1) 미인증일(missed)만 SUCCESS로 보정한다.
     *   (2) 오늘(D)에 대한 PersonalCheckIn은 만들지 않는다(이중 카운트 방지).
     *   (3) 오늘(D)의 일반 인증은 여전히 허용되어 D 레코드를 SUCCESS로 만든다.
     *
     * 이 테스트는 그 '의도된 동작'을 고정한다(GREEN).
     * (이전엔 "복귀=오늘출석"으로 오판하여 RED 테스트를 두었으나, Phase 3 명세 확인 후 정정.
     *  "복귀만 반복 시 매일 -50" 현상은 유저가 오늘 일반 인증을 하지 않은 결과로, 명세상 의도이며 버그 아님.)
     */
    @Test
    void recovery_doesNotCreateTodayRecord_butNormalCheckInStillAllowed() {
        Long userId = newUserWithLocation("b4-");
        LocalDate day = LocalDate.of(2035, 7, 10); // 복귀 수행일 D
        LocalDate missed = day.minusDays(1);       // D-1 미인증

        clock.setDate(day);

        // D-1 미인증에 대한 복귀 미션(pending) 세팅
        PersonalCheckIn pending = personalCheckInRepository.save(
                PersonalCheckIn.recoveryPending(userId, missed));
        OffsetDateTime deadline = day.atTime(23, 59, 59).atZone(MutableClock.KST).toOffsetDateTime();
        em.persist(RecoveryMission.createPending(userId, pending.getId(), deadline));
        em.flush();

        // D일에 복귀 수행
        recoveryService.performRecovery(userId, 37.0, 127.0);

        // (1) 미인증일(D-1)은 SUCCESS로 보정됨
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, missed).orElseThrow().getStatus())
                .as("복귀 성공 시 미인증일은 SUCCESS로 보정되어야 한다")
                .isEqualTo(PersonalCheckInStatus.SUCCESS);

        // (2) 오늘(D) 레코드는 생성되지 않음 (이중 카운트 방지 — 명세대로)
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, day))
                .as("복귀는 오늘(D) PersonalCheckIn을 생성하지 않는다 (Phase 3 명세)")
                .isEmpty();

        // (3) 오늘(D)의 일반 인증은 여전히 허용되어 D 레코드를 SUCCESS로 만든다
        CheckInResponse resp = personalCheckInService.checkIn(userId, 37.0, 127.0);
        assertThat(resp.status())
                .as("복귀를 했어도 오늘의 일반 인증은 허용되어야 한다 (Phase 3 명세)")
                .isEqualTo(PersonalCheckInStatus.SUCCESS);
        assertThat(personalCheckInRepository.findByUserIdAndDate(userId, day))
                .as("오늘 일반 인증 후에는 D 레코드가 SUCCESS로 존재해야 한다")
                .isPresent();
    }
}
