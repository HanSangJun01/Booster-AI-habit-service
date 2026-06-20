package com.booster.user.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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
import org.hibernate.annotations.UpdateTimestamp;

import java.time.OffsetDateTime;

@Entity
@Table(name = "users")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(access = AccessLevel.PRIVATE)
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @Column(nullable = false)
    private String nickname;

    @Column(name = "coin_balance", nullable = false)
    private long coinBalance;

    @Column(name = "total_attendance", nullable = false)
    private int totalAttendance;

    @Column(name = "is_active", nullable = false)
    private boolean active;

    @CreationTimestamp
    @Column(name = "joined_at", nullable = false, updatable = false)
    private OffsetDateTime joinedAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    public static User create(String email, String passwordHash, String nickname) {
        return User.builder()
                .email(email)
                .passwordHash(passwordHash)
                .nickname(nickname)
                .coinBalance(0L)
                .totalAttendance(0)
                .active(true)
                .build();
    }

    /** 코인 잔액 변동. CoinService를 통해서만 호출(단일 진실 원천). */
    public void addCoins(long delta) {
        this.coinBalance += delta;
    }

    public void increaseAttendance() {
        this.totalAttendance += 1;
    }

    public void changeNickname(String nickname) {
        this.nickname = nickname;
    }

    public void deactivate() {
        this.active = false;
    }
}
