// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: message.zig

const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const auth_mod = @import("../../auth.zig");
const conversation_mod = @import("../../conversation.zig");
const message_mod = @import("../../message.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;
const getBearerToken = helpers.getBearerToken;

pub fn handleBatchSendMsg(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const BatchReq = struct {
        sendID: []const u8,
        recvIDs: [][]const u8,
        content: []const u8,
        contentType: i16 = 101,
        sessionType: i16 = 1,
    };
    const req = ctx.bindJson(BatchReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const session_type = switch (req.sessionType) {
        1 => message_mod.SessionType.single,
        2 => message_mod.SessionType.group,
        else => message_mod.SessionType.single,
    };
    const content_type = switch (req.contentType) {
        101 => message_mod.ContentType.text,
        102 => message_mod.ContentType.image,
        else => message_mod.ContentType.text,
    };
    for (req.recvIDs) |recv_id| {
        _ = message_mod.sendMessage(.{
            .send_id = req.sendID,
            .recv_id = recv_id,
            .session_type = session_type,
            .content_type = content_type,
            .content = req.content,
        }) catch continue;
    }
    return sendOk(ctx, null);
}

pub fn handleCheckMsgIsSendSuccess(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CheckReq = struct {
        clientMsgID: []const u8,
    };
    const req = ctx.bindJson(CheckReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const success = message_mod.checkMsgSendSuccess(req.clientMsgID);
    return sendOk(ctx, .{ .success = success });
}

pub fn handleClearConversationMsg(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ClearReq = struct {
        conversationID: []const u8,
    };
    const req = ctx.bindJson(ClearReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    message_mod.clearConversationMessages(req.conversationID) catch |err| {
        return sendFail(ctx, core.ErrorCode.clear_conversation_msg, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleDeleteMsgPhysical(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DeleteReq = struct {
        conversationID: []const u8,
        msgIDs: [][]const u8,
    };
    const req = ctx.bindJson(DeleteReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const count = message_mod.deleteMsgPhysical(req.conversationID, req.msgIDs) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_msg_physical, @errorName(err));
    };
    return sendOk(ctx, .{ .deletedCount = count });
}

pub fn handleDeleteMsgPhysicalBySeq(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        conversationID: []const u8,
        seqs: []i64,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var msg_ids = std.ArrayList([]const u8).empty;
    defer msg_ids.deinit(core.getAllocator());
    for (req.seqs) |seq| {
        if (message_mod.getClientMsgIdBySeq(req.conversationID, seq)) |msg_id| {
            try msg_ids.append(core.getAllocator(), msg_id);
        }
    }
    const count = message_mod.deleteMsgPhysical(req.conversationID, msg_ids.items) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_msg_physical_by_seq, @errorName(err));
    };
    return sendOk(ctx, .{ .deletedCount = count });
}

pub fn handleDeleteMsgs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DeleteMsgsReq = struct {
        conversationID: []const u8,
        seqs: []i64,
        userID: []const u8,
    };
    const req = ctx.bindJson(DeleteMsgsReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const count = message_mod.deleteMessages(req.conversationID, req.seqs, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_msgs, @errorName(err));
    };
    return sendOk(ctx, .{ .deletedCount = count });
}

pub fn handleGetConversationsHasReadAndMaxSeq(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        ownerUserID: []const u8,
        conversationIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var results = std.ArrayList(struct { conversationID: []const u8, hasReadSeq: i64, maxSeq: i64 }).empty;
    defer results.deinit(core.getAllocator());
    for (req.conversationIDs) |cid| {
        if (conversation_mod.getConversation(req.ownerUserID, cid) catch null) |c| {
            try results.append(core.getAllocator(), .{ .conversationID = cid, .hasReadSeq = c.has_read_seq, .maxSeq = c.max_seq });
        }
    }
    return sendOk(ctx, .{ .conversations = results.items });
}

pub fn handleGetGroupMessageHasRead(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ReadReq = struct {
        conversationID: []const u8,
        clientMsgID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(ReadReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const has_read = message_mod.getGroupMessageHasRead(req.conversationID, req.clientMsgID, req.userID);
    return sendOk(ctx, .{ .hasRead = has_read });
}

pub fn handleGetGroupMessageReadNum(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ReadReq = struct {
        conversationID: []const u8,
        clientMsgID: []const u8,
    };
    const req = ctx.bindJson(ReadReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const result = message_mod.getGroupMessageReadNum(req.conversationID, req.clientMsgID);
    return sendOk(ctx, .{ .readNum = result.read_num, .unreadNum = result.unread_num });
}

pub fn handleGetSeq(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SeqReq = struct {
        conversationID: []const u8,
    };
    const req = ctx.bindJson(SeqReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const max_seq = message_mod.getMaxSeq(req.conversationID);
    return sendOk(ctx, .{ .maxSeq = max_seq });
}

pub fn handleGetServerTime(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const now = core.unixNowSeconds();
    return sendOk(ctx, .{ .serverTime = now });
}

pub fn handleMarkConversationAsRead(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ReadReq = struct {
        ownerUserID: []const u8,
        conversationID: []const u8,
        hasReadSeq: i64,
    };
    const req = ctx.bindJson(ReadReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = conversation_mod.updateConversation(req.ownerUserID, req.conversationID, .{ .has_read_seq = req.hasReadSeq }) catch |err| {
        return sendFail(ctx, core.ErrorCode.mark_conversation_as_read, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleMarkConversationRead(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ReadReq = struct {
        ownerUserID: []const u8,
        conversationID: []const u8,
        hasReadSeq: i64,
    };
    const req = ctx.bindJson(ReadReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = conversation_mod.updateConversation(req.ownerUserID, req.conversationID, .{ .has_read_seq = req.hasReadSeq }) catch |err| {
        return sendFail(ctx, core.ErrorCode.mark_conversation_read, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleMarkGroupMessageRead(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ReadReq = struct {
        conversationID: []const u8,
        clientMsgID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(ReadReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    message_mod.trackGroupMessageRead(req.conversationID, req.clientMsgID, req.userID);
    return sendOk(ctx, null);
}

pub fn handleMarkMsgsAsRead(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ReadReq = struct {
        conversationID: []const u8,
        seqs: []i64,
    };
    const req = ctx.bindJson(ReadReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const reader = getReaderFromToken(ctx) orelse return sendFail(ctx, 401, "Unauthorized");
    for (req.seqs) |seq| {
        _ = message_mod.markMessageRead(reader, req.conversationID, seq);
    }
    // Read receipt (Go: HasReadReceipt=2200 notification to the peer) — single
    // chats only; group read receipts use a separate mechanism.
    if (req.seqs.len > 0) {
        const last_seq = req.seqs[req.seqs.len - 1];
        if (conversation_mod.getConversation(reader, req.conversationID) catch null) |conv| {
            if (conv.conversation_type == .single and conv.user_id.len > 0) {
                const content = try std.fmt.allocPrint(core.getAllocator(), "{{\"conversationID\":\"{s}\",\"hasReadSeq\":{d}}}", .{ req.conversationID, last_seq });
                defer core.getAllocator().free(content);
                _ = message_mod.sendMessage(.{
                    .send_id = reader,
                    .recv_id = conv.user_id,
                    .session_type = .notification,
                    .content_type = .read_receipt,
                    .content = content,
                    .options = .{ .is_not_notification = true },
                }) catch {};
            }
        }
    }
    return sendOk(ctx, null);
}
/// Resolve the authenticated user id from the request token.
fn getReaderFromToken(ctx: *http.Context) ?[]const u8 {
    const token = getBearerToken(ctx) orelse return null;
    const info = auth_mod.parseToken(token) catch return null;
    return info.user_id;
}

pub fn handleMarkUserMessageRead(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ReadReq = struct {
        conversationID: []const u8,
        seq: i64,
    };
    const req = ctx.bindJson(ReadReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const reader = getReaderFromToken(ctx) orelse return sendFail(ctx, 401, "Unauthorized");
    _ = message_mod.markMessageRead(reader, req.conversationID, req.seq);
    return sendOk(ctx, null);
}

pub fn handleModifyMessage(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ModifyReq = struct {
        conversationID: []const u8,
        seq: i64,
        userID: []const u8,
        newContent: []const u8,
    };
    const req = ctx.bindJson(ModifyReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = message_mod.modifyMessage(req.conversationID, req.seq, req.userID, req.newContent) catch |err| {
        return sendFail(ctx, core.ErrorCode.modify_message, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handlePullMsgBySeqs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const PullReq = struct {
        conversationID: []const u8,
        seqList: []i64,
    };
    const req = ctx.bindJson(PullReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const messages = message_mod.getMessagesBySeqList(req.conversationID, req.seqList) catch |err| {
        return sendFail(ctx, core.ErrorCode.pull_msg_by_seqs, @errorName(err));
    };
    {
        var msgs_json = std.ArrayList(@TypeOf(dto.messageToJson(messages[0]))).empty;
        defer msgs_json.deinit(core.getAllocator());
        for (messages) |m| {
            try msgs_json.append(core.getAllocator(), dto.messageToJson(m));
        }
        return sendOk(ctx, .{ .messages = msgs_json.items });
    }
}

pub fn handleRevokeMsg(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RevokeReq = struct {
        conversationID: []const u8,
        seq: i64,
        userID: []const u8,
    };
    const req = ctx.bindJson(RevokeReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = message_mod.recallMessage(req.conversationID, req.seq, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.revoke_msg, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleSearchMsg(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SearchReq = struct {
        conversationID: []const u8,
        keyword: []const u8,
        limit: i64 = 20,
    };
    const req = ctx.bindJson(SearchReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const messages = message_mod.searchMessages(req.conversationID, req.keyword, req.limit) catch |err| {
        return sendFail(ctx, core.ErrorCode.search_msg, @errorName(err));
    };
    {
        var msgs_json = std.ArrayList(@TypeOf(dto.messageToJson(messages[0]))).empty;
        defer msgs_json.deinit(core.getAllocator());
        for (messages) |m| {
            try msgs_json.append(core.getAllocator(), dto.messageToJson(m));
        }
        return sendOk(ctx, .{ .messages = msgs_json.items });
    }
}

pub fn handleSendBusinessNotification(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const NotifyReq = struct {
        recvID: []const u8,
        content: []const u8,
    };
    const req = ctx.bindJson(NotifyReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const msg = message_mod.sendBusinessNotification(req.recvID, req.content) catch |err| {
        return sendFail(ctx, core.ErrorCode.send_business_notification, @errorName(err));
    };
    return sendOk(ctx, .{
        .serverMsgID = msg.server_msg_id,
        .clientMsgID = msg.client_msg_id,
        .sendTime = msg.send_time,
    });
}

pub fn handleSendMessage(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SendMsgReq = struct {
        sendID: []const u8,
        recvID: ?[]const u8 = null,
        groupID: ?[]const u8 = null,
        senderPlatformID: i16 = 1,
        senderNickname: ?[]const u8 = null,
        senderFaceUrl: ?[]const u8 = null,
        sessionType: i16,
        msgFrom: i16 = 100,
        contentType: i16,
        content: []const u8,
        options: struct {
            isHistory: bool = true,
            isPersistent: bool = true,
            isSenderSync: bool = true,
            isOfflinePush: bool = true,
            isUnreadCount: bool = true,
            isNotNotification: bool = false,
        } = .{},
        offlinePush: ?[]const u8 = null,
        atUserIDList: ?[]const u8 = null,
        ex: ?[]const u8 = null,
    };
    const req = ctx.bindJson(SendMsgReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    core.metricMessageSent();
    const session_type = switch (req.sessionType) {
        1 => message_mod.SessionType.single,
        2 => message_mod.SessionType.group,
        3 => message_mod.SessionType.notification,
        else => message_mod.SessionType.single,
    };
    const content_type = switch (req.contentType) {
        101 => message_mod.ContentType.text,
        102 => message_mod.ContentType.image,
        103 => message_mod.ContentType.audio,
        104 => message_mod.ContentType.video,
        105 => message_mod.ContentType.file,
        106 => message_mod.ContentType.at_text,
        107 => message_mod.ContentType.merge,
        108 => message_mod.ContentType.card,
        109 => message_mod.ContentType.location,
        110 => message_mod.ContentType.custom,
        111 => message_mod.ContentType.recall,
        113 => message_mod.ContentType.typing,
        114 => message_mod.ContentType.quote,
        115 => message_mod.ContentType.custom_face,
        116 => message_mod.ContentType.group_announcement,
        117 => message_mod.ContentType.group_call,
        1000 => message_mod.ContentType.system_notification,
        else => message_mod.ContentType.text,
    };
    const msg = message_mod.sendMessage(.{
        .send_id = req.sendID,
        .recv_id = req.recvID orelse "",
        .group_id = req.groupID orelse "",
        .sender_platform_id = req.senderPlatformID,
        .sender_nickname = req.senderNickname orelse "",
        .sender_face_url = req.senderFaceUrl orelse "",
        .session_type = session_type,
        .msg_from = req.msgFrom,
        .content_type = content_type,
        .content = req.content,
        .options = .{
            .is_history = req.options.isHistory,
            .is_persistent = req.options.isPersistent,
            .is_sender_sync = req.options.isSenderSync,
            .is_offline_push = req.options.isOfflinePush,
            .is_unread_count = req.options.isUnreadCount,
            .is_not_notification = req.options.isNotNotification,
        },
        .offline_push = req.offlinePush,
        .at_user_id_list = req.atUserIDList,
        .ex = req.ex,
    }) catch |err| {
        return sendFail(ctx, core.ErrorCode.send_message, @errorName(err));
    };
    return sendOk(ctx, .{
        .serverMsgID = msg.server_msg_id,
        .clientMsgID = msg.client_msg_id,
        .sendTime = msg.send_time,
        .seq = msg.seq,
        .modify = null,
    });
}

pub fn handleSetConversationHasReadSeq(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SetReq = struct {
        ownerUserID: []const u8,
        conversationID: []const u8,
        hasReadSeq: i64,
    };
    const req = ctx.bindJson(SetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = conversation_mod.updateConversation(req.ownerUserID, req.conversationID, .{ .has_read_seq = req.hasReadSeq }) catch |err| {
        return sendFail(ctx, core.ErrorCode.set_conversation_has_read_seq, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleUserClearAllMsg(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ClearReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(ClearReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    message_mod.clearAllMessages(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.user_clear_all_msg, @errorName(err));
    };
    return sendOk(ctx, null);
}
