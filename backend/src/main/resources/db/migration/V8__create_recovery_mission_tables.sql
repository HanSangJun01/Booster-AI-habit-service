-- A-axis Phase 3: RecoveryMission
-- bs-20 기준. PersonalCheckIn(미인증일)과 1:1 (personal_check_in_id UNIQUE).

CREATE TABLE recovery_missions (
    id                   BIGSERIAL PRIMARY KEY,
    personal_check_in_id BIGINT       NOT NULL UNIQUE REFERENCES personal_check_ins(id),
    user_id              BIGINT       NOT NULL REFERENCES users(id),
    deadline_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    completed_at         TIMESTAMP WITH TIME ZONE,
    status               VARCHAR(20)  NOT NULL
                             CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED')),
    created_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recovery_missions_user_status ON recovery_missions (user_id, status);
CREATE INDEX idx_recovery_missions_status_deadline ON recovery_missions (status, deadline_at);
