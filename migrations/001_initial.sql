-- ============================================
-- ZIM Server - Complete PostgreSQL Schema
-- Based on OpenIM Server enterprise edition
-- ============================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- pgmq is optional: queue features need it, but the server must still start
-- without it (queue module degrades gracefully).
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS "pgmq";
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pgmq extension unavailable — queue features disabled';
END $$;

-- ============================================
-- USERS
-- ============================================
CREATE TABLE IF NOT EXISTS users (
    user_id          VARCHAR(64) PRIMARY KEY,
    nickname         VARCHAR(255) NOT NULL DEFAULT '',
    face_url         VARCHAR(1024) NOT NULL DEFAULT '',
    gender           SMALLINT NOT NULL DEFAULT 0,
    level            SMALLINT NOT NULL DEFAULT 0,
    birth            TIMESTAMPTZ,
    area_code        VARCHAR(8) NOT NULL DEFAULT '',
    telephone        VARCHAR(32) NOT NULL DEFAULT '',
    ex               TEXT NOT NULL DEFAULT '',
    app_manager_level SMALLINT NOT NULL DEFAULT 0,
    global_recv_msg_opt SMALLINT NOT NULL DEFAULT 0,
    register_type    SMALLINT NOT NULL DEFAULT 0,
    create_time      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_create_time ON users(create_time);
CREATE INDEX IF NOT EXISTS idx_users_nickname ON users(nickname);

-- ============================================
-- USER ONLINE STATUS
-- ============================================
CREATE TABLE IF NOT EXISTS user_online_status (
    user_id         VARCHAR(64) PRIMARY KEY,
    platform_id     SMALLINT NOT NULL DEFAULT 0,
    status          SMALLINT NOT NULL DEFAULT 0,
    conn_id         VARCHAR(64) NOT NULL DEFAULT '',
    is_background   BOOLEAN NOT NULL DEFAULT FALSE,
    token           TEXT NOT NULL DEFAULT '',
    platform        VARCHAR(32) NOT NULL DEFAULT '',
    last_seen       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_user_online_status_platform ON user_online_status(user_id, platform_id);

-- ============================================
-- AUTH TOKENS
-- ============================================
CREATE TABLE IF NOT EXISTS auth_tokens (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(64) NOT NULL REFERENCES users(user_id),
    token           TEXT NOT NULL,
    platform_id     SMALLINT NOT NULL DEFAULT 0,
    expire_time     TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_user ON auth_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_token ON auth_tokens(token);

-- ============================================
-- CONVERSATIONS (per-user conversation records)
-- ============================================
CREATE TABLE IF NOT EXISTS conversations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_user_id       VARCHAR(64) NOT NULL,
    conversation_id     VARCHAR(128) NOT NULL,
    conversation_type   SMALLINT NOT NULL DEFAULT 0,
    user_id             VARCHAR(64) NOT NULL DEFAULT '',
    group_id            VARCHAR(128) NOT NULL DEFAULT '',
    recv_msg_opt        SMALLINT NOT NULL DEFAULT 0,
    is_pinned           BOOLEAN NOT NULL DEFAULT FALSE,
    is_private_chat     BOOLEAN NOT NULL DEFAULT FALSE,
    burn_duration       INTEGER NOT NULL DEFAULT 30,
    group_at_type       SMALLINT NOT NULL DEFAULT 0,
    attached_info       TEXT NOT NULL DEFAULT '',
    ex                  TEXT NOT NULL DEFAULT '',
    max_seq             BIGINT NOT NULL DEFAULT 0,
    min_seq             BIGINT NOT NULL DEFAULT 0,
    has_read_seq        BIGINT NOT NULL DEFAULT 0,
    latest_msg          TEXT NOT NULL DEFAULT '',
    latest_msg_send_time BIGINT NOT NULL DEFAULT 0,
    latest_msg_send_id  VARCHAR(64) NOT NULL DEFAULT '',
    latest_msg_content_type SMALLINT NOT NULL DEFAULT 0,
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    update_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_msg_destruct     BOOLEAN NOT NULL DEFAULT FALSE,
    msg_destruct_time   BIGINT NOT NULL DEFAULT 0,
    latest_msg_destruct_time TIMESTAMPTZ,
    UNIQUE(owner_user_id, conversation_id)
);
CREATE INDEX IF NOT EXISTS idx_conversations_owner ON conversations(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_type ON conversations(conversation_type);
CREATE INDEX IF NOT EXISTS idx_conversations_update_time ON conversations(update_time);

-- ============================================
-- SEQ TRACKING (for message sequencing)
-- ============================================
CREATE TABLE IF NOT EXISTS seq_conversations (
    conversation_id   VARCHAR(128) PRIMARY KEY,
    max_seq           BIGINT NOT NULL DEFAULT 0,
    min_seq           BIGINT NOT NULL DEFAULT 0,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User-level seq for incremental sync
CREATE TABLE IF NOT EXISTS seq_users (
    user_id           VARCHAR(64) NOT NULL,
    conversation_id   VARCHAR(128) NOT NULL,
    has_read_seq      BIGINT NOT NULL DEFAULT 0,
    seq               BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, conversation_id)
);

-- ============================================
-- MESSAGES
-- ============================================
CREATE TABLE IF NOT EXISTS messages (
    msg_id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id   VARCHAR(128) NOT NULL,
    sender_id         VARCHAR(64) NOT NULL,
    receiver_id       VARCHAR(64) NOT NULL DEFAULT '',
    group_id          VARCHAR(128) NOT NULL DEFAULT '',
    client_msg_id     VARCHAR(128) NOT NULL,
    server_msg_id     VARCHAR(128) NOT NULL DEFAULT '',
    sender_platform_id SMALLINT NOT NULL DEFAULT 0,
    sender_nickname   VARCHAR(255) NOT NULL DEFAULT '',
    sender_face_url   VARCHAR(1024) NOT NULL DEFAULT '',
    session_type      SMALLINT NOT NULL DEFAULT 0,
    msg_from          SMALLINT NOT NULL DEFAULT 0,
    content_type      SMALLINT NOT NULL DEFAULT 0,
    content           TEXT NOT NULL,
    seq               BIGINT NOT NULL DEFAULT 0,
    send_time         BIGINT NOT NULL DEFAULT 0,
    create_time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status            SMALLINT NOT NULL DEFAULT 0,
    is_read           BOOLEAN NOT NULL DEFAULT FALSE,
    options           JSONB DEFAULT '{}',
    offline_push      JSONB DEFAULT '{}',
    at_user_id_list   JSONB DEFAULT '[]',
    attached_info     TEXT NOT NULL DEFAULT '',
    ex                TEXT NOT NULL DEFAULT '',
    key_version       SMALLINT NOT NULL DEFAULT 0,
    is_revoke         BOOLEAN NOT NULL DEFAULT FALSE,
    revoke_content    TEXT NOT NULL DEFAULT '',
    UNIQUE(conversation_id, client_msg_id)
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_seq ON messages(conversation_id, seq);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_send_time ON messages(send_time);
CREATE INDEX IF NOT EXISTS idx_messages_client_msg_id ON messages(client_msg_id);

-- ============================================
-- GROUPS
-- ============================================
CREATE TABLE IF NOT EXISTS groups (
    group_id              VARCHAR(128) PRIMARY KEY,
    group_name            VARCHAR(255) NOT NULL DEFAULT '',
    notification          TEXT NOT NULL DEFAULT '',
    introduction          TEXT NOT NULL DEFAULT '',
    face_url              VARCHAR(1024) NOT NULL DEFAULT '',
    ex                    TEXT NOT NULL DEFAULT '',
    status                SMALLINT NOT NULL DEFAULT 0,
    creator_user_id       VARCHAR(64) NOT NULL DEFAULT '',
    group_type            SMALLINT NOT NULL DEFAULT 0,
    need_verification     SMALLINT NOT NULL DEFAULT 0,
    look_member_info      SMALLINT NOT NULL DEFAULT 0,
    apply_member_friend   SMALLINT NOT NULL DEFAULT 0,
    notification_update_time TIMESTAMPTZ,
    notification_user_id  VARCHAR(64) NOT NULL DEFAULT '',
    display_is_read       BOOLEAN NOT NULL DEFAULT FALSE,
    create_time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_groups_creator ON groups(creator_user_id);
CREATE INDEX IF NOT EXISTS idx_groups_status ON groups(status);
CREATE INDEX IF NOT EXISTS idx_groups_type ON groups(group_type);
CREATE INDEX IF NOT EXISTS idx_groups_create_time ON groups(create_time);

-- ============================================
-- GROUP MEMBERS
-- ============================================
CREATE TABLE IF NOT EXISTS group_members (
    id                  UUID DEFAULT uuid_generate_v4(),
    group_id            VARCHAR(128) NOT NULL REFERENCES groups(group_id),
    user_id             VARCHAR(64) NOT NULL,
    nickname            VARCHAR(255) NOT NULL DEFAULT '',
    face_url            VARCHAR(1024) NOT NULL DEFAULT '',
    role_level          SMALLINT NOT NULL DEFAULT 0,
    join_time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    join_source         SMALLINT NOT NULL DEFAULT 0,
    inviter_user_id     VARCHAR(64) NOT NULL DEFAULT '',
    operator_user_id    VARCHAR(64) NOT NULL DEFAULT '',
    mute_end_time       TIMESTAMPTZ,
    ex                  TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (group_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_role ON group_members(group_id, role_level);

-- ============================================
-- GROUP REQUESTS (join applications)
-- ============================================
CREATE TABLE IF NOT EXISTS group_requests (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             VARCHAR(64) NOT NULL,
    group_id            VARCHAR(128) NOT NULL REFERENCES groups(group_id),
    handle_result       SMALLINT NOT NULL DEFAULT 0,
    req_msg             TEXT NOT NULL DEFAULT '',
    handled_msg         TEXT NOT NULL DEFAULT '',
    req_time            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    handle_user_id      VARCHAR(64) NOT NULL DEFAULT '',
    handled_time        TIMESTAMPTZ,
    join_source         SMALLINT NOT NULL DEFAULT 0,
    inviter_user_id     VARCHAR(64) NOT NULL DEFAULT '',
    ex                  TEXT NOT NULL DEFAULT '',
    UNIQUE(user_id, group_id)
);
CREATE INDEX IF NOT EXISTS idx_group_requests_user ON group_requests(user_id, handle_result);
CREATE INDEX IF NOT EXISTS idx_group_requests_group ON group_requests(group_id, handle_result);

-- ============================================
-- FRIENDS
-- ============================================
CREATE TABLE IF NOT EXISTS friends (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_user_id       VARCHAR(64) NOT NULL,
    friend_user_id      VARCHAR(64) NOT NULL,
    remark              VARCHAR(255) NOT NULL DEFAULT '',
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    add_source          SMALLINT NOT NULL DEFAULT 0,
    operator_user_id    VARCHAR(64) NOT NULL DEFAULT '',
    ex                  TEXT NOT NULL DEFAULT '',
    is_pinned           BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE(owner_user_id, friend_user_id)
);
CREATE INDEX IF NOT EXISTS idx_friends_owner ON friends(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_friends_friend ON friends(friend_user_id);
CREATE INDEX IF NOT EXISTS idx_friends_create_time ON friends(create_time);

-- ============================================
-- FRIEND REQUESTS
-- ============================================
CREATE TABLE IF NOT EXISTS friend_requests (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    from_user_id        VARCHAR(64) NOT NULL,
    to_user_id          VARCHAR(64) NOT NULL,
    handle_result       SMALLINT NOT NULL DEFAULT 0,
    req_msg             TEXT NOT NULL DEFAULT '',
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    handler_user_id     VARCHAR(64) NOT NULL DEFAULT '',
    handle_msg          TEXT NOT NULL DEFAULT '',
    handle_time         TIMESTAMPTZ,
    ex                  TEXT NOT NULL DEFAULT '',
    UNIQUE(from_user_id, to_user_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_requests_from ON friend_requests(from_user_id, handle_result);
CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_user_id, handle_result);

-- ============================================
-- BLACKLIST
-- ============================================
CREATE TABLE IF NOT EXISTS blacks (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_user_id       VARCHAR(64) NOT NULL,
    block_user_id       VARCHAR(64) NOT NULL,
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    add_source          SMALLINT NOT NULL DEFAULT 0,
    operator_user_id    VARCHAR(64) NOT NULL DEFAULT '',
    ex                  TEXT NOT NULL DEFAULT '',
    UNIQUE(owner_user_id, block_user_id)
);
CREATE INDEX IF NOT EXISTS idx_blacks_owner ON blacks(owner_user_id);

-- ============================================
-- SUBSCRIBE USERS (for online status subscription)
-- ============================================
CREATE TABLE IF NOT EXISTS subscribe_users (
    user_id             VARCHAR(64) PRIMARY KEY,
    user_id_list        JSONB NOT NULL DEFAULT '[]',
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- MESSAGE GROUP READ (read receipts for group messages)
-- ============================================
CREATE TABLE IF NOT EXISTS msg_group_read (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id     VARCHAR(128) NOT NULL,
    msg_seq             BIGINT NOT NULL,
    user_id             VARCHAR(64) NOT NULL,
    read_time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(conversation_id, msg_seq, user_id)
);
CREATE INDEX IF NOT EXISTS idx_msg_group_read_conversation ON msg_group_read(conversation_id, msg_seq);

-- ============================================
-- PINNED MESSAGES
-- ============================================
CREATE TABLE IF NOT EXISTS msg_pinned (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id     VARCHAR(128) NOT NULL,
    msg_seq             BIGINT NOT NULL,
    user_id             VARCHAR(64) NOT NULL,
    pin_time            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_time           TIMESTAMPTZ,
    UNIQUE(conversation_id, msg_seq, user_id)
);
CREATE INDEX IF NOT EXISTS idx_msg_pinned_conversation ON msg_pinned(conversation_id);

-- ============================================
-- USER COMMANDS (custom user data)
-- ============================================
CREATE TABLE IF NOT EXISTS user_commands (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             VARCHAR(64) NOT NULL,
    type                INTEGER NOT NULL,
    uuid                VARCHAR(128) NOT NULL,
    value               TEXT NOT NULL DEFAULT '',
    ex                  TEXT NOT NULL DEFAULT '',
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, type, uuid)
);
CREATE INDEX IF NOT EXISTS idx_user_commands_user ON user_commands(user_id, type);

-- ============================================
-- NOTIFICATION ACCOUNTS
-- ============================================
CREATE TABLE IF NOT EXISTS notification_accounts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             VARCHAR(64) NOT NULL UNIQUE,
    nickname            VARCHAR(255) NOT NULL DEFAULT '',
    face_url            VARCHAR(1024) NOT NULL DEFAULT '',
    ex                  TEXT NOT NULL DEFAULT '',
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
