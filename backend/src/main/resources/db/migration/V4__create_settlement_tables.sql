-- Phase 4a: Settlement audit record
-- BS-22 confirmed schema

CREATE TABLE settlements (
    id                BIGSERIAL PRIMARY KEY,
    challenge_id      BIGINT          NOT NULL,
    computed_at       TIMESTAMP WITH TIME ZONE,
    total_pool        BIGINT          NOT NULL DEFAULT 0 CHECK (total_pool >= 0),
    per_winner_payout BIGINT          NOT NULL DEFAULT 0 CHECK (per_winner_payout >= 0),
    status            VARCHAR(20)     NOT NULL DEFAULT 'PENDING'
                          CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED')),
    winner_team_id    BIGINT,
    loser_team_id     BIGINT,
    draw              BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_settlement_challenge_id UNIQUE (challenge_id)
);

CREATE INDEX idx_settlements_status ON settlements (status);
