package com.booster.settlement.domain;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "settlements")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder
@AllArgsConstructor
public class Settlement {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "challenge_id", nullable = false, unique = true)
    private Long challengeId;

    @Column(name = "computed_at")
    private LocalDateTime computedAt;

    @Column(name = "total_pool", nullable = false)
    @Builder.Default
    private long totalPool = 0L;

    @Column(name = "per_winner_payout", nullable = false)
    @Builder.Default
    private long perWinnerPayout = 0L;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private SettlementStatus status;

    @Column(name = "winner_team_id")
    private Long winnerTeamId;

    @Column(name = "loser_team_id")
    private Long loserTeamId;

    @Column(nullable = false)
    @Builder.Default
    private boolean draw = false;

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

    public void complete(LocalDateTime computedAt, long totalPool, long perWinnerPayout,
                         Long winnerTeamId, Long loserTeamId, boolean draw) {
        this.computedAt = computedAt;
        this.totalPool = totalPool;
        this.perWinnerPayout = perWinnerPayout;
        this.winnerTeamId = winnerTeamId;
        this.loserTeamId = loserTeamId;
        this.draw = draw;
        this.status = SettlementStatus.COMPLETED;
    }

    public void fail() {
        this.status = SettlementStatus.FAILED;
    }
}
