package com.booster.weeklygoal.repository;

import com.booster.weeklygoal.domain.WeeklyEvaluation;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.Optional;

public interface WeeklyEvaluationRepository extends JpaRepository<WeeklyEvaluation, Long> {

    boolean existsByUserIdAndWeekStart(Long userId, LocalDate weekStart);

    Optional<WeeklyEvaluation> findByUserIdAndWeekStart(Long userId, LocalDate weekStart);

    /** 대시보드: 가장 최근 채점 결과(지난주 결과 표시용). */
    Optional<WeeklyEvaluation> findFirstByUserIdOrderByWeekStartDesc(Long userId);
}
