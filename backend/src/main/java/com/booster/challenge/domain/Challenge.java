package com.booster.challenge.domain;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "challenges")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
@AllArgsConstructor
public class Challenge {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 50)
    private String category;

    @Column(nullable = false, length = 200)
    private String title;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(name = "verification_type", nullable = false, length = 20)
    private VerificationType verificationType;

    @Column(name = "duration_days", nullable = false)
    private int durationDays;

    @Column(name = "deposit_coins", nullable = false)
    private long depositCoins;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private ChallengeVisibility visibility;

    @Enumerated(EnumType.STRING)
    @Column(name = "approval_type", nullable = false, length = 20)
    private ApprovalType approvalType;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private ChallengeStatus status;

    @Column(name = "invite_code", unique = true, length = 20)
    private String inviteCode;

    @Column(name = "max_participants", nullable = false)
    private int maxParticipants;

    @Column(name = "started_at")
    private LocalDateTime startedAt;

    @Column(name = "ended_at")
    private LocalDateTime endedAt;

    @Column(name = "created_by", nullable = false)
    private Long createdBy;

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

    public void start(LocalDateTime startedAt, LocalDateTime endedAt) {
        this.status = ChallengeStatus.ACTIVE;
        this.startedAt = startedAt;
        this.endedAt = endedAt;
    }

    public void markEnded() {
        this.status = ChallengeStatus.ENDED;
    }

    public void setInviteCode(String inviteCode) {
        this.inviteCode = inviteCode;
    }
}
