-- ============================================
-- Migration 012: Favorite/collect messages + client config
-- ============================================

CREATE TABLE IF NOT EXISTS collects (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     VARCHAR(64) NOT NULL,
    collect_type VARCHAR(32) NOT NULL DEFAULT 'msg',
    content     TEXT NOT NULL DEFAULT '',
    uuid        VARCHAR(128) NOT NULL DEFAULT '',
    create_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_collects_user ON collects(user_id);
CREATE INDEX IF NOT EXISTS idx_collects_type ON collects(user_id, collect_type);

CREATE TABLE IF NOT EXISTS client_configs (
    key         VARCHAR(128) PRIMARY KEY,
    value       TEXT NOT NULL DEFAULT '',
    update_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
