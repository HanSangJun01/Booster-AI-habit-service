-- =====================================================================
-- 멀티서버 P1(정산 이중지급 방지) 테스트 전용 시드
-- =====================================================================
-- 목적: 3인스턴스 동시 정산에서 "정확히 1회 / 이중지급 없음"을 검증 가능하게
--       실제 users 행을 갖춘 ENDED 챌린지를 만든다.
--
-- 왜 실제 users 인가:
--   기존 b-axis-seed-saturation.sql 은 "읽기 부하테스트"용이라 참여자에 합성
--   user_id(1,000,000+, users 행 없음)를 쓴다. 리더보드 조회는 users 를 안 보므로
--   문제없지만, 정산(코인 지급)은 users 를 조회하므로 "사용자 없음"으로 전부 FAILED
--   된다. 이 시드는 정산이 실제로 COMPLETED 되도록 실제 users 를 심는다.
--
-- 데이터 형상:
--   - 20 ENDED 챌린지 (MST_0001..MST_0020), duration 5, deposit 1000
--   - 챌린지당 2팀(A팀/B팀) × 5명 = 200 참여자 = 200 실제 유저(id 2000001..2000200)
--   - A팀 전원 5일 SUCCESS 체크인 / B팀 무체크인 → A팀 승리 확정
--   - 정산 결과(기대): 승팀 5명이 totalPool(=1000×10=10000)을 5등분 → 1인당 2000코인
--   - settlements 는 넣지 않는다(스케줄러가 정산하게 둔다)
--
-- 이중지급 지표: 승자 1인 coin_balance == 2000 (정상). 두 번 지급되면 4000+.
--
-- 주의: Spring 메인 코드는 절대 수정하지 않는다. 이 파일은 테스트 데이터 전용이며
--       재실행 가능(idempotent)하도록 상단에서 MST 데이터를 정리한다.
-- =====================================================================

\set ON_ERROR_STOP on
BEGIN;

-- 0) 재실행 대비 정리 (FK 의존 순서: 자식 → 부모)
DELETE FROM coin_transactions WHERE user_id BETWEEN 2000001 AND 2000999;
DELETE FROM settlements s USING challenges c WHERE s.challenge_id = c.id AND c.title LIKE 'MST_%';
DELETE FROM challenge_check_ins ci USING challenges c WHERE ci.challenge_id = c.id AND c.title LIKE 'MST_%';
DELETE FROM challenge_participants p USING challenges c WHERE p.challenge_id = c.id AND c.title LIKE 'MST_%';
DELETE FROM teams t USING challenges c WHERE t.challenge_id = c.id AND c.title LIKE 'MST_%';
DELETE FROM challenges WHERE title LIKE 'MST_%';
DELETE FROM users WHERE id BETWEEN 2000001 AND 2000999;

-- 1) 실제 유저 200명 (id 2000001..2000200). password_hash = 'seed1234' bcrypt(로그인 불필요, 존재만 필요)
INSERT INTO users
  (id, email, password_hash, nickname, coin_balance, total_attendance, is_active, joined_at, updated_at)
SELECT
  g,
  'mst_' || g || '@booster.test',
  '$2a$10$OPMJyoUHc4S7lKCMUB0lMuAje8xZU.tG.rUVnKTrewFa47gVxamCa',
  'mst' || g,
  0, 0, true, now(), now()
FROM generate_series(2000001, 2000200) AS g;

-- 2) ENDED 챌린지 20개
INSERT INTO challenges
  (category, title, description, verification_type, duration_days, deposit_coins,
   visibility, approval_type, status, max_participants, started_at, ended_at, created_by, created_at, updated_at)
SELECT
  'EXERCISE',
  'MST_' || lpad(g::text, 4, '0'),
  'multi-server P1 settlement test',
  'GPS',
  5,
  1000,
  'PUBLIC',
  'AUTO',
  'ENDED',
  10,
  DATE '2026-01-01',
  TIMESTAMP '2026-01-06 00:00:00',
  900001,
  now(), now()
FROM generate_series(1, 20) AS g;

-- 3) 팀 2개씩 (A팀/B팀)
INSERT INTO teams
  (challenge_id, name, participation_rate, initial_member_count, created_at, updated_at)
SELECT c.id, tn.name, 0, 5, now(), now()
FROM challenges c
CROSS JOIN (VALUES ('A팀'), ('B팀')) AS tn(name)
WHERE c.title LIKE 'MST_%';

-- 4) 참여자 10명씩 (idx 1..5 → A팀, 6..10 → B팀), 실제 유저 매핑
--    user_id = 2000000 + (챌린지순번-1)*10 + idx  → 2000001..2000200 (유저와 1:1)
WITH ch AS (
  SELECT id, row_number() OVER (ORDER BY title) AS seq
  FROM challenges WHERE title LIKE 'MST_%'
)
INSERT INTO challenge_participants
  (challenge_id, user_id, team_id, status, gps_locked, joined_at, approved_at, active_until, created_at, updated_at)
SELECT
  ch.id,
  2000000 + (ch.seq - 1) * 10 + s.idx,
  t.id,
  'CONFIRMED',
  false,
  now(), now(), NULL, now(), now()
FROM ch
CROSS JOIN generate_series(1, 10) AS s(idx)
JOIN teams t
  ON t.challenge_id = ch.id
 AND t.name = CASE WHEN s.idx <= 5 THEN 'A팀' ELSE 'B팀' END;

-- 5) 체크인: A팀 전원 5일(01-01..01-05) SUCCESS. B팀은 무체크인 → A팀 참여율 우위 → 승리
INSERT INTO challenge_check_ins
  (participant_id, challenge_id, team_id, check_in_date, status, verified_at, created_at, updated_at)
SELECT
  p.id, p.challenge_id, p.team_id,
  DATE '2026-01-01' + d.off,
  'SUCCESS',
  now(), now(), now()
FROM challenge_participants p
JOIN teams t ON t.id = p.team_id AND t.name = 'A팀'
JOIN challenges c ON c.id = p.challenge_id AND c.title LIKE 'MST_%'
CROSS JOIN generate_series(0, 4) AS d(off);

-- 6) settlements 없음 — 스케줄러(retryFailedSettlements)가 정산하도록 둔다.

COMMIT;
\echo '=== MST P1 SEED COMPLETE: 20 ENDED challenges / 200 real users / A-team wins (expect 2000 coins each winner) ==='
