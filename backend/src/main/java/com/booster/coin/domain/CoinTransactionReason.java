package com.booster.coin.domain;

/**
 * 코인 변동 사유 (A/B축 통합 단일 enum).
 * DB coin_transactions.type CHECK 제약과 값이 일치해야 한다(V6 + V9 마이그레이션).
 * B축 contract 사유({@link com.booster.shared.contract.CoinTransactionReason})는
 * CoinServiceAdapter 에서 이 enum으로 이름 매핑된다.
 */
public enum CoinTransactionReason {
    // --- A축 (개인 습관/복귀) ---
    SIGNUP_BONUS,           // +500 가입 보너스
    STREAK_REWARD,          // +100 스트릭 7일 달성
    RECOVERY_SUCCESS,       // -50 복귀 미션 성공
    RECOVERY_FAILURE,       // -100 복귀 미션 실패(잔액 부족 시 클램핑)

    // --- B축 (챌린지 예치/정산) ---
    CHALLENGE_DEPOSIT,      // 챌린지 참가 예치금 차감
    SETTLEMENT_WIN,         // 정산 승리 보상 지급
    DEPOSIT_REFUND,         // 정산 시 예치금 환불
    DEPOSIT_CANCEL_REFUND   // 참가 취소 시 예치금 환불
}
