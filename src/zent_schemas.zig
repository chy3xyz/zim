//! zent schema definitions (pilot: `users`).
//!
//! Schema-as-code mirrors of zim's existing PostgreSQL tables (see
//! `migrations/001_initial.sql`). The zent client generates SELECTs with an
//! explicit column list, so columns present in the table but not declared
//! here (e.g. `birth`/`create_time` TIMESTAMPTZ) are simply never selected —
//! the migration itself stays the source of truth for DDL.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const User = Schema("User", .{
    .table_name = "users",
    .pk = "user_id",
    .fields = &.{
        field.String("user_id"),
        field.String("nickname").Default(""),
        field.String("face_url").Default(""),
        field.Int("gender").Default(0),
        field.Int("level").Default(0),
        field.String("area_code").Default(""),
        field.String("telephone").Default(""),
        field.String("ex").Default(""),
        field.Int("app_manager_level").Default(0),
        field.Int("global_recv_msg_opt").Default(0),
        field.Int("register_type").Default(0),
    },
});

/// `collects` (favorite messages) — UUID pk as string; `create_time`
/// (TIMESTAMPTZ) stays undeclared: reads/writes of the epoch field go
/// through sql_scan DTO queries with `EXTRACT(EPOCH ...)::bigint AS
/// create_time`, which is also why this schema only backs the entity
/// delete path.
pub const Collect = Schema("Collect", .{
    .table_name = "collects",
    .pk = "id",
    .fields = &.{
        field.String("id"),
        field.String("user_id"),
        field.String("collect_type").Default("msg"),
        field.String("content").Default(""),
        field.String("uuid").Default(""),
    },
});

/// `conversations` (per-user conversation records) — business key is the
/// UNIQUE (owner_user_id, conversation_id) pair, which the typed upsert
/// (`SaveOrUpdateOnWith`) targets. `create_time`/`update_time`
/// (TIMESTAMPTZ, NOW() defaults) and `latest_msg_destruct_time` (nullable,
/// unused by the app model) stay undeclared — epochs are read through
/// sql_scan DTO queries with `EXTRACT(EPOCH ...)::bigint` aliases.
pub const Conversation = Schema("Conversation", .{
    .table_name = "conversations",
    .pk = "id",
    .fields = &.{
        field.String("id"),
        field.String("owner_user_id"),
        field.String("conversation_id"),
        field.Int("conversation_type").Default(0),
        field.String("user_id").Default(""),
        field.String("group_id").Default(""),
        field.Int("recv_msg_opt").Default(0),
        field.Bool("is_pinned").Default(false),
        field.Bool("is_private_chat").Default(false),
        field.Int("burn_duration").Default(30),
        field.Int("group_at_type").Default(0),
        field.String("attached_info").Default(""),
        field.String("ex").Default(""),
        field.Int("max_seq").Default(0),
        field.Int("min_seq").Default(0),
        field.Int("has_read_seq").Default(0),
        field.String("latest_msg").Default(""),
        field.Int("latest_msg_send_time").Default(0),
        field.String("latest_msg_send_id").Default(""),
        field.Int("latest_msg_content_type").Default(0),
        field.Bool("is_msg_destruct").Default(false),
        field.Int("msg_destruct_time").Default(0),
    },
});

pub const all = &.{ User, Collect, Conversation };
