const std = @import("std");
const core = @import("core");
const db_mod = @import("../db_postgres.zig");
const model = @import("model.zig");

pub const MessagePersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) MessagePersistence {
        return MessagePersistence{
            .allocator = allocator,
            .db = db,
        };
    }

    pub fn deinit(self: *MessagePersistence) void {
        _ = self;
    }

    // ── Statistics (active users / groups) ───────────────────────
    // `group_mode` = true counts group messages (group_id != ''), false counts
    // single-chat messages. Timestamps are epoch seconds on create_time.

    pub fn activeMsgCount(self: *MessagePersistence, start_time: i64, end_time: i64, group_mode: bool) usize {
        const sql = if (group_mode)
            "SELECT COUNT(*) FROM messages WHERE group_id != '' AND EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2"
        else
            "SELECT COUNT(*) FROM messages WHERE group_id = '' AND EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2";
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

    pub fn activeEntityCount(self: *MessagePersistence, start_time: i64, end_time: i64, group_mode: bool) usize {
        const sql = if (group_mode)
            "SELECT COUNT(DISTINCT group_id) FROM messages WHERE group_id != '' AND EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2"
        else
            "SELECT COUNT(DISTINCT sender_id) FROM messages WHERE group_id = '' AND EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2";
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

    pub fn activeDateCount(self: *MessagePersistence, allocator: std.mem.Allocator, start_time: i64, end_time: i64, group_mode: bool) ![]model.DayCount {
        const sql = if (group_mode)
            "SELECT to_char(create_time AT TIME ZONE 'UTC', 'YYYY-MM-DD'), COUNT(*) FROM messages WHERE group_id != '' AND EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2 GROUP BY 1 ORDER BY 1"
        else
            "SELECT to_char(create_time AT TIME ZONE 'UTC', 'YYYY-MM-DD'), COUNT(*) FROM messages WHERE group_id = '' AND EXTRACT(EPOCH FROM create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM create_time)::bigint <= $2 GROUP BY 1 ORDER BY 1";
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

    /// Top senders (user mode) or top groups (group mode) by message count.
    pub fn activeTopEntities(self: *MessagePersistence, allocator: std.mem.Allocator, start_time: i64, end_time: i64, group_mode: bool, limit: i64) ![]model.TopEntity {
        const sql = if (group_mode)
            "SELECT m.group_id, g.group_name, g.face_url, COUNT(*) FROM messages m JOIN groups g ON m.group_id = g.group_id WHERE m.group_id != '' AND EXTRACT(EPOCH FROM m.create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM m.create_time)::bigint <= $2 GROUP BY m.group_id, g.group_name, g.face_url ORDER BY 4 DESC LIMIT $3"
        else
            "SELECT m.sender_id, u.nickname, u.face_url, COUNT(*) FROM messages m JOIN users u ON m.sender_id = u.user_id WHERE m.group_id = '' AND EXTRACT(EPOCH FROM m.create_time)::bigint >= $1 AND EXTRACT(EPOCH FROM m.create_time)::bigint <= $2 GROUP BY m.sender_id, u.nickname, u.face_url ORDER BY 4 DESC LIMIT $3";
        const params = &[_]db_mod.QueryParam{ .{ .bigint = start_time }, .{ .bigint = end_time }, .{ .bigint = limit } };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        var list = std.ArrayList(model.TopEntity).empty;
        defer list.deinit(allocator);
        for (result.rows) |row| {
            try list.append(allocator, .{
                .id = try allocator.dupe(u8, row[0]),
                .name = try allocator.dupe(u8, row[1]),
                .face_url = try allocator.dupe(u8, row[2]),
                .count = try std.fmt.parseInt(i64, row[3], 10),
            });
        }
        return list.toOwnedSlice(allocator);
    }

    fn escapeString(self: *MessagePersistence, s: []const u8) []u8 {
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

    fn generateMsgID(allocator: std.mem.Allocator) ![]const u8 {
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

    fn getSendTime() i64 {
        return core.unixNowMillis();
    }

    fn optionsToJson(allocator: std.mem.Allocator, opts: model.MessageOptions) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{{\"isHistory\":{s},\"isPersistent\":{s},\"isSenderSync\":{s},\"isOfflinePush\":{s},\"isUnreadCount\":{s},\"isNotNotification\":{s}}}", .{
            if (opts.is_history) "true" else "false",
            if (opts.is_persistent) "true" else "false",
            if (opts.is_sender_sync) "true" else "false",
            if (opts.is_offline_push) "true" else "false",
            if (opts.is_unread_count) "true" else "false",
            if (opts.is_not_notification) "true" else "false",
        });
    }

    pub fn send(self: *MessagePersistence, input: model.MessageSendInput) !model.Message {
        return self.sendOn(self.db, input);
    }

    /// Transactional variant: message insert + conversation sync run on the
    /// same `Tx` so a failed sync rolls back the insert (no orphan messages).
    pub fn sendTx(self: *MessagePersistence, tx: *db_mod.Tx, input: model.MessageSendInput) !model.Message {
        return self.sendOn(tx, input);
    }

    fn sendOn(self: *MessagePersistence, exec: anytype, input: model.MessageSendInput) !model.Message {
        const client_msg_id = try generateMsgID(self.allocator);
        const server_msg_id = try generateMsgID(self.allocator);
        const is_notification = input.options.is_not_notification;
        const conversation_id = try model.getConversationID(input.send_id, input.recv_id, input.group_id, input.session_type, is_notification);
        const seq = try self.getNextSeqOn(exec, conversation_id);
        const now = getSendTime();
        const session_type_val = @backingInt(input.session_type);
        const content_type_val = @backingInt(input.content_type);

        const options_str = try optionsToJson(self.allocator, input.options);
        defer self.allocator.free(options_str);
        const offline_push_str = if (input.offline_push) |v| v else "{}";
        const at_list_str = if (input.at_user_id_list) |v| v else "[]";
        const ex_str = if (input.ex) |v| v else "";

        const sql = "INSERT INTO messages (conversation_id, sender_id, receiver_id, group_id, client_msg_id, server_msg_id, sender_platform_id, sender_nickname, sender_face_url, session_type, msg_from, content_type, content, seq, send_time, create_time, status, is_read, options, offline_push, at_user_id_list, attached_info, ex, key_version, is_revoke, revoke_content, is_edit, edit_time) " ++
            "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW(), 0, FALSE, $16, $17, $18, '', $19, 0, FALSE, '', FALSE, NULL) " ++
            "RETURNING msg_id, conversation_id, sender_id, receiver_id, group_id, client_msg_id, server_msg_id, sender_platform_id, sender_nickname, sender_face_url, session_type, msg_from, content_type, content, seq, send_time, EXTRACT(EPOCH FROM create_time)::bigint, status, is_read, options, offline_push, at_user_id_list, attached_info, ex, key_version, is_revoke, revoke_content, is_edit, COALESCE(EXTRACT(EPOCH FROM edit_time)::bigint, 0)";
        const params = &[_]db_mod.QueryParam{
            .{ .string = conversation_id },
            .{ .string = input.send_id },
            .{ .string = input.recv_id },
            .{ .string = input.group_id },
            .{ .string = client_msg_id },
            .{ .string = server_msg_id },
            .{ .smallint = input.sender_platform_id },
            .{ .string = input.sender_nickname },
            .{ .string = input.sender_face_url },
            .{ .smallint = session_type_val },
            .{ .smallint = input.msg_from },
            .{ .smallint = content_type_val },
            .{ .string = input.content },
            .{ .bigint = seq },
            .{ .bigint = now },
            .{ .string = options_str },
            .{ .string = offline_push_str },
            .{ .string = at_list_str },
            .{ .string = ex_str },
        };
        const result = try exec.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        if (result.row_count == 0) return error.InsertFailed;

        const row = result.rows[0];
        return self.parseMessageRow(row);
    }

    fn parseMessageRow(self: *MessagePersistence, row: []const []const u8) !model.Message {
        return model.Message{
            .msg_id = try self.allocator.dupe(u8, row[0]),
            .conversation_id = try self.allocator.dupe(u8, row[1]),
            .sender_id = try self.allocator.dupe(u8, row[2]),
            .receiver_id = try self.allocator.dupe(u8, row[3]),
            .group_id = try self.allocator.dupe(u8, row[4]),
            .client_msg_id = try self.allocator.dupe(u8, row[5]),
            .server_msg_id = try self.allocator.dupe(u8, row[6]),
            .sender_platform_id = try std.fmt.parseInt(i16, row[7], 10),
            .sender_nickname = try self.allocator.dupe(u8, row[8]),
            .sender_face_url = try self.allocator.dupe(u8, row[9]),
            .session_type = @fromBackingInt(@intCast(try std.fmt.parseInt(i16, row[10], 10))),
            .msg_from = try std.fmt.parseInt(i16, row[11], 10),
            .content_type = @fromBackingInt(@intCast(try std.fmt.parseInt(i16, row[12], 10))),
            .content = try self.allocator.dupe(u8, row[13]),
            .seq = try std.fmt.parseInt(i64, row[14], 10),
            .send_time = try std.fmt.parseInt(i64, row[15], 10),
            .create_time = try std.fmt.parseInt(i64, row[16], 10),
            .status = try std.fmt.parseInt(i16, row[17], 10),
            .is_read = row[18][0] == 't',
            .options = try self.allocator.dupe(u8, row[19]),
            .offline_push = try self.allocator.dupe(u8, row[20]),
            .at_user_id_list = try self.allocator.dupe(u8, row[21]),
            .attached_info = try self.allocator.dupe(u8, row[22]),
            .ex = try self.allocator.dupe(u8, row[23]),
            .key_version = try std.fmt.parseInt(i16, row[24], 10),
            .is_revoke = row[25][0] == 't',
            .revoke_content = try self.allocator.dupe(u8, row[26]),
            .is_edit = row[27][0] == 't',
            .edit_time = std.fmt.parseInt(i64, row[28], 10) catch 0,
        };
    }

    fn getNextSeqOn(self: *MessagePersistence, exec: anytype, conversation_id: []const u8) !i64 {
        // Atomic upsert: concurrent senders on the same conversation serialize
        // on the row lock and each get a distinct max_seq (previously a
        // SELECT-then-UPDATE race could hand out duplicate seqs).
        const sql = "INSERT INTO seq_conversations (conversation_id, max_seq, min_seq) VALUES ($1, 1, 0) " ++
            "ON CONFLICT (conversation_id) DO UPDATE SET max_seq = seq_conversations.max_seq + 1 RETURNING max_seq";
        const params = &[_]db_mod.QueryParam{.{ .string = conversation_id }};
        const result = try exec.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count > 0) {
            return std.fmt.parseInt(i64, result.rows[0][0], 10) catch 1;
        }
        return 1;
    }

    pub fn getByConversation(self: *MessagePersistence, allocator: std.mem.Allocator, conversation_id: []const u8, offset: i64, limit: i64) ![]model.Message {
        _ = allocator;
        const sql = "SELECT msg_id, conversation_id, sender_id, receiver_id, group_id, client_msg_id, server_msg_id, sender_platform_id, sender_nickname, sender_face_url, session_type, msg_from, content_type, content, seq, send_time, EXTRACT(EPOCH FROM create_time)::bigint, status, is_read, options, offline_push, at_user_id_list, attached_info, ex, key_version, is_revoke, revoke_content, is_edit, COALESCE(EXTRACT(EPOCH FROM edit_time)::bigint, 0) FROM messages WHERE conversation_id = $1 ORDER BY seq DESC LIMIT $2 OFFSET $3";
        const params = &[_]db_mod.QueryParam{
            .{ .string = conversation_id },
            .{ .bigint = limit },
            .{ .bigint = offset },
        };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.Message).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, try self.parseMessageRow(row));
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn getBySeqRange(self: *MessagePersistence, allocator: std.mem.Allocator, conversation_id: []const u8, begin_seq: i64, end_seq: i64, limit: i64, ascending: bool) ![]model.Message {
        _ = allocator;
        const order = if (ascending) "ASC" else "DESC";
        const sql = try std.fmt.allocPrint(self.allocator, "SELECT msg_id, conversation_id, sender_id, receiver_id, group_id, client_msg_id, server_msg_id, sender_platform_id, sender_nickname, sender_face_url, session_type, msg_from, content_type, content, seq, send_time, EXTRACT(EPOCH FROM create_time)::bigint, status, is_read, options, offline_push, at_user_id_list, attached_info, ex, key_version, is_revoke, revoke_content, is_edit, COALESCE(EXTRACT(EPOCH FROM edit_time)::bigint, 0) FROM messages WHERE conversation_id = $1 AND seq >= $2 AND seq <= $3 ORDER BY seq {s} LIMIT $4", .{order});
        defer self.allocator.free(sql);
        const params = &[_]db_mod.QueryParam{
            .{ .string = conversation_id },
            .{ .bigint = begin_seq },
            .{ .bigint = end_seq },
            .{ .bigint = limit },
        };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.Message).empty;
        defer list.deinit(self.allocator);

        for (result.rows) |row| {
            try list.append(self.allocator, try self.parseMessageRow(row));
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn getBySeqList(self: *MessagePersistence, allocator: std.mem.Allocator, conversation_id: []const u8, seqs: []const i64) ![]model.Message {
        _ = allocator;
        if (seqs.len == 0) return &[_]model.Message{};
        // Build IN clause manually (PostgreSQL doesn't support array parameters for IN in libpq easily)
        var sql_builder = std.ArrayList(u8).empty;
        defer sql_builder.deinit(self.allocator);
        try sql_builder.appendSlice(self.allocator, "SELECT msg_id, conversation_id, sender_id, receiver_id, group_id, client_msg_id, server_msg_id, sender_platform_id, sender_nickname, sender_face_url, session_type, msg_from, content_type, content, seq, send_time, EXTRACT(EPOCH FROM create_time)::bigint, status, is_read, options, offline_push, at_user_id_list, attached_info, ex, key_version, is_revoke, revoke_content, is_edit, COALESCE(EXTRACT(EPOCH FROM edit_time)::bigint, 0) FROM messages WHERE conversation_id = $1 AND seq IN (");
        var i: usize = 0;
        while (i < seqs.len) : (i += 1) {
            if (i > 0) try sql_builder.appendSlice(self.allocator, ",");
            const seq_str = try std.fmt.allocPrint(self.allocator, "{d}", .{seqs[i]});
            defer self.allocator.free(seq_str);
            try sql_builder.appendSlice(self.allocator, seq_str);
        }
        try sql_builder.appendSlice(self.allocator, ") ORDER BY seq DESC");
        const sql = try sql_builder.toOwnedSlice(self.allocator);
        defer self.allocator.free(sql);
        const params = &[_]db_mod.QueryParam{.{ .string = conversation_id }};
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        var list = std.ArrayList(model.Message).empty;
        defer list.deinit(self.allocator);
        // Index rows by seq so we can re-emit in the *requested* order,
        // matching Go's GetMsgBySeqs (which iterates the requested seqs).
        var by_seq = std.AutoHashMap(i64, model.Message).init(self.allocator);
        defer by_seq.deinit();
        for (result.rows) |row| {
            const msg = try self.parseMessageRow(row);
            try by_seq.put(msg.seq, msg);
        }
        for (seqs) |s| {
            if (by_seq.get(s)) |m| {
                try list.append(self.allocator, m);
            }
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn recall(self: *MessagePersistence, conversation_id: []const u8, seq: i64, user_id: []const u8) !bool {
        const revoke_json = try std.fmt.allocPrint(self.allocator, "{{\"user_id\":\"{s}\",\"time\":0}}", .{self.escapeString(user_id)});
        defer self.allocator.free(revoke_json);

        const sql = "UPDATE messages SET is_revoke = TRUE, revoke_content = $1 WHERE conversation_id = $2 AND seq = $3";
        const params = &[_]db_mod.QueryParam{
            .{ .string = revoke_json },
            .{ .string = conversation_id },
            .{ .bigint = seq },
        };
        _ = try self.db.execParams(sql, params);
        return true;
    }

    pub fn modifyMessage(self: *MessagePersistence, conversation_id: []const u8, seq: i64, user_id: []const u8, new_content: []const u8) !bool {
        const sql = "UPDATE messages SET content = $1, is_edit = TRUE, edit_time = NOW() WHERE conversation_id = $2 AND seq = $3 AND sender_id = $4";
        const params = &[_]db_mod.QueryParam{
            .{ .string = new_content },
            .{ .string = conversation_id },
            .{ .bigint = seq },
            .{ .string = user_id },
        };
        const r = try self.db.execParams(sql, params);
        return r > 0;
    }

    pub fn delete(self: *MessagePersistence, conversation_id: []const u8, seqs: []const i64, user_id: []const u8) !usize {
        _ = user_id;
        var deleted: usize = 0;
        for (seqs) |seq| {
            const sql = "DELETE FROM messages WHERE conversation_id = $1 AND seq = $2";
            const params = &[_]db_mod.QueryParam{
                .{ .string = conversation_id },
                .{ .bigint = seq },
            };
            _ = try self.db.execParams(sql, params);
            deleted += 1;
        }
        return deleted;
    }

    pub fn markRead(self: *MessagePersistence, owner_user_id: []const u8, conversation_id: []const u8, seq: i64) bool {
        const sql = "UPDATE messages SET is_read = TRUE WHERE conversation_id = $1 AND seq <= $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = conversation_id }, .{ .bigint = seq } };
        _ = self.db.execParams(sql, params) catch return false;
        // Advance the reader's conversation has_read_seq too (Go MarkMsgsAsRead
        // sets both is_read and the conversation read seq — otherwise unread
        // counts never drop for /msg/mark_msgs_as_read).
        const seq_sql = "UPDATE conversations SET has_read_seq = GREATEST(has_read_seq, $1) WHERE owner_user_id = $2 AND conversation_id = $3";
        const seq_params = &[_]db_mod.QueryParam{ .{ .bigint = seq }, .{ .string = owner_user_id }, .{ .string = conversation_id } };
        _ = self.db.execParams(seq_sql, seq_params) catch {};
        return true;
    }

    pub fn getMaxSeq(self: *MessagePersistence, conversation_id: []const u8) i64 {
        const sql = "SELECT max_seq FROM seq_conversations WHERE conversation_id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = conversation_id }};
        const result = self.db.queryParams(sql, params) catch return 0;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(i64, result.rows[0][0], 10) catch 0;
    }

    pub fn count(self: *MessagePersistence) usize {
        const sql = "SELECT COUNT(*) FROM messages";
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

    pub fn clearConversation(self: *MessagePersistence, conversation_id: []const u8) !void {
        const sql = "DELETE FROM messages WHERE conversation_id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = conversation_id }};
        _ = try self.db.execParams(sql, params);
    }

    pub fn clearAll(self: *MessagePersistence, user_id: []const u8) !void {
        _ = user_id;
        const sql = "DELETE FROM messages";
        _ = try self.db.exec(sql);
    }

    pub fn search(self: *MessagePersistence, allocator: std.mem.Allocator, conversation_id: []const u8, keyword: []const u8, limit: i64) ![]model.Message {
        const pattern = try std.fmt.allocPrint(self.allocator, "%{s}%", .{keyword});
        defer self.allocator.free(pattern);
        const sql = "SELECT msg_id, conversation_id, sender_id, receiver_id, group_id, client_msg_id, server_msg_id, sender_platform_id, sender_nickname, sender_face_url, session_type, msg_from, content_type, content, seq, send_time, EXTRACT(EPOCH FROM create_time)::bigint, status, is_read, options, offline_push, at_user_id_list, attached_info, ex, is_edit, COALESCE(EXTRACT(EPOCH FROM edit_time)::bigint, 0) FROM messages WHERE conversation_id = $1 AND content ILIKE $2 ORDER BY seq DESC LIMIT $3::int";
        const params = &[_]db_mod.QueryParam{ .{ .string = conversation_id }, .{ .string = pattern }, .{ .bigint = limit } };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.Message).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.Message{
                .msg_id = try allocator.dupe(u8, row[0]),
                .conversation_id = try allocator.dupe(u8, row[1]),
                .sender_id = try allocator.dupe(u8, row[2]),
                .receiver_id = try allocator.dupe(u8, row[3]),
                .group_id = try allocator.dupe(u8, row[4]),
                .client_msg_id = try allocator.dupe(u8, row[5]),
                .server_msg_id = try allocator.dupe(u8, row[6]),
                .sender_platform_id = try std.fmt.parseInt(i16, row[7], 10),
                .sender_nickname = try allocator.dupe(u8, row[8]),
                .sender_face_url = try allocator.dupe(u8, row[9]),
                .session_type = @fromBackingInt(@intCast(try std.fmt.parseInt(i16, row[10], 10))),
                .msg_from = try std.fmt.parseInt(i16, row[11], 10),
                .content_type = @fromBackingInt(@intCast(try std.fmt.parseInt(i16, row[12], 10))),
                .content = try allocator.dupe(u8, row[13]),
                .seq = try std.fmt.parseInt(i64, row[14], 10),
                .send_time = try std.fmt.parseInt(i64, row[15], 10),
                .create_time = try std.fmt.parseInt(i64, row[16], 10),
                .status = try std.fmt.parseInt(i16, row[17], 10),
                .is_read = std.mem.eql(u8, row[18], "t") or std.mem.eql(u8, row[18], "true") or std.mem.eql(u8, row[18], "1"),
                .options = try allocator.dupe(u8, row[19]),
                .offline_push = try allocator.dupe(u8, row[20]),
                .at_user_id_list = try allocator.dupe(u8, row[21]),
                .attached_info = try allocator.dupe(u8, row[22]),
                .ex = try allocator.dupe(u8, row[23]),
                .key_version = 0,
                .is_revoke = false,
                .revoke_content = "",
                .is_edit = row[24][0] == 't',
                .edit_time = std.fmt.parseInt(i64, row[25], 10) catch 0,
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn checkMsgSendSuccess(self: *MessagePersistence, client_msg_id: []const u8) bool {
        const sql = "SELECT 1 FROM messages WHERE client_msg_id = $1 LIMIT 1";
        const result = self.db.queryParams(sql, &.{.{ .string = client_msg_id }}) catch return false;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        return result.row_count > 0;
    }

    pub fn getClientMsgIdBySeq(self: *MessagePersistence, conversation_id: []const u8, seq: i64) ?[]const u8 {
        const sql = "SELECT client_msg_id FROM messages WHERE conversation_id = $1 AND seq = $2 LIMIT 1";
        const result = self.db.queryParams(sql, &.{ .{ .string = conversation_id }, .{ .bigint = seq } }) catch return null;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return null;
        return core.getAllocator().dupe(u8, result.rows[0][0]) catch null;
    }

    pub fn trackGroupMessageRead(self: *MessagePersistence, conversation_id: []const u8, client_msg_id: []const u8, user_id: []const u8) void {
        const sql = "INSERT INTO group_message_read (conversation_id, client_msg_id, user_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING";
        _ = self.db.execParams(sql, &.{ .{ .string = conversation_id }, .{ .string = client_msg_id }, .{ .string = user_id } }) catch {};
    }

    pub fn getGroupMessageReadNum(self: *MessagePersistence, conversation_id: []const u8, client_msg_id: []const u8) model.GroupMessageReadResult {
        if (conversation_id.len <= 3) return .{ .read_num = 0, .unread_num = 0 };
        const group_id = conversation_id[3..]; // strip "sg_"
        const read_sql = "SELECT COUNT(*) FROM group_message_read WHERE conversation_id = $1 AND client_msg_id = $2";
        const read_result = self.db.queryParams(read_sql, &.{ .{ .string = conversation_id }, .{ .string = client_msg_id } }) catch return .{ .read_num = 0, .unread_num = 0 };
        defer {
            for (read_result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(read_result.rows);
        }
        const read_num: i64 = if (read_result.row_count > 0) std.fmt.parseInt(i64, read_result.rows[0][0], 10) catch 0 else 0;

        const total_sql = "SELECT COUNT(*) FROM group_members WHERE group_id = $1";
        const total_result = self.db.queryParams(total_sql, &.{.{ .string = group_id }}) catch return .{ .read_num = read_num, .unread_num = 0 };
        defer {
            for (total_result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(total_result.rows);
        }
        const total: i64 = if (total_result.row_count > 0) std.fmt.parseInt(i64, total_result.rows[0][0], 10) catch 0 else 0;
        const unread = if (total > read_num) total - read_num else 0;
        return .{ .read_num = read_num, .unread_num = unread };
    }

    pub fn getGroupMessageHasRead(self: *MessagePersistence, conversation_id: []const u8, client_msg_id: []const u8, user_id: []const u8) bool {
        const sql = "SELECT 1 FROM group_message_read WHERE conversation_id = $1 AND client_msg_id = $2 AND user_id = $3 LIMIT 1";
        const result = self.db.queryParams(sql, &.{ .{ .string = conversation_id }, .{ .string = client_msg_id }, .{ .string = user_id } }) catch return false;
        defer {
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        return result.row_count > 0;
    }
};
