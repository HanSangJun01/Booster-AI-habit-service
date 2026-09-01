-- [인증 위치 변경 예약] 개인 인증 장소를 아무 때나 못 바꾸게 하고, 다음 달 1일부터 반영한다.
--
-- 배경: PUT /api/users/me/location 이 언제든 즉시 반영돼서, 인증 직전에 지금 있는 자리로
-- 장소를 옮기면 어디서든 통과할 수 있었다. 반경 상한(GpsPolicy)을 둬도 장소 자체를 옮길 수
-- 있으면 위치 인증의 의미가 없다.
--
-- 설계: 주간 목표(pending_target_days)와 똑같은 예약 방식을 쓴다. 이 둘은 한 세트로 움직인다 —
-- "이번 달의 내 목표와 내 장소"를 정하고, 바꾸고 싶으면 다음 달 1일부터 적용된다.
--   · 최초 등록(POST)은 예약 없이 즉시 반영한다. 아직 이번 달 기준이 없는 상태라 묶을 게 없다.
--   · 변경(PUT)은 pending_* 에 담아두고, 월초에 RecoveryTicketService.runMonthly 가 승격한다
--     (무료 구제권 지급과 같은 멱등 키를 공유하므로 한 달에 정확히 한 번만 적용된다).
--
-- 네 컬럼은 항상 한 벌로 채워지거나 한 벌로 비어 있다. 좌표만 있고 반경이 없으면 반경 0인
-- 장소가 되어 아무 데서도 인증이 안 되므로, CHECK 로 부분 예약을 막는다.

ALTER TABLE personal_locations
    ADD COLUMN pending_lat           DOUBLE PRECISION,
    ADD COLUMN pending_lng           DOUBLE PRECISION,
    ADD COLUMN pending_radius_meters INT,
    ADD COLUMN pending_place_name    VARCHAR(200);

ALTER TABLE personal_locations
    ADD CONSTRAINT personal_locations_pending_location_all_or_none
        CHECK (
            (pending_lat IS NULL AND pending_lng IS NULL AND pending_radius_meters IS NULL)
            OR
            (pending_lat IS NOT NULL AND pending_lng IS NOT NULL AND pending_radius_meters IS NOT NULL)
        );

-- 반경 상·하한은 애플리케이션(GpsPolicy)과 같은 값으로 DB 에서도 막는다. 예약 값이 상한을
-- 넘으면 승격되는 순간 인증이 무력화되므로, 예약 시점에 걸러야 한다.
ALTER TABLE personal_locations
    ADD CONSTRAINT personal_locations_pending_radius_range
        CHECK (pending_radius_meters IS NULL
               OR (pending_radius_meters >= 10 AND pending_radius_meters <= 1000));

COMMENT ON COLUMN personal_locations.pending_lat IS '변경 예약된 위도. 다음 달 1일에 lat 으로 승격.';
COMMENT ON COLUMN personal_locations.pending_lng IS '변경 예약된 경도.';
COMMENT ON COLUMN personal_locations.pending_radius_meters IS '변경 예약된 반경(m).';
COMMENT ON COLUMN personal_locations.pending_place_name IS '변경 예약된 장소 이름.';
