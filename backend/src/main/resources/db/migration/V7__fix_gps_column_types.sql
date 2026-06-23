-- V7: Fix GPS column types in challenge_participants
-- DECIMAL(10,7) → DOUBLE PRECISION to match Java Double entity fields
-- (Hibernate 6.6+ rejects precision/scale on float types, per earlier fix in ChallengeParticipant.java)

ALTER TABLE challenge_participants
    ALTER COLUMN gps_lat TYPE DOUBLE PRECISION USING gps_lat::DOUBLE PRECISION;

ALTER TABLE challenge_participants
    ALTER COLUMN gps_lng TYPE DOUBLE PRECISION USING gps_lng::DOUBLE PRECISION;
