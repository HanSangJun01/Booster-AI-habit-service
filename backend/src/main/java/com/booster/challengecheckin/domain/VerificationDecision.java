package com.booster.challengecheckin.domain;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "verification_decisions")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
@AllArgsConstructor
public class VerificationDecision {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "submission_id", nullable = false, unique = true)
    private Long submissionId;

    @Column(name = "final_passed")
    private Boolean finalPassed;

    @Column(name = "failure_reason", length = 200)
    private String failureReason;

    @Enumerated(EnumType.STRING)
    @Column(name = "decision_status", nullable = false, length = 20)
    private DecisionStatus decisionStatus;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (decisionStatus == null) decisionStatus = DecisionStatus.CONFIRMED;
    }

    public void confirm(Boolean finalPassed, String failureReason) {
        this.finalPassed = finalPassed;
        this.failureReason = failureReason;
        this.decisionStatus = DecisionStatus.CONFIRMED;
    }
}
