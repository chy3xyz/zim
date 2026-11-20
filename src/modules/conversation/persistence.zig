const std = @import("std");
const core = @import("core");
const db_mod = @import("../../modules/db_postgres.zig");
const zent = @import("zent");
const zent_db = @import("../../zent_db.zig");
const model = @import("model.zig");

/// Full-row projection shared by get/getByOwner/getByOwnerSince — epoch
/// columns aliased to the model field names so sql_scan maps by name.
const CONV_SELECT = "SELECT id, owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, EXTRACT(EPOCH FROM create_time)::bigint AS create_time, EXTRACT(EPOCH FROM update_time)::bigint AS update_time, is_msg_destruct, msg_destruct_time FROM conversations";

/// sql_scan DTO for a full conversations row. `conversation_type` stays i16:
/// the scanner zero-initializes DTO structs, and model.ConversationType has
/// no tag 0 (comptime failure) — the enum is materialized in convRowToModel.
/// Scanner-duplicated strings transfer into model.Conversation (same
/// request-scoped lifetime contract as rowToConversation).
const ConvRow = struct {
    id: []const u8,
    owner_user_id: []const u8,
    conversation_id: []const u8,
    conversation_type: i16,
    user_id: []const u8,
    group_id: []const u8,
    recv_msg_opt: i16,
    is_pinned: bool,
    is_private_chat: bool,
    burn_duration: i64,
    attached_info: []const u8,
    ex: []const u8,
    max_seq: i64,
    min_seq: i64,
    has_read_seq: i64,
    latest_msg: []const u8,
    latest_msg_send_time: i64,
    latest_msg_send_id: []const u8,
    latest_msg_content_type: i16,
    group_at_type: i16,
    create_time: i64,
    update_time: i64,
    is_msg_destruct: bool,
    msg_destruct_time: i64,
};

fn convRowToModel(row: ConvRow) model.Conversation {
    return .{
        .id = row.id,
        .owner_user_id = row.owner_user_id,
        .conversation_id = row.conversation_id,
        .conversation_type = @fromBackingInt(@intCast(row.conversation_type)),
        .user_id = row.user_id,
        .group_id = row.group_id,
        .recv_msg_opt = row.recv_msg_opt,
        .is_pinned = row.is_pinned,
        .is_private_chat = row.is_private_chat,
        .burn_duration = @intCast(row.burn_duration),
        .attached_info = row.attached_info,
        .ex = row.ex,
        .max_seq = row.max_seq,
        .min_seq = row.min_seq,
        .has_read_seq = row.has_read_seq,
        .latest_msg = row.latest_msg,
        .latest_msg_send_time = row.latest_msg_send_time,
        .latest_msg_send_id = row.latest_msg_send_id,
        .latest_msg_content_type = row.latest_msg_content_type,
        .group_at_type = row.group_at_type,
        .create_time = row.create_time,
        .update_time = row.update_time,
        .is_msg_destruct = row.is_msg_destruct,
        .msg_destruct_time = row.msg_destruct_time,
    };
}

