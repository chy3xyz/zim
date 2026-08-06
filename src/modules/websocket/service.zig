const std = @import("std");
const core = @import("core");
const model = @import("model.zig");
const message_mod = @import("../message.zig");
const conversation_mod = @import("../conversation.zig");
const sdkws = @import("sdkws");

const WSClient = model.WSClient;
const sendWSResponse = model.sendWSResponse;
const sendWSError = model.sendWSError;
const sendError = model.sendError;

pub fn handleWSGetMaxSeq(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    const req = sdkws.GetMaxSeqReq.decode(data_bytes, core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to decode GetMaxSeqReq", operation_id);
        return;
    };
    defer core.getAllocator().free(req.user_id);

    // Get max seq across all user's conversations
    var max_seq: i64 = 0;
    const conversations = conversation_mod.getConversationsByOwner(req.user_id) catch &[_]conversation_mod.Conversation{};
    defer {
        for (conversations) |c| {
            core.getAllocator().free(c.id);
            core.getAllocator().free(c.owner_user_id);
            core.getAllocator().free(c.conversation_id);
            core.getAllocator().free(c.user_id);
            core.getAllocator().free(c.group_id);
            core.getAllocator().free(c.attached_info);
            core.getAllocator().free(c.ex);
            core.getAllocator().free(c.latest_msg);
            core.getAllocator().free(c.latest_msg_send_id);
        }
        core.getAllocator().free(conversations);
    }

    for (conversations) |conv| {
        if (conv.max_seq > max_seq) {
            max_seq = conv.max_seq;
        }
    }

    const resp = sdkws.GetMaxSeqResp{ .max_seqs = max_seq, .min_seqs = 0 };
    const resp_bytes = resp.encode(core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to encode GetMaxSeqResp", operation_id);
        return;
    };
    defer core.getAllocator().free(resp_bytes);
    sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", resp_bytes);
}

pub fn handleWSPullMsgBySeqList(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    const req = sdkws.PullMessageBySeqsReq.decode(data_bytes, core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to decode PullMessageBySeqsReq", operation_id);
        return;
    };
    defer {
        core.getAllocator().free(req.user_id);
        for (req.seq_ranges) |sr| {
            core.getAllocator().free(sr.conversation_id);
        }
        core.getAllocator().free(req.seq_ranges);
    }

    const ascending = req.order == 1;
    var all_msgs = std.ArrayList(sdkws.MsgData).empty;
    defer {
        for (all_msgs.items) |m| {
            core.getAllocator().free(m.send_id);
            core.getAllocator().free(m.recv_id);
            core.getAllocator().free(m.group_id);
            core.getAllocator().free(m.client_msg_id);
            core.getAllocator().free(m.server_msg_id);
            core.getAllocator().free(m.sender_nickname);
            core.getAllocator().free(m.sender_face_url);
            core.getAllocator().free(m.content);
            for (m.at_user_id_list) |uid| core.getAllocator().free(uid);
            core.getAllocator().free(m.at_user_id_list);
            core.getAllocator().free(m.attached_info);
            core.getAllocator().free(m.ex);
        }
        all_msgs.deinit(core.getAllocator());
    }

    for (req.seq_ranges) |sr| {
        const limit = if (sr.num > 0) sr.num else 100;
        const begin_seq = if (sr.begin > 0) sr.begin else 1;
        const end_seq = if (sr.end > 0) sr.end else std.math.maxInt(i64);

        const msgs = message_mod.getMessagesBySeqRange(sr.conversation_id, begin_seq, end_seq, limit, ascending) catch continue;
        defer core.getAllocator().free(msgs);

        for (msgs) |msg| {
            const session_type: i32 = switch (msg.session_type) {
                .single => 1,
                .group => 2,
                .notification => 3,
            };
            const content_type: i32 = switch (msg.content_type) {
                .text => 101,
                .image => 102,
                .audio => 103,
                .video => 104,
                .file => 105,
                .at_text => 106,
                .merge => 107,
                .card => 108,
                .location => 109,
                .custom => 110,
                .recall => 111,
                .typing => 113,
                .quote => 114,
                .custom_face => 115,
                .group_announcement => 116,
                .group_call => 117,
                .system_notification => 1000,
                .read_receipt => 2200,
            };
            all_msgs.append(core.getAllocator(), sdkws.MsgData{
                .send_id = core.getAllocator().dupe(u8, msg.sender_id) catch continue,
                .recv_id = core.getAllocator().dupe(u8, msg.receiver_id) catch continue,
                .group_id = core.getAllocator().dupe(u8, msg.group_id) catch continue,
                .client_msg_id = core.getAllocator().dupe(u8, msg.client_msg_id) catch continue,
                .server_msg_id = core.getAllocator().dupe(u8, msg.server_msg_id) catch continue,
                .sender_platform_id = msg.sender_platform_id,
                .sender_nickname = core.getAllocator().dupe(u8, msg.sender_nickname) catch continue,
                .sender_face_url = core.getAllocator().dupe(u8, msg.sender_face_url) catch continue,
                .session_type = session_type,
                .msg_from = msg.msg_from,
                .content_type = content_type,
                .content = core.getAllocator().dupe(u8, msg.content) catch continue,
                .seq = msg.seq,
                .send_time = msg.send_time,
                .create_time = msg.create_time,
                .status = msg.status,
                .is_read = msg.is_read,
            }) catch continue;
        }
    }

    const pull_msgs = sdkws.PullMsgs{ .msgs = all_msgs.items, .is_end = true, .end_seq = 0 };
    const resp_bytes = pull_msgs.encode(core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to encode PullMsgs", operation_id);
        return;
    };
    defer core.getAllocator().free(resp_bytes);
    sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", resp_bytes);
}

