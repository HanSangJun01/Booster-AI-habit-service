package com.booster.weeklygoal.repository;

import com.booster.weeklygoal.domain.EvaluationResult;
import com.booster.weeklygoal.domain.WeeklyEvaluation;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

public interface WeeklyEvaluationRepository extends JpaRepository<WeeklyEvaluation, Long> {

    boolean existsByUserIdAndWeekStart(Long userId, LocalDate weekStart);

    Optional<WeeklyEvaluation> findByUserIdAndWeekStart(Long userId, LocalDate weekStart);

    /** 대시보드: 가장 최근 채점 결과(지난주 결과 표시용). */
    Optional<WeeklyEvaluation> findFirstByUserIdOrderByWeekStartDesc(Long userId);

    /** 구제 대기 중인 건(사용자당 최대 1건이 정상). 사후 구매·안내 팝업의 대상. */
    Optional<WeeklyEvaluation> findFirstByUserIdAndResultOrderByWeekStartDesc(
            Long userId, EvaluationResult result);

    /** 만료 스케줄러: 기한이 지난 구제 대기 건. */
    List<WeeklyEvaluation> findByResultAndRescueDeadlineLessThanEqual(
            EvaluationResult result, OffsetDateTime now);
}
