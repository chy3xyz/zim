-- ============================================
-- Migration 011: Tag system for office module
-- ============================================

CREATE TABLE IF NOT EXISTS tags (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     VARCHAR(64) NOT NULL,
    tag_name    VARCHAR(255) NOT NULL,
    create_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tags_user ON tags(user_id);

CREATE TABLE IF NOT EXISTS tag_members (
    tag_id      UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    user_id     VARCHAR(64) NOT NULL,
    PRIMARY KEY (tag_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_tag_members_tag ON tag_members(tag_id);
CREATE INDEX IF NOT EXISTS idx_tag_members_user ON tag_members(user_id);
