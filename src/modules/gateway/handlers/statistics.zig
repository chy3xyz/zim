// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: statistics.zig

const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const user_mod = @import("../../user.zig");
const message_mod = @import("../../message.zig");
const group_mod = @import("../../group.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOkDataJson = helpers.sendOkDataJson;
const appendDayCountJson = helpers.appendDayCountJson;
const appendEscapedString = helpers.appendEscapedString;
const sendFail = helpers.sendFail;

pub fn handleStatisticsGroupActive(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const StatsReq = struct {
        startTime: ?i64 = null,
        endTime: ?i64 = null,
        pageNumber: u32 = 1,
        showNumber: u32 = 20,
    };
    const req = ctx.bindJson(StatsReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const start = req.startTime orelse 0;
    const end = req.endTime orelse 4102444800; // 2100-01-01
    const msg_count: i64 = @intCast(message_mod.activeMsgCount(start, end, true));
    const group_count: i64 = @intCast(message_mod.activeEntityCount(start, end, true));
    const days = message_mod.activeDateCount(core.getAllocator(), start, end, true) catch &.{};
    const top = message_mod.activeTopEntities(core.getAllocator(), start, end, true, req.showNumber) catch &.{};
    var json = std.ArrayList(u8).empty;
    defer json.deinit(core.getAllocator());
    var num_buf: [32]u8 = undefined;
    try json.appendSlice(core.getAllocator(), "{\"msgCount\":");
    try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{msg_count}) catch unreachable);
    try json.appendSlice(core.getAllocator(), ",\"groupCount\":");
    try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{group_count}) catch unreachable);
    try json.appendSlice(core.getAllocator(), ",\"dateCount\":");
    try appendDayCountJson(core.getAllocator(), &json, days);
    try json.appendSlice(core.getAllocator(), ",\"groups\":[");
    for (top, 0..) |g, i| {
        if (i > 0) try json.appendSlice(core.getAllocator(), ",");
        try json.appendSlice(core.getAllocator(), "{\"group\":{\"groupID\":\"");
        try appendEscapedString(core.getAllocator(), &json, g.id);
        try json.appendSlice(core.getAllocator(), "\",\"groupName\":\"");
        try appendEscapedString(core.getAllocator(), &json, g.name);
        try json.appendSlice(core.getAllocator(), "\",\"faceURL\":\"");
        try appendEscapedString(core.getAllocator(), &json, g.face_url);
        try json.appendSlice(core.getAllocator(), "\"},\"count\":");
        try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{g.count}) catch unreachable);
        try json.appendSlice(core.getAllocator(), "}");
    }
    try json.appendSlice(core.getAllocator(), "]}");
    return sendOkDataJson(ctx, json.items);
}

pub fn handleStatisticsGroupCreate(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const StatsReq = struct {
        startTime: ?i64 = null,
        endTime: ?i64 = null,
    };
    const req = ctx.bindJson(StatsReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const start = req.startTime orelse 0;
    const end = req.endTime orelse 4102444800; // 2100-01-01
    const total: i64 = @intCast(if (req.startTime != null and req.endTime != null) group_mod.groupCountSince(start, end) else group_mod.groupCount());
    const before: i64 = if (req.startTime != null) @intCast(group_mod.groupCountBefore(start)) else 0;
    const days = group_mod.groupCountByDay(core.getAllocator(), start, end) catch &.{};
    var json = std.ArrayList(u8).empty;
    defer json.deinit(core.getAllocator());
    var num_buf: [32]u8 = undefined;
    try json.appendSlice(core.getAllocator(), "{\"total\":");
    try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{total}) catch unreachable);
    try json.appendSlice(core.getAllocator(), ",\"before\":");
    try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{before}) catch unreachable);
    try json.appendSlice(core.getAllocator(), ",\"count\":{");
    for (days, 0..) |d, i| {
        if (i > 0) try json.appendSlice(core.getAllocator(), ",");
        try json.appendSlice(core.getAllocator(), "\"");
        try json.appendSlice(core.getAllocator(), d.day);
        try json.appendSlice(core.getAllocator(), "\":");
        try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{d.count}) catch unreachable);
    }
    try json.appendSlice(core.getAllocator(), "}}");
    return sendOkDataJson(ctx, json.items);
}

