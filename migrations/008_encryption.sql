-- ============================================
-- End-to-end encryption keys
-- ============================================

CREATE TABLE IF NOT EXISTS encryption_keys (
    id              SERIAL PRIMARY KEY,
    conversation_id VARCHAR(128) NOT NULL,
    version         SMALLINT NOT NULL DEFAULT 1,
    key_data        TEXT NOT NULL DEFAULT '',
    create_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (conversation_id, version)
);

CREATE INDEX IF NOT EXISTS idx_encryption_keys_conv ON encryption_keys(conversation_id);
