package com.booster.participant.domain;

import com.booster.challenge.domain.Challenge;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "challenge_participants")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
@AllArgsConstructor
public class ChallengeParticipant {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "challenge_id", nullable = false)
    private Challenge challenge;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "team_id")
    private Long teamId;

    @Column(name = "personal_statement", columnDefinition = "TEXT")
    private String personalStatement;

    @Column(name = "gps_lat")
    private Double gpsLat;

    @Column(name = "gps_lng")
    private Double gpsLng;

    @Column(name = "gps_radius_meters")
    private Integer gpsRadiusMeters;

    @Column(name = "gps_place_name", length = 200)
    private String gpsPlaceName;

    @Column(name = "gps_locked", nullable = false)
    private boolean gpsLocked;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private ParticipantStatus status;

    @Column(name = "active_until")
    private LocalDateTime activeUntil;

    @Column(name = "joined_at", nullable = false, updatable = false)
    private LocalDateTime joinedAt;

    @Column(name = "approved_at")
    private LocalDateTime approvedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        if (joinedAt == null) joinedAt = LocalDateTime.now();
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (updatedAt == null) updatedAt = LocalDateTime.now();
    }

    public void confirm(LocalDateTime approvedAt) {
        this.status = ParticipantStatus.CONFIRMED;
        this.approvedAt = approvedAt;
    }

    public void reject() {
        this.status = ParticipantStatus.REJECTED;
    }

    public void cancel() {
        this.status = ParticipantStatus.CANCELLED;
    }

    public void markLeft(LocalDateTime activeUntil) {
        this.status = ParticipantStatus.LEFT;
        this.activeUntil = activeUntil;
    }

    public void assignTeam(Long teamId, LocalDateTime challengeEndedAt) {
        this.teamId = teamId;
        this.gpsLocked = true;
        this.activeUntil = challengeEndedAt;
    }
}
