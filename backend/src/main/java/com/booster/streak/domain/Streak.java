package com.booster.streak.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 사용자별 연속 인증 기록. user_id를 PK로 공유(1:1).
 * bs-20: currentStreak / maxStreak / lastSuccessDate.
 */
@Entity
@Table(name = "streaks")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Streak {

    @Id
    @Column(name = "user_id")
    private Long userId;

    @Column(name = "current_streak", nullable = false)
    private int currentStreak;

    @Column(name = "max_streak", nullable = false)
    private int maxStreak;

    @Column(name = "last_success_date")
    private LocalDate lastSuccessDate;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    private Streak(Long userId) {
        this.userId = userId;
        this.currentStreak = 0;
        this.maxStreak = 0;
        this.lastSuccessDate = null;
    }

    public static Streak init(Long userId) {
        return new Streak(userId);
    }

    /** 인증 성공: currentStreak +1, maxStreak 갱신, lastSuccessDate 설정. */
    public void recordSuccess(LocalDate date) {
        this.currentStreak += 1;
        if (this.currentStreak > this.maxStreak) {
            this.maxStreak = this.currentStreak;
        }
        this.lastSuccessDate = date;
    }

    /** 복귀 미션 성공 시 스트릭 유지(증가 없음), lastSuccessDate만 수행일로 갱신. */
    public void keepAlive(LocalDate date) {
        this.lastSuccessDate = date;
    }

    /** 복귀 실패: 스트릭 초기화. */
    public void reset() {
        this.currentStreak = 0;
        this.lastSuccessDate = null;
    }

    /** 보상 마일스톤(interval 일수의 배수) 도달 여부. */
    public boolean isRewardMilestone(int intervalDays) {
        return this.currentStreak > 0 && this.currentStreak % intervalDays == 0;
    }
}
