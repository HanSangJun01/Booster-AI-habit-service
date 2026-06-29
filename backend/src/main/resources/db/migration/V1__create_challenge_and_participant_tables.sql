-- Phase 1: Challenge lifecycle & Participant GPS registration

CREATE TABLE challenges (
    id                  BIGSERIAL PRIMARY KEY,
    category            VARCHAR(50)     NOT NULL,
    title               VARCHAR(200)    NOT NULL,
    description         TEXT,
    verification_type   VARCHAR(50)     NOT NULL
                            CHECK (verification_type IN ('GPS', 'PHOTO', 'AI', 'GPS_PHOTO', 'GPS_PHOTO_AI')),
    duration_days       INT             NOT NULL CHECK (duration_days > 0),
    deposit_coins       BIGINT          NOT NULL CHECK (deposit_coins >= 0),
    visibility          VARCHAR(20)     NOT NULL CHECK (visibility IN ('PUBLIC', 'PRIVATE')),
    approval_type       VARCHAR(20)     NOT NULL CHECK (approval_type IN ('AUTO', 'LEADER')),
    status              VARCHAR(20)     NOT NULL DEFAULT 'READY'
                            CHECK (status IN ('READY', 'ACTIVE', 'ENDED', 'CANCELLED')),
    invite_code         VARCHAR(20)     UNIQUE,
    max_participants    INT             NOT NULL DEFAULT 10 CHECK (max_participants > 0),
    started_at          TIMESTAMP WITH TIME ZONE,
    ended_at            TIMESTAMP WITH TIME ZONE,
    created_by          BIGINT          NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE challenge_participants (
    id                  BIGSERIAL PRIMARY KEY,
    challenge_id        BIGINT          NOT NULL REFERENCES challenges(id),
    user_id             BIGINT          NOT NULL,
    team_id             BIGINT,
    personal_statement  TEXT,
    gps_lat             DOUBLE PRECISION,
    gps_lng             DOUBLE PRECISION,
    gps_radius_meters   INT             CHECK (gps_radius_meters > 0),
    gps_place_name      VARCHAR(200),
    gps_locked          BOOLEAN         NOT NULL DEFAULT FALSE,
    status              VARCHAR(20)     NOT NULL
                            CHECK (status IN ('PENDING', 'CONFIRMED', 'REJECTED', 'CANCELLED', 'LEFT')),
    active_until        TIMESTAMP WITH TIME ZONE,
    joined_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    approved_at         TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_challenge_user UNIQUE (challenge_id, user_id)
);

CREATE INDEX idx_challenges_status      ON challenges (status);
CREATE INDEX idx_challenges_category    ON challenges (category);
CREATE INDEX idx_challenges_visibility  ON challenges (visibility);
CREATE INDEX idx_challenges_invite_code ON challenges (invite_code) WHERE invite_code IS NOT NULL;

CREATE INDEX idx_participants_challenge_id ON challenge_participants (challenge_id);
CREATE INDEX idx_participants_user_id      ON challenge_participants (user_id);
CREATE INDEX idx_participants_team_id      ON challenge_participants (team_id) WHERE team_id IS NOT NULL;
CREATE INDEX idx_participants_status       ON challenge_participants (status);
