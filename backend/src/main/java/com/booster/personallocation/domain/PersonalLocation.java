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
 * bs-20 Principle 4: PersonalCheckIn 전용. ChallengeParticipant의 GPS와 무관(A축 독립).
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
}
