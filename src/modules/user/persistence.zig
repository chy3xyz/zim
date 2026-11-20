const std = @import("std");
const db_mod = @import("../../modules/db_postgres.zig");
const zent = @import("zent");
const zent_db = @import("../../zent_db.zig");
const model = @import("model.zig");

fn rowToUser(allocator: std.mem.Allocator, row: []const []const u8) !model.User {
    return model.User{
        .user_id = try allocator.dupe(u8, row[0]),
        .nickname = try allocator.dupe(u8, row[1]),
        .face_url = try allocator.dupe(u8, row[2]),
        .gender = try std.fmt.parseInt(i16, row[3], 10),
        .level = try std.fmt.parseInt(i16, row[4], 10),
        .birth = if (row[5].len > 0) try std.fmt.parseInt(i64, row[5], 10) else null,
        .area_code = try allocator.dupe(u8, row[6]),
        .telephone = try allocator.dupe(u8, row[7]),
        .ex = try allocator.dupe(u8, row[8]),
        .app_manager_level = try std.fmt.parseInt(i16, row[9], 10),
        .global_recv_msg_opt = try std.fmt.parseInt(i16, row[10], 10),
        .register_type = try std.fmt.parseInt(i16, row[11], 10),
        .password_hash = try allocator.dupe(u8, row[12]),
        .create_time = try std.fmt.parseInt(i64, row[13], 10),
    };
}

fn rowToUserNoPwd(allocator: std.mem.Allocator, row: []const []const u8) !model.User {
    return model.User{
        .user_id = try allocator.dupe(u8, row[0]),
        .nickname = try allocator.dupe(u8, row[1]),
        .face_url = try allocator.dupe(u8, row[2]),
        .gender = try std.fmt.parseInt(i16, row[3], 10),
        .level = try std.fmt.parseInt(i16, row[4], 10),
        .birth = if (row[5].len > 0) try std.fmt.parseInt(i64, row[5], 10) else null,
        .area_code = try allocator.dupe(u8, row[6]),
        .telephone = try allocator.dupe(u8, row[7]),
        .ex = try allocator.dupe(u8, row[8]),
        .app_manager_level = try std.fmt.parseInt(i16, row[9], 10),
        .global_recv_msg_opt = try std.fmt.parseInt(i16, row[10], 10),
        .register_type = try std.fmt.parseInt(i16, row[11], 10),
        .password_hash = "",
        .create_time = try std.fmt.parseInt(i64, row[12], 10),
    };
}

fn freeResult(allocator: std.mem.Allocator, result: db_mod.QueryResult) void {
    for (result.rows) |row| {
        for (row) |cell| allocator.free(cell);
        _ = allocator.free(row);
    }
    _ = allocator.free(result.rows);
}

