package com.booster.challengecheckin.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public record AiVerificationResponse(
        Long aiResultId,
        Long submissionId,
        boolean passed,
        BigDecimal confidenceScore,
        List<String> detectedLabels,
        String reason,
        String modelName,
        String storageKey,
        LocalDateTime createdAt,
        Boolean finalPassed
) {
}
