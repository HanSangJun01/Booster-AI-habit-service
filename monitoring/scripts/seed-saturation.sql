-- =====================================================================
-- seed-saturation.sql
-- Purpose : Seed large-scale SATURATION test data for B-axis backend
--           to reveal which resource (HikariCP / CPU / index scan) saturates
--           first, so we can decide whether Redis caching is warranted.
--
-- Idempotent: all rows are tagged with title prefix 'SAT_'. Re-running first
--             deletes ALL 'SAT_%' data in FK-safe order, then regenerates.
--             Existing (non-SAT) production/test data is NEVER touched.
--
-- Saturation surfaces created:
--   1. HOT-KEY   : 2 "popular" challenges (SAT_HOT_1 / SAT_HOT_2),
--                  duration 120d, 10 participants each -> deep per-user history.
--                  These are the id(s) to hammer with thousands of concurrent
--                  identical requests (the only scenario where Redis may win).
--   2. BREADTH   : N_BREADTH challenges x 10 participants each -> reads fan out
--                  across many challenge_id (cache-miss / working-set pressure).
--   3. DEEP HIST : HOT challenges (120 checkins/participant) + configurable
--                  breadth history depth -> leaderboard GROUP BY scans more rows.
--
-- Domain caps: <=10 participants/challenge (2 teams x 5). Enforced here.
-- No FK on challenge_participants.user_id -> synthetic user_ids use 1_000_000+
-- offset to never collide with real users (observed real range 1..32).
--
-- Run: docker exec -i booster-db psql -U booster -d booster < seed-saturation.sql
-- =====================================================================

\set ON_ERROR_STOP on
\timing on

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Scale configuration (single source of truth)
--    Adjust these to scale up/down; everything else derives from them.
-- ---------------------------------------------------------------------
-- N_BREADTH        : number of breadth challenges (each 10 participants)
-- BREADTH_DAYS     : check-in history depth per breadth participant
-- HOT_DAYS         : check-in history depth per HOT participant (deep history)
-- USER_ID_OFFSET   : synthetic user_id base (avoid real-user collision)
-- CHECKIN_BASE_DATE: earliest check_in_date (kept in a fixed past window)
--
-- Defaults => 500 challenges, 5000 participants,
--             breadth checkins ~498*10*20 = 99,600 + hot 2*10*120 = 2,400
--             => ~102,000 check-ins total.

-- ---------------------------------------------------------------------
-- 1. FK-safe cleanup of any previous SAT_ run
--    Order: check_ins -> participants -> teams -> challenges
--    (verification_submissions references check_ins, but SAT run never
--     creates them, so no SAT check_in is referenced.)
-- ---------------------------------------------------------------------
DELETE FROM settlements s
 USING challenges c
 WHERE s.challenge_id = c.id
   AND c.title LIKE 'SAT_%';

DELETE FROM challenge_check_ins ci
 USING challenges c
 WHERE ci.challenge_id = c.id
   AND c.title LIKE 'SAT_%';

DELETE FROM challenge_participants p
 USING challenges c
 WHERE p.challenge_id = c.id
   AND c.title LIKE 'SAT_%';

DELETE FROM teams t
 USING challenges c
 WHERE t.challenge_id = c.id
   AND c.title LIKE 'SAT_%';

DELETE FROM challenges
 WHERE title LIKE 'SAT_%';

-- ---------------------------------------------------------------------
-- 2. Challenges
--    HOT: SAT_HOT_1, SAT_HOT_2  (duration 120, ACTIVE)
--    BREADTH: SAT_BREADTH_000001 .. (duration 20, ~half ACTIVE half ENDED)
-- ---------------------------------------------------------------------
INSERT INTO challenges
  (category, title, description, verification_type, duration_days,
   deposit_coins, visibility, approval_type, status, max_participants,
   started_at, ended_at, created_by, created_at, updated_at)
SELECT
  'EXERCISE',
  'SAT_HOT_' || g,
  'saturation hot-key challenge',
  'GPS',
  120,
  1000,
  'PUBLIC',
  'AUTO',
  'ACTIVE',
  10,
  DATE '2026-01-01',                       -- started_at
  NULL,                                    -- ended_at (still ACTIVE)
  900000 + g,                              -- created_by (synthetic)
  now(), now()
FROM generate_series(1, 2) AS g;

INSERT INTO challenges
  (category, title, description, verification_type, duration_days,
   deposit_coins, visibility, approval_type, status, max_participants,
   started_at, ended_at, created_by, created_at, updated_at)
SELECT
  'EXERCISE',
  'SAT_BREADTH_' || lpad(g::text, 6, '0'),
  'saturation breadth challenge',
  'GPS',
  20,
  1000,
  'PUBLIC',
  'AUTO',
  CASE WHEN g % 2 = 0 THEN 'ENDED' ELSE 'ACTIVE' END,
  10,
  DATE '2026-01-01',
  CASE WHEN g % 2 = 0 THEN (DATE '2026-01-01' + 20) ELSE NULL END,
  900000,
  now(), now()
FROM generate_series(1, 498) AS g;

