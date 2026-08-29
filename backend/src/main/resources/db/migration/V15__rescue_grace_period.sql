-- [구제 유예] 미달 + 구제권 없음 → 즉시 실패가 아니라 "구제 대기" 로 두고 기한 내 구매 기회를 준다.
--
-- 배경: 주간 채점이 매주 월 00:01 에 자동으로 돌기 때문에, 구제권이 없는 사용자는 아무 예고 없이
-- 스트릭 0 + 코인 차감을 맞았다. 스트릭 30을 쌓은 사용자가 예고 없이 0이 되면 이탈한다.
-- 게임의 "이어하기"처럼, 실패가 확정되기 전에 한 번 선택할 기회를 준다.
--
-- 흐름:
--   미달 + 구제권 없음  →  PENDING_RESCUE (스트릭 유지, 코인 차감 없음, 기한 부여)
--     ├ 기한 내 구매    →  RESCUED  (코인 지불, 스트릭 유지)
--     └ 기한 경과       →  FAILED   (스트릭 0, 코인 차감) — 만료 스케줄러가 확정

-- 1) 판정 결과에 PENDING_RESCUE 추가 --------------------------------------
ALTER TABLE weekly_evaluations
    DROP CONSTRAINT weekly_evaluations_result_check;

ALTER TABLE weekly_evaluations
    ADD CONSTRAINT weekly_evaluations_result_check
    CHECK (result IN ('ACHIEVED', 'RESCUED', 'FAILED', 'PENDING_RESCUE'));

-- 2) 구제 기한 --------------------------------------------------------------
-- PENDING_RESCUE 일 때만 채워진다. 이 시각이 지나면 만료 스케줄러가 FAILED 로 확정한다.
ALTER TABLE weekly_evaluations
    ADD COLUMN rescue_deadline TIMESTAMP WITH TIME ZONE;

-- 만료 대상(기한 지난 PENDING_RESCUE)을 스케줄러가 훑는 경로.
CREATE INDEX idx_weekly_evaluations_pending_rescue
    ON weekly_evaluations (result, rescue_deadline)
    WHERE result = 'PENDING_RESCUE';

-- 3) 코인 거래 사유 확장 -----------------------------------------------------
-- 사후 구매는 "미리 사둔 것"보다 비싸므로 일반 구매와 구분해 기록한다(정산·분석용).
ALTER TABLE coin_transactions
    DROP CONSTRAINT coin_transactions_type_check;

ALTER TABLE coin_transactions
    ADD CONSTRAINT coin_transactions_type_check
    CHECK (type IN (
        'SIGNUP_BONUS', 'STREAK_REWARD', 'RECOVERY_SUCCESS', 'RECOVERY_FAILURE',
        'CHALLENGE_DEPOSIT', 'SETTLEMENT_WIN', 'DEPOSIT_REFUND', 'DEPOSIT_CANCEL_REFUND',
        'WEEKLY_MISS_PENALTY', 'RECOVERY_TICKET_PURCHASE', 'LATE_RESCUE_PURCHASE'
    ));
