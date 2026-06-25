-- team_id is optional for solo participants (no team assigned yet)
ALTER TABLE challenge_check_ins ALTER COLUMN team_id DROP NOT NULL;