-- ---------------------------------------------------------------------
-- 3. Teams : 2 per SAT challenge ('A팀','B팀'), 5 members each
-- ---------------------------------------------------------------------
INSERT INTO teams
  (challenge_id, name, participation_rate, initial_member_count, created_at, updated_at)
SELECT c.id, tn.name, 0, 5, now(), now()
FROM challenges c
CROSS JOIN (VALUES ('A팀'), ('B팀')) AS tn(name)
WHERE c.title LIKE 'SAT_%';

-- ---------------------------------------------------------------------
-- 4. Participants : 10 per SAT challenge (idx 1..5 -> A팀, 6..10 -> B팀)
--    user_id = USER_ID_OFFSET + idx  (unique within a challenge; reused
--    across challenges, which the (challenge_id,user_id) unique allows).
--    All CONFIRMED so leaderboard/team-detail treat them as active members.
-- ---------------------------------------------------------------------
INSERT INTO challenge_participants
  (challenge_id, user_id, team_id, status, gps_locked,
   joined_at, approved_at, active_until, created_at, updated_at)
SELECT
  c.id,
  1000000 + s.idx                              AS user_id,
  t.id                                         AS team_id,
  'CONFIRMED',
  false,
  now(),
  now(),
  NULL,
  now(), now()
FROM challenges c
CROSS JOIN generate_series(1, 10) AS s(idx)
JOIN teams t
  ON t.challenge_id = c.id
 AND t.name = CASE WHEN s.idx <= 5 THEN 'A팀' ELSE 'B팀' END
WHERE c.title LIKE 'SAT_%';

-- ---------------------------------------------------------------------
-- 5. Check-ins : one row per (participant, day-offset) where day-offset
--    ranges 0..(history_depth-1). history_depth = challenge.duration_days.
--    check_in_date = 2026-01-01 + offset  (unique per participant -> never
--    violates unique_participant_date). status mostly SUCCESS with variety.
-- ---------------------------------------------------------------------
INSERT INTO challenge_check_ins
  (participant_id, challenge_id, team_id, check_in_date, status,
   verified_at, created_at, updated_at)
SELECT
  p.id,
  p.challenge_id,
  p.team_id,
  DATE '2026-01-01' + d.off                     AS check_in_date,
  CASE (d.off % 10)
    WHEN 8 THEN 'FAILED'
    WHEN 9 THEN 'PENDING'
    WHEN 7 THEN 'LATE_SUCCESS'
    ELSE 'SUCCESS'
  END                                           AS status,
  CASE WHEN (d.off % 10) IN (8,9) THEN NULL ELSE now() END,
  now(), now()
FROM challenge_participants p
JOIN challenges c ON c.id = p.challenge_id
CROSS JOIN LATERAL generate_series(0, c.duration_days - 1) AS d(off)
WHERE c.title LIKE 'SAT_%';

-- ---------------------------------------------------------------------
-- 6. [JWT 전환] 로그인 가능한 실제 users 앵커 행
--    A/B축 통합 후 Spring Security가 모든 엔드포인트를 JWT로 보호하므로
--    saturation-test.js S3(team-detail)는 실제 로그인 토큰이 필요하다.
--    synthetic 참여자 user_id=1000001(A팀, HOT 챌린지의 CONFIRMED 멤버)와
--    id가 일치하는 users 행을 심어, 이 앵커로 로그인해 team-detail을 호출할 수 있게 한다.
--    password = 'seed1234' (bcrypt). 재실행 대비 ON CONFLICT (id) DO NOTHING.
-- ---------------------------------------------------------------------
INSERT INTO users
  (id, email, password_hash, nickname,
   coin_balance, total_attendance, is_active, joined_at, updated_at)
VALUES
  (1000001, 'sat_hot@booster.test',
   '$2a$10$OPMJyoUHc4S7lKCMUB0lMuAje8xZU.tG.rUVnKTrewFa47gVxamCa',
   'sat_hot', 0, 0, true, now(), now())
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 7. ENDED 챌린지에 COMPLETED settlements 선등록.
--    ChallengeEndScheduler.retryFailedSettlements(5분 주기)는 settlement가 없는
--    ENDED 챌린지를 전부 재정산 시도한다. SAT_ 참여자는 synthetic user라 코인
--    지급이 매번 실패하므로, 선등록하지 않으면 ENDED ~249건이 5분마다 실패
--    반복(로그 폭주 + 스케줄러 점유)된다. DRAW-COMPLETED로 심어 스킵시킨다.
-- ---------------------------------------------------------------------
INSERT INTO settlements
  (challenge_id, computed_at, total_pool, per_winner_payout, status,
   winner_team_id, loser_team_id, draw, created_at, updated_at)
SELECT
  c.id, now(), c.deposit_coins * 10, 0, 'COMPLETED',
  NULL, NULL, true, now(), now()
FROM challenges c
WHERE c.title LIKE 'SAT_%'
  AND c.status = 'ENDED'
ON CONFLICT (challenge_id) DO NOTHING;

COMMIT;

\echo '=== SATURATION SEED COMPLETE ==='
