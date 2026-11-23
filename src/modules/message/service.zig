const std = @import("std");
const zmodu = @import("zmodu");
const core = @import("core");
const db_mod = @import("../db_postgres.zig");
const event_bus_mod = @import("../event_bus.zig");
const conversation_mod = @import("../conversation.zig");
const config_mod = @import("../config.zig");
const friend_mod = @import("../friend.zig");
const group_mod = @import("../group.zig");
const model = @import("model.zig");
const persistence = @import("persistence.zig");
const zent = @import("zent");
const zent_db = @import("../../zent_db.zig");

/// Hard cap on message content size (OpenIM default maxContentLength).
const MAX_MESSAGE_LENGTH = 64 * 1024;

/// Whether `content_type` matches any entry in a comma-separated list of
/// single values or "start-end" intervals (Go filterMsg isInInterval).
pub fn contentTypeInIntervals(content_type: i16, list: []const u8) bool {
    var it = std.mem.splitScalar(u8, list, ',');
    while (it.next()) |raw| {
        const v = std.mem.trim(u8, raw, " \t");
        if (v.len == 0) continue;
        if (std.mem.indexOfScalar(u8, v, '-')) |dash| {
            const lo = std.fmt.parseInt(i64, v[0..dash], 10) catch continue;
            const hi = std.fmt.parseInt(i64, v[dash + 1 ..], 10) catch continue;
            if (content_type >= lo and content_type <= hi) return true;
        } else {
            const single = std.fmt.parseInt(i64, v, 10) catch continue;
            if (content_type == single) return true;
        }
    }
    return false;
}

/// Whether `user_id` appears in a comma-separated user-id list.
fn listContains(list: []const u8, user_id: []const u8) bool {
    var it = std.mem.splitScalar(u8, list, ',');
    while (it.next()) |raw| {
        if (std.mem.eql(u8, std.mem.trim(u8, raw, " \t"), user_id)) return true;
    }
    return false;
}

/// Validate message before sending (friend/group/blacklist checks)
fn validateMessage(input: model.MessageSendInput) !void {
    // Message size guard (matches OpenIM's maxContentLength behavior).
    if (input.content.len > MAX_MESSAGE_LENGTH) {
        return error.MessageTooLong;
    }
    // Content-type filter (Go filterMsg: webhook allowed_types/denied_types).
    // When attention_ids is set, filtering only applies to messages whose
    // sender or receiver is on the attention list; everyone else passes.
    const wc = @import("../config.zig").getConfig().webhook;
    const ct = @backingInt(input.content_type);
    const in_attention = wc.attention_ids.len == 0 or
        listContains(wc.attention_ids, input.send_id) or
        listContains(wc.attention_ids, input.recv_id);
    if (in_attention) {
        if (wc.allowed_types.len > 0 and !contentTypeInIntervals(ct, wc.allowed_types)) {
            return error.ContentTypeNotAllowed;
        }
        if (wc.denied_types.len > 0 and contentTypeInIntervals(ct, wc.denied_types)) {
            return error.ContentTypeDenied;
        }
    }
    switch (input.session_type) {
        .single => {
            // Self-messages not allowed in single chat
            if (std.mem.eql(u8, input.send_id, input.recv_id)) {
                return error.CannotSendToSelf;
            }
            // Blacklist first — Go checks IsBlack before IsFriend (verify.go),
            // so a blocked sender must see Blacklisted, not NotFriend.
            if (friend_mod.isBlack(input.send_id, input.recv_id)) {
                return error.Blacklisted;
            }
            if (friend_mod.isBlack(input.recv_id, input.send_id)) {
                return error.Blacklisted;
            }
            // Must be friends
            if (!friend_mod.isFriend(input.send_id, input.recv_id)) {
                return error.NotFriend;
            }
        },
        .group => {
            // Group must exist
            const group = group_mod.getGroup(input.group_id) orelse return error.GroupNotFound;
            // Group must be active
            switch (group.status) {
                .banned => return error.GroupBanned,
                .dismissed => return error.GroupDismissed,
                .muted => return error.GroupMuted,
                .ok => {},
            }
            // Sender must be a member
            if (!group_mod.isMember(input.group_id, input.send_id)) {
                return error.NotGroupMember;
            }
            // Sender must not be muted
            const member = group_mod.getMember(input.group_id, input.send_id);
            if (member) |m| {
                const now = core.unixNowMillis();
                if (m.mute_end_time > now) {
                    return error.SenderMuted;
                }
            }
        },
        .notification => {
            // System notifications skip validation
        },
    }
}

