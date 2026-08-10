package com.booster.weeklygoal.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/**
 * 주간 목표 변경 요청.
 *
 * <p>진행 중인 주의 기준은 바꾸지 않는다(주 중간에 목표를 낮춰 그 주를 통과하는 회피 차단).
 * 요청 값은 예약으로 저장되고 다음 주 월요일 채점 시점에 반영된다.
 */
public record WeeklyGoalUpdateRequest(
        @NotNull(message = "목표 횟수는 필수입니다.")
        @Min(value = 2, message = "주간 목표는 2회 이상이어야 합니다.")
        @Max(value = 7, message = "주간 목표는 7회 이하여야 합니다.")
        Integer targetDays
) {
}
