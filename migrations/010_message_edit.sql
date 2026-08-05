-- ============================================
-- Migration 010: Add message editing support
-- ============================================

ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_edit BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS edit_time TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_messages_is_edit ON messages(conversation_id, is_edit);
