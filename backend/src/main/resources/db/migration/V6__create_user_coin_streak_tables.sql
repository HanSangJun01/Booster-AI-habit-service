-- A-axis Phase 1: User / CoinTransaction / Streak
-- bs-20 기준. Flyway 번호는 B축(V1~V5)과의 통합 충돌 방지를 위해 V6부터 시작한다.

CREATE TABLE users (
    id               BIGSERIAL PRIMARY KEY,
    email            VARCHAR(255)    NOT NULL UNIQUE,
    password_hash    VARCHAR(255)    NOT NULL,
    nickname         VARCHAR(30)     NOT NULL,
    coin_balance     BIGINT          NOT NULL DEFAULT 0,
    total_attendance INT             NOT NULL DEFAULT 0,
    is_active        BOOLEAN         NOT NULL DEFAULT TRUE,
    joined_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE coin_transactions (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT       NOT NULL REFERENCES users(id),
    type          VARCHAR(30)  NOT NULL
                      CHECK (type IN ('SIGNUP_BONUS', 'STREAK_REWARD', 'RECOVERY_SUCCESS', 'RECOVERY_FAILURE')),
    amount        BIGINT       NOT NULL,
    balance_after BIGINT       NOT NULL,
    reference_id  BIGINT,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE streaks (
    user_id           BIGINT      PRIMARY KEY REFERENCES users(id),
    current_streak    INT         NOT NULL DEFAULT 0,
    max_streak        INT         NOT NULL DEFAULT 0,
    last_success_date DATE,
    updated_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_coin_transactions_user_id ON coin_transactions (user_id);
CREATE INDEX idx_coin_transactions_user_created ON coin_transactions (user_id, created_at DESC);
