package com.booster.personalcheckin.dto;

import com.booster.personalcheckin.domain.PersonalCheckInStatus;

import java.time.LocalDate;
import java.time.OffsetDateTime;

public record CheckInResponse(
        LocalDate date,
        PersonalCheckInStatus status,
        OffsetDateTime verifiedAt,
        int currentStreak,
        int maxStreak,
        long coinBalance,
        boolean rewardGranted,

        /**
         * 이번 체크인의 id. AI 를 쓰는 목표에서 사진 업로드 2단계 호출
         * ({@code POST /api/personal/check-in/{checkInId}/ai-verification})의 입력이다.
         * 팀 챌린지의 submissionId 와 같은 역할.
         */
        Long checkInId
) {
}