pub const UserPersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) UserPersistence {
        return .{ .allocator = allocator, .db = db };
    }

    // ── Users ─────────────────────────────────────────────────────

    pub fn create(self: *UserPersistence, input: model.UserCreateInput, password_hash: []const u8) !model.User {
        const user_id = input.user_id orelse try model.generateUserID(self.allocator);

        const sql = "INSERT INTO users (user_id, nickname, face_url, gender, level, birth, area_code, telephone, ex, app_manager_level, global_recv_msg_opt, register_type, password_hash, create_time)" ++
            " VALUES ($1, $2, $3, $4, 1, NULL, $5, $6, $7, $8, $9, 0, $10, NOW())" ++
            " RETURNING user_id, nickname, face_url, gender, level, birth, area_code, telephone, ex, app_manager_level, global_recv_msg_opt, register_type, password_hash, EXTRACT(EPOCH FROM create_time)::bigint";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .string = input.nickname },
            .{ .string = input.face_url orelse "" },
            .{ .smallint = input.gender },
            .{ .string = input.area_code },
            .{ .string = input.telephone },
            .{ .string = input.ex },
            .{ .smallint = input.app_manager_level },
            .{ .smallint = input.global_recv_msg_opt },
            .{ .string = password_hash },
        };
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return error.InsertFailed;
        return try rowToUser(self.allocator, result.rows[0]);
    }

    pub fn get(self: *UserPersistence, user_id: []const u8) !?model.User {
        const sql = "SELECT user_id, nickname, face_url, gender, level, birth, area_code, telephone, ex, app_manager_level, global_recv_msg_opt, register_type, password_hash, EXTRACT(EPOCH FROM create_time)::bigint FROM users WHERE user_id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = self.db.queryParams(sql, params) catch return null;
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return null;
        return try rowToUser(self.allocator, result.rows[0]);
    }

    pub fn getByTelephone(self: *UserPersistence, telephone: []const u8) !?model.User {
        const sql = "SELECT user_id, nickname, face_url, gender, level, birth, area_code, telephone, ex, app_manager_level, global_recv_msg_opt, register_type, password_hash, EXTRACT(EPOCH FROM create_time)::bigint FROM users WHERE telephone = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = telephone }};
        const result = self.db.queryParams(sql, params) catch return null;
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return null;
        return try rowToUser(self.allocator, result.rows[0]);
    }

    pub fn update(self: *UserPersistence, user_id: []const u8, input: model.UserUpdateInput) !?model.User {
        var set_parts = std.ArrayList([]const u8).empty;
        defer set_parts.deinit(self.allocator);
        var params = std.ArrayList(db_mod.QueryParam).empty;
        defer params.deinit(self.allocator);
        var idx: i32 = 1;

        if (input.nickname) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "nickname = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.face_url) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "face_url = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.gender) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "gender = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }
        if (input.birth) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "birth = ${d}", .{idx}));
            try params.append(self.allocator, .{ .bigint = v });
            idx += 1;
        }
        if (input.area_code) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "area_code = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.telephone) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "telephone = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.ex) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ex = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.global_recv_msg_opt) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "global_recv_msg_opt = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }

        if (set_parts.items.len == 0) return self.get(user_id);

        try set_parts.append(self.allocator, "updated_at = NOW()");
        var set_clause = std.ArrayList(u8).empty;
        defer set_clause.deinit(self.allocator);
        for (set_parts.items, 0..) |part, i| {
            if (i > 0) try set_clause.appendSlice(self.allocator, ", ");
            try set_clause.appendSlice(self.allocator, part);
        }

        const sql = try std.fmt.allocPrint(self.allocator, "UPDATE users SET {s} WHERE user_id = ${d}", .{ set_clause.items, idx });
        defer self.allocator.free(sql);
        try params.append(self.allocator, .{ .string = user_id });

        _ = try self.db.execParams(sql, params.items);
        return self.get(user_id);
    }

    pub fn updatePassword(self: *UserPersistence, user_id: []const u8, password_hash: []const u8) !bool {
        const sql = "UPDATE users SET password_hash = $1, updated_at = NOW() WHERE user_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = password_hash }, .{ .string = user_id } };
        const r = try self.db.execParams(sql, params);
        return r > 0;
    }

    pub fn delete(self: *UserPersistence, user_id: []const u8) bool {
        // Atomic cascade: user + tokens + friendships + requests + blacks +
        // conversations + commands + online status.
        if (zent_db.getDriver()) |drv| {
            var ztx = zent.codegen.beginTxFromDriver(zent_db.schema_infos, drv, zent_db.getAllocator()) catch return false;
            defer ztx.deinit();
            errdefer ztx.rollback() catch {};
            const adapter = zent_db.LegacyExecAdapter{ .drv = ztx.tx, .alloc = self.allocator };
            _ = adapter.execParams("DELETE FROM auth_tokens WHERE user_id = $1", &.{.{ .string = user_id }}) catch return false;
            _ = adapter.execParams("DELETE FROM friends WHERE owner_user_id = $1 OR friend_user_id = $1", &.{.{ .string = user_id }}) catch return false;
            _ = adapter.execParams("DELETE FROM friend_requests WHERE from_user_id = $1 OR to_user_id = $1", &.{.{ .string = user_id }}) catch return false;
            _ = adapter.execParams("DELETE FROM blacks WHERE owner_user_id = $1 OR block_user_id = $1", &.{.{ .string = user_id }}) catch return false;
            _ = adapter.execParams("DELETE FROM conversations WHERE owner_user_id = $1", &.{.{ .string = user_id }}) catch return false;
            _ = adapter.execParams("DELETE FROM user_commands WHERE user_id = $1", &.{.{ .string = user_id }}) catch return false;
            _ = adapter.execParams("DELETE FROM user_online_status WHERE user_id = $1", &.{.{ .string = user_id }}) catch return false;
            _ = adapter.execParams("DELETE FROM users WHERE user_id = $1", &.{.{ .string = user_id }}) catch return false;
            ztx.commit() catch return false;
            return true;
        }
        var tx = self.db.begin() catch return false;
        errdefer tx.rollback();
        _ = tx.execParams("DELETE FROM auth_tokens WHERE user_id = $1", &.{.{ .string = user_id }}) catch return false;
        _ = tx.execParams("DELETE FROM friends WHERE owner_user_id = $1 OR friend_user_id = $1", &.{.{ .string = user_id }}) catch return false;
        _ = tx.execParams("DELETE FROM friend_requests WHERE from_user_id = $1 OR to_user_id = $1", &.{.{ .string = user_id }}) catch return false;
        _ = tx.execParams("DELETE FROM blacks WHERE owner_user_id = $1 OR block_user_id = $1", &.{.{ .string = user_id }}) catch return false;
        _ = tx.execParams("DELETE FROM conversations WHERE owner_user_id = $1", &.{.{ .string = user_id }}) catch return false;
        _ = tx.execParams("DELETE FROM user_commands WHERE user_id = $1", &.{.{ .string = user_id }}) catch return false;
        _ = tx.execParams("DELETE FROM user_online_status WHERE user_id = $1", &.{.{ .string = user_id }}) catch return false;
        _ = tx.execParams("DELETE FROM users WHERE user_id = $1", &.{.{ .string = user_id }}) catch return false;
        tx.commit() catch return false;
        return true;
    }

    pub fn search(self: *UserPersistence, query: []const u8, limit: u32) ![]model.User {
        const pattern = try std.fmt.allocPrint(self.allocator, "%{s}%", .{query});
        defer self.allocator.free(pattern);
        const sql = "SELECT user_id, nickname, face_url, gender, level, birth, area_code, telephone, ex, app_manager_level, global_recv_msg_opt, register_type, EXTRACT(EPOCH FROM create_time)::bigint FROM users WHERE nickname LIKE $1 OR user_id LIKE $1 LIMIT $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = pattern }, .{ .int = limit } };
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);

        var list = std.ArrayList(model.User).empty;
        defer list.deinit(self.allocator);
        for (result.rows) |row| {
            try list.append(self.allocator, try rowToUserNoPwd(self.allocator, row));
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn count(self: *UserPersistence) usize {
        const sql = "SELECT COUNT(*) FROM users";
        const result = self.db.query(sql) catch return 0;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(usize, result.rows[0][0], 10) catch 0;
    }

    pub fn countSince(self: *UserPersistence, start_time: i64, end_time: i64) usize {
        const sql = "SELECT COUNT(*) FROM users WHERE EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2";
        const params = &[_]db_mod.QueryParam{ .{ .bigint = start_time }, .{ .bigint = end_time } };
        const result = self.db.queryParams(sql, params) catch return 0;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(usize, result.rows[0][0], 10) catch 0;
    }

    pub fn countBefore(self: *UserPersistence, start_time: i64) usize {
        const sql = "SELECT COUNT(*) FROM users WHERE EXTRACT(EPOCH FROM create_time)::bigint < $1";
        const params = &[_]db_mod.QueryParam{.{ .bigint = start_time }};
        const result = self.db.queryParams(sql, params) catch return 0;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(usize, result.rows[0][0], 10) catch 0;
    }

    /// Per-day registration counts within [start_time, end_time], oldest first.
    pub fn countByDay(self: *UserPersistence, allocator: std.mem.Allocator, start_time: i64, end_time: i64) ![]model.DayCount {
        // zent path (preferred): DTO scanning by column name replaces the
        // hand-written row loop; falls back to db_postgres when the zent
        // layer is down (docs/zent-migration.md).
        if (zent_db.getDriver()) |drv| {
            var rows = try zent.sql_scan.queryAll(
                model.DayCount,
                allocator,
                drv,
                "SELECT to_char(create_time AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day, COUNT(*) AS count FROM users WHERE EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2 GROUP BY 1 ORDER BY 1",
                &.{ .{ .int = start_time }, .{ .int = end_time } },
            );
            return rows.toOwnedSlice();
        }
        const sql = "SELECT to_char(create_time AT TIME ZONE 'UTC', 'YYYY-MM-DD'), COUNT(*) FROM users WHERE EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2 GROUP BY 1 ORDER BY 1";
        const params = &[_]db_mod.QueryParam{ .{ .bigint = start_time }, .{ .bigint = end_time } };
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);
        var list = std.ArrayList(model.DayCount).empty;
        defer list.deinit(allocator);
        for (result.rows) |row| {
            try list.append(allocator, .{
                .day = try allocator.dupe(u8, row[0]),
                .count = try std.fmt.parseInt(i64, row[1], 10),
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getAllUserIDs(self: *UserPersistence, allocator: std.mem.Allocator) ![]const []const u8 {
        const sql = "SELECT user_id FROM users ORDER BY create_time DESC";
        const result = self.db.query(sql) catch return allocator.alloc([]const u8, 0);
        defer freeResult(self.allocator, result);

        var list = std.ArrayList([]const u8).empty;
        defer list.deinit(allocator);
        for (result.rows) |row| {
            try list.append(allocator, try allocator.dupe(u8, row[0]));
        }
        return list.toOwnedSlice(allocator);
    }

    // ── Online status ─────────────────────────────────────────────

    pub fn setOnline(self: *UserPersistence, user_id: []const u8, status: i32) void {
        const sql = "INSERT INTO user_online_status (user_id, status, last_seen) VALUES ($1, $2, NOW()) ON CONFLICT (user_id) DO UPDATE SET status = $2, last_seen = NOW()";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .int = status } };
        _ = self.db.execParams(sql, params) catch return;
    }

    pub fn isOnline(self: *UserPersistence, user_id: []const u8) bool {
        const sql = "SELECT status FROM user_online_status WHERE user_id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = self.db.queryParams(sql, params) catch return false;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return false;
        return result.rows[0][0][0] == '1';
    }

    pub fn getOnlineUsers(self: *UserPersistence) ![]const []const u8 {
        const sql = "SELECT user_id FROM user_online_status WHERE status = 1";
        const result = try self.db.query(sql);
        defer freeResult(self.allocator, result);

        var list = std.ArrayList([]const u8).empty;
        for (result.rows) |row| {
            try list.append(self.allocator, try self.allocator.dupe(u8, row[0]));
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn activeCount(self: *UserPersistence) usize {
        const sql = "SELECT COUNT(*) FROM user_online_status WHERE status = 1";
        const result = self.db.query(sql) catch return 0;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(usize, result.rows[0][0], 10) catch 0;
    }

    // ── User commands ─────────────────────────────────────────────

    pub fn addCommand(self: *UserPersistence, user_id: []const u8, command_id: []const u8, command_value: []const u8) !void {
        const sql = "INSERT INTO user_commands (user_id, command_id, command_value) VALUES ($1, $2, $3) ON CONFLICT (user_id, command_id) DO UPDATE SET command_value = $3, updated_at = NOW()";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .string = command_id }, .{ .string = command_value } };
        _ = try self.db.execParams(sql, params);
    }

    pub fn deleteCommand(self: *UserPersistence, user_id: []const u8, command_id: []const u8) !void {
        const sql = "DELETE FROM user_commands WHERE user_id = $1 AND command_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .string = command_id } };
        _ = try self.db.execParams(sql, params);
    }

    pub fn getCommand(self: *UserPersistence, user_id: []const u8, command_id: []const u8, allocator: std.mem.Allocator) !?model.UserCommand {
        const sql = "SELECT command_id, command_value, EXTRACT(EPOCH FROM create_time)::bigint FROM user_commands WHERE user_id = $1 AND command_id = $2 LIMIT 1";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .string = command_id } };
        const result = self.db.queryParams(sql, params) catch return null;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return null;
        const row = result.rows[0];
        return .{
            .command_id = try allocator.dupe(u8, row[0]),
            .command_value = try allocator.dupe(u8, row[1]),
            .create_time = try std.fmt.parseInt(i64, row[2], 10),
        };
    }

    pub fn getAllCommands(self: *UserPersistence, user_id: []const u8, allocator: std.mem.Allocator) ![]model.UserCommand {
        const sql = "SELECT command_id, command_value, EXTRACT(EPOCH FROM create_time)::bigint FROM user_commands WHERE user_id = $1 ORDER BY create_time DESC";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = self.db.queryParams(sql, params) catch return allocator.alloc(model.UserCommand, 0);
        defer freeResult(self.allocator, result);

        var list = try allocator.alloc(model.UserCommand, result.row_count);
        for (0..result.row_count) |i| {
            const row = result.rows[i];
            list[i] = .{
                .command_id = try allocator.dupe(u8, row[0]),
                .command_value = try allocator.dupe(u8, row[1]),
                .create_time = try std.fmt.parseInt(i64, row[2], 10),
            };
        }
        return list;
    }
};
