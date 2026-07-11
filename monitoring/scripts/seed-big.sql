-- [BS-30 C] 대용량 데이터에서 인덱스/쿼리플랜 확인용. seed3rd 유저에 코인내역 30만 건 주입 후 EXPLAIN.
-- 멱등: reference_id=-888 마커로 재실행 시 정리 후 재삽입.
-- 선행: seed3rd@booster.test 가 먼저 생성돼 있어야 함(signup API + seed-3rd.sql).
\timing on

-- seed3rd의 user_id를 이메일로 조회해 :uid 로 바인딩(유저 생성 순서에 의존하지 않도록).
SELECT id AS uid FROM users WHERE email = 'seed3rd@booster.test' \gset
\if :{?uid}
\else
  \echo '오류: seed3rd@booster.test 유저가 없습니다. 먼저 signup API로 생성하세요.'
  \quit
\endif

DELETE FROM coin_transactions WHERE user_id = :uid AND reference_id = -888;

INSERT INTO coin_transactions (user_id, type, amount, balance_after, reference_id, created_at)
SELECT :uid, 'STREAK_REWARD', 100, 500, -888, now() - (s.n || ' seconds')::interval
FROM generate_series(1, 300000) AS s(n);

ANALYZE coin_transactions;

-- 코인내역 페이징 1페이지(20건) — 인덱스(user_id, created_at DESC) 타는지
EXPLAIN ANALYZE
SELECT * FROM coin_transactions WHERE user_id = :uid ORDER BY created_at DESC LIMIT 20;

-- 페이징 COUNT — 대용량에서 얼마나 걸리는지
EXPLAIN ANALYZE
SELECT count(*) FROM coin_transactions WHERE user_id = :uid;

-- 대시보드 캘린더(이번 달) — 인덱스(user_id, check_in_date) 타는지
EXPLAIN ANALYZE
SELECT * FROM personal_check_ins
WHERE user_id = :uid AND check_in_date BETWEEN date_trunc('month', current_date)::date AND current_date;
