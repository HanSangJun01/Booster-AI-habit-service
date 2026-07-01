package com.booster.streak.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.DynamicUpdate;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 사용자별 연속 인증 기록. user_id를 PK로 공유(1:1).
 * bs-25: currentStreak / maxStreak / lastSuccessDate.
 *
 * <p>★동시성: {@code @DynamicUpdate} — 변경된 컬럼만 UPDATE. 이게 없으면 복귀의 keepAlive
 * (lastSuccessDate 만 변경)가 flush 시 current_streak 까지 옛 값으로 덮어써, 동시에 커밋된
 * checkIn 의 +1 을 날리는 lost update 가 발생한다(BS-30 C5).
 */
@Entity
@Table(name = "streaks")
@DynamicUpdate
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

    /**
     * 인증 성공 기록. 연속성 인지:
     * <ul>
     *   <li>직전 성공일이 하루 이상 비어 있으면(갭) currentStreak 을 1로 새로 시작한다.</li>
     *   <li>최초/연속/당일 재기록은 +1 누적(복귀 keepAlive 로 lastSuccessDate 가 당일로 당겨진
     *       경우도 갭이 아니므로 정상 누적).</li>
     * </ul>
     * (BS-30 B1) 갭을 무시하고 무조건 +1 하면 끊긴 스트릭이 7일 마일스톤에 도달해 보상이
     * 부당 지급된다. 결정: 잠정/끊긴 스트릭에는 보상 보류 → 연속성으로 강제한다.
     */
    public void recordSuccess(LocalDate date) {
        boolean brokenGap = lastSuccessDate != null && lastSuccessDate.isBefore(date.minusDays(1));
        if (brokenGap) {
            this.currentStreak = 1;
        } else {
            this.currentStreak += 1;
        }
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
