//! Admin persistence (Phase 89) — Go open-im-chat aligned admin surface.
//!
//! - `admin_blocks`: banned users (login rejected, sessions force-logged out)
//! - `client_configs.allow_register`: registration toggle ("1"/"0"; absent = allowed)
//!
//! Dual-path zent (docs/zent-migration.md): PK deletes + toggles are single
//! statements via `drv.exec`; reads/list scan via `sql_scan` DTOs.

const std = @import("std");
const core = @import("core");
const zent = @import("zent");
const zent_db = @import("../../zent_db.zig");

pub const BlockInfo = struct {
    user_id: []const u8,
    reason: []const u8,
    operator_user_id: []const u8,
    create_time: i64,
};

/// Joined view for the admin panel: block row + live profile fields
/// (BlockUserInfo camelCase contract is applied by the handler DTO).
pub const BlockUserRow = struct {
    user_id: []const u8,
    reason: []const u8,
    operator_user_id: []const u8,
    create_time: i64,
    nickname: []const u8,
    face_url: []const u8,
    gender: i64,
};

pub fn isBlocked(user_id: []const u8) bool {
    const drv = zent_db.getDriver() orelse return false;
    const row = (zent.sql_scan.queryOne(
        struct { user_id: []const u8 },
        core.getAllocator(),
        drv,
        "SELECT user_id FROM admin_blocks WHERE user_id = $1",
        &.{.{ .string = user_id }},
    ) catch return false) orelse return false;
    return row.user_id.len > 0;
}

pub fn blockUser(user_id: []const u8, reason: []const u8, operator_user_id: []const u8) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    _ = try drv.exec(
        "INSERT INTO admin_blocks (user_id, reason, operator_user_id, create_time) VALUES ($1, $2, $3, $4) ON CONFLICT (user_id) DO UPDATE SET reason = EXCLUDED.reason, operator_user_id = EXCLUDED.operator_user_id",
        &.{ .{ .string = user_id }, .{ .string = reason }, .{ .string = operator_user_id }, .{ .int = core.unixNowSeconds() } },
    );
}

pub fn unblockUser(user_id: []const u8) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    _ = try drv.exec("DELETE FROM admin_blocks WHERE user_id = $1", &.{.{ .string = user_id }});
}

/// Newest-first blocked list joined with user profiles, paginated.
pub fn searchBlocks(allocator: std.mem.Allocator, offset: i64, limit: i64) ![]BlockUserRow {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    var rows = try zent.sql_scan.queryAll(
        BlockUserRow,
        allocator,
        drv,
        "SELECT b.user_id, b.reason, b.operator_user_id, b.create_time, COALESCE(u.nickname, '') AS nickname, COALESCE(u.face_url, '') AS face_url, COALESCE(u.gender, 0) AS gender " ++
            "FROM admin_blocks b LEFT JOIN users u ON b.user_id = u.user_id ORDER BY b.create_time DESC LIMIT $1 OFFSET $2",
        &.{ .{ .int = limit }, .{ .int = offset } },
    );
    return rows.toOwnedSlice();
}

pub fn countBlocks() i64 {
    const drv = zent_db.getDriver() orelse return 0;
    const row = (zent.sql_scan.queryOne(
        struct { total: i64 },
        core.getAllocator(),
        drv,
        "SELECT COUNT(*) AS total FROM admin_blocks",
        &.{},
    ) catch return 0) orelse return 0;
    return row.total;
}

/// Registration toggle stored in client_configs (key absent = allowed).
pub fn getAllowRegister() bool {
    const drv = zent_db.getDriver() orelse return true;
    const row = (zent.sql_scan.queryOne(
        struct { value: []const u8 },
        core.getAllocator(),
        drv,
        "SELECT value FROM client_configs WHERE key = 'allow_register'",
        &.{},
    ) catch return true) orelse return true;
    return !std.mem.eql(u8, row.value, "0");
}

pub fn setAllowRegister(enabled: bool) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    _ = try drv.exec(
        "INSERT INTO client_configs (key, value, update_time) VALUES ('allow_register', $1, NOW()) " ++
            "ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, update_time = NOW()",
        &.{.{ .string = if (enabled) "1" else "0" }},
    );
}

/// True when a users row exists for `user_id`.
pub fn userExists(user_id: []const u8) bool {
    const drv = zent_db.getDriver() orelse return false;
    const row = (zent.sql_scan.queryOne(
        struct { user_id: []const u8 },
        core.getAllocator(),
        drv,
        "SELECT user_id FROM users WHERE user_id = $1",
        &.{.{ .string = user_id }},
    ) catch return false) orelse return false;
    return row.user_id.len > 0;
}

/// Idempotent admin seed: INSERT if missing, then promote to
/// app_manager_level = 1 (covers a pre-existing normal account of the same id).
pub fn ensureAdminUser(user_id: []const u8, password_hash: []const u8) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    _ = try drv.exec(
        "INSERT INTO users (user_id, nickname, face_url, gender, level, birth, area_code, telephone, ex, app_manager_level, global_recv_msg_opt, register_type, password_hash, create_time) " ++
            "VALUES ($1, 'Administrator', '', 1, 1, NULL, '', '', '', 1, 0, 0, $2, NOW()) ON CONFLICT (user_id) DO NOTHING",
        &.{ .{ .string = user_id }, .{ .string = password_hash } },
    );
    _ = try drv.exec(
        "UPDATE users SET app_manager_level = 1, password_hash = $2 WHERE user_id = $1",
        &.{ .{ .string = user_id }, .{ .string = password_hash } },
    );
}
