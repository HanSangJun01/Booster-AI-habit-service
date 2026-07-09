package com.booster.user.dto;

import com.booster.user.domain.User;

import java.time.OffsetDateTime;

public record MyPageResponse(
        Long userId,
        String email,
        String nickname,
        OffsetDateTime joinedAt,
        int totalAttendance,
        long coinBalance
) {
    public static MyPageResponse from(User user) {
        return new MyPageResponse(
                user.getId(),
                user.getEmail(),
                user.getNickname(),
                user.getJoinedAt(),
                user.getTotalAttendance(),
                user.getCoinBalance());
    }
}
