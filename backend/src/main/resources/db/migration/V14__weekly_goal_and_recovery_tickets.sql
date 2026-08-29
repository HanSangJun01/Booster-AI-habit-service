-- [주간 목표 모델 전환] 복귀 미션(일 단위) → 주간 채점 + 구제권(주/월 단위)
--
-- 배경: 기존 개인 트랙은 "매일 인증" 전제였다. 스트릭은 연속 일수, 복귀 미션은 "어제 안 했으면"
-- 매일 발동했다. 주 N회 목표를 도입하면 주 3회 사용자는 스트릭이 영원히 1에 머물고,
-- 쉬는 게 정상인 날마다 복귀 미션이 발동한다. 판정 단위를 '일'에서 '주'로 올린다.
--
-- 새 모델:
--   · 스트릭 = 실제 인증 횟수 누적 (인증 즉시 +1). 주간 채점 미달 확정 시에만 0
--   · 매주 월요일 00:00 채점 — 지난주 성공 횟수 >= 목표면 달성
--   · 미달 시 구제권 자동 소모 → 스트릭 유지 (못 한 인증은 채워주지 않음, 코인 차감 없음)
--   · 구제권 없으면 스트릭 0 + 코인 차감
--   · 구제권: 매월 1일 무료 1개(이월 없음) + 코인으로 추가 구매
--   · 복귀 미션(GPS 재인증) 폐지

-- 1) 주간 목표 --------------------------------------------------------------
-- 목표는 개인 인증 설정의 일부이므로 personal_locations 에 둔다(사용자당 1행, user_id PK).
-- pending_target_days: 목표 변경 예약. 주 중간 변경으로 그 주 채점 기준이 흔들리는 것을 막기 위해
-- 즉시 반영하지 않고 다음 주 월요일 채점 시점에 weekly_target_days 로 승격한다.
ALTER TABLE personal_locations
    ADD COLUMN weekly_target_days INT NOT NULL DEFAULT 3
        CHECK (weekly_target_days BETWEEN 2 AND 7);

ALTER TABLE personal_locations
    ADD COLUMN pending_target_days INT
        CHECK (pending_target_days BETWEEN 2 AND 7);

-- 2) 구제권 ------------------------------------------------------------------
-- 무료분과 구매분을 分리해서 센다. 소멸 규칙이 다르기 때문이다.
--   · 무료: 매월 1일에 1개로 재설정. 안 쓰면 사라진다(이월 없음)
--   · 구매: 코인을 지불한 것이므로 절대 소멸하지 않는다
-- 소모는 무료분 → 구매분 순서다. 무료분이 어차피 월말에 사라지므로 그게 사용자에게 유리하다.
ALTER TABLE users
    ADD COLUMN free_recovery_tickets INT NOT NULL DEFAULT 1
        CHECK (free_recovery_tickets >= 0);

ALTER TABLE users
    ADD COLUMN paid_recovery_tickets INT NOT NULL DEFAULT 0
        CHECK (paid_recovery_tickets >= 0);

-- 매월 1일 무료 지급의 멱등 키. 이미 이 달에 지급했으면 재실행해도 중복 지급하지 않는다.
-- 값은 해당 월의 1일(예: 2026-08-01).
ALTER TABLE users
    ADD COLUMN tickets_granted_month DATE;

-- 3) 주간 채점 기록 -----------------------------------------------------------
-- 스케줄러 멱등성(재실행/다중 인스턴스)의 핵심. UNIQUE(user_id, week_start) 가
-- "한 주는 한 번만 채점된다"를 DB 레벨에서 보장한다.
CREATE TABLE weekly_evaluations (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT       NOT NULL REFERENCES users(id),
    week_start    DATE         NOT NULL,          -- 평가 대상 주의 월요일
    target_days   INT          NOT NULL,          -- 그 주에 적용된 목표(사후 추적용)
    success_count INT          NOT NULL,          -- 그 주 SUCCESS 체크인 수
    result        VARCHAR(20)  NOT NULL
                      CHECK (result IN ('ACHIEVED', 'RESCUED', 'FAILED')),
    evaluated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_weekly_evaluation_user_week UNIQUE (user_id, week_start)
);

CREATE INDEX idx_weekly_evaluations_user_week
    ON weekly_evaluations (user_id, week_start DESC);

-- 4) 코인 거래 사유 확장 -------------------------------------------------------
-- 추가: WEEKLY_MISS_PENALTY(구제권 없이 미달), RECOVERY_TICKET_PURCHASE(구제권 구매)
-- 제거: RECOVERY_SUCCESS / RECOVERY_FAILURE — 복귀 미션 폐지로 더 이상 발생하지 않는다.
--       단 기존 행이 남아 있을 수 있어 CHECK 목록에는 유지한다(과거 데이터 보존).
ALTER TABLE coin_transactions
    DROP CONSTRAINT coin_transactions_type_check;

ALTER TABLE coin_transactions
    ADD CONSTRAINT coin_transactions_type_check
    CHECK (type IN (
        'SIGNUP_BONUS', 'STREAK_REWARD', 'RECOVERY_SUCCESS', 'RECOVERY_FAILURE',
        'CHALLENGE_DEPOSIT', 'SETTLEMENT_WIN', 'DEPOSIT_REFUND', 'DEPOSIT_CANCEL_REFUND',
        'WEEKLY_MISS_PENALTY', 'RECOVERY_TICKET_PURCHASE'
    ));

-- 5) 복귀 미션 테이블 제거 -----------------------------------------------------
-- personal_check_ins(id) 를 FK 로 참조하므로, 6)에서 그 행들을 지우기 전에 먼저 드롭한다.
DROP TABLE IF EXISTS recovery_missions;

-- 6) 개인 체크인 상태 축소 -----------------------------------------------------
-- RECOVERY_PENDING 은 복귀 미션 전용 상태였다. 새 모델에서 "그날 안 함"은 레코드 부재로 표현하며,
-- 별도 상태를 만들지 않는다. 기존 RECOVERY_PENDING/FAILED 행은 정리 후 제약을 좁힌다.
DELETE FROM personal_check_ins WHERE status <> 'SUCCESS';

ALTER TABLE personal_check_ins
    DROP CONSTRAINT personal_check_ins_status_check;

ALTER TABLE personal_check_ins
    ADD CONSTRAINT personal_check_ins_status_check
    CHECK (status IN ('SUCCESS'));
