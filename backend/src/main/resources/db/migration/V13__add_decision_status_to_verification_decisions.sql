-- Phase 2 AI 인증 확장 대응:
-- verification_decisions에 판정 진행 상태(PENDING/CONFIRMED) 컬럼 추가 및
-- final_passed를 nullable로 완화한다.
--
-- 배경 (팀 협의 결과):
--   - AI 인증은 지연/실패 가능성이 있어, 체크인 시점에 GPS만으로 최종 판정을
--     확정하면 이후 AI 결과 반영이 어색해진다.
--   - 따라서 verification_type이 AI를 포함하는 경우 체크인 시점엔 결정을
--     PENDING으로 만들어두고, AI 결과 수신 후 최종 확정하는 흐름으로 변경한다.
--
-- 기존 행 영향:
--   - 기 저장된 verification_decisions는 이미 최종 확정된 상태이므로
--     DEFAULT 'CONFIRMED'로 채운다. 기존 데이터/QA 시나리오에 영향 없음.

ALTER TABLE verification_decisions
    ALTER COLUMN final_passed DROP NOT NULL;

ALTER TABLE verification_decisions
    ADD COLUMN decision_status VARCHAR(20) NOT NULL DEFAULT 'CONFIRMED'
        CHECK (decision_status IN ('PENDING', 'CONFIRMED'));

CREATE INDEX idx_verification_decisions_status
    ON verification_decisions(decision_status);
