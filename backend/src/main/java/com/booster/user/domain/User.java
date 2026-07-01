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
import org.hibernate.annotations.DynamicUpdate;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.OffsetDateTime;

/**
 * ★동시성: {@code @DynamicUpdate} — 변경된 컬럼만 UPDATE 한다. 이게 없으면 checkIn 이
 * total_attendance 만 바꿔도 flush 시 coin_balance 까지 (읽었던 옛 값으로) 덮어써서,
 * 동시에 커밋된 CoinService 의 코인 차감을 통째로 날리는 lost update 가 발생한다(BS-30 C1).
 */
@Entity
@Table(name = "users")
@DynamicUpdate
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