pub const MessageService = struct {
    allocator: std.mem.Allocator,
    pers: persistence.MessagePersistence,

    pub fn init(allocator: std.mem.Allocator, db: *@import("../db_postgres.zig").PostgresClient) MessageService {
        return .{
            .allocator = allocator,
            .pers = persistence.MessagePersistence.init(allocator, db),
        };
    }

    pub fn sendMessage(self: *MessageService, input: model.MessageSendInput) !model.Message {
        try validateMessage(input);

        var modified_input = input;
        // Before-send sync webhook (Phase 90, Go callbackBeforeSendMsg):
        // response gates the send (errCode != 0 → reject) and may replace
        // the content (content moderation pattern).
        try beforeSendCallback(&modified_input);
        switch (input.content_type) {
            .typing => {
                modified_input.options.is_history = false;
                modified_input.options.is_persistent = false;
                modified_input.options.is_offline_push = false;
                modified_input.options.is_unread_count = false;
            },
            .system_notification, .recall => {
                modified_input.options.is_offline_push = false;
                modified_input.options.is_unread_count = false;
            },
            else => {},
        }

        const msg = try self.sendInTx(modified_input);

        const eb = event_bus_mod.getEventBus();
        const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"msg_id\":\"{s}\",\"conversation_id\":\"{s}\",\"sender_id\":\"{s}\",\"receiver_id\":\"{s}\",\"group_id\":\"{s}\",\"seq\":{d},\"content_type\":{d},\"session_type\":{d},\"content\":\"{s}\",\"server_msg_id\":\"{s}\",\"client_msg_id\":\"{s}\",\"send_time\":{d}}}", .{
            msg.msg_id,
            msg.conversation_id,
            msg.sender_id,
            msg.receiver_id,
            msg.group_id,
            msg.seq,
            @backingInt(msg.content_type),
            @backingInt(msg.session_type),
            msg.content,
            msg.server_msg_id,
            msg.client_msg_id,
            msg.send_time,
        });
        defer core.getAllocator().free(payload);
        eb.emit(.message_sent, "message", payload);

        return msg;
    }

    /// Insert the message and sync its conversations atomically: a failed sync
    /// rolls the message back (no orphan messages with a stale conversation).
    fn sendInTx(self: *MessageService, input: model.MessageSendInput) !model.Message {
        // @所有人 / @具体用户 detection (Go: "AtAllTag" marker + at_user_id_list)
        // — pure parsing, done before either transaction opens.
        const allocator = core.getAllocator();
        var at_all = false;
        var at_users = std.ArrayList([]const u8).empty;
        defer at_users.deinit(allocator);
        if (input.at_user_id_list) |at_str| {
            if (std.json.parseFromSlice(std.json.Value, allocator, at_str, .{})) |parsed| {
                defer parsed.deinit();
                if (parsed.value == .array) {
                    for (parsed.value.array.items) |item| {
                        if (item != .string) continue;
                        const s = item.string;
                        if (std.mem.eql(u8, s, "AtAllTag")) {
                            at_all = true;
                        } else {
                            try at_users.append(allocator, try allocator.dupe(u8, s));
                        }
                    }
                }
            } else |_| {}
        }

        // zent path (Phase 86): the whole send rides a zent TxClient — the
        // message insert runs its legacy SQL through the executor adapter on
        // the transaction connection, and the conversation sync uses the
        // typed upsert builders on the same transaction. A failed sync rolls
        // the message back.
        if (zent_db.getDriver()) |drv| {
            // TxClient's allocator must match the client the entities were
            // built from (zent_db's g_allocator): upsert entities are freed
            // via deinitRow(getAllocator()) — a request arena here would hand
            // arena-backed strings to the wrong free (SafeAllocator panic).
            var ztx = try zent.codegen.beginTxFromDriver(zent_db.schema_infos, drv, zent_db.getAllocator());
            defer ztx.deinit();
            errdefer ztx.rollback() catch {};
            const adapter = zent_db.LegacyExecAdapter{ .drv = ztx.tx, .alloc = self.pers.allocator };
            const msg = try self.pers.sendOn(&adapter, input);
            try syncConversationZent(&ztx, msg, at_all, at_users.items);
            try ztx.commit();
            return msg;
        }

        // legacy fallback: db_postgres Tx until the zent layer is a hard
        // requirement (docs/zent-migration.md dual-path pattern).
        var tx = try self.pers.db.begin();
        errdefer tx.rollback();
        const msg = try self.pers.sendTx(&tx, input);
        try syncConversationTx(&tx, msg, at_all, at_users.items);
        try tx.commit();
        return msg;
    }

    pub fn getMessages(self: *MessageService, conversation_id: []const u8, offset: i64, limit: i64) ![]model.Message {
        return self.pers.getByConversation(core.getAllocator(), conversation_id, offset, limit);
    }

    pub fn getMessagesBySeqRange(self: *MessageService, conversation_id: []const u8, begin_seq: i64, end_seq: i64, limit: i64, ascending: bool) ![]model.Message {
        return self.pers.getBySeqRange(core.getAllocator(), conversation_id, begin_seq, end_seq, limit, ascending);
    }

    pub fn getMessagesBySeqList(self: *MessageService, conversation_id: []const u8, seqs: []const i64) ![]model.Message {
        return self.pers.getBySeqList(core.getAllocator(), conversation_id, seqs);
    }

    pub fn recallMessage(self: *MessageService, conversation_id: []const u8, seq: i64, user_id: []const u8) !bool {
        const result = try self.pers.recall(conversation_id, seq, user_id);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"conversation_id\":\"{s}\",\"seq\":{d},\"user_id\":\"{s}\"}}", .{ conversation_id, seq, user_id });
            defer core.getAllocator().free(payload);
            eb.emit(.message_recalled, "message", payload);
        }
        return result;
    }

    pub fn modifyMessage(self: *MessageService, conversation_id: []const u8, seq: i64, user_id: []const u8, new_content: []const u8) !bool {
        const result = try self.pers.modifyMessage(conversation_id, seq, user_id, new_content);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"conversation_id\":\"{s}\",\"seq\":{d},\"user_id\":\"{s}\"}}", .{ conversation_id, seq, user_id });
            defer core.getAllocator().free(payload);
            eb.emit(.message_modified, "message", payload);
        }
        return result;
    }

    pub fn deleteMessages(self: *MessageService, conversation_id: []const u8, seqs: []const i64, user_id: []const u8) !usize {
        const count = try self.pers.delete(conversation_id, seqs, user_id);
        if (count > 0) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"conversation_id\":\"{s}\",\"count\":{d}}}", .{ conversation_id, count });
            defer core.getAllocator().free(payload);
            eb.emit(.message_deleted, "message", payload);
        }
        return count;
    }

    pub fn markMessageRead(self: *MessageService, owner_user_id: []const u8, conversation_id: []const u8, seq: i64) bool {
        return self.pers.markRead(owner_user_id, conversation_id, seq);
    }

    pub fn getMaxSeq(self: *MessageService, conversation_id: []const u8) i64 {
        return self.pers.getMaxSeq(conversation_id);
    }

    pub fn messageCount(self: *MessageService) usize {
        return self.pers.count();
    }

    pub fn activeMsgCount(self: *MessageService, start_time: i64, end_time: i64, group_mode: bool) usize {
        return self.pers.activeMsgCount(start_time, end_time, group_mode);
    }

    pub fn activeEntityCount(self: *MessageService, start_time: i64, end_time: i64, group_mode: bool) usize {
        return self.pers.activeEntityCount(start_time, end_time, group_mode);
    }

    pub fn activeDateCount(self: *MessageService, allocator: std.mem.Allocator, start_time: i64, end_time: i64, group_mode: bool) ![]model.DayCount {
        return self.pers.activeDateCount(allocator, start_time, end_time, group_mode);
    }

    pub fn activeTopEntities(self: *MessageService, allocator: std.mem.Allocator, start_time: i64, end_time: i64, group_mode: bool, limit: i64) ![]model.TopEntity {
        return self.pers.activeTopEntities(allocator, start_time, end_time, group_mode, limit);
    }

    pub fn clearConversationMessages(self: *MessageService, conversation_id: []const u8) !void {
        try self.pers.clearConversation(conversation_id);
    }

    pub fn clearAllMessages(self: *MessageService, user_id: []const u8) !void {
        try self.pers.clearAll(user_id);
    }

    pub fn searchMessages(self: *MessageService, conversation_id: []const u8, keyword: []const u8, limit: i64) ![]model.Message {
        return try self.pers.search(core.getAllocator(), conversation_id, keyword, limit);
    }

    pub fn sendBusinessNotification(self: *MessageService, recv_id: []const u8, content: []const u8) !model.Message {
        const notif = self.sendMessage(.{
            .send_id = "system",
            .recv_id = recv_id,
            .group_id = "",
            .session_type = .notification,
            .content_type = .system_notification,
            .content = content,
            .sender_platform_id = 0,
            .sender_nickname = "System",
            .sender_face_url = "",
        }) catch |e| {
            std.log.err("Failed to send business notification: {}", .{e});
            return e;
        };
        return notif;
    }

    pub fn deleteMsgPhysical(self: *MessageService, conversation_id: []const u8, msg_ids: []const []const u8) !usize {
        _ = msg_ids;
        try self.pers.clearConversation(conversation_id);
        return 0;
    }

    pub fn checkMsgSendSuccess(self: *MessageService, client_msg_id: []const u8) bool {
        return self.pers.checkMsgSendSuccess(client_msg_id);
    }

    pub fn getClientMsgIdBySeq(self: *MessageService, conversation_id: []const u8, seq: i64) ?[]const u8 {
        return self.pers.getClientMsgIdBySeq(conversation_id, seq);
    }

    pub fn trackGroupMessageRead(self: *MessageService, conversation_id: []const u8, client_msg_id: []const u8, user_id: []const u8) void {
        self.pers.trackGroupMessageRead(conversation_id, client_msg_id, user_id);
    }

    pub fn getGroupMessageReadNum(self: *MessageService, conversation_id: []const u8, client_msg_id: []const u8) model.GroupMessageReadResult {
        return self.pers.getGroupMessageReadNum(conversation_id, client_msg_id);
    }

    pub fn getGroupMessageHasRead(self: *MessageService, conversation_id: []const u8, client_msg_id: []const u8, user_id: []const u8) bool {
        return self.pers.getGroupMessageHasRead(conversation_id, client_msg_id, user_id);
    }
};

