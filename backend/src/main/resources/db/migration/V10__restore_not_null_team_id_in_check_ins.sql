-- Restore NOT NULL on team_id: service-level guard now rejects check-ins
-- without team assignment (added in BS-30), so null rows can no longer be created.
DELETE FROM challenge_check_ins WHERE team_id IS NULL;
ALTER TABLE challenge_check_ins ALTER COLUMN team_id SET NOT NULL;
