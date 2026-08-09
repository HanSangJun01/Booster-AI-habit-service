package com.booster.challengecheckin.domain;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "ai_verification_results")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
@AllArgsConstructor
public class AiVerificationResult {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "submission_id", nullable = false, unique = true)
    private Long submissionId;

    @Column(name = "model_name", nullable = false, length = 100)
    private String modelName;

    @Column(name = "is_passed", nullable = false)
    private boolean isPassed;

    @Column(name = "confidence_score", nullable = false, precision = 5, scale = 4)
    private BigDecimal confidenceScore;

    @Column(name = "detected_labels", nullable = false, columnDefinition = "TEXT")
    private String detectedLabels;

    @Column(name = "reason", length = 500)
    private String reason;

    @Column(name = "storage_key", nullable = false, length = 500)
    private String storageKey;

    @Column(name = "raw_response", columnDefinition = "TEXT")
    private String rawResponse;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
