// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: conversation.zig

const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const conversation_mod = @import("../../conversation.zig");
const group_mod = @import("../../group.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleGetAllConversations(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetAllReq = struct {
        ownerUserID: []const u8,
    };
    const req = ctx.bindJson(GetAllReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const all_convs = conversation_mod.getConversationsByOwner(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_all_conversations, @errorName(err));
    };
    {
        var convs_json = std.ArrayList(@TypeOf(dto.conversationToJson(all_convs[0]))).empty;
        defer convs_json.deinit(core.getAllocator());
        for (all_convs) |c| {
            try convs_json.append(core.getAllocator(), dto.conversationToJson(c));
        }
        return sendOk(ctx, .{ .conversations = convs_json.items });
    }
}

pub fn handleGetConversation(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetConvReq = struct {
        ownerUserID: []const u8,
        conversationID: []const u8,
    };
    const req = ctx.bindJson(GetConvReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const conv = conversation_mod.getConversation(req.ownerUserID, req.conversationID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_conversation, @errorName(err));
    };
    if (conv == null) return sendFail(ctx, 404, "Not Found");
    const c = conv.?;
    return sendOk(ctx, .{
        .conversationID = c.conversation_id,
        .conversationType = @backingInt(c.conversation_type),
        .userID = c.user_id,
        .groupID = c.group_id,
        .recvMsgOpt = c.recv_msg_opt,
        .isPinned = c.is_pinned,
        .isPrivateChat = c.is_private_chat,
        .burnDuration = c.burn_duration,
        .groupAtType = c.group_at_type,
        .attachedInfo = c.attached_info,
        .ex = c.ex,
        .maxSeq = c.max_seq,
        .minSeq = c.min_seq,
        .hasReadSeq = c.has_read_seq,
        .latestMsg = c.latest_msg,
        .latestMsgSendTime = c.latest_msg_send_time,
        .latestMsgSendID = c.latest_msg_send_id,
        .latestMsgContentType = c.latest_msg_content_type,
        .createTime = c.create_time,
        .updateTime = c.update_time,
        .isMsgDestruct = c.is_msg_destruct,
        .msgDestructTime = c.msg_destruct_time,
    });
}

pub fn handleGetConversationOfflinePushUserIDs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    return sendOk(ctx, .{ .userIDs = &.{} });
}

pub fn handleGetConversations(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetConvsReq = struct {
        ownerUserID: []const u8,
        conversationIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetConvsReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var convs = std.ArrayList(struct {
        conversationID: []const u8,
        conversationType: i16,
        userID: []const u8,
        groupID: []const u8,
        recvMsgOpt: i16,
        isPinned: bool,
        maxSeq: i64,
        minSeq: i64,
        hasReadSeq: i64,
        latestMsg: []const u8,
        latestMsgSendTime: i64,
        latestMsgSendID: []const u8,
        latestMsgContentType: i16,
        createTime: i64,
        updateTime: i64,
    }).empty;
    defer convs.deinit(core.getAllocator());
    for (req.conversationIDs) |cid| {
        if (conversation_mod.getConversation(req.ownerUserID, cid) catch null) |c| {
            try convs.append(core.getAllocator(), .{
                .conversationID = c.conversation_id,
                .conversationType = @backingInt(c.conversation_type),
                .userID = c.user_id,
                .groupID = c.group_id,
                .recvMsgOpt = c.recv_msg_opt,
                .isPinned = c.is_pinned,
                .maxSeq = c.max_seq,
                .minSeq = c.min_seq,
                .hasReadSeq = c.has_read_seq,
                .latestMsg = c.latest_msg,
                .latestMsgSendTime = c.latest_msg_send_time,
                .latestMsgSendID = c.latest_msg_send_id,
                .latestMsgContentType = c.latest_msg_content_type,
                .createTime = c.create_time,
                .updateTime = c.update_time,
            });
        }
    }
    return sendOk(ctx, .{ .conversations = convs.items });
}

pub fn handleGetFullConversationIDs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        ownerUserID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const convs = conversation_mod.getConversationsByOwner(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_full_conversation_ids, @errorName(err));
    };
    var ids = std.ArrayList([]const u8).empty;
    defer ids.deinit(core.getAllocator());
    for (convs) |c| {
        try ids.append(core.getAllocator(), c.conversation_id);
    }
    return sendOk(ctx, .{ .conversationIDs = ids.items });
}

