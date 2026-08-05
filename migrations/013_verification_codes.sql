-- Auth verification codes (DB-backed, survives restarts)
CREATE TABLE IF NOT EXISTS auth_verification_codes (
    target      VARCHAR(255) PRIMARY KEY,
    code        VARCHAR(16)  NOT NULL,
    expire_time BIGINT       NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_verification_expire ON auth_verification_codes(expire_time);
