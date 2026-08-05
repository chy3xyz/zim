// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: third.zig

const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const third_mod = @import("../../third.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleFCMUpdateToken(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const FCMReq = struct {
        userID: []const u8,
        platformID: i32,
        fcmToken: []const u8,
    };
    const req = ctx.bindJson(FCMReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    third_mod.saveFCMToken(req.userID, req.platformID, req.fcmToken) catch |err| {
        return sendFail(ctx, core.ErrorCode.fcm_update_token, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleObjectAccessUrl(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const AccessReq = struct {
        objectKey: []const u8,
        expirySeconds: u32 = 3600,
    };
    const req = ctx.bindJson(AccessReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const url = third_mod.accessUrl(core.getAllocator(), req.objectKey, req.expirySeconds) catch |err| {
        return sendFail(ctx, core.ErrorCode.object_access_url, @errorName(err));
    };
    defer core.getAllocator().free(url);
    return sendOk(ctx, .{ .url = url });
}

pub fn handleObjectAuthSign(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SignReq = struct {
        objectKey: []const u8,
        method: []const u8 = "GET",
        expirySeconds: u32 = 3600,
    };
    const req = ctx.bindJson(SignReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const url = third_mod.presignedUrl(core.getAllocator(), req.method, req.objectKey, req.expirySeconds) catch |err| {
        return sendFail(ctx, core.ErrorCode.object_auth_sign, @errorName(err));
    };
    defer core.getAllocator().free(url);
    return sendOk(ctx, .{ .url = url });
}

pub fn handleObjectPartLimit(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    return sendOk(ctx, .{ .minPartSize = 1024 * 1024, .maxPartSize = 100 * 1024 * 1024, .maxNumSize = 10000 });
}

pub fn handleSearchLogs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SearchReq = struct {
        userID: ?[]const u8 = null,
        platform: ?i32 = null,
        startTime: ?i64 = null,
        endTime: ?i64 = null,
        pageNumber: i32 = 1,
        showNumber: i32 = 20,
    };
    const req = ctx.bindJson(SearchReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const result = third_mod.searchLogs(core.getAllocator(), req.userID, req.platform, req.startTime, req.endTime, req.pageNumber, req.showNumber) catch |err| {
        return sendFail(ctx, core.ErrorCode.search_logs, @errorName(err));
    };
    var logs_json = std.ArrayList(@TypeOf(dto.logEntryToJson(result.logs[0]))).empty;
    defer logs_json.deinit(core.getAllocator());
    for (result.logs) |l| {
        try logs_json.append(core.getAllocator(), dto.logEntryToJson(l));
    }
    return sendOk(ctx, .{ .logs = logs_json.items, .total = result.total });
}

pub fn handleSetAppBadge(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const BadgeReq = struct {
        userID: []const u8,
        appUnreadCount: i32,
    };
    const req = ctx.bindJson(BadgeReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    core.logInfo("Set app badge user={s} count={d}", .{ req.userID, req.appUnreadCount });
    return sendOk(ctx, .{ .unreadCount = req.appUnreadCount });
}

pub fn handleUploadLogs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const LogReq = struct {
        userID: []const u8,
        platform: i32,
        fileURL: []const u8,
    };
    const req = ctx.bindJson(LogReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    third_mod.saveLog(req.userID, req.platform, req.fileURL) catch |err| {
        return sendFail(ctx, core.ErrorCode.upload_logs, @errorName(err));
    };
    return sendOk(ctx, null);
}