pub fn handleGetIncrementalConversations(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const IncReq = struct {
        ownerUserID: []const u8,
        sinceTimestamp: i64,
    };
    const req = ctx.bindJson(IncReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const convs = conversation_mod.getConversationsByOwnerSince(req.ownerUserID, req.sinceTimestamp) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_incremental_conversations, @errorName(err));
    };
    var convs_json = std.ArrayList(@TypeOf(dto.conversationToJson(convs[0]))).empty;
    defer convs_json.deinit(core.getAllocator());
    for (convs) |c| {
        try convs_json.append(core.getAllocator(), dto.conversationToJson(c));
    }
    return sendOk(ctx, .{ .conversations = convs_json.items });
}

pub fn handleGetNotNotifyConversationIDs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        ownerUserID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const convs = conversation_mod.getConversationsByOwner(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_not_notify_conversation_ids, @errorName(err));
    };
    var ids = std.ArrayList([]const u8).empty;
    defer ids.deinit(core.getAllocator());
    for (convs) |c| {
        if (c.recv_msg_opt != 0) {
            try ids.append(core.getAllocator(), c.conversation_id);
        }
    }
    return sendOk(ctx, .{ .conversationIDs = ids.items });
}

pub fn handleGetOwnerConversation(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetOwnerReq = struct {
        ownerUserID: []const u8,
        conversationID: []const u8,
    };
    const req = ctx.bindJson(GetOwnerReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const conv = conversation_mod.getConversation(req.ownerUserID, req.conversationID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_owner_conversation, @errorName(err));
    };
    if (conv == null) return sendFail(ctx, 404, "Not Found");
    const c = conv.?;
    return sendOk(ctx, .{
        .conversationID = c.conversation_id,
        .conversationType = @backingInt(c.conversation_type),
        .userID = c.user_id,
        .groupID = c.group_id,
        .recvMsgOpt = c.recv_msg_opt,
        .isPinned = c.is_pinned,
        .maxSeq = c.max_seq,
        .minSeq = c.min_seq,
        .hasReadSeq = c.has_read_seq,
        .latestMsg = c.latest_msg,
        .latestMsgSendTime = c.latest_msg_send_time,
        .latestMsgSendID = c.latest_msg_send_id,
        .latestMsgContentType = c.latest_msg_content_type,
        .createTime = c.create_time,
        .updateTime = c.update_time,
    });
}

pub fn handleGetPinnedConversationIDs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        ownerUserID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const convs = conversation_mod.getConversationsByOwner(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_pinned_conversation_ids, @errorName(err));
    };
    var ids = std.ArrayList([]const u8).empty;
    defer ids.deinit(core.getAllocator());
    for (convs) |c| {
        if (c.is_pinned) {
            try ids.append(core.getAllocator(), c.conversation_id);
        }
    }
    return sendOk(ctx, .{ .conversationIDs = ids.items });
}