pub fn handleStatisticsUserActive(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const StatsReq = struct {
        startTime: ?i64 = null,
        endTime: ?i64 = null,
        pageNumber: u32 = 1,
        showNumber: u32 = 20,
    };
    const req = ctx.bindJson(StatsReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const start = req.startTime orelse 0;
    const end = req.endTime orelse 4102444800; // 2100-01-01
    const msg_count: i64 = @intCast(message_mod.activeMsgCount(start, end, false));
    const user_count: i64 = @intCast(message_mod.activeEntityCount(start, end, false));
    const days = message_mod.activeDateCount(core.getAllocator(), start, end, false) catch &.{};
    const top = message_mod.activeTopEntities(core.getAllocator(), start, end, false, req.showNumber) catch &.{};
    var json = std.ArrayList(u8).empty;
    defer json.deinit(core.getAllocator());
    var num_buf: [32]u8 = undefined;
    try json.appendSlice(core.getAllocator(), "{\"msgCount\":");
    try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{msg_count}) catch unreachable);
    try json.appendSlice(core.getAllocator(), ",\"userCount\":");
    try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{user_count}) catch unreachable);
    try json.appendSlice(core.getAllocator(), ",\"dateCount\":");
    try appendDayCountJson(core.getAllocator(), &json, days);
    try json.appendSlice(core.getAllocator(), ",\"users\":[");
    for (top, 0..) |u, i| {
        if (i > 0) try json.appendSlice(core.getAllocator(), ",");
        try json.appendSlice(core.getAllocator(), "{\"user\":{\"userID\":\"");
        try appendEscapedString(core.getAllocator(), &json, u.id);
        try json.appendSlice(core.getAllocator(), "\",\"nickname\":\"");
        try appendEscapedString(core.getAllocator(), &json, u.name);
        try json.appendSlice(core.getAllocator(), "\",\"faceURL\":\"");
        try appendEscapedString(core.getAllocator(), &json, u.face_url);
        try json.appendSlice(core.getAllocator(), "\"},\"count\":");
        try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{u.count}) catch unreachable);
        try json.appendSlice(core.getAllocator(), "}");
    }
    try json.appendSlice(core.getAllocator(), "]}");
    return sendOkDataJson(ctx, json.items);
}

pub fn handleStatisticsUserRegister(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const StatsReq = struct {
        startTime: ?i64 = null,
        endTime: ?i64 = null,
    };
    const req = ctx.bindJson(StatsReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const start = req.startTime orelse 0;
    const end = req.endTime orelse 4102444800; // 2100-01-01
    const total: i64 = @intCast(if (req.startTime != null and req.endTime != null) user_mod.userCountSince(start, end) else user_mod.userCount());
    const before: i64 = if (req.startTime != null) @intCast(user_mod.userCountBefore(start)) else 0;
    const days = user_mod.userCountByDay(core.getAllocator(), start, end) catch &.{};
    var json = std.ArrayList(u8).empty;
    defer json.deinit(core.getAllocator());
    var num_buf: [32]u8 = undefined;
    try json.appendSlice(core.getAllocator(), "{\"total\":");
    try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{total}) catch unreachable);
    try json.appendSlice(core.getAllocator(), ",\"before\":");
    try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{before}) catch unreachable);
    try json.appendSlice(core.getAllocator(), ",\"count\":{");
    for (days, 0..) |d, i| {
        if (i > 0) try json.appendSlice(core.getAllocator(), ",");
        try json.appendSlice(core.getAllocator(), "\"");
        try json.appendSlice(core.getAllocator(), d.day);
        try json.appendSlice(core.getAllocator(), "\":");
        try json.appendSlice(core.getAllocator(), std.fmt.bufPrint(&num_buf, "{d}", .{d.count}) catch unreachable);
    }
    try json.appendSlice(core.getAllocator(), "}}");
    return sendOkDataJson(ctx, json.items);
}
