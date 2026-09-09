package com.booster.auth.dto;

import com.booster.user.domain.User;

import java.time.OffsetDateTime;

/**
 * 가입 응답.
 *
 * <p>{@code accessToken} 을 함께 내려준다. 이게 없던 시절 클라이언트는 가입 직후 같은 자격증명으로
 * 로그인을 한 번 더 호출해야 했고, 그 결과 <b>BCrypt 해싱이 가입·로그인 두 번</b> 돌아 체감 지연이
 * 두 배가 됐다(BCrypt 는 BS-30 부하 측정에서 최대 병목으로 확인된 연산이다).
 */
public record SignupResponse(
        Long userId,
        String email,
        String nickname,
        long coinBalance,
        OffsetDateTime joinedAt,
        String accessToken
) {
    public static SignupResponse from(User user, String accessToken) {
        return new SignupResponse(
                user.getId(),
                user.getEmail(),
                user.getNickname(),
                user.getCoinBalance(),
                user.getJoinedAt(),
                accessToken);
    }
}
