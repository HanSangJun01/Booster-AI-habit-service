-- Phase 3: ChallengeCheckIn team verification & participation rate
-- BS-22 confirmed schema

CREATE TABLE challenge_check_ins (
    id              BIGSERIAL PRIMARY KEY,
    participant_id  BIGINT          NOT NULL REFERENCES challenge_participants(id),
    challenge_id    BIGINT          NOT NULL,
    team_id         BIGINT          NOT NULL,
    check_in_date   DATE            NOT NULL,
    status          VARCHAR(20)     NOT NULL CHECK (status IN ('SUCCESS', 'FAILED')),
    verified_at     TIMESTAMP WITH TIME ZONE,
    current_lat     DECIMAL(10, 7),
    current_lng     DECIMAL(10, 7),
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_participant_date UNIQUE (participant_id, check_in_date)
);

CREATE INDEX idx_checkins_participant_id ON challenge_check_ins (participant_id);
CREATE INDEX idx_checkins_challenge_id   ON challenge_check_ins (challenge_id);
CREATE INDEX idx_checkins_team_id        ON challenge_check_ins (team_id);
CREATE INDEX idx_checkins_date           ON challenge_check_ins (check_in_date);