pub fn handleWSPullMsg(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    const req = sdkws.GetSeqMessageReq.decode(data_bytes, core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to decode GetSeqMessageReq", operation_id);
        return;
    };
    defer {
        core.getAllocator().free(req.user_id);
        core.getAllocator().free(req.conversation_id);
    }

    // Use seq range for efficient single-seq lookup
    const msgs = message_mod.getMessagesBySeqRange(req.conversation_id, req.seq, req.seq, 1, false) catch |e| {
        sendWSError(client, req_id, msg_incr, model.WSDataError, @errorName(e), operation_id);
        return;
    };
    defer core.getAllocator().free(msgs);

    var found_msg: ?sdkws.MsgData = null;
    if (msgs.len > 0) {
        const msg = msgs[0];
        const session_type: i32 = switch (msg.session_type) {
            .single => 1,
            .group => 2,
            .notification => 3,
        };
        const content_type: i32 = @backingInt(msg.content_type);
        found_msg = sdkws.MsgData{
            .send_id = core.getAllocator().dupe(u8, msg.sender_id) catch "",
            .recv_id = core.getAllocator().dupe(u8, msg.receiver_id) catch "",
            .group_id = core.getAllocator().dupe(u8, msg.group_id) catch "",
            .client_msg_id = core.getAllocator().dupe(u8, msg.client_msg_id) catch "",
            .server_msg_id = core.getAllocator().dupe(u8, msg.server_msg_id) catch "",
            .sender_platform_id = msg.sender_platform_id,
            .sender_nickname = core.getAllocator().dupe(u8, msg.sender_nickname) catch "",
            .sender_face_url = core.getAllocator().dupe(u8, msg.sender_face_url) catch "",
            .session_type = session_type,
            .msg_from = msg.msg_from,
            .content_type = content_type,
            .content = core.getAllocator().dupe(u8, msg.content) catch "",
            .seq = msg.seq,
            .send_time = msg.send_time,
            .create_time = msg.create_time,
            .status = msg.status,
            .is_read = msg.is_read,
        };
    }

    const resp = sdkws.GetSeqMessageResp{ .msg = found_msg };
    const resp_bytes = resp.encode(core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to encode GetSeqMessageResp", operation_id);
        return;
    };
    defer core.getAllocator().free(resp_bytes);
    sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", resp_bytes);
}

