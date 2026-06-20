package com.booster.auth.dto;

import com.booster.user.domain.User;

import java.time.OffsetDateTime;

public record SignupResponse(
        Long userId,
        String email,
        String nickname,
        long coinBalance,
        OffsetDateTime joinedAt
) {
    public static SignupResponse from(User user) {
        return new SignupResponse(
                user.getId(),
                user.getEmail(),
                user.getNickname(),
                user.getCoinBalance(),
                user.getJoinedAt());
    }
}
