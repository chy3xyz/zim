const std = @import("std");
const core = @import("core");
const db_mod = @import("../../modules/db_postgres.zig");
const model = @import("model.zig");

fn rowToConversation(allocator: std.mem.Allocator, row: []const []const u8) !model.Conversation {
    return model.Conversation{
        .id = try allocator.dupe(u8, row[0]),
        .owner_user_id = try allocator.dupe(u8, row[1]),
        .conversation_id = try allocator.dupe(u8, row[2]),
        .conversation_type = @enumFromInt(try std.fmt.parseInt(i16, row[3], 10)),
        .user_id = try allocator.dupe(u8, row[4]),
        .group_id = try allocator.dupe(u8, row[5]),
        .recv_msg_opt = try std.fmt.parseInt(i16, row[6], 10),
        .is_pinned = row[7][0] == 't',
        .is_private_chat = row[8][0] == 't',
        .burn_duration = try std.fmt.parseInt(i32, row[9], 10),
        .attached_info = try allocator.dupe(u8, row[10]),
        .ex = try allocator.dupe(u8, row[11]),
        .max_seq = try std.fmt.parseInt(i64, row[12], 10),
        .min_seq = try std.fmt.parseInt(i64, row[13], 10),
        .has_read_seq = try std.fmt.parseInt(i64, row[14], 10),
        .latest_msg = try allocator.dupe(u8, row[15]),
        .latest_msg_send_time = try std.fmt.parseInt(i64, row[16], 10),
        .latest_msg_send_id = try allocator.dupe(u8, row[17]),
        .latest_msg_content_type = try std.fmt.parseInt(i16, row[18], 10),
        .group_at_type = try std.fmt.parseInt(i16, row[19], 10),
        .create_time = try std.fmt.parseInt(i64, row[20], 10),
        .update_time = try std.fmt.parseInt(i64, row[21], 10),
        .is_msg_destruct = row[22][0] == 't',
        .msg_destruct_time = try std.fmt.parseInt(i64, row[23], 10),
    };
}

fn freeResult(allocator: std.mem.Allocator, result: db_mod.QueryResult) void {
    for (result.rows) |row| {
        for (row) |cell| allocator.free(cell);
        _ = allocator.free(row);
    }
    _ = allocator.free(result.rows);
}

fn generateAESKey(allocator: std.mem.Allocator) ![]const u8 {
    var key_bytes: [32]u8 = undefined;
    core.secureRandomBytes(&key_bytes);
    const b64_len = std.base64.standard.Encoder.calcSize(key_bytes.len);
    const b64_buf = try allocator.alloc(u8, b64_len);
    return std.base64.standard.Encoder.encode(b64_buf, &key_bytes);
}

