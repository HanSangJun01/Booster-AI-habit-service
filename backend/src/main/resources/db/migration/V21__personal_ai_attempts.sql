-- (BS-41 악용 방어, 개인 트랙) AI 판정 시도 기록.
--
-- 개인 트랙은 AI 가 거절하면 체크인을 삭제해 재시도를 열어주는 설계라(V16),
-- personal_ai_verifications 가 CASCADE 로 함께 지워져 "몇 번 시도했는가"와
-- "어떤 사진을 냈는가"가 남지 않는다. 상한·쿨다운·사진 재사용 차단은 삭제에서
-- 살아남는 기록이 있어야 성립하므로, 체크인과 FK 로 묶지 않는 별도 시도 대장을 둔다.
--
-- 팀 트랙의 대응물은 verification_submissions(시도 이력) + ai_verification_results.image_sha256.
-- 개인 트랙은 제출 테이블이 없으므로 이 한 테이블이 두 역할(회차 카운트 + 이미지 지문)을 겸한다.
--
-- 행은 AI 판정이 실제로 내려진 시도에만 남는다 — ai-service 502 같은 판정 실패는
-- 트랜잭션 롤백으로 기록되지 않아 시도 횟수를 소모하지 않는다.

CREATE TABLE personal_ai_attempts (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT                   NOT NULL REFERENCES users(id),
    attempt_date DATE                     NOT NULL,
    image_sha256 VARCHAR(64)              NOT NULL,
    is_passed    BOOLEAN                  NOT NULL,
    created_at   TIMESTAMP WITH TIME ZONE NOT NULL
);

-- 하루 시도 상한 카운트 경로
CREATE INDEX idx_personal_ai_attempts_user_date
    ON personal_ai_attempts (user_id, attempt_date);

-- 같은 사용자의 사진 재사용 차단 경로
CREATE INDEX idx_personal_ai_attempts_user_sha
    ON personal_ai_attempts (user_id, image_sha256);
