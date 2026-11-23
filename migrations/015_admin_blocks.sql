-- ============================================
-- ADMIN: user blocks + registration toggle (Phase 89)
-- Go open-im-chat aligned admin surface: /block/add|del|search,
-- /user/allow_register (toggle stored in client_configs).
-- ============================================

CREATE TABLE IF NOT EXISTS admin_blocks (
    user_id          VARCHAR(64) PRIMARY KEY,
    reason           VARCHAR(255) NOT NULL DEFAULT '',
    operator_user_id VARCHAR(64) NOT NULL DEFAULT '',
    create_time      BIGINT NOT NULL DEFAULT 0
);
