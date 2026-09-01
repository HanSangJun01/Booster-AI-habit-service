-- [개인 목표 카테고리] 개인 습관도 운동/공부 중 하나를 정한다.
--
-- 배경: 팀 챌린지에는 challenges.category 가 있는데 개인 트랙에는 없었다. 그래서 AI 사진 인증을
-- 할 때 앱이 업로드할 때마다 카테고리를 직접 지정해야 했고, 사용자가 "나는 운동 습관을 만든다"는
-- 것을 정해 둘 자리가 없었다. 온보딩에서 목표(운동/공부)를 먼저 고르는 흐름으로 바꾸면서
-- 그 선택을 저장할 곳이 필요해졌다.
--
-- 값 집합은 앱·ai-service 와 같은 2종이다(독서는 공부로 합쳤고, 기상은 사진 판정 기준이 없어 뺐다).
--
-- 즉시 반영: 목표 횟수·인증 장소와 달리 예약제로 두지 않는다. 카테고리를 바꿔도 이번 주 채점
-- 기준(횟수)이나 인증 위치가 흔들리지 않아, 늦춰서 얻을 이득이 없다.
--
-- 기본값 EXERCISE: 이미 쓰고 있는 사용자에게 뭔가를 고르라고 되묻지 않기 위한 값이다.

ALTER TABLE personal_locations
    ADD COLUMN category VARCHAR(20) NOT NULL DEFAULT 'EXERCISE';

ALTER TABLE personal_locations
    ADD CONSTRAINT personal_locations_category_check
        CHECK (category IN ('EXERCISE', 'STUDY'));

COMMENT ON COLUMN personal_locations.category IS '개인 목표 카테고리(EXERCISE/STUDY). AI 사진 판정 기준.';
