package com.booster.personalcheckin.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 개인 일일 인증 기록. bs-25: UNIQUE(user_id, date) — 사용자·날짜당 1건.
 * ★불변식: 이 테이블은 개인 스트릭/코인/복귀 흐름 전용. 챌린지(B축) 인증과 완전히 분리된다.
 */
@Entity
@Table(name = "personal_check_ins",
        uniqueConstraints = @UniqueConstraint(name = "uq_personal_check_in_user_date",
                columnNames = {"user_id", "check_in_date"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(access = AccessLevel.PRIVATE)
public class PersonalCheckIn {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "check_in_date", nullable = false)
    private LocalDate date;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private PersonalCheckInStatus status;

    @Column(name = "verified_at")
    private OffsetDateTime verifiedAt;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    public static PersonalCheckIn success(Long userId, LocalDate date, OffsetDateTime verifiedAt) {
        return PersonalCheckIn.builder()
                .userId(userId)
                .date(date)
                .status(PersonalCheckInStatus.SUCCESS)
                .verifiedAt(verifiedAt)
                .build();
    }

    /** 스케줄러: 미인증일을 복귀 대기 상태로 생성. */
    public static PersonalCheckIn recoveryPending(Long userId, LocalDate date) {
        return PersonalCheckIn.builder()
                .userId(userId)
                .date(date)
                .status(PersonalCheckInStatus.RECOVERY_PENDING)
                .build();
    }

    /** 복귀 미션 성공 시 미인증일 보정. */
    public void markSuccess(OffsetDateTime verifiedAt) {
        this.status = PersonalCheckInStatus.SUCCESS;
        this.verifiedAt = verifiedAt;
    }

    /** 복귀 미션 데드라인 초과 시 최종 실패. */
    public void markFailed() {
        this.status = PersonalCheckInStatus.FAILED;
    }

    public boolean isSuccess() {
        return this.status == PersonalCheckInStatus.SUCCESS;
    }
}
