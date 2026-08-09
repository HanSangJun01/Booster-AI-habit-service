-- A/B축 통합: coin_transactions.type CHECK 제약을 B축(챌린지/정산) 사유까지 확장한다.
-- A축 4종(SIGNUP_BONUS/STREAK_REWARD/RECOVERY_SUCCESS/RECOVERY_FAILURE) +
-- B축 4종(CHALLENGE_DEPOSIT/SETTLEMENT_WIN/DEPOSIT_REFUND/DEPOSIT_CANCEL_REFUND)
-- = 단일 enum(com.booster.coin.domain.CoinTransactionReason)과 값이 일치해야 한다.
-- (V6에서 인라인 무명 CHECK로 생성 → Postgres 기본 제약명 coin_transactions_type_check)

ALTER TABLE coin_transactions
    DROP CONSTRAINT coin_transactions_type_check;

ALTER TABLE coin_transactions
    ADD CONSTRAINT coin_transactions_type_check
    CHECK (type IN (
        'SIGNUP_BONUS', 'STREAK_REWARD', 'RECOVERY_SUCCESS', 'RECOVERY_FAILURE',
        'CHALLENGE_DEPOSIT', 'SETTLEMENT_WIN', 'DEPOSIT_REFUND', 'DEPOSIT_CANCEL_REFUND'
    ));
