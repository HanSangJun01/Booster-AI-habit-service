package com.booster.concurrency;

import com.booster.auth.dto.SignupRequest;
import com.booster.shared.common.BusinessException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [BS-30 7차 F4] 동일 이메일 동시 가입.
 *
 * <p>{@code AuthService.signup} 은 {@code existsByEmail} 선검사 후 {@code save} 한다. 동시 2건이
 * 선검사를 모두 통과하면 두 번째 save 가 email UNIQUE 를 위반 → 원시
 * {@code DataIntegrityViolationException}(→500) 으로 누출됐다. 수정 후에는 실패한 쪽이
 * {@code BusinessException(DUPLICATE_EMAIL, 409)} 로 변환되어야 한다.
 */
class F4ConcurrentSignupTest extends ConcurrencyTestBase {

    @Test
    @DisplayName("동시 동일이메일 가입: 정확히 1건 성공, 실패측은 DUPLICATE_EMAIL(409)")
    void concurrentSameEmailSignup_conflictMustBeBusinessException() throws Exception {
        String email = "dupF4-" + SEQ.incrementAndGet() + "-" + System.nanoTime() + "@ct.test";

        List<Throwable> errors = runConcurrently(List.of(
                () -> authService.signup(new SignupRequest(email, "password1234", "u")),
                () -> authService.signup(new SignupRequest(email, "password1234", "u"))));

        // 이메일 UNIQUE 상, 정확히 1명만 생성되어야 한다.
        assertThat(userRepository.findByEmail(email))
                .as("동시 가입 후 해당 이메일 유저는 정확히 1명")
                .isPresent();

        // 실패한 쪽(정확히 1건)의 예외는 원시 예외가 아니라 BusinessException(DUPLICATE_EMAIL) 이어야 한다.
        assertThat(errors)
                .as("동시 가입 중 정확히 1건은 중복으로 거부되어야 한다")
                .hasSize(1);
        for (Throwable e : errors) {
            Throwable cause = rootBusinessCause(e);
            assertThat(cause)
                    .as("중복 가입 충돌은 BusinessException 으로 변환되어야 한다. 원시 누출=%s",
                            e.getClass().getName())
                    .isInstanceOf(BusinessException.class);
            assertThat(((BusinessException) cause).getCode()).isEqualTo("DUPLICATE_EMAIL");
        }
    }
}
