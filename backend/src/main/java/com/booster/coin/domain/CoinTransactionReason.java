package com.booster.coin.domain;

/**
 * A축 코인 변동 사유. (bs-25 §코인 로직)
 * 통합 시 B축의 사유(CHALLENGE_DEPOSIT/SETTLEMENT_WIN/DEPOSIT_REFUND 등)와 단일 enum으로 합친다.
 */
public enum CoinTransactionReason {
    SIGNUP_BONUS,      // +500 가입 보너스
    STREAK_REWARD,     // +100 스트릭 7일 달성
    RECOVERY_SUCCESS,  // -50 복귀 미션 성공
    RECOVERY_FAILURE   // -100 복귀 미션 실패(잔액 부족 시 클램핑)
}
