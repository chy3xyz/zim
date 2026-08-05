const std = @import("std");
const db_mod = @import("../db_postgres.zig");
const model = @import("model.zig");

pub const FriendPersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) FriendPersistence {
        return FriendPersistence{
            .allocator = allocator,
            .db = db,
        };
    }

    pub fn deinit(self: *FriendPersistence) void {
        _ = self;
    }

    fn escapeString(self: *FriendPersistence, s: []const u8) []const u8 {
        _ = self;
        return s;
    }

    pub fn freeResult(self: *FriendPersistence, result: db_mod.QueryResult) void {
        for (result.rows) |row| {
            for (row) |cell| self.allocator.free(cell);
            self.allocator.free(row);
        }
        self.allocator.free(result.rows);
    }

    pub fn addFriendRequest(self: *FriendPersistence, from_user_id: []const u8, to_user_id: []const u8, req_msg: []const u8) !model.FriendRequest {
        // Check if already friends
        const check_sql = "SELECT 1 FROM friends WHERE owner_user_id = $1 AND friend_user_id = $2";
        const check_params = &[_]db_mod.QueryParam{ .{ .string = from_user_id }, .{ .string = to_user_id } };
        const check_result = self.db.queryParams(check_sql, check_params) catch null;
        if (check_result) |cr| {
            defer {
                for (cr.rows) |row| {
                    _ = self.allocator.free(row);
                }
                _ = self.allocator.free(cr.rows);
            }
            if (cr.row_count > 0) return error.AlreadyFriends;
        }

        const sql = "INSERT INTO friend_requests (from_user_id, to_user_id, handle_result, req_msg, create_time, handler_user_id, handle_msg, ex) VALUES ($1, $2, 0, $3, NOW(), '', '', '') ON CONFLICT (from_user_id, to_user_id) DO UPDATE SET req_msg = $3, handle_result = 0, create_time = NOW() RETURNING from_user_id, to_user_id, handle_result, req_msg, EXTRACT(EPOCH FROM create_time)::bigint, handler_user_id, handle_msg, COALESCE(EXTRACT(EPOCH FROM handle_time)::bigint, 0), ex";
        const params = &[_]db_mod.QueryParam{ .{ .string = from_user_id }, .{ .string = to_user_id }, .{ .string = req_msg } };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        if (result.row_count == 0) return error.QueryFailed;
        const row = result.rows[0];
        return model.FriendRequest{
            .from_user_id = try self.allocator.dupe(u8, row[0]),
            .to_user_id = try self.allocator.dupe(u8, row[1]),
            .handle_result = @enumFromInt(try std.fmt.parseInt(i16, row[2], 10)),
            .req_msg = try self.allocator.dupe(u8, row[3]),
            .create_time = try std.fmt.parseInt(i64, row[4], 10),
            .handler_user_id = try self.allocator.dupe(u8, row[5]),
            .handle_msg = try self.allocator.dupe(u8, row[6]),
            .handle_time = std.fmt.parseInt(i64, row[7], 10) catch 0,
            .ex = try self.allocator.dupe(u8, row[8]),
        };
    }

    pub fn respondFriendRequest(self: *FriendPersistence, from_user_id: []const u8, to_user_id: []const u8, accept: bool, handle_msg: []const u8) !void {
        // Atomic: mark request handled + bidirectional friend rows in one tx.
        var tx = try self.db.begin();
        errdefer tx.rollback();

        const result_val: i16 = if (accept) 1 else -1;
        const sql = "UPDATE friend_requests SET handle_result = $1, handle_msg = $2, handle_time = NOW(), handler_user_id = $3 WHERE from_user_id = $4 AND to_user_id = $5 AND handle_result = 0";
        const params = &[_]db_mod.QueryParam{
            .{ .smallint = result_val },
            .{ .string = handle_msg },
            .{ .string = to_user_id },
            .{ .string = from_user_id },
            .{ .string = to_user_id },
        };
        _ = try tx.execParams(sql, params);

        if (accept) {
            // Create bidirectional friend entries
            const sql1 = "INSERT INTO friends (owner_user_id, friend_user_id, remark, add_source, operator_user_id, ex, is_pinned) VALUES ($1, $2, '', 0, '', '', FALSE) ON CONFLICT DO NOTHING";
            const p1 = &[_]db_mod.QueryParam{ .{ .string = from_user_id }, .{ .string = to_user_id } };
            _ = try tx.execParams(sql1, p1);

            const sql2 = "INSERT INTO friends (owner_user_id, friend_user_id, remark, add_source, operator_user_id, ex, is_pinned) VALUES ($1, $2, '', 0, '', '', FALSE) ON CONFLICT DO NOTHING";
            const p2 = &[_]db_mod.QueryParam{ .{ .string = to_user_id }, .{ .string = from_user_id } };
            _ = try tx.execParams(sql2, p2);
        }
        try tx.commit();
    }

    pub fn getFriends(self: *FriendPersistence, allocator: std.mem.Allocator, user_id: []const u8) ![]model.FriendInfo {
        const sql = "SELECT f.owner_user_id, f.friend_user_id, u.nickname, u.face_url, f.remark, EXTRACT(EPOCH FROM f.create_time)::bigint, f.add_source, f.operator_user_id, f.ex, EXTRACT(EPOCH FROM f.updated_at)::bigint, f.is_pinned FROM friends f JOIN users u ON f.friend_user_id = u.user_id WHERE f.owner_user_id = $1 ORDER BY f.updated_at DESC";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.FriendInfo).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.FriendInfo{
                .owner_user_id = try allocator.dupe(u8, row[0]),
                .friend_user_id = try allocator.dupe(u8, row[1]),
                .nickname = try allocator.dupe(u8, row[2]),
                .face_url = try allocator.dupe(u8, row[3]),
                .remark = try allocator.dupe(u8, row[4]),
                .create_time = try std.fmt.parseInt(i64, row[5], 10),
                .add_source = try std.fmt.parseInt(i16, row[6], 10),
                .operator_user_id = try allocator.dupe(u8, row[7]),
                .ex = try allocator.dupe(u8, row[8]),
                .updated_at = std.fmt.parseInt(i64, row[9], 10) catch 0,
                .is_pinned = row[10].len > 0 and row[10][0] == 't',
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getFriendsSince(self: *FriendPersistence, allocator: std.mem.Allocator, user_id: []const u8, since: i64) ![]model.FriendInfo {
        const sql = "SELECT f.owner_user_id, f.friend_user_id, u.nickname, u.face_url, f.remark, EXTRACT(EPOCH FROM f.create_time)::bigint, f.add_source, f.operator_user_id, f.ex, EXTRACT(EPOCH FROM f.updated_at)::bigint, f.is_pinned FROM friends f JOIN users u ON f.friend_user_id = u.user_id WHERE f.owner_user_id = $1 AND EXTRACT(EPOCH FROM f.updated_at)::bigint > $2 ORDER BY f.updated_at DESC";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .bigint = since } };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.FriendInfo).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.FriendInfo{
                .owner_user_id = try allocator.dupe(u8, row[0]),
                .friend_user_id = try allocator.dupe(u8, row[1]),
                .nickname = try allocator.dupe(u8, row[2]),
                .face_url = try allocator.dupe(u8, row[3]),
                .remark = try allocator.dupe(u8, row[4]),
                .create_time = try std.fmt.parseInt(i64, row[5], 10),
                .add_source = try std.fmt.parseInt(i16, row[6], 10),
                .operator_user_id = try allocator.dupe(u8, row[7]),
                .ex = try allocator.dupe(u8, row[8]),
                .updated_at = std.fmt.parseInt(i64, row[9], 10) catch 0,
                .is_pinned = row[10].len > 0 and row[10][0] == 't',
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getFriendRequests(self: *FriendPersistence, allocator: std.mem.Allocator, user_id: []const u8, as_sender: bool) ![]model.FriendRequestInfo {
        const field = if (as_sender) "fr.from_user_id" else "fr.to_user_id";
        const sql = try std.fmt.allocPrint(self.allocator, "SELECT fr.from_user_id, fu.nickname, fu.face_url, fr.to_user_id, tu.nickname, tu.face_url, " ++
            "fr.handle_result, fr.req_msg, EXTRACT(EPOCH FROM fr.create_time)::bigint, " ++
            "fr.handler_user_id, fr.handle_msg, COALESCE(EXTRACT(EPOCH FROM fr.handle_time)::bigint, 0), fr.ex " ++
            "FROM friend_requests fr " ++
            "JOIN users fu ON fr.from_user_id = fu.user_id " ++
            "JOIN users tu ON fr.to_user_id = tu.user_id " ++
            "WHERE {s} = $1 ORDER BY fr.create_time DESC", .{field});
        defer self.allocator.free(sql);
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.FriendRequestInfo).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.FriendRequestInfo{
                .from_user_id = try allocator.dupe(u8, row[0]),
                .from_nickname = try allocator.dupe(u8, row[1]),
                .from_face_url = try allocator.dupe(u8, row[2]),
                .to_user_id = try allocator.dupe(u8, row[3]),
                .to_nickname = try allocator.dupe(u8, row[4]),
                .to_face_url = try allocator.dupe(u8, row[5]),
                .handle_result = @enumFromInt(try std.fmt.parseInt(i16, row[6], 10)),
                .req_msg = try allocator.dupe(u8, row[7]),
                .create_time = try std.fmt.parseInt(i64, row[8], 10),
                .handler_user_id = try allocator.dupe(u8, row[9]),
                .handle_msg = try allocator.dupe(u8, row[10]),
                .handle_time = std.fmt.parseInt(i64, row[11], 10) catch 0,
                .ex = try allocator.dupe(u8, row[12]),
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn deleteFriend(self: *FriendPersistence, owner_user_id: []const u8, friend_user_id: []const u8) !bool {
        // Atomic: remove both directions of the friendship in one transaction.
        var tx = try self.db.begin();
        errdefer tx.rollback();

        const sql1 = "DELETE FROM friends WHERE owner_user_id = $1 AND friend_user_id = $2";
        const params1 = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .string = friend_user_id } };
        const r1 = try tx.execParams(sql1, params1);

        const sql2 = "DELETE FROM friends WHERE owner_user_id = $1 AND friend_user_id = $2";
        const params2 = &[_]db_mod.QueryParam{ .{ .string = friend_user_id }, .{ .string = owner_user_id } };
        const r2 = try tx.execParams(sql2, params2);

        try tx.commit();
        return r1 > 0 or r2 > 0;
    }

    pub fn addBlack(self: *FriendPersistence, owner_user_id: []const u8, block_user_id: []const u8) !void {
        // Delete any existing friendship first
        _ = self.deleteFriend(owner_user_id, block_user_id) catch {};

        const sql = "INSERT INTO blacks (owner_user_id, block_user_id, add_source, operator_user_id, ex) VALUES ($1, $2, 0, '', '') ON CONFLICT DO NOTHING";
        const params = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .string = block_user_id } };
        _ = try self.db.execParams(sql, params);
    }

    pub fn removeBlack(self: *FriendPersistence, owner_user_id: []const u8, block_user_id: []const u8) !bool {
        const sql = "DELETE FROM blacks WHERE owner_user_id = $1 AND block_user_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .string = block_user_id } };
        const r = try self.db.execParams(sql, params);
        return r > 0;
    }

    pub fn getBlacks(self: *FriendPersistence, allocator: std.mem.Allocator, user_id: []const u8) ![]model.BlackInfo {
        const sql = "SELECT b.owner_user_id, b.block_user_id, u.user_id, u.nickname, u.face_url, u.gender, EXTRACT(EPOCH FROM b.create_time)::bigint, b.add_source, b.operator_user_id, b.ex, EXTRACT(EPOCH FROM b.updated_at)::bigint FROM blacks b JOIN users u ON b.block_user_id = u.user_id WHERE b.owner_user_id = $1 ORDER BY b.updated_at DESC";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.BlackInfo).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.BlackInfo{
                .owner_user_id = try allocator.dupe(u8, row[0]),
                .block_user_id = try allocator.dupe(u8, row[1]),
                .user_id = try allocator.dupe(u8, row[2]),
                .nickname = try allocator.dupe(u8, row[3]),
                .face_url = try allocator.dupe(u8, row[4]),
                .gender = try std.fmt.parseInt(i16, row[5], 10),
                .create_time = try std.fmt.parseInt(i64, row[6], 10),
                .add_source = try std.fmt.parseInt(i16, row[7], 10),
                .operator_user_id = try allocator.dupe(u8, row[8]),
                .ex = try allocator.dupe(u8, row[9]),
                .updated_at = std.fmt.parseInt(i64, row[10], 10) catch 0,
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getBlacksSince(self: *FriendPersistence, allocator: std.mem.Allocator, user_id: []const u8, since: i64) ![]model.BlackInfo {
        const sql = "SELECT b.owner_user_id, b.block_user_id, u.user_id, u.nickname, u.face_url, u.gender, EXTRACT(EPOCH FROM b.create_time)::bigint, b.add_source, b.operator_user_id, b.ex, EXTRACT(EPOCH FROM b.updated_at)::bigint FROM blacks b JOIN users u ON b.block_user_id = u.user_id WHERE b.owner_user_id = $1 AND EXTRACT(EPOCH FROM b.updated_at)::bigint > $2 ORDER BY b.updated_at DESC";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .bigint = since } };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.BlackInfo).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.BlackInfo{
                .owner_user_id = try allocator.dupe(u8, row[0]),
                .block_user_id = try allocator.dupe(u8, row[1]),
                .user_id = try allocator.dupe(u8, row[2]),
                .nickname = try allocator.dupe(u8, row[3]),
                .face_url = try allocator.dupe(u8, row[4]),
                .gender = try std.fmt.parseInt(i16, row[5], 10),
                .create_time = try std.fmt.parseInt(i64, row[6], 10),
                .add_source = try std.fmt.parseInt(i16, row[7], 10),
                .operator_user_id = try allocator.dupe(u8, row[8]),
                .ex = try allocator.dupe(u8, row[9]),
                .updated_at = std.fmt.parseInt(i64, row[10], 10) catch 0,
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn setRemark(self: *FriendPersistence, owner_user_id: []const u8, friend_user_id: []const u8, remark: []const u8) !bool {
        const sql = "UPDATE friends SET remark = $1 WHERE owner_user_id = $2 AND friend_user_id = $3";
        const params = &[_]db_mod.QueryParam{
            .{ .string = remark },
            .{ .string = owner_user_id },
            .{ .string = friend_user_id },
        };
        const r = try self.db.execParams(sql, params);
        return r > 0;
    }

    /// Partial update of friend fields (remark / is_pinned / ex), only non-null fields are applied.
    pub fn updateFriend(self: *FriendPersistence, owner_user_id: []const u8, friend_user_id: []const u8, remark: ?[]const u8, is_pinned: ?bool, ex: ?[]const u8) !bool {
        var sql = std.ArrayList(u8).empty;
        defer sql.deinit(self.allocator);
        try sql.appendSlice(self.allocator, "UPDATE friends SET ");
        var params: [5]db_mod.QueryParam = undefined;
        var n: usize = 0;
        var idx: usize = 1;
        var num_buf: [8]u8 = undefined;
        if (remark) |v| {
            if (n > 0) try sql.appendSlice(self.allocator, ", ");
            try sql.appendSlice(self.allocator, "remark = $");
            try sql.appendSlice(self.allocator, std.fmt.bufPrint(&num_buf, "{d}", .{idx}) catch unreachable);
            params[n] = .{ .string = v };
            n += 1;
            idx += 1;
        }
        if (is_pinned) |v| {
            if (n > 0) try sql.appendSlice(self.allocator, ", ");
            try sql.appendSlice(self.allocator, "is_pinned = $");
            try sql.appendSlice(self.allocator, std.fmt.bufPrint(&num_buf, "{d}", .{idx}) catch unreachable);
            params[n] = .{ .bool = v };
            n += 1;
            idx += 1;
        }
        if (ex) |v| {
            if (n > 0) try sql.appendSlice(self.allocator, ", ");
            try sql.appendSlice(self.allocator, "ex = $");
            try sql.appendSlice(self.allocator, std.fmt.bufPrint(&num_buf, "{d}", .{idx}) catch unreachable);
            params[n] = .{ .string = v };
            n += 1;
            idx += 1;
        }
        if (n == 0) return false;
        try sql.appendSlice(self.allocator, " WHERE owner_user_id = $");
        try sql.appendSlice(self.allocator, std.fmt.bufPrint(&num_buf, "{d}", .{idx}) catch unreachable);
        try sql.appendSlice(self.allocator, " AND friend_user_id = $");
        try sql.appendSlice(self.allocator, std.fmt.bufPrint(&num_buf, "{d}", .{idx + 1}) catch unreachable);
        params[n] = .{ .string = owner_user_id };
        params[n + 1] = .{ .string = friend_user_id };
        const r = try self.db.execParams(sql.items, params[0 .. n + 2]);
        return r > 0;
    }

    pub fn isFriend(self: *FriendPersistence, user_id_1: []const u8, user_id_2: []const u8) bool {
        const sql = "SELECT 1 FROM friends WHERE (owner_user_id = $1 AND friend_user_id = $2) OR (owner_user_id = $2 AND friend_user_id = $1) LIMIT 1";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id_1 }, .{ .string = user_id_2 } };
        const result = self.db.queryParams(sql, params) catch return false;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        return result.row_count > 0;
    }

    pub fn isBlack(self: *FriendPersistence, owner_user_id: []const u8, block_user_id: []const u8) bool {
        const sql = "SELECT 1 FROM blacks WHERE owner_user_id = $1 AND block_user_id = $2 LIMIT 1";
        const params = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .string = block_user_id } };
        const result = self.db.queryParams(sql, params) catch return false;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        return result.row_count > 0;
    }

    pub fn friendCount(self: *FriendPersistence) usize {
        const sql = "SELECT COUNT(*) FROM friends";
        const result = self.db.query(sql) catch return 0;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(usize, result.rows[0][0], 10) catch 0;
    }

    pub fn importFriends(self: *FriendPersistence, owner_user_id: []const u8, friend_user_ids: []const []const u8) !usize {
        var count: usize = 0;
        for (friend_user_ids) |fid| {
            const sql = "INSERT INTO friends (owner_user_id, friend_user_id, remark, create_time, add_source, operator_user_id, ex, is_pinned) " ++
                "VALUES ($1, $2, '', NOW(), 0, $3, '', FALSE) ON CONFLICT DO NOTHING";
            const params = &[_]db_mod.QueryParam{
                .{ .string = owner_user_id },
                .{ .string = fid },
                .{ .string = owner_user_id },
            };
            const r = self.db.execParams(sql, params) catch continue;
            if (r > 0) count += 1;

            // Also create reverse relationship
            const sql2 = "INSERT INTO friends (owner_user_id, friend_user_id, remark, create_time, add_source, operator_user_id, ex, is_pinned) " ++
                "VALUES ($1, $2, '', NOW(), 0, $3, '', FALSE) ON CONFLICT DO NOTHING";
            const params2 = &[_]db_mod.QueryParam{
                .{ .string = fid },
                .{ .string = owner_user_id },
                .{ .string = owner_user_id },
            };
            _ = self.db.execParams(sql2, params2) catch {};
        }
        return count;
    }

    pub fn deleteFriendRequest(self: *FriendPersistence, from_user_id: []const u8, to_user_id: []const u8) !bool {
        const sql = "DELETE FROM friend_requests WHERE from_user_id = $1 AND to_user_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = from_user_id }, .{ .string = to_user_id } };
        const r = try self.db.execParams(sql, params);
        return r > 0;
    }
};
