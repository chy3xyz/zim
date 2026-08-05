// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: office.zig

const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const office_mod = @import("../../office.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleAddComment(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CommentReq = struct {
        momentID: []const u8,
        userID: []const u8,
        nickname: []const u8,
        faceURL: []const u8,
        replyUserID: ?[]const u8 = null,
        replyNickname: ?[]const u8 = null,
        replyFaceURL: ?[]const u8 = null,
        content: []const u8,
    };
    const req = ctx.bindJson(CommentReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = office_mod.addComment(req.momentID, req.userID, req.nickname, req.faceURL, req.replyUserID, req.replyNickname, req.replyFaceURL, req.content);
    return sendOk(ctx, null);
}

pub fn handleAddFavoriteMessage(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const AddReq = struct {
        userID: []const u8,
        collectType: []const u8,
        content: []const u8,
        uuid: []const u8,
    };
    const req = ctx.bindJson(AddReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const collect = office_mod.addCollect(req.userID, req.collectType, req.content, req.uuid) catch |err| {
        return sendFail(ctx, core.ErrorCode.add_favorite_message, @errorName(err));
    };
    return sendOk(ctx, dto.collectToJson(collect));
}

pub fn handleClearUnreadWorkMoments(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ClearReq = struct {
        userID: []const u8,
        readType: i32 = 0,
    };
    const req = ctx.bindJson(ClearReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    office_mod.clearUnreadWorkMoments(req.userID, req.readType);
    return sendOk(ctx, null);
}

pub fn handleCreateTag(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const TagReq = struct {
        userID: []const u8,
        tagName: []const u8,
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(TagReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const tag = office_mod.createTag(.{ .user_id = req.userID, .tag_name = req.tagName, .user_ids = req.userIDs }) catch |err| {
        return sendFail(ctx, core.ErrorCode.create_tag, @errorName(err));
    };
    return sendOk(ctx, dto.tagToJson(tag));
}

pub fn handleCreateWorkMoment(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CreateReq = struct {
        userID: []const u8,
        content: []const u8,
        metas: ?[]const u8 = null,
        permission: ?[]const u8 = null,
        atUserIDs: ?[]const u8 = null,
        permissionUserIDs: ?[]const u8 = null,
    };
    const req = ctx.bindJson(CreateReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const moment = office_mod.createWorkMoment(.{
        .user_id = req.userID,
        .content = req.content,
        .metas = req.metas,
        .permission = req.permission,
        .at_user_ids = req.atUserIDs,
        .permission_user_ids = req.permissionUserIDs,
    }) catch |err| {
        return sendFail(ctx, core.ErrorCode.create_work_moment, @errorName(err));
    };
    return sendOk(ctx, dto.workMomentToJson(moment));
}

pub fn handleDeleteComment(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        momentID: []const u8,
        commentID: []const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = office_mod.deleteComment(req.momentID, req.commentID);
    return sendOk(ctx, null);
}

pub fn handleDeleteTag(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        tagID: []const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = office_mod.deleteTag(req.tagID) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_tag, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleDeleteWorkMoment(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        momentID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = office_mod.deleteWorkMoment(req.momentID, req.userID);
    return sendOk(ctx, null);
}

pub fn handleGetClientConfig(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    return sendOk(ctx, .{ .version = "1.0.0" });
}

pub fn handleGetFavoriteMessages(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
        collectTypes: [][]const u8 = &.{},
        pageNumber: u32 = 1,
        showNumber: u32 = 20,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const collects = office_mod.getCollects(core.getAllocator(), req.userID, req.collectTypes, req.pageNumber, req.showNumber) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_favorite_messages, @errorName(err));
    };
    var collects_json = std.ArrayList(@TypeOf(dto.collectToJson(collects[0]))).empty;
    defer collects_json.deinit(core.getAllocator());
    for (collects) |c| {
        try collects_json.append(core.getAllocator(), dto.collectToJson(c));
    }
    return sendOk(ctx, .{ .collects = collects_json.items });
}

pub fn handleGetRecvWorkMoments(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
        pageNumber: u32 = 1,
        showNumber: u32 = 20,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const moments = office_mod.getRecvWorkMoments(core.getAllocator(), req.userID, req.pageNumber, req.showNumber) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_recv_work_moments, @errorName(err));
    };
    var moments_json = std.ArrayList(@TypeOf(dto.workMomentToJson(moments[0]))).empty;
    defer moments_json.deinit(core.getAllocator());
    for (moments) |m| {
        try moments_json.append(core.getAllocator(), dto.workMomentToJson(m));
    }
    return sendOk(ctx, .{ .moments = moments_json.items });
}

pub fn handleGetSendWorkMoments(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
        pageNumber: u32 = 1,
        showNumber: u32 = 20,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const moments = office_mod.getSendWorkMoments(core.getAllocator(), req.userID, req.userID, req.pageNumber, req.showNumber) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_send_work_moments, @errorName(err));
    };
    var moments_json = std.ArrayList(@TypeOf(dto.workMomentToJson(moments[0]))).empty;
    defer moments_json.deinit(core.getAllocator());
    for (moments) |m| {
        try moments_json.append(core.getAllocator(), dto.workMomentToJson(m));
    }
    return sendOk(ctx, .{ .moments = moments_json.items });
}

