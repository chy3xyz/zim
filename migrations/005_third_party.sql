-- ============================================
-- Third-party services tables
-- RustFS object storage, FCM tokens, app logs, webhook events
-- ============================================

-- FCM push tokens
CREATE TABLE IF NOT EXISTS fcm_tokens (
    id          SERIAL PRIMARY KEY,
    user_id     VARCHAR(64) NOT NULL,
    platform_id SMALLINT NOT NULL DEFAULT 0,
    fcm_token   TEXT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, platform_id)
);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user ON fcm_tokens(user_id);

-- App logs uploaded by clients
CREATE TABLE IF NOT EXISTS app_logs (
    id          SERIAL PRIMARY KEY,
    user_id     VARCHAR(64) NOT NULL,
    platform    SMALLINT NOT NULL DEFAULT 0,
    file_url    TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_app_logs_user ON app_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_app_logs_created ON app_logs(created_at);

-- Webhook events queue
CREATE TABLE IF NOT EXISTS webhook_events (
    id          SERIAL PRIMARY KEY,
    event_type  VARCHAR(64) NOT NULL,
    payload     TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered   BOOLEAN NOT NULL DEFAULT FALSE,
    delivered_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_webhook_events_delivered ON webhook_events(delivered, created_at);
