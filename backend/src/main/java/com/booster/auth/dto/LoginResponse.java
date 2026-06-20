package com.booster.auth.dto;

public record LoginResponse(
        Long userId,
        String email,
        String nickname,
        String accessToken
) {
}
