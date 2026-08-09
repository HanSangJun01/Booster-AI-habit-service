-- Phase 2 확장: AI 사진 인증 결과 저장 (BS-27 정본 네이밍)
-- - verification_submissions와 1:1 관계 (기존 GpsVerificationResult 패턴과 동일)
-- - verification_decisions에 AI 통과 여부를 종합하는 로직은 팀 결정 대기 중이며,
--   결합 규칙 확정 시 별도 마이그레이션(V13)에서 컬럼/제약 추가 예정.
-- - 이미지 원본은 ai-service의 storage 계층이 소유. storage_key로만 참조한다.

CREATE TABLE ai_verification_results (
    id               BIGSERIAL PRIMARY KEY,
    submission_id    BIGINT                   NOT NULL REFERENCES verification_submissions(id),
    model_name       VARCHAR(100)             NOT NULL,
    is_passed        BOOLEAN                  NOT NULL,
    confidence_score NUMERIC(5, 4)            NOT NULL
                         CHECK (confidence_score BETWEEN 0.0 AND 1.0),
    detected_labels  TEXT                     NOT NULL DEFAULT '[]',
    reason           VARCHAR(500),
    storage_key      VARCHAR(500)             NOT NULL,
    raw_response     TEXT,
    created_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_ai_result_per_submission UNIQUE (submission_id)
);

CREATE INDEX idx_ai_verification_results_submission_id
    ON ai_verification_results(submission_id);
