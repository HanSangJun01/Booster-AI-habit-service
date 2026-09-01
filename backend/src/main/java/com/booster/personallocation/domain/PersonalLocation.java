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
import com.booster.challenge.domain.VerificationType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.EnumType;

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

    /**
     * 인증 방식. 팀 챌린지의 {@code challenges.verification_type} 과 같은 의미다.
     *   GPS          위치만 — 체크인 즉시 확정
     *   AI           사진만 — 체크인은 PENDING, 사진 업로드로 확정
     *   GPS_PHOTO_AI 위치 통과 후 사진까지 — GPS 실패는 400 즉시 거절
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "verification_type", nullable = false, length = 20)
    private VerificationType verificationType = VerificationType.GPS;

    /**
     * 개인 목표 카테고리(EXERCISE/STUDY). AI 사진 판정의 기준이 된다.
     *
     * <p>목표 횟수·장소와 달리 즉시 반영한다 — 바꿔도 이번 주 채점 기준이나 인증 위치가
     * 흔들리지 않아 늦출 이유가 없다.
     */
    @Column(name = "category", nullable = false, length = 20)
    private String category = "EXERCISE";

    /** 주간 목표(주당 인증 횟수, 2~7). 주간 채점의 기준값. */
    @Column(name = "weekly_target_days", nullable = false)
    private int weeklyTargetDays = 3;

    /**
     * 목표 변경 예약값. 즉시 반영하면 주 중간에 목표를 낮춰 그 주 채점을 통과할 수 있으므로,
     * 다음 주 월요일 채점 시점에 {@link #applyPendingTargetIfAny()} 로 승격한다.
     */
    @Column(name = "pending_target_days")
    private Integer pendingTargetDays;

    /**
     * 인증 장소 변경 예약값. 네 개가 한 벌로 채워지거나 한 벌로 비어 있다(DB CHECK 로도 강제).
     *
     * <p>즉시 반영하면 인증 직전에 지금 있는 자리로 장소를 옮겨 어디서든 통과할 수 있다.
     * 목표 횟수와 같은 시점(다음 달 1일)에 {@link #applyPendingChangesIfAny()} 로 승격한다 —
     * "이번 달의 목표와 장소"가 한 세트로 움직인다.
     */
    @Column(name = "pending_lat")
    private Double pendingLat;

    @Column(name = "pending_lng")
    private Double pendingLng;

    @Column(name = "pending_radius_meters")
    private Integer pendingRadiusMeters;

    @Column(name = "pending_place_name")
    private String pendingPlaceName;

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

    /** 인증 방식 변경. 목표 횟수와 달리 즉시 반영한다(채점 기준이 아니라 인증 절차만 바뀐다). */
    public void changeVerificationType(VerificationType verificationType) {
        this.verificationType = verificationType;
    }

    /** 목표 카테고리 변경(EXERCISE/STUDY). 즉시 반영한다. */
    public void changeCategory(String category) {
        this.category = category;
    }

    public boolean needsGps() {
        return verificationType == VerificationType.GPS
                || verificationType == VerificationType.GPS_PHOTO_AI;
    }

    public boolean needsAi() {
        return verificationType == VerificationType.AI
                || verificationType == VerificationType.GPS_PHOTO_AI;
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

    /**
     * 인증 장소 변경 예약. 다음 달 1일부터 반영된다.
     *
     * <p>바로 바꿔 주면 인증 직전에 현재 위치로 옮겨 어디서든 통과할 수 있어서, 위치 인증이
     * 의미를 잃는다. 이사처럼 진짜 옮겨야 하는 경우는 한 달 안에 예정할 수 있으므로 예약제로 둔다.
     */
    public void reserveLocation(double lat, double lng, int radiusMeters, String placeName) {
        this.pendingLat = lat;
        this.pendingLng = lng;
        this.pendingRadiusMeters = radiusMeters;
        this.pendingPlaceName = placeName;
    }

    /** 변경 예약을 취소한다(다시 지금 장소로 두고 싶을 때). */
    public void cancelLocationReservation() {
        this.pendingLat = null;
        this.pendingLng = null;
        this.pendingRadiusMeters = null;
        this.pendingPlaceName = null;
    }

    public boolean hasPendingLocation() {
        return pendingLat != null && pendingLng != null && pendingRadiusMeters != null;
    }

    /**
     * 예약된 목표·장소를 승격한다. 월초(무료 구제권 지급 시점)에 한 번 호출된다.
     *
     * <p>목표와 장소가 한 세트로 같이 넘어간다.
     */
    public void applyPendingChangesIfAny() {
        if (this.pendingTargetDays != null) {
            this.weeklyTargetDays = this.pendingTargetDays;
            this.pendingTargetDays = null;
        }
        if (hasPendingLocation()) {
            this.lat = this.pendingLat;
            this.lng = this.pendingLng;
            this.radiusMeters = this.pendingRadiusMeters;
            this.placeName = this.pendingPlaceName;
            cancelLocationReservation();
        }
    }
}
