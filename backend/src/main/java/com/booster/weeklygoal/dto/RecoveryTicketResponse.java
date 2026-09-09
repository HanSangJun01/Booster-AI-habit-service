package com.booster.weeklygoal.dto;

/**
 * 구제권 현황.
 *
 * @param recoveryTickets 보유 수량
 * @param price           1개당 코인 가격
 * @param coinBalance     구매 후 코인 잔액
 */
public record RecoveryTicketResponse(
        int recoveryTickets,
        long price,
        long coinBalance
) {
}
