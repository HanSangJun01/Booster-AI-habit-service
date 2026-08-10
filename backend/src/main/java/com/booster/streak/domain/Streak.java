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
     * 인증 성공 기록 — 무조건 +1.
     *
     * <p>[주간 목표 모델] 스트릭은 "목표를 지키는 동안 누적된 실제 인증 횟수"다. 날짜 갭을 보지
     * 않는다 — 주 3회 목표라면 월·수·금 사이의 빈 날은 정상이기 때문이다.
     *
     * <p>과거 모델은 여기서 갭을 검사해 리셋했고(BS-30 B1), 그래서 리셋 책임이 체크인과 복귀 만료
     * 두 곳에 흩어져 있었다. 새 모델은 리셋을 <b>주간 채점 한 곳</b>으로 모은다(3.2 참조).
     */
    public void recordSuccess(LocalDate date) {
        this.currentStreak += 1;
        if (this.currentStreak > this.maxStreak) {
            this.maxStreak = this.currentStreak;
        }
        this.lastSuccessDate = date;
    }

    /** 주간 목표 미달 + 구제권 없음: 스트릭 초기화. */
    public void reset() {
        this.currentStreak = 0;
        this.lastSuccessDate = null;
    }

    /** 보상 마일스톤(interval 일수의 배수) 도달 여부. */
    public boolean isRewardMilestone(int intervalDays) {
        return this.currentStreak > 0 && this.currentStreak % intervalDays == 0;
    }
}
