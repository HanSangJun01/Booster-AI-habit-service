-- Phase 3: ChallengeCheckIn verification & participation rate

CREATE TABLE challenge_check_ins (
    id              BIGSERIAL PRIMARY KEY,
    participant_id  BIGINT          NOT NULL REFERENCES challenge_participants(id),
    challenge_id    BIGINT          NOT NULL,
    team_id         BIGINT          NOT NULL,
    check_in_date   DATE            NOT NULL,
    status          VARCHAR(20)     NOT NULL
                        CHECK (status IN ('SUCCESS', 'FAILED', 'LATE_SUCCESS', 'PENDING')),
    verified_at     TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_participant_date UNIQUE (participant_id, check_in_date)
);

CREATE INDEX idx_checkins_participant_id ON challenge_check_ins (participant_id);
CREATE INDEX idx_checkins_challenge_id   ON challenge_check_ins (challenge_id);
CREATE INDEX idx_checkins_team_id        ON challenge_check_ins (team_id);
CREATE INDEX idx_checkins_date           ON challenge_check_ins (check_in_date);
CREATE INDEX idx_checkins_challenge_date ON challenge_check_ins (challenge_id, check_in_date);

CREATE TABLE verification_submissions (
    id             BIGSERIAL PRIMARY KEY,
    check_in_id    BIGINT                   NOT NULL REFERENCES challenge_check_ins(id),
    submitted_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    submitted_lat  DOUBLE PRECISION         NOT NULL,
    submitted_lng  DOUBLE PRECISION         NOT NULL,
    attempt_number INT                      NOT NULL DEFAULT 1,
    created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_verification_submissions_check_in_id ON verification_submissions(check_in_id);

CREATE TABLE gps_verification_results (
    id               BIGSERIAL PRIMARY KEY,
    submission_id    BIGINT           NOT NULL REFERENCES verification_submissions(id),
    target_lat       DOUBLE PRECISION NOT NULL,
    target_lng       DOUBLE PRECISION NOT NULL,
    radius_meters    INT              NOT NULL,
    distance_meters  NUMERIC(10, 2)   NOT NULL,
    is_within_radius BOOLEAN          NOT NULL,
    created_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_gps_result_per_submission UNIQUE (submission_id)
);

CREATE TABLE verification_decisions (
    id             BIGSERIAL PRIMARY KEY,
    submission_id  BIGINT       NOT NULL REFERENCES verification_submissions(id),
    final_passed   BOOLEAN      NOT NULL,
    failure_reason VARCHAR(200),
    created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_decision_per_submission UNIQUE (submission_id)
);