fn rowToConversation(allocator: std.mem.Allocator, row: []const []const u8) !model.Conversation {
    return model.Conversation{
        .id = try allocator.dupe(u8, row[0]),
        .owner_user_id = try allocator.dupe(u8, row[1]),
        .conversation_id = try allocator.dupe(u8, row[2]),
        .conversation_type = @fromBackingInt(@intCast(try std.fmt.parseInt(i16, row[3], 10))),
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

/// RFC 4122 v4 UUID from the OS CSPRNG (random UUID) — conversations.id is
/// DB-defaulted (`uuid_generate_v4()`) in the legacy branch, but the zent
/// typed upsert requires a caller-provided text pk (zent v0.84+ policy).
fn generateUuidV4(allocator: std.mem.Allocator) ![]const u8 {
    var bytes: [16]u8 = undefined;
    core.secureRandomBytes(&bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    var hex: [32]u8 = undefined;
    const charset = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        hex[i * 2] = charset[b >> 4];
        hex[i * 2 + 1] = charset[b & 0x0f];
    }
    return std.fmt.allocPrint(allocator, "{s}-{s}-{s}-{s}-{s}", .{
        hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32],
    });
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

    /// Typed upsert shared by the direct (pooled client) and transactional
    /// (TxClient client view) zent paths. GREATEST keeps max_seq/group_at_type
    /// monotonic; the caller-provided UUID pk is preserved on conflict.
    fn upsertWithLatestOnClient(client: zent_db.ClientType, owner_user_id: []const u8, conversation_id: []const u8, conversation_type: i16, user_id: []const u8, group_id: []const u8, latest_msg: []const u8, latest_send_time: i64, latest_send_id: []const u8, latest_content_type: i16, max_seq: i64, group_at_type: i16) !void {
        var b = try client.conversation.Create();
        defer b.deinit();
        // zent v0.84+ requires a caller-provided text pk; generate a v4
        // UUID and keep the existing id on the conflict path.
        const new_id = try generateUuidV4(core.getAllocator());
        _ = try b.setFieldValue("id", new_id);
        _ = try b.setFieldValue("owner_user_id", owner_user_id);
        _ = try b.setFieldValue("conversation_id", conversation_id);
        // zent schema fields are i64 — smallint inputs cast at the boundary
        _ = try b.setFieldValue("conversation_type", @as(i64, conversation_type));
        _ = try b.setFieldValue("user_id", user_id);
        _ = try b.setFieldValue("group_id", group_id);
        _ = try b.setFieldValue("latest_msg", latest_msg);
        _ = try b.setFieldValue("latest_msg_send_time", latest_send_time);
        _ = try b.setFieldValue("latest_msg_send_id", latest_send_id);
        _ = try b.setFieldValue("latest_msg_content_type", @as(i64, latest_content_type));
        _ = try b.setFieldValue("max_seq", max_seq);
        _ = try b.setFieldValue("group_at_type", @as(i64, group_at_type));
        var created = try b.SaveOrUpdateOnWith(
            &.{ "owner_user_id", "conversation_id" },
            &.{
                .{ .column = "id", .expr = "{t:id}" },
                .{ .column = "max_seq", .expr = "GREATEST({t:max_seq}, {x:max_seq})" },
                .{ .column = "group_at_type", .expr = "GREATEST({t:group_at_type}, {x:group_at_type})" },
                .{ .column = "update_time", .expr = "NOW()" },
            },
        );
        zent_db.deinitRow(@TypeOf(client.conversation).entity_info, &created);
    }

    /// Upsert a conversation with the latest message info in one statement.
    /// `exec` may be a `*PostgresClient` or a `*Tx` (transactional message send).
    /// max_seq is monotonic (GREATEST) so out-of-order sends never regress it.
    ///
    /// zent path (preferred): typed `SaveOrUpdateOnWith` against the
    /// UNIQUE (owner_user_id, conversation_id) business key — the GREATEST
    /// monotonic columns ride the `{t:col}/{x:col}` upsert expression
    /// templates (docs/zent-migration.md). Guarded by a comptime type check:
    /// a legacy `*Tx` must stay on the legacy branch — the zent pool holds a
    /// different connection, and mixing them would break the send
    /// transaction's atomicity.
    pub fn upsertWithLatest(self: *ConversationPersistence, exec: anytype, owner_user_id: []const u8, conversation_id: []const u8, conversation_type: i16, user_id: []const u8, group_id: []const u8, latest_msg: []const u8, latest_send_time: i64, latest_send_id: []const u8, latest_content_type: i16, max_seq: i64, group_at_type: i16) !void {
        _ = self;
        // Inside a zent transaction the caller passes the TxClient's typed
        // client view — the upsert rides the transaction connection via the
        // typed builder (Phase 86 activates this branch from sendInTx).
        if (@TypeOf(exec) == zent_db.ClientType) {
            try upsertWithLatestOnClient(exec, owner_user_id, conversation_id, conversation_type, user_id, group_id, latest_msg, latest_send_time, latest_send_id, latest_content_type, max_seq, group_at_type);
            return;
        }
        if (zent_db.getClient() != null and @TypeOf(exec) == *db_mod.PostgresClient) {
            try upsertWithLatestOnClient(zent_db.getClient().?.*, owner_user_id, conversation_id, conversation_type, user_id, group_id, latest_msg, latest_send_time, latest_send_id, latest_content_type, max_seq, group_at_type);
            return;
        }
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

    /// zent-tx batch variant: identical multi-row SQL, executed through the
    /// transaction's own driver so the fan-out stays atomic with the message
    /// insert (Phase 86). Parameter construction switches QueryParam → Value.
    pub fn upsertWithLatestBatchZent(self: *ConversationPersistence, tx: zent.sql_driver.Tx, items: []const UpsertItem) !void {
        if (items.len == 0) return;
        var idx: usize = 0;
        while (idx < items.len) : (idx += MAX_BATCH_ROWS) {
            const chunk = items[idx..@min(idx + MAX_BATCH_ROWS, items.len)];
            try self.upsertChunkZent(tx, chunk);
        }
    }

    fn upsertChunkZent(self: *ConversationPersistence, tx: zent.sql_driver.Tx, items: []const UpsertItem) !void {
        const per = 11;
        var sql_builder = std.ArrayList(u8).empty;
        defer sql_builder.deinit(self.allocator);
        try sql_builder.appendSlice(self.allocator, "INSERT INTO conversations (owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, create_time, update_time) VALUES ");
        var args = std.ArrayList(zent.sql.Value).empty;
        defer args.deinit(self.allocator);
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
            try args.appendSlice(self.allocator, &.{
                .{ .string = it.owner_user_id },
                .{ .string = it.conversation_id },
                .{ .int = it.conversation_type },
                .{ .string = it.user_id },
                .{ .string = it.group_id },
                .{ .int = it.max_seq },
                .{ .string = it.latest_msg },
                .{ .int = it.latest_send_time },
                .{ .string = it.latest_send_id },
                .{ .int = it.latest_content_type },
                .{ .int = it.group_at_type },
            });
        }
        try sql_builder.appendSlice(self.allocator, " ON CONFLICT (owner_user_id, conversation_id) DO UPDATE SET latest_msg = EXCLUDED.latest_msg, latest_msg_send_time = EXCLUDED.latest_msg_send_time, latest_msg_send_id = EXCLUDED.latest_msg_send_id, latest_msg_content_type = EXCLUDED.latest_msg_content_type, max_seq = GREATEST(conversations.max_seq, EXCLUDED.max_seq), group_at_type = GREATEST(conversations.group_at_type, EXCLUDED.group_at_type), update_time = NOW()");
        const sql = try sql_builder.toOwnedSlice(self.allocator);
        defer self.allocator.free(sql);
        _ = try tx.exec(sql, args.items);
    }

    // ── Conversations ─────────────────────────────────────────────

    pub fn create(self: *ConversationPersistence, input: model.ConversationCreateInput) !model.Conversation {
        const conv_type = @backingInt(input.conversation_type);
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
        // zent path (preferred): DTO scan by column name — the projection is
        // an expression (EXTRACT epoch) so raw SQL is the right tool
        // (BEST_PRACTICES §1).
        if (zent_db.getDriver()) |drv| {
            const row = (zent.sql_scan.queryOne(
                ConvRow,
                self.allocator,
                drv,
                CONV_SELECT ++ " WHERE owner_user_id = $1 AND conversation_id = $2",
                &.{ .{ .string = owner_user_id }, .{ .string = conversation_id } },
            ) catch return null) orelse return null;
            return convRowToModel(row);
        }
        const sql = "SELECT id, owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, group_at_type, EXTRACT(EPOCH FROM create_time)::bigint, EXTRACT(EPOCH FROM update_time)::bigint, is_msg_destruct, msg_destruct_time FROM conversations WHERE owner_user_id = $1 AND conversation_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .string = conversation_id } };
        const result = self.db.queryParams(sql, params) catch return null;
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return null;
        return try rowToConversation(self.allocator, result.rows[0]);
    }

    pub fn getByOwner(self: *ConversationPersistence, allocator: std.mem.Allocator, owner_user_id: []const u8) ![]model.Conversation {
        _ = allocator;
        if (zent_db.getDriver()) |drv| {
            var rows = try zent.sql_scan.queryAll(
                ConvRow,
                self.allocator,
                drv,
                CONV_SELECT ++ " WHERE owner_user_id = $1",
                &.{.{ .string = owner_user_id }},
            );
            defer rows.deinit();
            const list = try self.allocator.alloc(model.Conversation, rows.items.len);
            for (rows.items, 0..) |row, i| list[i] = convRowToModel(row);
            return list;
        }
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
        if (zent_db.getDriver()) |drv| {
            var rows = try zent.sql_scan.queryAll(
                ConvRow,
                self.allocator,
                drv,
                CONV_SELECT ++ " WHERE owner_user_id = $1 AND EXTRACT(EPOCH FROM update_time)::bigint > $2",
                &.{ .{ .string = owner_user_id }, .{ .int = since_timestamp } },
            );
            defer rows.deinit();
            const list = try self.allocator.alloc(model.Conversation, rows.items.len);
            for (rows.items, 0..) |row, i| list[i] = convRowToModel(row);
            return list;
        }
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
        // zent path (preferred): dynamic SET plus the non-schema update_time
        // column is raw-by-design (BEST_PRACTICES §1 decision table), so this
        // rides drv.exec through the zent pool — same statement as legacy.
        if (zent_db.getDriver()) |drv| {
            var set_parts = std.ArrayList([]const u8).empty;
            defer set_parts.deinit(self.allocator);
            var args = std.ArrayList(zent.sql.Value).empty;
            defer args.deinit(self.allocator);
            var idx: i32 = 1;

            if (input.recv_msg_opt) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "recv_msg_opt = ${d}", .{idx}));
                try args.append(self.allocator, .{ .int = v });
                idx += 1;
            }
            if (input.is_pinned) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "is_pinned = ${d}", .{idx}));
                try args.append(self.allocator, .{ .bool = v });
                idx += 1;
            }
            if (input.group_at_type) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "group_at_type = ${d}", .{idx}));
                try args.append(self.allocator, .{ .int = v });
                idx += 1;
            }
            if (input.attached_info) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "attached_info = ${d}", .{idx}));
                try args.append(self.allocator, .{ .string = v });
                idx += 1;
            }
            if (input.ex) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ex = ${d}", .{idx}));
                try args.append(self.allocator, .{ .string = v });
                idx += 1;
            }
            if (input.is_msg_destruct) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "is_msg_destruct = ${d}", .{idx}));
                try args.append(self.allocator, .{ .bool = v });
                idx += 1;
            }
            if (input.msg_destruct_time) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "msg_destruct_time = ${d}", .{idx}));
                try args.append(self.allocator, .{ .int = v });
                idx += 1;
            }
            if (input.latest_msg) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "latest_msg = ${d}", .{idx}));
                try args.append(self.allocator, .{ .string = v });
                idx += 1;
            }
            if (input.latest_msg_send_time) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "latest_msg_send_time = ${d}", .{idx}));
                try args.append(self.allocator, .{ .int = v });
                idx += 1;
            }
            if (input.latest_msg_send_id) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "latest_msg_send_id = ${d}", .{idx}));
                try args.append(self.allocator, .{ .string = v });
                idx += 1;
            }
            if (input.latest_msg_content_type) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "latest_msg_content_type = ${d}", .{idx}));
                try args.append(self.allocator, .{ .int = v });
                idx += 1;
            }
            if (input.has_read_seq) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "has_read_seq = ${d}", .{idx}));
                try args.append(self.allocator, .{ .int = v });
                idx += 1;
            }
            if (input.max_seq) |v| {
                try set_parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "max_seq = ${d}", .{idx}));
                try args.append(self.allocator, .{ .int = v });
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
            try args.append(self.allocator, .{ .string = owner_user_id });
            try args.append(self.allocator, .{ .string = conversation_id });
            _ = try drv.exec(sql, args.items);
            return self.get(owner_user_id, conversation_id);
        }
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
        if (zent_db.getClient()) |client| {
            const preds = client.conversation.predicates;
            _ = zent.crud_helpers.delete(client.conversation, .{
                preds.owner_user_idEQ(.{ .string = owner_user_id }),
                preds.conversation_idEQ(.{ .string = conversation_id }),
            }) catch return false;
            return true;
        }
        const sql = "DELETE FROM conversations WHERE owner_user_id = $1 AND conversation_id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = owner_user_id }, .{ .string = conversation_id } };
        _ = self.db.execParams(sql, params) catch return false;
        return true;
    }

    pub fn updateSeq(self: *ConversationPersistence, owner_user_id: []const u8, conversation_id: []const u8, max_seq: i64) !void {
        // update_time is a non-schema column → raw through the zent pool.
        if (zent_db.getDriver()) |drv| {
            _ = try drv.exec(
                "UPDATE conversations SET max_seq = $1, update_time = NOW() WHERE owner_user_id = $2 AND conversation_id = $3",
                &.{ .{ .int = max_seq }, .{ .string = owner_user_id }, .{ .string = conversation_id } },
            );
            return;
        }
        const sql = "UPDATE conversations SET max_seq = $1, update_time = NOW() WHERE owner_user_id = $2 AND conversation_id = $3";
        const params = &[_]db_mod.QueryParam{ .{ .bigint = max_seq }, .{ .string = owner_user_id }, .{ .string = conversation_id } };
        _ = try self.db.execParams(sql, params);
    }

    pub fn count(self: *ConversationPersistence) usize {
        // zent path (preferred): typed aggregate (BEST_PRACTICES §4).
        if (zent_db.getClient()) |client| {
            var q = client.conversation.Query();
            defer q.deinit();
            const n = q.Count() catch return 0;
            return @intCast(@max(n, 0));
        }
        const sql = "SELECT COUNT(*) FROM conversations";
        const result = self.db.query(sql) catch return 0;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(usize, result.rows[0][0], 10) catch 0;
    }

    // ── Encryption keys ───────────────────────────────────────────

    pub fn getEncryptionKeys(self: *ConversationPersistence, conversation_id: []const u8, allocator: std.mem.Allocator) ![]model.VersionKey {
        if (zent_db.getDriver()) |drv| {
            var rows = try zent.sql_scan.queryAll(
                model.VersionKey,
                allocator,
                drv,
                "SELECT version, key_data AS key FROM encryption_keys WHERE conversation_id = $1 ORDER BY version DESC",
                &.{.{ .string = conversation_id }},
            );
            return rows.toOwnedSlice();
        }
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
        if (zent_db.getDriver()) |drv| {
            const MaxVersion = struct { max: ?i64 };
            const row = (zent.sql_scan.queryOne(
                MaxVersion,
                self.allocator,
                drv,
                "SELECT MAX(version) AS max FROM encryption_keys WHERE conversation_id = $1",
                &.{.{ .string = conversation_id }},
            ) catch return) orelse return;
            const next_version: i32 = @intCast((row.max orelse 0) + 1);

            const key_data = generateAESKey(self.allocator) catch return;
            defer self.allocator.free(key_data);

            _ = drv.exec(
                "INSERT INTO encryption_keys (conversation_id, version, key_data) VALUES ($1, $2, $3)",
                &.{ .{ .string = conversation_id }, .{ .int = next_version }, .{ .string = key_data } },
            ) catch {};
            return;
        }
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
