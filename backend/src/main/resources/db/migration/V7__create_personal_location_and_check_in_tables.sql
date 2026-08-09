-- A-axis Phase 2: PersonalLocation / PersonalCheckIn
-- bs-25 기준. 개인 인증 전용 테이블(챌린지 인증과 분리).

CREATE TABLE personal_locations (
    user_id       BIGINT       PRIMARY KEY REFERENCES users(id),
    lat           DOUBLE PRECISION NOT NULL,
    lng           DOUBLE PRECISION NOT NULL,
    radius_meters INT          NOT NULL CHECK (radius_meters > 0),
    place_name    VARCHAR(200),
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE personal_check_ins (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT       NOT NULL REFERENCES users(id),
    check_in_date DATE         NOT NULL,
    status        VARCHAR(20)  NOT NULL
                      CHECK (status IN ('SUCCESS', 'RECOVERY_PENDING', 'FAILED')),
    verified_at   TIMESTAMP WITH TIME ZONE,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_personal_check_in_user_date UNIQUE (user_id, check_in_date)
);

CREATE INDEX idx_personal_check_ins_user_date ON personal_check_ins (user_id, check_in_date);
CREATE INDEX idx_personal_check_ins_date ON personal_check_ins (check_in_date);
