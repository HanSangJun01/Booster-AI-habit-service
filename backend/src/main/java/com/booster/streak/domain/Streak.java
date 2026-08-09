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
 * <p>★동시성: {@code @DynamicUpdate} — 변경된 컬럼만 UPDATE 해 서로 다른 컬럼을 만지는 트랜잭션이
 * flush 시 상대 컬럼을 옛 값으로 덮어쓰는 lost update 를 줄인다. 근본 보호는 쓰기 진입 시 User 행
 * 비관락으로 사용자 단위 직렬화(BS-30 C1/C5).
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
     *   <li>최초/연속/당일 재기록은 +1 누적.</li>
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

    /**
     * 복귀 성공 = '복귀한 날의 인증'으로 완전 간주(F2 팀 결정: 복귀 당일 별도 인증 불가).
     * 미인증일이 SUCCESS로 보정되어 갭이 메워졌으므로 연속성 검사 없이 +1 하고, lastSuccessDate를
     * 복귀일로 전진한다(단조). 이로써 복귀일이 다음 날 다시 미인증으로 잡히는 무한 복귀 루프가 없고,
     * 같은 날 인증-vs-복귀 순서 의존(F7)도 사라진다(복귀일 일반 인증은 서비스에서 차단).
     */
    public void recordRecoverySuccess(LocalDate recoveryDay) {
        this.currentStreak += 1;
        if (this.currentStreak > this.maxStreak) {
            this.maxStreak = this.currentStreak;
        }
        if (this.lastSuccessDate == null || this.lastSuccessDate.isBefore(recoveryDay)) {
            this.lastSuccessDate = recoveryDay;
        }
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
