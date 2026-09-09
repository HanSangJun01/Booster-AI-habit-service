package com.booster.weeklygoal.dto;

import com.booster.challenge.domain.VerificationType;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/**
 * 주간 목표 · 인증 방식 변경 요청.
 *
 * <p>목표 횟수는 진행 중인 기간의 채점 기준이므로 즉시 반영하지 않고 예약했다가 다음 달 1일에
 * 반영한다(주 중간에 낮춰서 통과하는 회피 차단). 반면 <b>인증 방식은 즉시 반영</b>한다 —
 * 채점 기준이 아니라 인증 절차만 바뀌므로 회피에 쓸 수 없다.
 *
 * @param verificationType 생략하면 인증 방식은 그대로 둔다
 */
public record WeeklyGoalUpdateRequest(
        @NotNull(message = "목표 횟수는 필수입니다.")
        @Min(value = 2, message = "주간 목표는 2회 이상이어야 합니다.")
        @Max(value = 7, message = "주간 목표는 7회 이하여야 합니다.")
        Integer targetDays,

        VerificationType verificationType,

        /**
         * 목표 카테고리(EXERCISE/STUDY). 생략하면 기존 값을 유지한다.
         *
         * <p>온보딩에서 "운동 / 공부" 를 먼저 고르고 그 다음 인증 장소를 정한다. 이 값이
         * AI 사진 판정의 기준이 된다.
         */
        @Pattern(regexp = "EXERCISE|STUDY", message = "카테고리는 EXERCISE 또는 STUDY 만 가능합니다.")
        String category
) {
}
