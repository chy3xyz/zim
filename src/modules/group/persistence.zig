const std = @import("std");
const core = @import("core");
const db_mod = @import("../db_postgres.zig");
const model = @import("model.zig");

pub const GroupPersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) GroupPersistence {
        return GroupPersistence{
            .allocator = allocator,
            .db = db,
        };
    }

    pub fn deinit(self: *GroupPersistence) void {
        _ = self;
    }

    pub fn freeResult(self: *GroupPersistence, result: db_mod.QueryResult) void {
        for (result.rows) |row| {
            for (row) |cell| self.allocator.free(cell);
            self.allocator.free(row);
        }
        self.allocator.free(result.rows);
    }

    fn escapeString(self: *GroupPersistence, s: []const u8) []u8 {
        var escaped = std.ArrayList(u8).empty;
        for (s) |c| {
            switch (c) {
                '\'' => {
                    escaped.appendSlice(self.allocator, "''") catch {};
                },
                else => {
                    escaped.append(self.allocator, c) catch {};
                },
            }
        }
        return escaped.toOwnedSlice(self.allocator) catch "";
    }

    fn generateGroupID(allocator: std.mem.Allocator) ![]const u8 {
        var bytes: [16]u8 = undefined;
        core.secureRandomBytes(&bytes);
        bytes[6] = (bytes[6] & 0x0F) | 0x40;
        bytes[8] = (bytes[8] & 0x3F) | 0x80;
        return try std.fmt.allocPrint(allocator, "{x:0>8}-{x:0>4}-4{x:0>3}-{x:0>4}-{x:0>12}", .{
            std.mem.readInt(u32, bytes[0..4], .big),
            std.mem.readInt(u16, bytes[4..6], .big),
            std.mem.readInt(u16, bytes[6..8], .big),
            std.mem.readInt(u16, bytes[8..10], .big),
            std.mem.readInt(u48, bytes[10..16], .big),
        });
    }

    pub fn create(self: *GroupPersistence, input: model.GroupCreateInput) !model.Group {
        // Atomic: group + owner member + initial members in one transaction.
        var tx = try self.db.begin();
        errdefer tx.rollback();

        const group_id = input.group_id orelse try generateGroupID(self.allocator);
        const now = core.unixNowSeconds();

        const sql = "INSERT INTO groups (group_id, group_name, notification, introduction, face_url, ex, status, creator_user_id, group_type, need_verification, look_member_info, apply_member_friend, notification_update_time, notification_user_id, display_is_read, create_time, updated_at) " ++
            "VALUES ($1, $2, $3, $4, $5, $6, 0, $7, $8, $9, 0, 0, to_timestamp($10), '', FALSE, NOW(), NOW()) " ++
            "RETURNING group_id, group_name, notification, introduction, face_url, ex, status, creator_user_id, group_type, need_verification, look_member_info, apply_member_friend, EXTRACT(EPOCH FROM notification_update_time)::bigint, notification_user_id, display_is_read, EXTRACT(EPOCH FROM create_time)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint";
        const params = &[_]db_mod.QueryParam{
            .{ .string = group_id },
            .{ .string = input.group_name },
            .{ .string = input.notification },
            .{ .string = input.introduction },
            .{ .string = input.face_url },
            .{ .string = input.ex },
            .{ .string = input.creator_user_id },
            .{ .smallint = @intFromEnum(input.group_type) },
            .{ .smallint = input.need_verification },
            .{ .bigint = now },
        };
        const result = try tx.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        if (result.row_count == 0) return error.InsertFailed;

        const row = result.rows[0];
        const group = try self.parseGroupRow(row);

        // Add creator as owner member
        const member_sql = "INSERT INTO group_members (group_id, user_id, nickname, face_url, role_level, join_time, join_source, inviter_user_id, operator_user_id, mute_end_time, ex) " ++
            "VALUES ($1, $2, '', '', $3, to_timestamp($4), 0, '', $5, NULL, '') " ++
            "ON CONFLICT (group_id, user_id) DO NOTHING";
        const member_params = &[_]db_mod.QueryParam{
            .{ .string = group_id },
            .{ .string = input.creator_user_id },
            .{ .smallint = @intFromEnum(model.MemberRole.owner) },
            .{ .bigint = now },
            .{ .string = input.creator_user_id },
        };
        _ = try tx.execParams(member_sql, member_params);

        // Add other members
        for (input.member_user_ids) |uid| {
            const m_params = &[_]db_mod.QueryParam{
                .{ .string = group_id },
                .{ .string = uid },
                .{ .smallint = @intFromEnum(model.MemberRole.member) },
                .{ .bigint = now },
                .{ .string = input.creator_user_id },
            };
            _ = try tx.execParams(member_sql, m_params);
        }

        try tx.commit();
        return group;
    }

    fn parseGroupRow(self: *GroupPersistence, row: []const []const u8) !model.Group {
        return model.Group{
            .group_id = try self.allocator.dupe(u8, row[0]),
            .group_name = try self.allocator.dupe(u8, row[1]),
            .notification = try self.allocator.dupe(u8, row[2]),
            .introduction = try self.allocator.dupe(u8, row[3]),
            .face_url = try self.allocator.dupe(u8, row[4]),
            .ex = try self.allocator.dupe(u8, row[5]),
            .status = @enumFromInt(try std.fmt.parseInt(i16, row[6], 10)),
            .creator_user_id = try self.allocator.dupe(u8, row[7]),
            .group_type = @enumFromInt(try std.fmt.parseInt(i16, row[8], 10)),
            .need_verification = try std.fmt.parseInt(i16, row[9], 10),
            .look_member_info = try std.fmt.parseInt(i16, row[10], 10),
            .apply_member_friend = try std.fmt.parseInt(i16, row[11], 10),
            .notification_update_time = try std.fmt.parseInt(i64, row[12], 10),
            .notification_user_id = try self.allocator.dupe(u8, row[13]),
            .display_is_read = row[14][0] == 't',
            // create RETURNING has no member_count; get() recomputes it.
            .member_count = 0,
            .create_time = try std.fmt.parseInt(i64, row[15], 10),
            .updated_at = try std.fmt.parseInt(i64, row[16], 10),
        };
    }

    pub fn get(self: *GroupPersistence, group_id: []const u8) ?model.Group {
        const sql = "SELECT group_id, group_name, notification, introduction, face_url, ex, status, creator_user_id, group_type, need_verification, look_member_info, apply_member_friend, COALESCE(EXTRACT(EPOCH FROM notification_update_time)::bigint, 0), notification_user_id, display_is_read, (SELECT COUNT(*) FROM group_members WHERE group_id = g.group_id), EXTRACT(EPOCH FROM create_time)::bigint, EXTRACT(EPOCH FROM updated_at)::bigint FROM groups g WHERE g.group_id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = group_id }};
        const result = self.db.queryParams(sql, params) catch return null;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return null;
        return self.parseGroupRow(result.rows[0]) catch null;
    }

    pub fn getMembers(self: *GroupPersistence, allocator: std.mem.Allocator, group_id: []const u8) ![]model.GroupMember {
        _ = allocator;
        const sql = "SELECT gm.group_id, gm.user_id, gm.nickname, gm.face_url, gm.role_level, EXTRACT(EPOCH FROM gm.join_time)::bigint, gm.join_source, gm.inviter_user_id, gm.operator_user_id, COALESCE(EXTRACT(EPOCH FROM gm.mute_end_time)::bigint, 0), gm.ex, EXTRACT(EPOCH FROM gm.updated_at)::bigint, COALESCE(u.app_manager_level, 0) FROM group_members gm LEFT JOIN users u ON gm.user_id = u.user_id WHERE gm.group_id = $1 ORDER BY gm.role_level ASC, gm.join_time ASC";
        const params = &[_]db_mod.QueryParam{.{ .string = group_id }};
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.GroupMember).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, model.GroupMember{
                .group_id = try self.allocator.dupe(u8, row[0]),
                .user_id = try self.allocator.dupe(u8, row[1]),
                .nickname = try self.allocator.dupe(u8, row[2]),
                .face_url = try self.allocator.dupe(u8, row[3]),
                .role_level = try std.fmt.parseInt(i16, row[4], 10),
                .join_time = try std.fmt.parseInt(i64, row[5], 10),
                .join_source = try std.fmt.parseInt(i16, row[6], 10),
                .inviter_user_id = try self.allocator.dupe(u8, row[7]),
                .operator_user_id = try self.allocator.dupe(u8, row[8]),
                .mute_end_time = try std.fmt.parseInt(i64, row[9], 10),
                .ex = try self.allocator.dupe(u8, row[10]),
                .updated_at = std.fmt.parseInt(i64, row[11], 10) catch 0,
                .app_manager_level = std.fmt.parseInt(i16, row[12], 10) catch 0,
            });
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn getMembersSince(self: *GroupPersistence, allocator: std.mem.Allocator, group_id: []const u8, since: i64) ![]model.GroupMember {
        _ = allocator;
        const sql = "SELECT gm.group_id, gm.user_id, gm.nickname, gm.face_url, gm.role_level, EXTRACT(EPOCH FROM gm.join_time)::bigint, gm.join_source, gm.inviter_user_id, gm.operator_user_id, COALESCE(EXTRACT(EPOCH FROM gm.mute_end_time)::bigint, 0), gm.ex, EXTRACT(EPOCH FROM gm.updated_at)::bigint, COALESCE(u.app_manager_level, 0) FROM group_members gm LEFT JOIN users u ON gm.user_id = u.user_id WHERE gm.group_id = $1 AND EXTRACT(EPOCH FROM gm.updated_at)::bigint > $2 ORDER BY gm.role_level ASC, gm.join_time ASC";
        const params = &[_]db_mod.QueryParam{ .{ .string = group_id }, .{ .bigint = since } };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.GroupMember).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, model.GroupMember{
                .group_id = try self.allocator.dupe(u8, row[0]),
                .user_id = try self.allocator.dupe(u8, row[1]),
                .nickname = try self.allocator.dupe(u8, row[2]),
                .face_url = try self.allocator.dupe(u8, row[3]),
                .role_level = try std.fmt.parseInt(i16, row[4], 10),
                .join_time = try std.fmt.parseInt(i64, row[5], 10),
                .join_source = try std.fmt.parseInt(i16, row[6], 10),
                .inviter_user_id = try self.allocator.dupe(u8, row[7]),
                .operator_user_id = try self.allocator.dupe(u8, row[8]),
                .mute_end_time = try std.fmt.parseInt(i64, row[9], 10),
                .ex = try self.allocator.dupe(u8, row[10]),
                .updated_at = std.fmt.parseInt(i64, row[11], 10) catch 0,
                .app_manager_level = std.fmt.parseInt(i16, row[12], 10) catch 0,
            });
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn getMember(self: *GroupPersistence, group_id: []const u8, user_id: []const u8) ?model.GroupMember {
        const sql = "SELECT gm.group_id, gm.user_id, gm.nickname, gm.face_url, gm.role_level, EXTRACT(EPOCH FROM gm.join_time)::bigint, gm.join_source, gm.inviter_user_id, gm.operator_user_id, COALESCE(EXTRACT(EPOCH FROM gm.mute_end_time)::bigint, 0), gm.ex, EXTRACT(EPOCH FROM gm.updated_at)::bigint, COALESCE(u.app_manager_level, 0) FROM group_members gm LEFT JOIN users u ON gm.user_id = u.user_id WHERE gm.group_id = $1 AND gm.user_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = group_id }, .{ .string = user_id } };
        const result = self.db.queryParams(sql, params) catch return null;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return null;
        const row = result.rows[0];
        return model.GroupMember{
            .group_id = self.allocator.dupe(u8, row[0]) catch return null,
            .user_id = self.allocator.dupe(u8, row[1]) catch return null,
            .nickname = self.allocator.dupe(u8, row[2]) catch return null,
            .face_url = self.allocator.dupe(u8, row[3]) catch return null,
            .role_level = std.fmt.parseInt(i16, row[4], 10) catch 0,
            .join_time = std.fmt.parseInt(i64, row[5], 10) catch 0,
            .join_source = std.fmt.parseInt(i16, row[6], 10) catch 0,
            .inviter_user_id = self.allocator.dupe(u8, row[7]) catch return null,
            .operator_user_id = self.allocator.dupe(u8, row[8]) catch return null,
            .mute_end_time = std.fmt.parseInt(i64, row[9], 10) catch 0,
            .ex = self.allocator.dupe(u8, row[10]) catch return null,
            .updated_at = std.fmt.parseInt(i64, row[11], 10) catch 0,
            .app_manager_level = std.fmt.parseInt(i16, row[12], 10) catch 0,
        };
    }

    pub fn addMember(self: *GroupPersistence, group_id: []const u8, user_id: []const u8, inviter: []const u8) !void {
        const now = core.unixNowSeconds();
        const sql = "INSERT INTO group_members (group_id, user_id, nickname, face_url, role_level, join_time, join_source, inviter_user_id, operator_user_id, mute_end_time, ex) VALUES ($1, $2, '', '', $3, to_timestamp($4), 0, $5, $5, NULL, '') ON CONFLICT (group_id, user_id) DO NOTHING";
        const params = &[_]db_mod.QueryParam{
            .{ .string = group_id },
            .{ .string = user_id },
            .{ .smallint = @intFromEnum(model.MemberRole.member) },
            .{ .bigint = now },
            .{ .string = inviter },
        };
        _ = try self.db.execParams(sql, params);

        // Touch group updated_at so incremental sync picks up member changes
        const touch_sql = "UPDATE groups SET updated_at = NOW() WHERE group_id = $1";
        const touch_params = &[_]db_mod.QueryParam{.{ .string = group_id }};
        _ = self.db.execParams(touch_sql, touch_params) catch {};
    }

    /// Batch-invite members atomically: all member rows + the group updated_at
    /// touch commit together, so a mid-loop failure leaves no partial invite.
    pub fn addMembersTx(self: *GroupPersistence, tx: *db_mod.Tx, group_id: []const u8, user_ids: []const []const u8, inviter: []const u8) !void {
        _ = self;
        if (user_ids.len == 0) return;
        const now = core.unixNowSeconds();
        const member_sql = "INSERT INTO group_members (group_id, user_id, nickname, face_url, role_level, join_time, join_source, inviter_user_id, operator_user_id, mute_end_time, ex) " ++
            "VALUES ($1, $2, '', '', $3, to_timestamp($4), 0, $5, $5, NULL, '') " ++
            "ON CONFLICT (group_id, user_id) DO NOTHING";
        for (user_ids) |uid| {
            const params = &[_]db_mod.QueryParam{
                .{ .string = group_id },
                .{ .string = uid },
                .{ .smallint = @intFromEnum(model.MemberRole.member) },
                .{ .bigint = now },
                .{ .string = inviter },
            };
            _ = try tx.execParams(member_sql, params);
        }
        _ = try tx.execParams("UPDATE groups SET updated_at = NOW() WHERE group_id = $1", &.{.{ .string = group_id }});
    }

    pub fn removeMember(self: *GroupPersistence, group_id: []const u8, user_id: []const u8) !bool {
        const sql = "DELETE FROM group_members WHERE group_id = $1 AND user_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = group_id }, .{ .string = user_id } };
        _ = try self.db.execParams(sql, params);

        // Touch group updated_at so incremental sync picks up member changes
        const touch_sql = "UPDATE groups SET updated_at = NOW() WHERE group_id = $1";
        const touch_params = &[_]db_mod.QueryParam{.{ .string = group_id }};
        _ = self.db.execParams(touch_sql, touch_params) catch {};
        return true;
    }

    pub fn setMemberRole(self: *GroupPersistence, group_id: []const u8, user_id: []const u8, role: model.MemberRole) !bool {
        const sql = "UPDATE group_members SET role_level = $1 WHERE group_id = $2 AND user_id = $3";
        const params = &[_]db_mod.QueryParam{ .{ .smallint = @intFromEnum(role) }, .{ .string = group_id }, .{ .string = user_id } };
        _ = try self.db.execParams(sql, params);
        return true;
    }

    /// Transfer group ownership atomically: old owner → member, new owner →
    /// owner, creator_user_id updated — all in one transaction so a failure
    /// never leaves a group without an owner.
    pub fn transferOwnerTx(self: *GroupPersistence, tx: *db_mod.Tx, group_id: []const u8, old_owner: []const u8, new_owner: []const u8) !void {
        _ = self;
        _ = try tx.execParams("UPDATE group_members SET role_level = $1 WHERE group_id = $2 AND user_id = $3", &.{
            .{ .smallint = @intFromEnum(model.MemberRole.member) },
            .{ .string = group_id },
            .{ .string = old_owner },
        });
        _ = try tx.execParams("UPDATE group_members SET role_level = $1 WHERE group_id = $2 AND user_id = $3", &.{
            .{ .smallint = @intFromEnum(model.MemberRole.owner) },
            .{ .string = group_id },
            .{ .string = new_owner },
        });
        _ = try tx.execParams("UPDATE groups SET creator_user_id = $1, updated_at = NOW() WHERE group_id = $2", &.{
            .{ .string = new_owner },
            .{ .string = group_id },
        });
    }

    pub fn dismiss(self: *GroupPersistence, group_id: []const u8) bool {
        // Atomic: remove group + members + pending requests together.
        var tx = self.db.begin() catch return false;
        errdefer tx.rollback();
        _ = tx.execParams("DELETE FROM group_members WHERE group_id = $1", &.{.{ .string = group_id }}) catch return false;
        _ = tx.execParams("DELETE FROM group_requests WHERE group_id = $1", &.{.{ .string = group_id }}) catch return false;
        _ = tx.execParams("DELETE FROM groups WHERE group_id = $1", &.{.{ .string = group_id }}) catch return false;
        tx.commit() catch return false;
        return true;
    }

    pub fn getJoinedGroups(self: *GroupPersistence, allocator: std.mem.Allocator, user_id: []const u8) ![]model.Group {
        _ = allocator;
        const sql = "SELECT g.group_id, g.group_name, g.notification, g.introduction, g.face_url, g.ex, g.status, g.creator_user_id, g.group_type, g.need_verification, g.look_member_info, g.apply_member_friend, COALESCE(EXTRACT(EPOCH FROM g.notification_update_time)::bigint, 0), g.notification_user_id, g.display_is_read, (SELECT COUNT(*) FROM group_members WHERE group_id = g.group_id), EXTRACT(EPOCH FROM g.create_time)::bigint, EXTRACT(EPOCH FROM g.updated_at)::bigint FROM groups g INNER JOIN group_members gm ON g.group_id = gm.group_id WHERE gm.user_id = $1 ORDER BY g.updated_at DESC";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.Group).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, try self.parseGroupRow(row));
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn getJoinedGroupsSince(self: *GroupPersistence, allocator: std.mem.Allocator, user_id: []const u8, since: i64) ![]model.Group {
        _ = allocator;
        const sql = "SELECT g.group_id, g.group_name, g.notification, g.introduction, g.face_url, g.ex, g.status, g.creator_user_id, g.group_type, g.need_verification, g.look_member_info, g.apply_member_friend, COALESCE(EXTRACT(EPOCH FROM g.notification_update_time)::bigint, 0), g.notification_user_id, g.display_is_read, (SELECT COUNT(*) FROM group_members WHERE group_id = g.group_id), EXTRACT(EPOCH FROM g.create_time)::bigint, EXTRACT(EPOCH FROM g.updated_at)::bigint FROM groups g INNER JOIN group_members gm ON g.group_id = gm.group_id WHERE gm.user_id = $1 AND (EXTRACT(EPOCH FROM g.updated_at)::bigint > $2 OR EXTRACT(EPOCH FROM gm.updated_at)::bigint > $2) ORDER BY g.updated_at DESC";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .bigint = since } };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.Group).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, try self.parseGroupRow(row));
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn isMember(self: *GroupPersistence, group_id: []const u8, user_id: []const u8) bool {
        const sql = "SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2 LIMIT 1";
        const params = &[_]db_mod.QueryParam{ .{ .string = group_id }, .{ .string = user_id } };
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

    pub fn update(self: *GroupPersistence, group_id: []const u8, input: model.GroupUpdateInput) !?model.Group {
        var set_parts = std.ArrayList([]const u8).empty;
        defer set_parts.deinit(self.allocator);
        var params = std.ArrayList(db_mod.QueryParam).empty;
        defer params.deinit(self.allocator);
        var idx: i32 = 1;

        if (input.group_name) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "group_name = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.notification) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "notification = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.introduction) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "introduction = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.face_url) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "face_url = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.ex) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ex = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.need_verification) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "need_verification = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }
        if (input.look_member_info) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "look_member_info = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }
        if (input.apply_member_friend) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "apply_member_friend = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }

        if (set_parts.items.len == 0) return self.get(group_id);

        try set_parts.append(self.allocator, "updated_at = NOW()");
        var set_clause = std.ArrayList(u8).empty;
        defer set_clause.deinit(self.allocator);
        for (set_parts.items, 0..) |part, i| {
            if (i > 0) try set_clause.appendSlice(self.allocator, ", ");
            try set_clause.appendSlice(self.allocator, part);
        }

        const sql = try std.fmt.allocPrint(self.allocator, "UPDATE groups SET {s} WHERE group_id = ${d}", .{ set_clause.items, idx });
        defer self.allocator.free(sql);
        try params.append(self.allocator, .{ .string = group_id });

        _ = try self.db.execParams(sql, params.items);
        return self.get(group_id);
    }

    pub fn muteMember(self: *GroupPersistence, group_id: []const u8, user_id: []const u8, mute_end_time: i64) !bool {
        const sql = "UPDATE group_members SET mute_end_time = to_timestamp($1) WHERE group_id = $2 AND user_id = $3";
        const params = &[_]db_mod.QueryParam{
            .{ .bigint = mute_end_time },
            .{ .string = group_id },
            .{ .string = user_id },
        };
        _ = try self.db.execParams(sql, params);
        return true;
    }

    pub fn muteGroup(self: *GroupPersistence, group_id: []const u8, muted: bool) !bool {
        const status: i16 = if (muted) 3 else 0;
        const sql = "UPDATE groups SET status = $1 WHERE group_id = $2";
        const params = &[_]db_mod.QueryParam{
            .{ .smallint = status },
            .{ .string = group_id },
        };
        _ = try self.db.execParams(sql, params);
        return true;
    }

    pub fn setMemberInfo(self: *GroupPersistence, group_id: []const u8, user_id: []const u8, nickname: ?[]const u8, face_url: ?[]const u8, role_level: ?i16, ex: ?[]const u8) !bool {
        var set_parts = std.ArrayList([]const u8).empty;
        defer set_parts.deinit(self.allocator);
        var params = std.ArrayList(db_mod.QueryParam).empty;
        defer params.deinit(self.allocator);
        var idx: i32 = 1;

        if (nickname) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "nickname = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (face_url) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "face_url = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (role_level) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "role_level = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }
        if (ex) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ex = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }

        if (set_parts.items.len == 0) return false;

        var set_clause = std.ArrayList(u8).empty;
        defer set_clause.deinit(self.allocator);
        for (set_parts.items, 0..) |part, i| {
            if (i > 0) try set_clause.appendSlice(self.allocator, ", ");
            try set_clause.appendSlice(self.allocator, part);
        }

        const sql = try std.fmt.allocPrint(self.allocator, "UPDATE group_members SET {s} WHERE group_id = ${d} AND user_id = ${d}", .{
            set_clause.items, idx, idx + 1,
        });
        defer self.allocator.free(sql);
        try params.append(self.allocator, .{ .string = group_id });
        try params.append(self.allocator, .{ .string = user_id });

        const r = try self.db.execParams(sql, params.items);
        return r > 0;
    }

    pub fn deleteGroupRequest(self: *GroupPersistence, user_id: []const u8, group_id: []const u8) !bool {
        const sql = "DELETE FROM group_requests WHERE user_id = $1 AND group_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .string = group_id } };
        const r = try self.db.execParams(sql, params);
        return r > 0;
    }

    pub fn addGroupRequest(self: *GroupPersistence, user_id: []const u8, group_id: []const u8, req_msg: []const u8) !void {
        const sql = "INSERT INTO group_requests (user_id, group_id, handle_result, req_msg, handled_msg, req_time, handle_user_id, handled_time, join_source, inviter_user_id, ex) " ++
            "VALUES ($1, $2, 0, $3, '', NOW(), '', NULL, 0, '', '') " ++
            "ON CONFLICT (user_id, group_id) DO UPDATE SET req_msg = $3, handle_result = 0, req_time = NOW()";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .string = group_id },
            .{ .string = req_msg },
        };
        _ = try self.db.execParams(sql, params);
    }

    pub fn respondGroupRequest(self: *GroupPersistence, user_id: []const u8, group_id: []const u8, handled_msg: []const u8, accept: bool, handler_user_id: []const u8) !bool {
        const result: i16 = if (accept) 1 else -1;
        const sql = "UPDATE group_requests SET handle_result = $1, handled_msg = $2, handled_time = NOW(), handle_user_id = $3 " ++
            "WHERE user_id = $4 AND group_id = $5";
        const params = &[_]db_mod.QueryParam{
            .{ .smallint = result },
            .{ .string = handled_msg },
            .{ .string = handler_user_id },
            .{ .string = user_id },
            .{ .string = group_id },
        };
        _ = try self.db.execParams(sql, params);

        if (accept) {
            try self.addMember(group_id, user_id, handler_user_id);
        }
        return true;
    }

    pub fn getGroupRequests(self: *GroupPersistence, allocator: std.mem.Allocator, group_id: ?[]const u8, user_id: ?[]const u8, handle_result: ?i16) ![]model.GroupRequest {
        _ = allocator;
        var cond_parts = std.ArrayList([]const u8).empty;
        defer cond_parts.deinit(self.allocator);
        var params = std.ArrayList(db_mod.QueryParam).empty;
        defer params.deinit(self.allocator);
        var idx: i32 = 1;

        if (group_id) |gid| {
            try cond_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "group_id = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = gid });
            idx += 1;
        }
        if (user_id) |uid| {
            try cond_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "user_id = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = uid });
            idx += 1;
        }
        if (handle_result) |hr| {
            try cond_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "handle_result = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = hr });
            idx += 1;
        }

        var where_clause: []const u8 = "";
        if (cond_parts.items.len > 0) {
            var clause = std.ArrayList(u8).empty;
            defer clause.deinit(self.allocator);
            for (cond_parts.items, 0..) |cond, i| {
                if (i > 0) try clause.appendSlice(self.allocator, " AND ");
                try clause.appendSlice(self.allocator, cond);
            }
            where_clause = try std.fmt.allocPrint(self.allocator, "WHERE {s}", .{clause.items});
        }

        const sql = try std.fmt.allocPrint(self.allocator, "SELECT user_id, group_id, handle_result, req_msg, handled_msg, EXTRACT(EPOCH FROM req_time)::bigint, handle_user_id, EXTRACT(EPOCH FROM handled_time)::bigint, join_source, inviter_user_id, ex " ++
            "FROM group_requests {s} ORDER BY req_time DESC", .{where_clause});
        defer self.allocator.free(sql);

        const result = try self.db.queryParams(sql, params.items);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.GroupRequest).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, model.GroupRequest{
                .user_id = try self.allocator.dupe(u8, row[0]),
                .group_id = try self.allocator.dupe(u8, row[1]),
                .handle_result = try std.fmt.parseInt(i16, row[2], 10),
                .req_msg = try self.allocator.dupe(u8, row[3]),
                .handled_msg = try self.allocator.dupe(u8, row[4]),
                .req_time = try std.fmt.parseInt(i64, row[5], 10),
                .handle_user_id = try self.allocator.dupe(u8, row[6]),
                .handled_time = if (row[7].len > 0) try std.fmt.parseInt(i64, row[7], 10) else 0,
                .join_source = try std.fmt.parseInt(i16, row[8], 10),
                .inviter_user_id = try self.allocator.dupe(u8, row[9]),
                .ex = try self.allocator.dupe(u8, row[10]),
            });
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn count(self: *GroupPersistence) usize {
        const sql = "SELECT COUNT(*) FROM groups";
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

    pub fn countSince(self: *GroupPersistence, start_time: i64, end_time: i64) usize {
        const sql = "SELECT COUNT(*) FROM groups WHERE EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2";
        const params = &[_]db_mod.QueryParam{ .{ .bigint = start_time }, .{ .bigint = end_time } };
        const result = self.db.queryParams(sql, params) catch return 0;
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

    pub fn countBefore(self: *GroupPersistence, start_time: i64) usize {
        const sql = "SELECT COUNT(*) FROM groups WHERE EXTRACT(EPOCH FROM create_time)::bigint < $1";
        const params = &[_]db_mod.QueryParam{.{ .bigint = start_time }};
        const result = self.db.queryParams(sql, params) catch return 0;
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

    /// Per-day group creation counts within [start_time, end_time], oldest first.
    pub fn countByDay(self: *GroupPersistence, allocator: std.mem.Allocator, start_time: i64, end_time: i64) ![]model.DayCount {
        const sql = "SELECT to_char(create_time AT TIME ZONE 'UTC', 'YYYY-MM-DD'), COUNT(*) FROM groups WHERE EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2 GROUP BY 1 ORDER BY 1";
        const params = &[_]db_mod.QueryParam{ .{ .bigint = start_time }, .{ .bigint = end_time } };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
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

    pub fn activeCount(self: *GroupPersistence) usize {
        // Active groups = groups with messages in last 24h
        const sql = "SELECT COUNT(DISTINCT group_id) FROM messages WHERE group_id != '' AND create_time > NOW() - INTERVAL '24 hours'";
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
};