pub fn handleGetUnreadWorkMomentsCount(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CountReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(CountReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const count = office_mod.getUnreadWorkMomentsCount(req.userID);
    return sendOk(ctx, .{ .count = count });
}

pub fn handleGetUserTags(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const tags = office_mod.getTags(core.getAllocator(), req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_user_tags, @errorName(err));
    };
    var tags_json = std.ArrayList(@TypeOf(dto.tagToJson(tags[0]))).empty;
    defer tags_json.deinit(core.getAllocator());
    for (tags) |t| {
        try tags_json.append(core.getAllocator(), dto.tagToJson(t));
    }
    return sendOk(ctx, .{ .tags = tags_json.items });
}

pub fn handleGetWorkMoment(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        momentID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const moment = office_mod.getWorkMoment(req.momentID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_work_moment, @errorName(err));
    };
    if (moment == null) return sendFail(ctx, 404, "Not Found");
    return sendOk(ctx, dto.workMomentToJson(moment.?));
}

pub fn handleGetWorkMomentLogs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const LogReq = struct {
        userID: []const u8,
        pageNumber: u32 = 1,
        showNumber: u32 = 20,
    };
    const req = ctx.bindJson(LogReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const moments = office_mod.findRelevantWorkMoments(core.getAllocator(), req.userID, req.pageNumber, req.showNumber) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_work_moment_logs, @errorName(err));
    };
    var moments_json = std.ArrayList(@TypeOf(dto.workMomentToJson(moments[0]))).empty;
    defer moments_json.deinit(core.getAllocator());
    for (moments) |m| {
        try moments_json.append(core.getAllocator(), dto.workMomentToJson(m));
    }
    return sendOk(ctx, .{ .moments = moments_json.items });
}

pub fn handleLikeWorkMoment(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const LikeReq = struct {
        momentID: []const u8,
        userID: []const u8,
        nickname: []const u8,
        faceURL: []const u8,
    };
    const req = ctx.bindJson(LikeReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = office_mod.likeWorkMoment(req.momentID, req.userID, req.nickname, req.faceURL);
    return sendOk(ctx, null);
}

pub fn handleRemoveFavoriteMessage(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        userID: []const u8,
        collectIDs: [][]const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = office_mod.removeCollect(req.userID, req.collectIDs) catch |err| {
        return sendFail(ctx, core.ErrorCode.remove_favorite_message, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleUpdateTag(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const UpdateReq = struct {
        tagID: []const u8,
        tagName: ?[]const u8 = null,
        addUserIDs: ?[][]const u8 = null,
        delUserIDs: ?[][]const u8 = null,
    };
    const req = ctx.bindJson(UpdateReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = office_mod.updateTag(.{
        .tag_id = req.tagID,
        .tag_name = req.tagName,
        .add_user_ids = req.addUserIDs orelse &.{},
        .del_user_ids = req.delUserIDs orelse &.{},
    }) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_favorite_messages, @errorName(err));
    };
    return sendOk(ctx, null);
}
