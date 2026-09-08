-- [인증 방식 고정] 개인 트랙 기본값을 GPS 에서 GPS_PHOTO_AI 로 바꾼다.
--
-- 배경: 인증 방식을 "위치 + 사진" 하나로 고정하기로 하고 고를 수 있는 값은 좁혔는데
-- (WeeklyGoalService), personal_locations.verification_type 의 기본값이 'GPS' 로 남아 있었다.
-- 그래서 새로 가입한 사람이 인증 장소만 등록하고 주간 목표를 건드리지 않으면 GPS 단독으로
-- 남아, 사진을 한 번도 요구하지 않는다 — 결정이 실제로는 적용되지 않는 상태였다.
--
-- 기존 행도 함께 옮긴다. 지금은 테스트 계정뿐이고, 남겨 두면 "어떤 사람은 사진을 요구받고
-- 어떤 사람은 아닌" 상태가 계속된다. 실사용자가 생긴 뒤라면 개별 안내가 필요한 변경이다.

ALTER TABLE personal_locations
    ALTER COLUMN verification_type SET DEFAULT 'GPS_PHOTO_AI';

UPDATE personal_locations
SET verification_type = 'GPS_PHOTO_AI'
WHERE verification_type <> 'GPS_PHOTO_AI';

COMMENT ON COLUMN personal_locations.verification_type IS
    '개인 인증 방식. 2026-09 부터 GPS_PHOTO_AI(위치+사진) 하나로 고정.';
