package com.booster.recovery.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.OffsetDateTime;

/**
 * 복귀 미션. PersonalCheckIn(미인증일)과 1:1 (personal_check_in_id UNIQUE).
 * bs-25 Phase 3: deadlineAt 이내 GPS 인증 시 성공(-50, 스트릭 유지),
 * 초과 시 스케줄러가 실패 처리(-100, 스트릭 0).
 */
@Entity
@Table(name = "recovery_missions")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(access = AccessLevel.PRIVATE)
public class RecoveryMission {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "personal_check_in_id", nullable = false, unique = true)
    private Long personalCheckInId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "deadline_at", nullable = false)
    private OffsetDateTime deadlineAt;

    @Column(name = "completed_at")
    private OffsetDateTime completedAt;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private RecoveryStatus status;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    public static RecoveryMission createPending(Long userId, Long personalCheckInId,
                                                OffsetDateTime deadlineAt) {
        return RecoveryMission.builder()
                .userId(userId)
                .personalCheckInId(personalCheckInId)
                .deadlineAt(deadlineAt)
                .status(RecoveryStatus.PENDING)
                .build();
    }

    public void complete(OffsetDateTime completedAt) {
        this.status = RecoveryStatus.COMPLETED;
        this.completedAt = completedAt;
    }

    public void fail() {
        this.status = RecoveryStatus.FAILED;
    }

    public boolean isPending() {
        return this.status == RecoveryStatus.PENDING;
    }
}
