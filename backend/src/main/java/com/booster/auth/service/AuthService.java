package com.booster.auth.service;

import com.booster.auth.dto.LoginRequest;
import com.booster.auth.dto.LoginResponse;
import com.booster.auth.dto.SignupRequest;
import com.booster.auth.dto.SignupResponse;
import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import com.booster.shared.common.BusinessException;
import com.booster.shared.security.JwtTokenProvider;
import com.booster.streak.domain.Streak;
import com.booster.streak.repository.StreakRepository;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final StreakRepository streakRepository;
    private final CoinService coinService;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider jwtTokenProvider;

    @Value("${booster.coin.signup-bonus}")
    private long signupBonus;

    /** 회원가입 → 가입 보너스 코인 지급 + Streak 초기화. */
    @Transactional
    public SignupResponse signup(SignupRequest request) {
        if (userRepository.existsByEmail(request.email())) {
            throw BusinessException.conflict("DUPLICATE_EMAIL", "이미 사용 중인 이메일입니다.");
        }

        // (BS-30 7차 F4) 동시 가입으로 위 존재검사를 둘 다 통과하면 두 번째 save가 email UNIQUE를
        // 위반한다. IDENTITY라 save()에서 즉시 INSERT되어 여기서 잡히므로 500이 아닌 409로 변환.
        User user;
        try {
            user = userRepository.save(User.create(
                    request.email(),
                    passwordEncoder.encode(request.password()),
                    request.nickname()));
        } catch (DataIntegrityViolationException e) {
            throw BusinessException.conflict("DUPLICATE_EMAIL", "이미 사용 중인 이메일입니다.");
        }

        streakRepository.save(Streak.init(user.getId()));
        coinService.grant(user.getId(), signupBonus, CoinTransactionReason.SIGNUP_BONUS, null);

        return SignupResponse.from(user);
    }

    /** 로그인 → JWT Access Token 발급. */
    @Transactional(readOnly = true)
    public LoginResponse login(LoginRequest request) {
        User user = userRepository.findByEmail(request.email())
                .orElseThrow(() -> BusinessException.unauthorized(
                        "INVALID_CREDENTIALS", "이메일 또는 비밀번호가 올바르지 않습니다."));

        // (BS-30 7차 F5) 비밀번호를 먼저 검증한다. active 검사를 앞에 두면 비번 없이도
        // 계정 비활성 여부(존재/탈퇴)를 식별할 수 있어 계정 열거에 악용될 수 있다.
        if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw BusinessException.unauthorized(
                    "INVALID_CREDENTIALS", "이메일 또는 비밀번호가 올바르지 않습니다.");
        }

        if (!user.isActive()) {
            throw BusinessException.unauthorized("INACTIVE_ACCOUNT", "비활성화된 계정입니다.");
        }

        String accessToken = jwtTokenProvider.createAccessToken(user.getId());
        return new LoginResponse(user.getId(), user.getEmail(), user.getNickname(), accessToken);
    }
}
