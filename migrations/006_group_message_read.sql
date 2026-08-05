-- ============================================
-- Group message read receipts
-- ============================================

CREATE TABLE IF NOT EXISTS group_message_read (
    id              SERIAL PRIMARY KEY,
    conversation_id VARCHAR(128) NOT NULL,
    client_msg_id   VARCHAR(128) NOT NULL,
    user_id         VARCHAR(64) NOT NULL,
    read_time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (conversation_id, client_msg_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_message_read_lookup ON group_message_read(conversation_id, client_msg_id);
CREATE INDEX IF NOT EXISTS idx_group_message_read_user ON group_message_read(conversation_id, user_id);
