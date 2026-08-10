package com.booster.personallocation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.OffsetDateTime;

/**
 * 개인 GPS 등록 위치 (사용자당 1개, user_id PK 공유).
 * bs-25 Principle 4: PersonalCheckIn 전용. ChallengeParticipant의 GPS와 무관(A축 독립).
 */
@Entity
@Table(name = "personal_locations")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class PersonalLocation {

    @Id
    @Column(name = "user_id")
    private Long userId;

    @Column(nullable = false)
    private double lat;

    @Column(nullable = false)
    private double lng;

    @Column(name = "radius_meters", nullable = false)
    private int radiusMeters;

    @Column(name = "place_name")
    private String placeName;

    /** 주간 목표(주당 인증 횟수, 2~7). 주간 채점의 기준값. */
    @Column(name = "weekly_target_days", nullable = false)
    private int weeklyTargetDays = 3;

    /**
     * 목표 변경 예약값. 즉시 반영하면 주 중간에 목표를 낮춰 그 주 채점을 통과할 수 있으므로,
     * 다음 주 월요일 채점 시점에 {@link #applyPendingTargetIfAny()} 로 승격한다.
     */
    @Column(name = "pending_target_days")
    private Integer pendingTargetDays;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    private PersonalLocation(Long userId, double lat, double lng, int radiusMeters, String placeName) {
        this.userId = userId;
        this.lat = lat;
        this.lng = lng;
        this.radiusMeters = radiusMeters;
        this.placeName = placeName;
    }

    public static PersonalLocation create(Long userId, double lat, double lng,
                                          int radiusMeters, String placeName) {
        return new PersonalLocation(userId, lat, lng, radiusMeters, placeName);
    }

    public void update(double lat, double lng, int radiusMeters, String placeName) {
        this.lat = lat;
        this.lng = lng;
        this.radiusMeters = radiusMeters;
        this.placeName = placeName;
    }

    /** 목표 변경 예약. 다음 주 월요일 채점 때 반영된다(진행 중인 주의 기준은 바뀌지 않는다). */
    public void reserveWeeklyTarget(int targetDays) {
        this.pendingTargetDays = targetDays;
    }

    /** 예약된 목표가 있으면 승격한다. 주간 채점 직후 호출. */
    public void applyPendingTargetIfAny() {
        if (this.pendingTargetDays != null) {
            this.weeklyTargetDays = this.pendingTargetDays;
            this.pendingTargetDays = null;
        }
    }
}
