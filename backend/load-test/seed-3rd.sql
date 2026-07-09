-- [BS-30 3차] seed3rd@booster.test 유저에 대량 이력 시딩
-- 목적: 데이터가 쌓였을 때 dashboard(이번 달 캘린더) / coins(페이징 COUNT) 쿼리 부하를 드러내기.
-- 선행: POST /api/auth/signup 으로 seed3rd@booster.test 가 먼저 생성돼 있어야 함(비밀번호 해시 때문에 가입은 API로).
-- 멱등: 다시 돌려도 중복 없이 동일 상태가 되도록 작성(ON CONFLICT / 시드 마커 reference_id=-999).
-- 실행(저장소 루트에서) — PowerShell stdin 파이프는 긴 줄이 깨지므로 "컨테이너에 복사 후 -f" 방식 사용:
--   docker compose -f backend/docker-compose.yml cp backend/load-test/seed-3rd.sql db:/tmp/seed-3rd.sql
--   docker compose -f backend/docker-compose.yml exec -T db psql -U booster -d booster -v ON_ERROR_STOP=1 -f /tmp/seed-3rd.sql

DO $$
DECLARE
    uid BIGINT;
BEGIN
    SELECT id INTO uid FROM users WHERE email = 'seed3rd@booster.test';
    IF uid IS NULL THEN
        RAISE EXCEPTION 'seed3rd@booster.test 유저가 없습니다. 먼저 signup API로 생성하세요.';
    END IF;

    -- ① 인증 장소(없으면 생성) → /users/me/location 200
    INSERT INTO personal_locations (user_id, lat, lng, radius_meters, place_name, created_at, updated_at)
    VALUES (uid, 37.5665, 126.9780, 200, 'seed-home', now(), now())
    ON CONFLICT (user_id) DO NOTHING;

    -- ② 이번 달 1일~오늘까지 매일 SUCCESS 체크인 → dashboard 캘린더 쿼리가 한 달치를 긁게 됨
    INSERT INTO personal_check_ins (user_id, check_in_date, status, verified_at, created_at)
    SELECT uid, g.d::date, 'SUCCESS', now(), now()
    FROM generate_series(date_trunc('month', current_date), current_date, interval '1 day') AS g(d)
    ON CONFLICT (user_id, check_in_date) DO NOTHING;

    -- ③ 코인 내역 300건(시드 마커로 재실행 시 정리 후 재삽입) → /users/me/coins 페이징 COUNT 부하
    DELETE FROM coin_transactions WHERE user_id = uid AND reference_id = -999;
    INSERT INTO coin_transactions (user_id, type, amount, balance_after, reference_id, created_at)
    SELECT uid,
           (ARRAY['STREAK_REWARD','RECOVERY_SUCCESS','RECOVERY_FAILURE'])[1 + (s.n % 3)],
           CASE WHEN s.n % 3 = 0 THEN 100 ELSE -50 END,
           500,
           -999,
           now() - (s.n || ' minutes')::interval
    FROM generate_series(1, 300) AS s(n);

    -- ④ 스트릭(없으면 생성/있으면 갱신)
    INSERT INTO streaks (user_id, current_streak, max_streak, last_success_date, updated_at)
    VALUES (uid, EXTRACT(DAY FROM current_date)::int, 30, current_date, now())
    ON CONFLICT (user_id) DO UPDATE
        SET current_streak    = EXCLUDED.current_streak,
            max_streak        = GREATEST(streaks.max_streak, EXCLUDED.max_streak),
            last_success_date = EXCLUDED.last_success_date,
            updated_at        = now();

    RAISE NOTICE '시드 완료: user_id=%, 이번달 체크인 % 건, 코인내역 300건',
        uid, (SELECT count(*) FROM personal_check_ins WHERE user_id = uid);
END $$;
