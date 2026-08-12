-- P3: 팀 참여율 동시 갱신(인스턴스 간) Lost Update 방지용 낙관적 락 버전 컬럼.
-- Team 엔티티의 @Version 필드에 매핑된다. 기존 행은 기본값 0으로 채운다.
ALTER TABLE teams ADD COLUMN version BIGINT NOT NULL DEFAULT 0;
