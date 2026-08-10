package com.booster.weeklygoal.domain;

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
 * 주간 채점 기록 (사용자 · 주 단위로 1건).
 *
 * <p>★멱등성: {@code UNIQUE(user_id, week_start)} 가 "한 주는 한 번만 채점된다"를 DB 레벨에서
 * 보장한다. 스케줄러가 재실행되거나 여러 인스턴스에서 동시에 발화해도 두 번째 INSERT 는 거부된다.
 * 코인 차감·스트릭 초기화가 걸린 경로이므로 이 보장이 필수다.
 */
@Entity
@Table(name = "weekly_evaluations",
        uniqueConstraints = @UniqueConstraint(name = "uq_weekly_evaluation_user_week",
                columnNames = {"user_id", "week_start"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(access = AccessLevel.PRIVATE)
public class WeeklyEvaluation {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    /** 평가 대상 주의 월요일. */
    @Column(name = "week_start", nullable = false)
    private LocalDate weekStart;

    /** 그 주에 적용된 목표(사후 추적용 — 목표가 바뀌어도 과거 판정 근거가 남는다). */
    @Column(name = "target_days", nullable = false)
    private int targetDays;

    @Column(name = "success_count", nullable = false)
    private int successCount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EvaluationResult result;

    @CreationTimestamp
    @Column(name = "evaluated_at", nullable = false, updatable = false)
    private OffsetDateTime evaluatedAt;

    public static WeeklyEvaluation of(Long userId, LocalDate weekStart, int targetDays,
                                      int successCount, EvaluationResult result) {
        return WeeklyEvaluation.builder()
                .userId(userId)
                .weekStart(weekStart)
                .targetDays(targetDays)
                .successCount(successCount)
                .result(result)
                .build();
    }
}
