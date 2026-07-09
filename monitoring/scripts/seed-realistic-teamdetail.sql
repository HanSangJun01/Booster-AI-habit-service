-- ============================================================
-- RT_ realistic seed data for team-detail cache re-validation
--
-- Idempotent + cleanup-able: always deletes any prior RT_ batch
-- (child -> parent FK order) before inserting a fresh one.
--
-- Produces:
--   50 ACTIVE challenges: 10x RT_HOT_%   (20%)
--                         40x RT_NORMAL_% (80%)
--   Each challenge: 10 CONFIRMED participants, 5:5 teams (A팀/B팀),
--   GPS registered (Seoul City Hall), and a partial set of today's
--   check-ins (3-6 of 10 members) so team-detail has meaningful data.
--
-- user_id scheme: 3_000_000 + challengeOffset*10 + memberIndex
--   (challengeOffset 0..49, memberIndex 0..9) -> range 3000000-3000499
--   Does not collide with existing SAT_ users (900000-900010 / 1000001-1000010).
--
-- Cleanup (run alone to remove all RT_ data):
--   DELETE FROM challenge_check_ins WHERE challenge_id IN (SELECT id FROM challenges WHERE title LIKE 'RT_%');
--   DELETE FROM challenge_participants WHERE challenge_id IN (SELECT id FROM challenges WHERE title LIKE 'RT_%');
--   DELETE FROM teams WHERE challenge_id IN (SELECT id FROM challenges WHERE title LIKE 'RT_%');
--   DELETE FROM challenges WHERE title LIKE 'RT_%';
-- ============================================================

BEGIN;

-- 1. Cleanup previous RT_ batch (child -> parent FK order)
DELETE FROM challenge_check_ins
WHERE challenge_id IN (SELECT id FROM challenges WHERE title LIKE 'RT_%');

DELETE FROM challenge_participants
WHERE challenge_id IN (SELECT id FROM challenges WHERE title LIKE 'RT_%');

DELETE FROM teams
WHERE challenge_id IN (SELECT id FROM challenges WHERE title LIKE 'RT_%');

DELETE FROM challenges
WHERE title LIKE 'RT_%';

-- 2. Seed challenges + teams + participants + today's check-ins
DO $$
DECLARE
    v_challenge_id     BIGINT;
    v_team_a_id         BIGINT;
    v_team_b_id         BIGINT;
    v_participant_id    BIGINT;
    v_title             TEXT;
    v_offset            INT;
    v_member            INT;
    v_user_id           BIGINT;
    v_team_id           BIGINT;
    v_started_days_ago  INT;
    v_checkin_count     INT;
    v_a_success         INT;
    v_b_success         INT;
    participant_ids     BIGINT[];
    team_ids            BIGINT[];