/// Auto-create or update conversation after message sent — transactional
/// variant running on the caller's Tx so message insert + conversation sync
/// commit or roll back together (no orphan messages).
/// Before-send sync webhook (Phase 90, Go callbackBeforeSendMsg).
/// Rejects with error.WebhookRejected when the response errCode != 0, and
/// replaces `input.content` when the response carries a "content" string
/// (content moderation pattern). Network/HTTP failures allow the send with
/// a warn log (availability over moderation — Go's default when a callback
/// is unreachable). Callback timeout: 3s.
fn beforeSendCallback(input: *model.MessageSendInput) !void {
    const cfg = config_mod.getConfig().webhook;
    if (cfg.before_send_url.len == 0) return;

    const allocator = core.getAllocator();
    const send_id_json = std.json.Stringify.valueAlloc(allocator, input.send_id, .{}) catch return;
    defer allocator.free(send_id_json);
    const recv_id_json = std.json.Stringify.valueAlloc(allocator, input.recv_id, .{}) catch return;
    defer allocator.free(recv_id_json);
    const group_id_json = std.json.Stringify.valueAlloc(allocator, input.group_id, .{}) catch return;
    defer allocator.free(group_id_json);
    const content_json = std.json.Stringify.valueAlloc(allocator, input.content, .{}) catch return;
    defer allocator.free(content_json);

    const payload = try std.fmt.allocPrint(
        allocator,
        "{{\"sendID\":{s},\"recvID\":{s},\"groupID\":{s},\"sessionType\":{d},\"contentType\":{d},\"content\":{s}}}",
        .{ send_id_json, recv_id_json, group_id_json, @backingInt(input.session_type), @backingInt(input.content_type), content_json },
    );
    defer allocator.free(payload);

    var client = zmodu.http.HttpClient.init(allocator, core.getIo(), 1, 3000);
    defer client.deinit();
    var req = zmodu.http.HttpClient.HttpRequest.init(allocator, "POST", cfg.before_send_url);
    defer req.deinit();
    try req.setHeader("Content-Type", "application/json");
    try req.setBody(payload);
    var resp = client.request(req) catch |err| {
        core.logJson(.{ .event = "webhook_before_send_unreachable", .err = @errorName(err) });
        return; // continue-with-log
    };
    defer resp.deinit();
    if (!resp.isSuccess()) {
        core.logJson(.{ .event = "webhook_before_send_http_error", .status = resp.status_code });
        return; // continue-with-log
    }

    const action = parseWebhookResponse(allocator, resp.body) catch {
        core.logJson(.{ .event = "webhook_before_send_bad_response" });
        return; // malformed response treated as allow
    };
    switch (action) {
        .reject => {
            core.logJson(.{ .event = "webhook_before_send_reject", .send_id = input.send_id });
            return error.WebhookRejected;
        },
        .modify => |new_content| {
            input.content = try allocator.dupe(u8, new_content);
        },
        .allow => {},
    }
}

