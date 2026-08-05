-- ============================================
-- User custom commands (process_user_command)
-- ============================================

CREATE TABLE IF NOT EXISTS user_commands (
    id              SERIAL PRIMARY KEY,
    user_id         VARCHAR(64) NOT NULL,
    command_id      VARCHAR(128) NOT NULL,
    command_value   TEXT NOT NULL DEFAULT '',
    create_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, command_id)
);

CREATE INDEX IF NOT EXISTS idx_user_commands_user ON user_commands(user_id);
