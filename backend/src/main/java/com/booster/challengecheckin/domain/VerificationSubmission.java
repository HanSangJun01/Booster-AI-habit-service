package com.booster.challengecheckin.domain;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "verification_submissions")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
@AllArgsConstructor
public class VerificationSubmission {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "check_in_id", nullable = false)
    private Long checkInId;

    @Column(name = "submitted_at", nullable = false)
    private LocalDateTime submittedAt;

    @Column(name = "submitted_lat", nullable = false)
    private Double submittedLat;

    @Column(name = "submitted_lng", nullable = false)
    private Double submittedLng;

    @Column(name = "attempt_number", nullable = false)
    private int attemptNumber;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (submittedAt == null) submittedAt = LocalDateTime.now();
    }
}