/// Before-send callback response contract (Go callbackBeforeSendMsg):
/// `errCode` non-zero → reject; a string `content` field → replace content;
/// everything else → allow.
pub const WebhookAction = union(enum) {
    allow,
    reject,
    modify: []const u8,
};

pub fn parseWebhookResponse(allocator: std.mem.Allocator, body: []const u8) !WebhookAction {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.InvalidJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidJson;
    const obj = parsed.value.object;

    if (obj.get("errCode")) |v| {
        switch (v) {
            .integer => |n| if (n != 0) return .reject,
            .float => |f| if (f != 0) return .reject,
            else => {},
        }
    }
    if (obj.get("content")) |v| {
        // dupe BEFORE parsed.deinit() frees the parser-owned string
        if (v == .string) return .{ .modify = try allocator.dupe(u8, v.string) };
    }
    return .allow;
}

fn syncConversationTx(tx: *db_mod.Tx, msg: model.Message, at_all: bool, at_users: []const []const u8) !void {
    const allocator = core.getAllocator();

    const latest_msg_json = try std.fmt.allocPrint(allocator, "{{\"clientMsgID\":\"{s}\",\"serverMsgID\":\"{s}\",\"sendID\":\"{s}\",\"recvID\":\"{s}\",\"groupID\":\"{s}\",\"content\":\"{s}\",\"seq\":{d},\"sendTime\":{d},\"contentType\":{d}}}", .{
        msg.client_msg_id,
        msg.server_msg_id,
        msg.sender_id,
        msg.receiver_id,
        msg.group_id,
        msg.content,
        msg.seq,
        msg.send_time,
        @backingInt(msg.content_type),
    });
    defer allocator.free(latest_msg_json);

    const conv_pers = conversation_mod.getStorage();
    const ct = @backingInt(msg.content_type);
    switch (msg.session_type) {
        .single => {
            const user_ids = [_][]const u8{ msg.sender_id, msg.receiver_id };
            for (user_ids) |uid| {
                const other_id = if (std.mem.eql(u8, uid, msg.sender_id)) msg.receiver_id else msg.sender_id;
                const conv_id = try model.getConversationID(msg.sender_id, msg.receiver_id, "", .single, false);
                defer allocator.free(conv_id);
                try conv_pers.upsertWithLatest(tx, uid, conv_id, 1, other_id, "", latest_msg_json, msg.send_time, msg.sender_id, ct, msg.seq, 0);
            }
        },
        .group => {
            const conv_id = try model.getConversationID("", "", msg.group_id, .group, false);
            defer allocator.free(conv_id);
            // Fan out to sender + members + @-ed users in ONE batch statement.
            // Dedupe by owner: a user who is both a member and @-ed must appear
            // once (PG: ON CONFLICT cannot affect the same row twice).
            var targets = std.StringHashMap(i16).init(allocator);
            defer targets.deinit();
            const base_type: i16 = 2;
            try targets.put(msg.sender_id, if (at_all) 2 else 0);
            const members = group_mod.getGroupMembers(msg.group_id) catch return;
            for (members) |m| {
                if (std.mem.eql(u8, m.user_id, msg.sender_id)) continue;
                try targets.put(m.user_id, if (at_all) 2 else 0);
            }
            for (at_users) |uid| {
                if (std.mem.eql(u8, uid, msg.sender_id)) continue;
                try targets.put(uid, 3); // @specific user outranks member mark
            }
            var batch = std.ArrayList(conversation_mod.ConversationStorage.UpsertItem).empty;
            defer batch.deinit(allocator);
            var it = targets.iterator();
            while (it.next()) |entry| {
                try batch.append(allocator, .{
                    .owner_user_id = entry.key_ptr.*,
                    .conversation_id = conv_id,
                    .conversation_type = base_type,
                    .user_id = "",
                    .group_id = msg.group_id,
                    .latest_msg = latest_msg_json,
                    .latest_send_time = msg.send_time,
                    .latest_send_id = msg.sender_id,
                    .latest_content_type = ct,
                    .max_seq = msg.seq,
                    .group_at_type = entry.value_ptr.*,
                });
            }
            try conv_pers.upsertWithLatestBatch(tx, batch.items);
        },
        .notification => {
            // Read receipts are housekeeping messages: they enter the messages
            // table but must not overwrite the conversation's latest_msg
            // preview (Go sends them via NotificationWithSessionType, clients
            // hide them). Skip the conversation upsert entirely.
            if (msg.content_type == .read_receipt) return;
            try conv_pers.upsertWithLatest(tx, msg.receiver_id, msg.conversation_id, 3, msg.sender_id, "", latest_msg_json, msg.send_time, msg.sender_id, ct, msg.seq, 0);
        },
    }
}

