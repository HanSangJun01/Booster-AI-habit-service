package com.booster.weeklygoal.dto;

import java.time.LocalDate;

/**
 * 주간 목표 현황.
 *
 * <p>구제권을 무료/구매로 나눠 내려준다. 소멸 규칙이 달라서(무료는 월말 소멸, 구매는 영구)
 * 앱이 "이번 달 안에 쓰세요" 같은 안내를 하려면 구분이 필요하다.
 *
 * <p>{@code recoveryTickets == 0} 이고 이번 주 달성이 어려우면, 앱은 {@code ticketPrice} 와
 * {@code coinBalance} 로 <b>"구제권을 구입할까요?"</b> 를 바로 띄울 수 있다. 그게 없으면
 * 사용자는 월요일 0시에 아무 예고 없이 스트릭 0 + 코인 차감을 맞는다.
 *
 * @param weekStart          이번 주 월요일
 * @param targetDays         이번 주에 적용 중인 목표
 * @param pendingTargetDays  예약된 목표(다음 달 1일 반영, 없으면 null)
 * @param successCount       이번 주 성공 횟수
 * @param remainingDays      오늘 포함 이번 주 남은 날수
 * @param recoveryTickets    보유 구제권 합계
 * @param freeTickets        그중 무료분 (이번 달 말에 소멸)
 * @param paidTickets        그중 구매분 (소멸하지 않음)
 * @param ticketPrice        구제권 1개 코인 가격
 * @param coinBalance        현재 코인 잔액
 * @param lastWeekResult     지난주 채점 결과(ACHIEVED/RESCUED/FAILED, 없으면 null)
 */
public record WeeklyGoalResponse(
        LocalDate weekStart,
        int targetDays,
        Integer pendingTargetDays,
        int successCount,
        int remainingDays,
        int recoveryTickets,
        int freeTickets,
        int paidTickets,
        long ticketPrice,
        long coinBalance,
        String lastWeekResult
) {
}
