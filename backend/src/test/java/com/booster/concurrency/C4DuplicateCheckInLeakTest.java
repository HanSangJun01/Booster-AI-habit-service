package com.booster.concurrency;

import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.shared.common.BusinessException;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [C4] 첫 인증 동시요청 시 UNIQUE 위반이 409가 아닌 예외로 누출.
 *
 * <p>당일 첫 {@code checkIn} 동시 2건 → 둘 다 {@code existing == null} 판정 → 둘 다 INSERT →
 * 두 번째가 {@code uq_personal_check_in_user_date} 위반 → 스프링이 {@code DataIntegrityViolationException}
 * 으로 변환해 던진다(= {@code BusinessException} 아님). GlobalExceptionHandler 의 일반 핸들러가
 * 잡아 HTTP 500/INTERNAL_ERROR 로 나간다.
 *
 * <p>올바른 동작: 실패한 쪽은 "오늘 이미 인증" 충돌이므로 {@code BusinessException(code=DUPLICATE_CHECK_IN, 409)}
 * 로 변환되어야 한다. 동시 인터리빙은 비결정적이므로 신규 유저로 다수 라운드를 돌려, 한 번이라도
 * 원시 {@code DataIntegrityViolationException} 이 누출되면 RED.
 */
@Import(TestClockConfig.class)
class C4DuplicateCheckInLeakTest extends ConcurrencyTestBase {

    @Autowired MutableClock clock;

    @Test
    @DisplayName("동시 첫 체크인 충돌은 BusinessException(DUPLICATE_CHECK_IN, 409)로 변환되어야 한다")
    void concurrentFirstCheckIn_conflictMustBeBusinessException() throws Exception {
        clock.setDate(LocalDate.of(2035, 6, 11));

        int iterations = 25;
        for (int i = 0; i < iterations; i++) {
            Long userId = newUserWithLocation("c4-");

            List<Throwable> errors = runConcurrently(List.of(
                    () -> personalCheckInService.checkIn(userId, LAT, LNG),
                    () -> personalCheckInService.checkIn(userId, LAT, LNG)));

            // DB UNIQUE 제약상 SUCCESS 레코드는 1건만 존재해야 한다(정합성).
            List<PersonalCheckIn> rows = personalCheckInRepository
                    .findByUserIdAndDateBetween(userId, LocalDate.of(2035, 6, 11), LocalDate.of(2035, 6, 11));
            assertThat(rows)
                    .as("iteration %d: 동시 첫 체크인 후 당일 레코드는 1건이어야 한다", i)
                    .hasSize(1);

            // 충돌로 실패한 쪽의 예외는 반드시 BusinessException(409) 여야 한다.
            for (Throwable e : errors) {
                Throwable cause = rootBusinessCause(e);
                assertThat(cause)
                        .as("iteration %d: 동시 체크인 충돌은 BusinessException 으로 변환되어야 한다. "
                                + "원시 예외 누출=%s", i, e.getClass().getName())
                        .isInstanceOf(BusinessException.class);
                assertThat(((BusinessException) cause).getCode())
                        .as("iteration %d: 충돌 코드는 DUPLICATE_CHECK_IN(409) 이어야 한다", i)
                        .isEqualTo("DUPLICATE_CHECK_IN");
            }
        }
    }
}
