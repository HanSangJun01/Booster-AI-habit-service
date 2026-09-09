-- (악용 방어) 인증 사진 재사용 차단용 지문.
-- 모델은 "운동으로 보이는가"만 알지 "이 사진을 전에 봤는가"는 모른다 — 같은
-- 챌린지 안에서 같은 이미지(바이트 단위 동일)를 다시 내면 AI를 부르기 전에
-- 409 DUPLICATE_IMAGE 로 끊는다. 자기 재사용과 팀원 간 돌려쓰기를 함께 잡는다.
-- 기존 행은 해시가 없으므로 NULL 허용. 크롭·재인코딩 우회는 pHash(지각 해시)
-- 도입 전까지는 모델의 판정에 맡긴다.

ALTER TABLE ai_verification_results
    ADD COLUMN image_sha256 VARCHAR(64);

CREATE INDEX idx_ai_verification_results_image_sha256
    ON ai_verification_results (image_sha256);