BEGIN
    FOR v_offset IN 0..49 LOOP
        IF v_offset < 10 THEN
            v_title := 'RT_HOT_' || (v_offset + 1);
        ELSE
            v_title := 'RT_NORMAL_' || (v_offset - 9);
        END IF;

        v_started_days_ago := 1 + (v_offset % 5); -- 1-5 days ago, well within 14-day duration

        INSERT INTO challenges (
            category, title, description, verification_type, duration_days,
            deposit_coins, visibility, approval_type, status,
            max_participants, started_at, ended_at, created_by
        ) VALUES (
            'EXERCISE', v_title, 'RT realistic seed for team-detail cache test',
            'GPS', 14, 1000, 'PUBLIC', 'AUTO', 'ACTIVE',
            10, NOW() - make_interval(days => v_started_days_ago), NULL,
            3000000 + v_offset
        ) RETURNING id INTO v_challenge_id;

        INSERT INTO teams (challenge_id, name, participation_rate, initial_member_count)
        VALUES (v_challenge_id, 'A팀', 0, 5) RETURNING id INTO v_team_a_id;

        INSERT INTO teams (challenge_id, name, participation_rate, initial_member_count)
        VALUES (v_challenge_id, 'B팀', 0, 5) RETURNING id INTO v_team_b_id;

        participant_ids := ARRAY[]::BIGINT[];
        team_ids := ARRAY[]::BIGINT[];

        FOR v_member IN 0..9 LOOP
            v_user_id := 3000000 + v_offset * 10 + v_member;
            v_team_id := CASE WHEN v_member < 5 THEN v_team_a_id ELSE v_team_b_id END;

            INSERT INTO challenge_participants (
                challenge_id, user_id, team_id, status,
                gps_lat, gps_lng, gps_radius_meters, gps_place_name, gps_locked,
                active_until, joined_at, approved_at
            ) VALUES (
                v_challenge_id, v_user_id, v_team_id, 'CONFIRMED',
                37.5665, 126.9780, 100, '서울시청', true,
                NOW() + INTERVAL '13 days',
                NOW() - make_interval(days => v_started_days_ago),
                NOW() - make_interval(days => v_started_days_ago)
            ) RETURNING id INTO v_participant_id;

            participant_ids := array_append(participant_ids, v_participant_id);
            team_ids := array_append(team_ids, v_team_id);
        END LOOP;

        -- [JWT 전환] 이 챌린지의 로그인 가능한 앵커 user 행.
        --   A/B축 통합 후 Spring Security가 team-detail을 JWT로 보호하고,
        --   team-detail은 "토큰 유저가 해당 챌린지의 CONFIRMED 참여자"일 것을 요구한다.
        --   첫 멤버(v_member=0 → user_id = 3000000 + v_offset*10)를 앵커로 삼아,
        --   그 user_id와 동일한 id의 실제 users 행을 심는다(로그인용).
        --   email은 챌린지 id로 결정론적 생성: rt_c<challengeId>@booster.test
        --   password = 'seed1234' (bcrypt). 재실행 대비 ON CONFLICT DO NOTHING.
        INSERT INTO users
          (id, email, password_hash, nickname,
           coin_balance, total_attendance, is_active, joined_at, updated_at)
        VALUES
          (3000000 + v_offset * 10,
           'rt_c' || v_challenge_id || '@booster.test',
           '$2a$10$OPMJyoUHc4S7lKCMUB0lMuAje8xZU.tG.rUVnKTrewFa47gVxamCa',
           'rt_c' || v_challenge_id,
           0, 0, true, now(), now())
        ON CONFLICT (id) DO NOTHING;

        -- Partial check-ins for today: 3-6 of 10 members, split across both teams
        v_checkin_count := 3 + (v_offset % 4); -- cycles 3,4,5,6
        v_a_success := LEAST(5, GREATEST(1, v_checkin_count / 2));
        v_b_success := v_checkin_count - v_a_success;

        FOR v_member IN 0..(v_a_success - 1) LOOP
            INSERT INTO challenge_check_ins (participant_id, challenge_id, team_id, check_in_date, status, verified_at)
            VALUES (participant_ids[v_member + 1], v_challenge_id, team_ids[v_member + 1], CURRENT_DATE, 'SUCCESS', NOW());
        END LOOP;

        FOR v_member IN 5..(5 + v_b_success - 1) LOOP
            INSERT INTO challenge_check_ins (participant_id, challenge_id, team_id, check_in_date, status, verified_at)
            VALUES (participant_ids[v_member + 1], v_challenge_id, team_ids[v_member + 1], CURRENT_DATE, 'SUCCESS', NOW());
        END LOOP;

        -- Plausible participation_rate per team based on today's check-ins
        UPDATE teams SET participation_rate = ROUND((v_a_success::numeric / 5) * 100, 2) WHERE id = v_team_a_id;
        UPDATE teams SET participation_rate = ROUND((v_b_success::numeric / 5) * 100, 2) WHERE id = v_team_b_id;
    END LOOP;
END $$;

COMMIT;