pub fn handleWSSendMsg(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    const msg_data = sdkws.MsgData.decode(data_bytes, core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to decode MsgData", operation_id);
        return;
    };

    const session_type: message_mod.SessionType = switch (msg_data.session_type) {
        2 => .group,
        else => .single,
    };

    const content_type: message_mod.ContentType = if (msg_data.content_type >= 101 and msg_data.content_type <= 117)
        @fromBackingInt(@intCast(msg_data.content_type))
    else if (msg_data.content_type == 1000)
        .system_notification
    else
        .text;

    const msg = message_mod.sendMessage(.{
        .send_id = msg_data.send_id,
        .recv_id = msg_data.recv_id,
        .group_id = msg_data.group_id,
        .session_type = session_type,
        .content_type = content_type,
        .content = msg_data.content,
        .sender_platform_id = @intCast(msg_data.sender_platform_id),
        .sender_nickname = msg_data.sender_nickname,
        .sender_face_url = msg_data.sender_face_url,
    }) catch |e| {
        sendWSError(client, req_id, msg_incr, model.WSDataError, @errorName(e), operation_id);
        return;
    };

    const resp = sdkws.UserSendMsgResp{
        .server_msg_id = msg.server_msg_id,
        .client_msg_id = msg.client_msg_id,
        .send_time = msg.send_time,
    };
    const resp_bytes = resp.encode(core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to encode UserSendMsgResp", operation_id);
        return;
    };
    defer core.getAllocator().free(resp_bytes);
    sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", resp_bytes);
}

pub fn handleWSGetConvMaxReadSeq(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    const req = sdkws.GetConvMaxReadSeqReq.decode(data_bytes, core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to decode GetConvMaxReadSeqReq", operation_id);
        return;
    };
    defer {
        core.getAllocator().free(req.user_id);
        core.getAllocator().free(req.conversation_id);
    }

    const conv = conversation_mod.getConversation(req.user_id, req.conversation_id) catch null;
    const max_read_seq = if (conv) |c| c.has_read_seq else 0;

    const resp = sdkws.GetConvMaxReadSeqResp{ .max_read_seq = max_read_seq };
    const resp_bytes = resp.encode(core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to encode GetConvMaxReadSeqResp", operation_id);
        return;
    };
    defer core.getAllocator().free(resp_bytes);
    sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", resp_bytes);
}

pub fn handleWSSetBackgroundStatus(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    _ = data_bytes;
    client.is_background = true;
    std.log.info("[WebSocket] User {s} set background status", .{client.user_id});
    sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", &[_]u8{});
}

pub fn handleWSPullConvLastMessage(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    const req = sdkws.GetLastMessageReq.decode(data_bytes, core.getAllocator()) catch {
        sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to decode GetLastMessageReq", operation_id);
        return;
    };

    const allocator = core.getAllocator();
    var results = std.ArrayList(sdkws.GetLastMessageResp).empty;
    defer {
        for (results.items) |r| {
            if (r.msg) |m| {
                allocator.free(m.send_id);
                allocator.free(m.recv_id);
                allocator.free(m.group_id);
                allocator.free(m.client_msg_id);
                allocator.free(m.server_msg_id);
                allocator.free(m.sender_nickname);
                allocator.free(m.sender_face_url);
                allocator.free(m.content);
                allocator.free(m.attached_info);
                allocator.free(m.ex);
            }
        }
        results.deinit(allocator);
    }

    for (req.conversation_ids) |conv_id| {
        const conv = conversation_mod.getConversation(client.user_id, conv_id) catch null;
        if (conv) |c| {
            if (c.latest_msg.len > 0) {
                const msg = sdkws.MsgData{
                    .send_id = allocator.dupe(u8, c.latest_msg_send_id) catch "",
                    .recv_id = "",
                    .group_id = allocator.dupe(u8, c.group_id) catch "",
                    .client_msg_id = "",
                    .server_msg_id = "",
                    .sender_platform_id = 0,
                    .sender_nickname = "",
                    .sender_face_url = "",
                    .session_type = @intCast(@backingInt(c.conversation_type)),
                    .msg_from = 0,
                    .content_type = c.latest_msg_content_type,
                    .content = allocator.dupe(u8, c.latest_msg) catch "",
                    .seq = c.max_seq,
                    .send_time = c.latest_msg_send_time,
                    .create_time = 0,
                    .status = 0,
                    .is_read = false,
                    .at_user_id_list = &.{},
                    .attached_info = "",
                    .ex = "",
                };
                const resp_item = sdkws.GetLastMessageResp{
                    .conversation_id = conv_id,
                    .msg = msg,
                };
                results.append(allocator, resp_item) catch {
                    sendWSError(client, req_id, msg_incr, model.WSDataError, "Out of memory", operation_id);
                    return;
                };
            }
        }
    }

    if (results.items.len > 0) {
        const first = results.items[0];
        const resp_bytes = first.encode(allocator) catch {
            sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to encode GetLastMessageResp", operation_id);
            return;
        };
        defer allocator.free(resp_bytes);
        sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", resp_bytes);
    } else {
        sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", &[_]u8{});
    }
}

