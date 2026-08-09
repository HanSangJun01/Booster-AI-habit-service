-- Phase 4b: Social — team chat & cheer emojis
-- BS-22 confirmed schema

CREATE TABLE chat_messages (
    id          BIGSERIAL PRIMARY KEY,
    team_id     BIGINT          NOT NULL,
    sender_id   BIGINT          NOT NULL,
    content     TEXT            NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_chat_messages_team_id_created_at ON chat_messages (team_id, created_at DESC);

CREATE TABLE cheer_emojis (
    id                   BIGSERIAL PRIMARY KEY,
    challenge_id         BIGINT          NOT NULL,
    from_participant_id  BIGINT          NOT NULL,
    to_participant_id    BIGINT          NOT NULL,
    emoji_type           VARCHAR(50)     NOT NULL,
    created_at           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT cheer_not_self CHECK (from_participant_id <> to_participant_id)
);

CREATE INDEX idx_cheer_emojis_challenge_id ON cheer_emojis (challenge_id);
