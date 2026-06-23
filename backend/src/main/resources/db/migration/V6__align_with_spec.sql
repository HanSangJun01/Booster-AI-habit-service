-- V6: Align implementation with MVP_API_SPEC.md + BS-27 verification schema
-- Decisions:
--   ChallengeStatus : RECRUITING→READY, ONGOING→ACTIVE, SETTLED→ENDED, CANCELLED added
--   CheckInStatus   : LATE_SUCCESS, PENDING added
--   verification_method → verification_type (enum-constrained)
--   GPS inline fields (current_lat/lng) removed from challenge_check_ins → gps_verification_results
--   verification_submissions, gps_verification_results, verification_decisions created (BS-27)

-- ─── 1. ChallengeStatus data migration ───────────────────────────────────────
ALTER TABLE challenges DROP CONSTRAINT IF EXISTS challenges_status_check;

UPDATE challenges SET status = 'READY'  WHERE status = 'RECRUITING';
UPDATE challenges SET status = 'ACTIVE' WHERE status = 'ONGOING';
UPDATE challenges SET status = 'ENDED'  WHERE status = 'SETTLED';

ALTER TABLE challenges
    ADD CONSTRAINT challenges_status_check
    CHECK (status IN ('READY', 'ACTIVE', 'ENDED', 'CANCELLED'));

-- ─── 2. verification_method → verification_type ──────────────────────────────
ALTER TABLE challenges RENAME COLUMN verification_method TO verification_type;

-- Normalise any free-text values to GPS (MVP default)
UPDATE challenges
SET verification_type = 'GPS'
WHERE verification_type NOT IN ('GPS', 'PHOTO', 'AI', 'GPS_PHOTO', 'GPS_PHOTO_AI');

ALTER TABLE challenges
    ADD CONSTRAINT challenges_verification_type_check
    CHECK (verification_type IN ('GPS', 'PHOTO', 'AI', 'GPS_PHOTO', 'GPS_PHOTO_AI'));

-- ─── 3. CheckInStatus: extend allowed values ─────────────────────────────────
ALTER TABLE challenge_check_ins DROP CONSTRAINT IF EXISTS challenge_check_ins_status_check;

ALTER TABLE challenge_check_ins
    ADD CONSTRAINT challenge_check_ins_status_check
    CHECK (status IN ('SUCCESS', 'FAILED', 'LATE_SUCCESS', 'PENDING'));

-- ─── 4. Remove inline GPS columns from challenge_check_ins ───────────────────
ALTER TABLE challenge_check_ins DROP COLUMN IF EXISTS current_lat;
ALTER TABLE challenge_check_ins DROP COLUMN IF EXISTS current_lng;

-- ─── 5. verification_submissions ─────────────────────────────────────────────
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

-- ─── 6. gps_verification_results ─────────────────────────────────────────────
CREATE TABLE gps_verification_results (
    id               BIGSERIAL PRIMARY KEY,
    submission_id    BIGINT          NOT NULL REFERENCES verification_submissions(id),
    target_lat       DOUBLE PRECISION NOT NULL,
    target_lng       DOUBLE PRECISION NOT NULL,
    radius_meters    INT             NOT NULL,
    distance_meters  NUMERIC(10, 2)  NOT NULL,
    is_within_radius BOOLEAN         NOT NULL,
    created_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_gps_result_per_submission UNIQUE (submission_id)
);

-- ─── 7. verification_decisions ───────────────────────────────────────────────
CREATE TABLE verification_decisions (
    id             BIGSERIAL PRIMARY KEY,
    submission_id  BIGINT       NOT NULL REFERENCES verification_submissions(id),
    final_passed   BOOLEAN      NOT NULL,
    failure_reason VARCHAR(200),
    created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_decision_per_submission UNIQUE (submission_id)
);