pub fn isTextPing(payload: []const u8) bool {
    if (payload.len < 15) return false;
    const ping_pat = "{\"type\":\"ping\"}";
    return std.mem.eql(u8, payload[0..ping_pat.len], ping_pat);
}

// Legacy handlers

pub fn handleSendMsg(client: *WSClient, params: std.json.ObjectMap) void {
    const data = params.get("data") orelse {
        sendError(client, "Missing data");
        return;
    };
    const msg_data = data.object;
    const send_id = msg_data.get("sendID") orelse {
        sendError(client, "Missing sendID");
        return;
    };
    const recv_id = msg_data.get("recvID") orelse {
        sendError(client, "Missing recvID");
        return;
    };
    const content = msg_data.get("content") orelse {
        sendError(client, "Missing content");
        return;
    };

    const session_type: message_mod.SessionType = if (msg_data.get("sessionType")) |st|
        switch (st.integer) {
            1 => .single,
            2 => .group,
            else => .single,
        }
    else
        .single;

    const content_type: message_mod.ContentType = if (msg_data.get("contentType")) |ct|
        switch (ct.integer) {
            101 => .text,
            102 => .image,
            103 => .audio,
            104 => .video,
            105 => .file,
            else => .text,
        }
    else
        .text;

    const msg = message_mod.sendMessage(message_mod.MessageSendInput{
        .send_id = send_id.string,
        .recv_id = recv_id.string,
        .session_type = session_type,
        .content_type = content_type,
        .content = content.string,
    }) catch |e| {
        sendError(client, @errorName(e));
        return;
    };

    const response = std.fmt.allocPrint(core.getAllocator(), "{{\"errCode\":0,\"errMsg\":\"\",\"data\":{{\"serverMsgID\":\"{s}\",\"clientMsgID\":\"{s}\",\"seq\":{d},\"sendTime\":{d}}}}}", .{ msg.server_msg_id, msg.client_msg_id, msg.seq, msg.send_time }) catch return;
    defer core.getAllocator().free(response);
    client.sendText(response) catch {};
}

pub fn handlePullMsg(client: *WSClient, params: std.json.ObjectMap) void {
    const conversation_id = if (params.get("conversationID")) |v| v.string else "";
    const messages = message_mod.getMessages(conversation_id, 0, 100) catch |e| {
        const response = std.fmt.allocPrint(core.getAllocator(), "{{\"errCode\":500,\"errMsg\":\"{s}\",\"data\":null}}", .{@errorName(e)}) catch return;
        defer core.getAllocator().free(response);
        client.sendText(response) catch {};
        return;
    };

    const response = std.fmt.allocPrint(core.getAllocator(), "{{\"errCode\":0,\"errMsg\":\"\",\"data\":{{\"msgs\":{any},\"maxSeq\":{d}}}}}", .{ messages, message_mod.getMaxSeq(conversation_id) }) catch return;
    defer core.getAllocator().free(response);
    client.sendText(response) catch {};
}

pub fn handleSyncMsg(client: *WSClient, params: std.json.ObjectMap) void {
    _ = params;
    const response = "{\"errCode\":0,\"errMsg\":\"\",\"data\":{\"msgs\":[],\"deletedMsgs\":[],\"hasMore\":false}}";
    client.sendText(response) catch {};
}