pub fn handleGetSortedConversationList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SortReq = struct {
        ownerUserID: ?[]const u8 = null,
        userID: ?[]const u8 = null,
        conversationIDs: ?[][]const u8 = null,
    };
    const req = ctx.bindJson(SortReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    // Go OpenIM SDK sends `userID`; older clients sent `ownerUserID`.
    const owner = req.userID orelse req.ownerUserID orelse return sendFail(ctx, 400, "Missing user identifier");
    const all_convs = conversation_mod.getConversationsByOwner(owner) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_sorted_conversation_list, @errorName(err));
    };
    // Sort by latestMsgSendTime descending (simple bubble sort)
    var i: usize = 0;
    while (i < all_convs.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < all_convs.len) : (j += 1) {
            if (all_convs[i].latest_msg_send_time < all_convs[j].latest_msg_send_time) {
                const tmp = all_convs[i];
                all_convs[i] = all_convs[j];
                all_convs[j] = tmp;
            }
        }
    }

    // Go OpenIM `GetSortedConversationListResp`: conversationElems + totals.
    // msgInfo mirrors Go `conversation.MsgInfo` (17 fields, json tags as-is).
    const MsgInfo = struct {
        serverMsgID: []const u8,
        clientMsgID: []const u8,
        sessionType: i16,
        sendID: []const u8,
        recvID: []const u8,
        senderName: []const u8,
        faceURL: []const u8,
        groupID: []const u8,
        groupName: []const u8,
        groupFaceURL: []const u8,
        groupType: i16,
        groupMemberCount: i64,
        LatestMsgRecvTime: i64,
        msgFrom: i16,
        contentType: i16,
        content: []const u8,
        ex: []const u8,
    };
    const Elem = struct {
        conversationID: []const u8,
        recvMsgOpt: i16,
        unreadCount: i64,
        isPinned: bool,
        msgInfo: MsgInfo,
    };

    var elems = std.ArrayList(Elem).empty;
    defer elems.deinit(core.getAllocator());
    var convs_json = std.ArrayList(@TypeOf(dto.conversationToJson(all_convs[0]))).empty;
    defer convs_json.deinit(core.getAllocator());
    var unread_total: i64 = 0;

    for (all_convs) |c| {
        const unread = c.max_seq - c.has_read_seq;
        unread_total += unread;

        var info = MsgInfo{
            .serverMsgID = "",
            .clientMsgID = "",
            .sessionType = if (c.conversation_type == .group) 2 else 1,
            .sendID = "",
            .recvID = "",
            .senderName = "",
            .faceURL = "",
            .groupID = c.group_id,
            .groupName = "",
            .groupFaceURL = "",
            .groupType = 0,
            .groupMemberCount = 0,
            .LatestMsgRecvTime = c.latest_msg_send_time,
            .msgFrom = 100,
            .contentType = c.latest_msg_content_type,
            .content = "",
            .ex = "",
        };
        if (std.json.parseFromSlice(std.json.Value, core.getAllocator(), c.latest_msg, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value == .object) {
                const obj = parsed.value.object;
                inline for (.{ "clientMsgID", "serverMsgID", "sendID", "recvID", "content", "ex" }) |key| {
                    if (obj.get(key)) |v| {
                        if (v == .string) {
                            @field(info, key) = core.getAllocator().dupe(u8, v.string) catch "";
                        }
                    }
                }
                // Message DTO emits senderNickname/senderFaceUrl; Go MsgInfo uses
                // senderName/faceURL — map across.
                if (obj.get("senderNickname")) |v| {
                    if (v == .string) info.senderName = core.getAllocator().dupe(u8, v.string) catch "";
                }
                if (obj.get("senderFaceUrl")) |v| {
                    if (v == .string) info.faceURL = core.getAllocator().dupe(u8, v.string) catch "";
                }
                if (obj.get("sessionType")) |v| {
                    if (v == .integer) info.sessionType = @intCast(v.integer);
                }
                if (obj.get("msgFrom")) |v| {
                    if (v == .integer) info.msgFrom = @intCast(v.integer);
                }
                if (obj.get("contentType")) |v| {
                    if (v == .integer) info.contentType = @intCast(v.integer);
                }
                if (obj.get("sendTime")) |v| {
                    if (v == .integer) info.LatestMsgRecvTime = @intCast(v.integer);
                }
            }
        } else |_| {}

        // Group conversations enrich msgInfo with group identity.
        if (c.conversation_type == .group) {
            if (group_mod.getGroup(c.group_id)) |g| {
                info.groupName = g.group_name;
                info.groupFaceURL = g.face_url;
                info.groupType = @backingInt(g.group_type);
                if (group_mod.getGroupMembers(c.group_id)) |members| {
                    info.groupMemberCount = @intCast(members.len);
                } else |_| {}
            }
        }

        try elems.append(core.getAllocator(), .{
            .conversationID = c.conversation_id,
            .recvMsgOpt = c.recv_msg_opt,
            .unreadCount = unread,
            .isPinned = c.is_pinned,
            .msgInfo = info,
        });
        try convs_json.append(core.getAllocator(), dto.conversationToJson(c));
    }

    return sendOk(ctx, .{
        .conversationElems = elems.items,
        .conversationTotal = all_convs.len,
        .unreadTotal = unread_total,
        .conversations = convs_json.items, // legacy flat form
    });
}

// ── JSSdk web-session aggregation endpoints (Go jssdk) ─────────

pub fn handleSetConversations(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SetConvReq = struct {
        ownerUserID: []const u8,
        conversations: []struct {
            conversationID: []const u8,
            recvMsgOpt: ?i16 = null,
            isPinned: ?bool = null,
            groupAtType: ?i16 = null,
            attachedInfo: ?[]const u8 = null,
            ex: ?[]const u8 = null,
            isMsgDestruct: ?bool = null,
            msgDestructTime: ?i64 = null,
            hasReadSeq: ?i64 = null,
        },
    };
    const req = ctx.bindJson(SetConvReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    for (req.conversations) |c| {
        _ = conversation_mod.updateConversation(req.ownerUserID, c.conversationID, .{
            .recv_msg_opt = c.recvMsgOpt,
            .is_pinned = c.isPinned,
            .group_at_type = c.groupAtType,
            .attached_info = c.attachedInfo,
            .ex = c.ex,
            .is_msg_destruct = c.isMsgDestruct,
            .msg_destruct_time = c.msgDestructTime,
            .has_read_seq = c.hasReadSeq,
        }) catch |err| {
            return sendFail(ctx, core.ErrorCode.set_conversations, @errorName(err));
        };
    }
    return sendOk(ctx, null);
}