pub const ConversationPersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) ConversationPersistence {
        return .{ .allocator = allocator, .db = db };
    }

    pub fn deinit(self: *ConversationPersistence) void {
        _ = self;
    }

    /// Upsert a conversation with the latest message info in one statement.
    /// `exec` may be a `*PostgresClient` or a `*Tx` (transactional message send).
    /// max_seq is monotonic (GREATEST) so out-of-order sends never regress it.
    pub fn upsertWithLatest(self: *ConversationPersistence, exec: anytype, owner_user_id: []const u8, conversation_id: []const u8, conversation_type: i16, user_id: []const u8, group_id: []const u8, latest_msg: []const u8, latest_send_time: i64, latest_send_id: []const u8, latest_content_type: i16, max_seq: i64, group_at_type: i16) !void {
        _ = self;
        const sql = "INSERT INTO conversations (owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, create_time, update_time) " ++
            "VALUES ($1, $2, $3, $4, $5, 0, FALSE, FALSE, 0, '', '', $6, 0, 0, $7, $8, $9, $10, $11, NOW(), NOW()) " ++
            "ON CONFLICT (owner_user_id, conversation_id) DO UPDATE SET " ++
            "latest_msg = EXCLUDED.latest_msg, latest_msg_send_time = EXCLUDED.latest_msg_send_time, " ++
            "latest_msg_send_id = EXCLUDED.latest_msg_send_id, latest_msg_content_type = EXCLUDED.latest_msg_content_type, " ++
            "max_seq = GREATEST(conversations.max_seq, EXCLUDED.max_seq), " ++
            "group_at_type = GREATEST(conversations.group_at_type, EXCLUDED.group_at_type), update_time = NOW()";
        const params = &[_]db_mod.QueryParam{
            .{ .string = owner_user_id },
            .{ .string = conversation_id },
            .{ .smallint = conversation_type },
            .{ .string = user_id },
            .{ .string = group_id },
            .{ .bigint = max_seq },
            .{ .string = latest_msg },
            .{ .bigint = latest_send_time },
            .{ .string = latest_send_id },
            .{ .smallint = latest_content_type },
            .{ .smallint = group_at_type },
        };
        _ = try exec.execParams(sql, params);
    }

    /// One row of a batched conversation upsert.
    pub const UpsertItem = struct {
        owner_user_id: []const u8,
        conversation_id: []const u8,
        conversation_type: i16,
        user_id: []const u8,
        group_id: []const u8,
        latest_msg: []const u8,
        latest_send_time: i64,
        latest_send_id: []const u8,
        latest_content_type: i16,
        max_seq: i64,
        group_at_type: i16,
    };

    /// Bulk upsert for group-message fan-out: one multi-row INSERT instead of
    /// N single-row statements (large groups: N round-trips → 1).
    /// Max rows per multi-row INSERT: keeps parameters under PostgreSQL's
    /// 65535 bound and statement size sane for very large groups.
    const MAX_BATCH_ROWS = 500;

    pub fn upsertWithLatestBatch(self: *ConversationPersistence, exec: anytype, items: []const UpsertItem) !void {
        if (items.len == 0) return;
        var idx: usize = 0;
        while (idx < items.len) : (idx += MAX_BATCH_ROWS) {
            const chunk = items[idx..@min(idx + MAX_BATCH_ROWS, items.len)];
            try self.upsertChunk(exec, chunk);
        }
    }

    fn upsertChunk(self: *ConversationPersistence, exec: anytype, items: []const UpsertItem) !void {
        const per = 11; // parameters per row
        var sql_builder = std.ArrayList(u8).empty;
        defer sql_builder.deinit(self.allocator);
        try sql_builder.appendSlice(self.allocator, "INSERT INTO conversations (owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, create_time, update_time) VALUES ");
        var params = std.ArrayList(db_mod.QueryParam).empty;
        defer params.deinit(self.allocator);
        for (items, 0..) |it, i| {
            if (i > 0) try sql_builder.appendSlice(self.allocator, ", ");
            const base: usize = i * per;
            var buf: [256]u8 = undefined;
            const row = try std.fmt.bufPrint(
                &buf,
                "(${d}, ${d}, ${d}, ${d}, ${d}, 0, FALSE, FALSE, 0, '', '', ${d}, 0, 0, ${d}, ${d}, ${d}, ${d}, ${d}, NOW(), NOW())",
                .{ base + 1, base + 2, base + 3, base + 4, base + 5, base + 6, base + 7, base + 8, base + 9, base + 10, base + 11 },
            );
            try sql_builder.appendSlice(self.allocator, row);
            try params.append(self.allocator, .{ .string = it.owner_user_id });
            try params.append(self.allocator, .{ .string = it.conversation_id });
            try params.append(self.allocator, .{ .smallint = it.conversation_type });
            try params.append(self.allocator, .{ .string = it.user_id });
            try params.append(self.allocator, .{ .string = it.group_id });
            try params.append(self.allocator, .{ .bigint = it.max_seq });
            try params.append(self.allocator, .{ .string = it.latest_msg });
            try params.append(self.allocator, .{ .bigint = it.latest_send_time });
            try params.append(self.allocator, .{ .string = it.latest_send_id });
            try params.append(self.allocator, .{ .smallint = it.latest_content_type });
            try params.append(self.allocator, .{ .smallint = it.group_at_type });
        }
        try sql_builder.appendSlice(self.allocator, " ON CONFLICT (owner_user_id, conversation_id) DO UPDATE SET latest_msg = EXCLUDED.latest_msg, latest_msg_send_time = EXCLUDED.latest_msg_send_time, latest_msg_send_id = EXCLUDED.latest_msg_send_id, latest_msg_content_type = EXCLUDED.latest_msg_content_type, max_seq = GREATEST(conversations.max_seq, EXCLUDED.max_seq), group_at_type = GREATEST(conversations.group_at_type, EXCLUDED.group_at_type), update_time = NOW()");
        const sql = try sql_builder.toOwnedSlice(self.allocator);
        defer self.allocator.free(sql);
        _ = try exec.execParams(sql, params.items);
    }

    // ── Conversations ─────────────────────────────────────────────

    pub fn create(self: *ConversationPersistence, input: model.ConversationCreateInput) !model.Conversation {
        const conv_type = @intFromEnum(input.conversation_type);
        const pinned: i16 = if (false) 1 else 0;
        const private_chat: i16 = if (input.is_private_chat) 1 else 0;

        const sql = "INSERT INTO conversations (owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, create_time, update_time) " ++
            "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, '', $10, NOW(), NOW())" ++
            " RETURNING id, owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, EXTRACT(EPOCH FROM create_time)::bigint, EXTRACT(EPOCH FROM update_time)::bigint, is_msg_destruct, msg_destruct_time";
        const params = &[_]db_mod.QueryParam{
            .{ .string = input.owner_user_id },
            .{ .string = input.conversation_id },
            .{ .smallint = conv_type },
            .{ .string = input.user_id },
            .{ .string = input.group_id },
            .{ .smallint = input.recv_msg_opt },
            .{ .smallint = pinned },
            .{ .smallint = private_chat },
            .{ .int = input.burn_duration },
            .{ .string = input.ex },
        };
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return error.InsertFailed;
        return try rowToConversation(self.allocator, result.rows[0]);
    }

    pub fn get(self: *ConversationPersistence, owner_user_id: []const u8, conversation_id: []const u8) !?model.Conversation {
        const sql = "SELECT id, owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, EXTRACT(EPOCH FROM create_time)::bigint, EXTRACT(EPOCH FROM update_time)::bigint, is_msg_destruct, msg_destruct_time FROM conversations WHERE owner_user_id = $1 AND conversation_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .string = conversation_id } };
        const result = self.db.queryParams(sql, params) catch return null;
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return null;
        return try rowToConversation(self.allocator, result.rows[0]);
    }

    pub fn getByOwner(self: *ConversationPersistence, allocator: std.mem.Allocator, owner_user_id: []const u8) ![]model.Conversation {
        _ = allocator;
        const sql = "SELECT id, owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, EXTRACT(EPOCH FROM create_time)::bigint, EXTRACT(EPOCH FROM update_time)::bigint, is_msg_destruct, msg_destruct_time FROM conversations WHERE owner_user_id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = owner_user_id }};
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);

        var list = std.ArrayList(model.Conversation).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, try rowToConversation(self.allocator, row));
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn getByOwnerSince(self: *ConversationPersistence, allocator: std.mem.Allocator, owner_user_id: []const u8, since_timestamp: i64) ![]model.Conversation {
        _ = allocator;
        const sql = "SELECT id, owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, EXTRACT(EPOCH FROM create_time)::bigint, EXTRACT(EPOCH FROM update_time)::bigint, is_msg_destruct, msg_destruct_time FROM conversations WHERE owner_user_id = $1 AND EXTRACT(EPOCH FROM update_time)::bigint > $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .bigint = since_timestamp } };
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);

        var list = std.ArrayList(model.Conversation).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, try rowToConversation(self.allocator, row));
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn update(self: *ConversationPersistence, owner_user_id: []const u8, conversation_id: []const u8, input: model.ConversationUpdateInput) !?model.Conversation {
        var set_parts = std.ArrayList([]const u8).empty;
        defer set_parts.deinit(self.allocator);
        var params = std.ArrayList(db_mod.QueryParam).empty;
        defer params.deinit(self.allocator);
        var idx: i32 = 1;

        if (input.recv_msg_opt) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "recv_msg_opt = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }
        if (input.is_pinned) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "is_pinned = ${d}", .{idx}));
            try params.append(self.allocator, .{ .bool = v });
            idx += 1;
        }
        if (input.group_at_type) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "group_at_type = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }
        if (input.attached_info) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "attached_info = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.ex) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ex = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.is_msg_destruct) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "is_msg_destruct = ${d}", .{idx}));
            try params.append(self.allocator, .{ .bool = v });
            idx += 1;
        }
        if (input.msg_destruct_time) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "msg_destruct_time = ${d}", .{idx}));
            try params.append(self.allocator, .{ .bigint = v });
            idx += 1;
        }
        if (input.latest_msg) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "latest_msg = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.latest_msg_send_time) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "latest_msg_send_time = ${d}", .{idx}));
            try params.append(self.allocator, .{ .bigint = v });
            idx += 1;
        }
        if (input.latest_msg_send_id) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "latest_msg_send_id = ${d}", .{idx}));
            try params.append(self.allocator, .{ .string = v });
            idx += 1;
        }
        if (input.latest_msg_content_type) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "latest_msg_content_type = ${d}", .{idx}));
            try params.append(self.allocator, .{ .smallint = v });
            idx += 1;
        }
        if (input.has_read_seq) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "has_read_seq = ${d}", .{idx}));
            try params.append(self.allocator, .{ .bigint = v });
            idx += 1;
        }
        if (input.max_seq) |v| {
            try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "max_seq = ${d}", .{idx}));
            try params.append(self.allocator, .{ .bigint = v });
            idx += 1;
        }

        if (set_parts.items.len == 0) return self.get(owner_user_id, conversation_id);

        try set_parts.append(self.allocator, "update_time = NOW()");
        var set_clause = std.ArrayList(u8).empty;
        defer set_clause.deinit(self.allocator);
        for (set_parts.items, 0..) |part, i| {
            if (i > 0) try set_clause.appendSlice(self.allocator, ", ");
            try set_clause.appendSlice(self.allocator, part);
        }

        const sql = try std.fmt.allocPrint(self.allocator, "UPDATE conversations SET {s} WHERE owner_user_id = ${d} AND conversation_id = ${d}", .{ set_clause.items, idx, idx + 1 });
        defer self.allocator.free(sql);
        try params.append(self.allocator, .{ .string = owner_user_id });
        try params.append(self.allocator, .{ .string = conversation_id });

        _ = try self.db.execParams(sql, params.items);
        return self.get(owner_user_id, conversation_id);
    }

    pub fn delete(self: *ConversationPersistence, owner_user_id: []const u8, conversation_id: []const u8) bool {
        const sql = "DELETE FROM conversations WHERE owner_user_id = $1 AND conversation_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .string = conversation_id } };
        _ = self.db.execParams(sql, params) catch return false;
        return true;
    }

    pub fn updateSeq(self: *ConversationPersistence, owner_user_id: []const u8, conversation_id: []const u8, max_seq: i64) !void {
        const sql = "UPDATE conversations SET max_seq = $1, update_time = NOW() WHERE owner_user_id = $2 AND conversation_id = $3";
        const params = &[_]db_mod.QueryParam{ .{ .bigint = max_seq }, .{ .string = owner_user_id }, .{ .string = conversation_id } };
        _ = try self.db.execParams(sql, params);
    }

    pub fn count(self: *ConversationPersistence) usize {
        const sql = "SELECT COUNT(*) FROM conversations";
        const result = self.db.query(sql) catch return 0;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(usize, result.rows[0][0], 10) catch 0;
    }

    // ── Encryption keys ───────────────────────────────────────────

    pub fn getEncryptionKeys(self: *ConversationPersistence, conversation_id: []const u8, allocator: std.mem.Allocator) ![]model.VersionKey {
        const sql = "SELECT version, key_data FROM encryption_keys WHERE conversation_id = $1 ORDER BY version DESC";
        const params = &[_]db_mod.QueryParam{.{ .string = conversation_id }};
        const result = self.db.queryParams(sql, params) catch return allocator.alloc(model.VersionKey, 0);
        defer freeResult(self.allocator, result);

        var list = try allocator.alloc(model.VersionKey, result.row_count);
        for (0..result.row_count) |i| {
            list[i] = .{
                .version = try std.fmt.parseInt(i32, result.rows[i][0], 10),
                .key = try allocator.dupe(u8, result.rows[i][1]),
            };
        }
        return list;
    }

    pub fn genEncryptionKey(self: *ConversationPersistence, conversation_id: []const u8) !void {
        const version_sql = "SELECT COALESCE(MAX(version), 0) FROM encryption_keys WHERE conversation_id = $1";
        const v_params = &[_]db_mod.QueryParam{.{ .string = conversation_id }};
        const v_result = self.db.queryParams(version_sql, v_params) catch return;
        defer freeResult(self.allocator, v_result);
        const next_version: i32 = if (v_result.row_count > 0)
            (std.fmt.parseInt(i32, v_result.rows[0][0], 10) catch 0) + 1
        else
            1;

        const key_data = generateAESKey(self.allocator) catch return;
        defer self.allocator.free(key_data);

        const insert_sql = "INSERT INTO encryption_keys (conversation_id, version, key_data) VALUES ($1, $2, $3)";
        const i_params = &[_]db_mod.QueryParam{
            .{ .string = conversation_id },
            .{ .smallint = @intCast(next_version) },
            .{ .string = key_data },
        };
        _ = self.db.execParams(insert_sql, i_params) catch {};
    }
};
