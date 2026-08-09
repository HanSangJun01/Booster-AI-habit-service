-- Phase 2: 5:5 auto team formation
-- BS-22 confirmed schema

CREATE TABLE teams (
    id                   BIGSERIAL PRIMARY KEY,
    challenge_id         BIGINT          NOT NULL REFERENCES challenges(id),
    name                 VARCHAR(100)    NOT NULL,
    participation_rate   DECIMAL(5, 2)   NOT NULL DEFAULT 0,
    result               VARCHAR(10)     CHECK (result IN ('WIN', 'LOSE', 'DRAW')),
    initial_member_count INT             NOT NULL DEFAULT 5,
    created_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_challenge_team_name UNIQUE (challenge_id, name)
);

-- challenge_participants.team_id now references teams
-- (logical FK — no physical FK to support future service separation)
CREATE INDEX idx_teams_challenge_id ON teams (challenge_id);
