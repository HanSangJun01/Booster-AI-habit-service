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

    /**
     * 취소했던 참가를 되살린다.
     *
     * <p>(challenge_id, user_id) 에 유니크 제약이 걸려 있어 새 행을 만들 수 없다. 그래서
     * 취소하면 CANCELLED 행이 남고, 예전에는 그 행 때문에 ALREADY_APPLIED 로 막혀
     * <b>한 번 취소하면 같은 방에 영영 다시 못 들어갔다.</b> 기존 행을 새 신청 내용으로
     * 덮어써서 재신청을 허용한다.
     *
     * <p>모집 중(READY)인 챌린지에서만 호출된다 — 체크인은 시작(ACTIVE) 이후에만
     * 생기므로 이 행에 딸린 체크인 기록이 남아 있을 수 없다.
     */
    public void rejoin(String personalStatement, Double gpsLat, Double gpsLng,
                       Integer gpsRadiusMeters, String gpsPlaceName, ParticipantStatus status) {
        this.personalStatement = personalStatement;
        this.gpsLat = gpsLat;
        this.gpsLng = gpsLng;
        this.gpsRadiusMeters = gpsRadiusMeters;
        this.gpsPlaceName = gpsPlaceName;
        this.gpsLocked = false;
        this.teamId = null;
        this.activeUntil = null;
        this.approvedAt = null;
        this.joinedAt = LocalDateTime.now();
        this.status = status;
    }
}
