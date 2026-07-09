package com.booster.challengecheckin.domain;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "challenge_check_ins")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
@AllArgsConstructor
public class ChallengeCheckIn {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "participant_id", nullable = false)
    private Long participantId;

    @Column(name = "challenge_id", nullable = false)
    private Long challengeId;

    @Column(name = "team_id")
    private Long teamId;

    @Column(name = "check_in_date", nullable = false)
    private LocalDate checkInDate;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private CheckInStatus status;

    @Column(name = "verified_at")
    private LocalDateTime verifiedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (updatedAt == null) updatedAt = LocalDateTime.now();
    }

    public void updateStatus(CheckInStatus status, LocalDateTime verifiedAt) {
        this.status = status;
        this.verifiedAt = verifiedAt;
    }
}