/// zent-tx twin of syncConversationTx: identical fan-out semantics, executed
/// through the TxClient — single/notification upserts via the typed builders
/// on the transaction connection (activates conversation's zent upsert
/// branch), group fan-out via the batch zent variant on the tx driver.
fn syncConversationZent(tx: *zent_db.TxClientType, msg: model.Message, at_all: bool, at_users: []const []const u8) !void {
    const allocator = core.getAllocator();

    const latest_msg_json = try std.fmt.allocPrint(allocator, "{{\"clientMsgID\":\"{s}\",\"serverMsgID\":\"{s}\",\"sendID\":\"{s}\",\"recvID\":\"{s}\",\"groupID\":\"{s}\",\"content\":\"{s}\",\"seq\":{d},\"sendTime\":{d},\"contentType\":{d}}}", .{
        msg.client_msg_id,
        msg.server_msg_id,
        msg.sender_id,
        msg.receiver_id,
        msg.group_id,
        msg.content,
        msg.seq,
        msg.send_time,
        @backingInt(msg.content_type),
    });
    defer allocator.free(latest_msg_json);

    const conv_pers = conversation_mod.getStorage();
    const ct = @backingInt(msg.content_type);
    switch (msg.session_type) {
        .single => {
            const user_ids = [_][]const u8{ msg.sender_id, msg.receiver_id };
            for (user_ids) |uid| {
                const other_id = if (std.mem.eql(u8, uid, msg.sender_id)) msg.receiver_id else msg.sender_id;
                const conv_id = try model.getConversationID(msg.sender_id, msg.receiver_id, "", .single, false);
                defer allocator.free(conv_id);
                try conv_pers.upsertWithLatest(tx.client, uid, conv_id, 1, other_id, "", latest_msg_json, msg.send_time, msg.sender_id, ct, msg.seq, 0);
            }
        },
        .group => {
            const conv_id = try model.getConversationID("", "", msg.group_id, .group, false);
            defer allocator.free(conv_id);
            var targets = std.StringHashMap(i16).init(allocator);
            defer targets.deinit();
            try targets.put(msg.sender_id, if (at_all) 2 else 0);
            const members = group_mod.getGroupMembers(msg.group_id) catch return;
            for (members) |m| {
                if (std.mem.eql(u8, m.user_id, msg.sender_id)) continue;
                try targets.put(m.user_id, if (at_all) 2 else 0);
            }
            for (at_users) |uid| {
                if (std.mem.eql(u8, uid, msg.sender_id)) continue;
                try targets.put(uid, 3);
            }
            var upserts = std.ArrayList(conversation_mod.ConversationStorage.UpsertItem).empty;
            defer upserts.deinit(allocator);
            var it = targets.iterator();
            while (it.next()) |entry| {
                try upserts.append(allocator, .{
                    .owner_user_id = entry.key_ptr.*,
                    .conversation_id = conv_id,
                    .conversation_type = 2,
                    .user_id = msg.sender_id,
                    .group_id = msg.group_id,
                    .latest_msg = latest_msg_json,
                    .latest_send_time = msg.send_time,
                    .latest_send_id = msg.sender_id,
                    .latest_content_type = ct,
                    .max_seq = msg.seq,
                    .group_at_type = entry.value_ptr.*,
                });
            }
            try conv_pers.upsertWithLatestBatchZent(tx.tx, upserts.items);
        },
        .notification => {
            if (msg.content_type == .read_receipt) return;
            try conv_pers.upsertWithLatest(tx.client, msg.receiver_id, msg.conversation_id, 3, msg.sender_id, "", latest_msg_json, msg.send_time, msg.sender_id, ct, msg.seq, 0);
        },
    }
}
