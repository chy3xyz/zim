// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: jssdk.zig

const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const user_mod = @import("../../user.zig");
const conversation_mod = @import("../../conversation.zig");
const message_mod = @import("../../message.zig");
const group_mod = @import("../../group.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

const JsConvJson = @TypeOf(dto.conversationToJson(@as(conversation_mod.Conversation, undefined)));

const JsMsgJson = @TypeOf(dto.messageToJson(@as(message_mod.Message, undefined)));

const JsUserJson = @TypeOf(dto.userToJson(@as(user_mod.User, undefined)));

const JsGroupJson = @TypeOf(dto.groupToJson(@as(group_mod.Group, undefined)));

const JsConvMsg = struct {
    conversation: JsConvJson,
    lastMsg: JsMsgJson,
    user: ?JsUserJson = null,
    group: ?JsGroupJson = null,
    maxSeq: i64,
    readSeq: i64,
};

pub fn buildJsConversation(c: conversation_mod.Conversation) JsConvMsg {
    var msg = JsConvMsg{
        .conversation = dto.conversationToJson(c),
        .lastMsg = undefined,
        .maxSeq = c.max_seq,
        .readSeq = c.has_read_seq,
    };
    if (message_mod.getMessages(c.conversation_id, 0, 1)) |msgs| {
        if (msgs.len > 0) msg.lastMsg = dto.messageToJson(msgs[0]);
    } else |_| {}
    if (c.conversation_type == .single) {
        if (user_mod.getUser(c.user_id)) |u| {
            if (u) |user| msg.user = dto.userToJson(user);
        } else |_| {}
    } else if (c.conversation_type == .group) {
        if (group_mod.getGroup(c.group_id)) |g| msg.group = dto.groupToJson(g);
    }
    return msg;
}

pub fn sendJssdkConversations(ctx: *http.Context, convs: []conversation_mod.Conversation) anyerror!void {
    var list = std.ArrayList(JsConvMsg).empty;
    defer list.deinit(core.getAllocator());
    var unread_total: i64 = 0;
    for (convs) |c| {
        unread_total += c.max_seq - c.has_read_seq;
        try list.append(core.getAllocator(), buildJsConversation(c));
    }
    return sendOk(ctx, .{ .unreadCount = unread_total, .conversations = list.items });
}

pub fn handleJssdkGetConversations(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const Req = struct {
        ownerUserID: []const u8,
        conversationIDs: ?[][]const u8 = null,
    };
    const req = ctx.bindJson(Req) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var convs = std.ArrayList(conversation_mod.Conversation).empty;
    defer convs.deinit(core.getAllocator());
    if (req.conversationIDs) |ids| {
        for (ids) |id| {
            if (conversation_mod.getConversation(req.ownerUserID, id)) |c| {
                if (c) |conv| try convs.append(core.getAllocator(), conv);
            } else |_| {}
        }
    } else {
        const all = conversation_mod.getConversationsByOwner(req.ownerUserID) catch |err| {
            return sendFail(ctx, core.ErrorCode.get_all_conversations, @errorName(err));
        };
        for (all) |c| try convs.append(core.getAllocator(), c);
    }
    return sendJssdkConversations(ctx, convs.items);
}

pub fn handleJssdkGetActiveConversations(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const Req = struct {
        ownerUserID: []const u8,
        count: i64 = 20,
    };
    const req = ctx.bindJson(Req) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const all = conversation_mod.getConversationsByOwner(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_all_conversations, @errorName(err));
    };
    // Most recently active conversations first
    var list = std.ArrayList(conversation_mod.Conversation).empty;
    defer list.deinit(core.getAllocator());
    for (all) |c| try list.append(core.getAllocator(), c);
    std.mem.sort(conversation_mod.Conversation, list.items, {}, struct {
        fn lt(_: void, a: conversation_mod.Conversation, b: conversation_mod.Conversation) bool {
            return a.latest_msg_send_time > b.latest_msg_send_time;
        }
    }.lt);
    const take: usize = if (req.count > 0) @intCast(req.count) else list.items.len;
    return sendJssdkConversations(ctx, if (take < list.items.len) list.items[0..take] else list.items);
}
