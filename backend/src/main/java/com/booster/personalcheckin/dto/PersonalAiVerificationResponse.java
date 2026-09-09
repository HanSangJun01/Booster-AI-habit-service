package com.booster.personalcheckin.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/**
 * 개인 AI 사진 인증 결과.
 *
 * @param passed          AI 판정
 * @param reason          판단 근거(한국어). 거절 시 사용자에게 보여줄 값
 * @param currentStreak   통과했을 때만 채워진다(거절이면 null)
 * @param rewardGranted   이번 확정으로 마일스톤 보상이 지급됐는지
 */
public record PersonalAiVerificationResponse(
        LocalDate date,
        boolean passed,
        BigDecimal confidenceScore,
        List<String> detectedLabels,
        String reason,
        String modelName,
        Integer currentStreak,
        long coinBalance,
        boolean rewardGranted
) {
}
