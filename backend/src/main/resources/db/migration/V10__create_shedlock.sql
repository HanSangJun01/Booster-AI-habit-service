-- [P1 멀티서버] ShedLock 분산 스케줄러 락 테이블.
-- ShedLock 표준 스키마(컬럼명/타입 고정) — 인스턴스 간 @Scheduled 중복 실행 직렬화용.
-- 컬럼은 이미 snake_case(D5 만족). 이 마이그레이션은 테스트에서도 실행된다(Flyway V1..V11).

CREATE TABLE shedlock (
    name       VARCHAR(64)  NOT NULL,
    lock_until TIMESTAMP    NOT NULL,
    locked_at  TIMESTAMP    NOT NULL,
    locked_by  VARCHAR(255) NOT NULL,
    PRIMARY KEY (name)
);
