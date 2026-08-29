-- [개인 트랙 AI 인증] 개인 습관에도 GPS / AI / GPS+AI 를 선택할 수 있게 한다.
--
-- 배경: 팀 챌린지는 challenges.verification_type 으로 GPS / AI / GPS_PHOTO_AI 를 고를 수 있는데,
-- 개인 습관은 GPS 고정이었다. 제출·판정 테이블이 개인 쪽에 아예 없어 사진을 붙일 자리가 없었기 때문이다.
-- (BS-27 에서 "verification-submissions 의 소유 축과 호출 흐름은 별도 확정이 필요하다" 로 미뤄둔 항목)
--
-- 설계: 팀 쪽 구조를 그대로 복제하지 않는다. 개인 체크인은 (user_id, date) 로 하루 1건이 유니크하고
-- 재시도 이력을 남길 이유가 없으므로, 제출 테이블 없이 체크인에 AI 결과를 1:1 로 붙인다.
--   팀   check_in → submissions(N) → gps_results / ai_results → decisions
--   개인 check_in → ai_verification(1)
--
-- 흐름:
--   GPS          체크인 즉시 SUCCESS (기존과 동일)
--   AI           체크인 시 PENDING → 사진 업로드로 확정
--   GPS_PHOTO_AI GPS 통과해야 PENDING → 사진 업로드로 확정 (GPS 실패는 400 즉시 거절)

-- 1) 개인 목표에 인증 방식 -----------------------------------------------------
-- 팀의 challenges.verification_type 과 같은 값 집합을 쓰되, 실제 지원하는 3종으로 제한한다.
ALTER TABLE personal_locations
    ADD COLUMN verification_type VARCHAR(20) NOT NULL DEFAULT 'GPS'
        CHECK (verification_type IN ('GPS', 'AI', 'GPS_PHOTO_AI'));

-- 2) 체크인에 PENDING 상태 추가 ------------------------------------------------
-- AI 를 쓰는 목표는 사진이 올라올 때까지 확정을 유보한다.
-- (V14 에서 SUCCESS 하나로 좁혔던 것을 AI 대응으로 다시 넓힌다)
ALTER TABLE personal_check_ins
    DROP CONSTRAINT personal_check_ins_status_check;

ALTER TABLE personal_check_ins
    ADD CONSTRAINT personal_check_ins_status_check
    CHECK (status IN ('SUCCESS', 'PENDING'));

-- 3) 개인 AI 판정 결과 ---------------------------------------------------------
-- 체크인과 1:1. 이미지 원본은 ai-service 의 storage 계층이 소유하고 storage_key 로만 참조한다.
CREATE TABLE personal_ai_verifications (
    id                    BIGSERIAL PRIMARY KEY,
    personal_check_in_id  BIGINT                   NOT NULL UNIQUE
                              REFERENCES personal_check_ins(id) ON DELETE CASCADE,
    model_name            VARCHAR(100)             NOT NULL,
    is_passed             BOOLEAN                  NOT NULL,
    confidence_score      NUMERIC(5, 4)            NOT NULL
                              CHECK (confidence_score BETWEEN 0.0 AND 1.0),
    detected_labels       TEXT                     NOT NULL DEFAULT '[]',
    reason                VARCHAR(500),
    storage_key           VARCHAR(500)             NOT NULL,
    created_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_personal_ai_verifications_check_in
    ON personal_ai_verifications (personal_check_in_id);
