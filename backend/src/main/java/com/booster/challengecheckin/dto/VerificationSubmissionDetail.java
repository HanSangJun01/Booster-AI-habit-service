package com.booster.challengecheckin.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/**
 * 인증 제출 1건의 상세 (MVP_API_SPEC §9.2).
 *
 * <p>제출 · GPS 판정 · AI 판정 · 최종 결정을 한 번에 묶어 준다. 인증이 왜 실패했는지 사용자에게
 * 설명하려면 이 조합이 필요하다 — GPS 반경을 벗어났는지, AI 가 거절했는지, 아직 AI 대기 중인지가
 * 각각 다른 테이블에 있기 때문이다.
 *
 * @param gps   verification_type 이 GPS 를 요구하지 않으면 null
 * @param ai    AI 판정 전이거나 AI 를 쓰지 않는 챌린지면 null
 */
public record VerificationSubmissionDetail(
        Long submissionId,
        Long checkInId,
        int attemptNumber,
        LocalDateTime submittedAt,
        Double submittedLat,
        Double submittedLng,
        GpsResult gps,
        AiResult ai,
        Decision decision
) {
    public record GpsResult(
            Double targetLat,
            Double targetLng,
            int radiusMeters,
            BigDecimal distanceMeters,
            boolean withinRadius
    ) {
    }

    public record AiResult(
            boolean passed,
            BigDecimal confidenceScore,
            List<String> detectedLabels,
            String reason,
            String modelName,
            String storageKey
    ) {
    }

    /**
     * @param decisionStatus PENDING(AI 대기) / CONFIRMED(확정)
     * @param finalPassed    PENDING 이면 null
     * @param failureReason  GPS_OUT_OF_RADIUS / AI_REJECTED 등
     */
    public record Decision(
            String decisionStatus,
            Boolean finalPassed,
            String failureReason
    ) {
    }
}
