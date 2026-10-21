const std = @import("std");
const zmodu = @import("zmodu");
const http = zmodu.http;
const message_mod = @import("../../message.zig");

pub fn sendOk(ctx: *http.Context, data: anytype) !void {
    try ctx.jsonStruct(200, .{ .errCode = 0, .errMsg = "", .data = data });
}

/// Send a pre-serialized `data` JSON payload (e.g. dynamic maps) inside the
/// standard `{errCode, errMsg, data}` envelope.
pub fn sendOkDataJson(ctx: *http.Context, data_json: []const u8) !void {
    ctx.status_code = 200;
    try ctx.setHeader("Content-Type", "application/json");
    try ctx.response_body.appendSlice(ctx.allocator, "{\"errCode\":0,\"errMsg\":\"\",\"data\":");
    try ctx.response_body.appendSlice(ctx.allocator, data_json);
    try ctx.response_body.appendSlice(ctx.allocator, "}");
    ctx.responded = true;
}

pub fn appendDayCountJson(allocator: std.mem.Allocator, json: *std.ArrayList(u8), days: []const message_mod.DayCount) !void {
    var num_buf: [32]u8 = undefined;
    try json.appendSlice(allocator, "{");
    for (days, 0..) |d, i| {
        if (i > 0) try json.appendSlice(allocator, ",");
        try json.appendSlice(allocator, "\"");
        try json.appendSlice(allocator, d.day);
        try json.appendSlice(allocator, "\":");
        try json.appendSlice(allocator, std.fmt.bufPrint(&num_buf, "{d}", .{d.count}) catch unreachable);
    }
    try json.appendSlice(allocator, "}");
}

pub fn appendEscapedString(allocator: std.mem.Allocator, json: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '"' => try json.appendSlice(allocator, "\\\""),
            '\\' => try json.appendSlice(allocator, "\\\\"),
            '\n' => try json.appendSlice(allocator, "\\n"),
            '\r' => try json.appendSlice(allocator, "\\r"),
            '\t' => try json.appendSlice(allocator, "\\t"),
            else => try json.append(allocator, ch),
        }
    }
}

pub fn sendFail(ctx: *http.Context, code: i32, msg: []const u8) !void {
    try ctx.jsonStruct(200, .{ .errCode = code, .errMsg = msg, .data = null });
}

/// Paths that skip token validation (OpenIM auth entrypoints + ops endpoints).
const public_paths = [_][]const u8{
    "/auth/get_user_token",
    "/auth/get_admin_token",
    "/auth/parse_token",
    "/account/login",
    "/account/register",
    "/account/code/send",
    "/account/code/verify",
    "/account/password/reset",
    "/health",
    "/openapi.json",
    "/user/user_register",
    "/msg/get_server_time",
    "/metrics",
};

pub fn isPublicPath(path: []const u8) bool {
    for (public_paths) |p| {
        if (std.mem.eql(u8, path, p)) return true;
    }
    return false;
}

pub fn getBearerToken(ctx: *http.Context) ?[]const u8 {
    if (ctx.header("token")) |v| return v;
    if (ctx.header("authorization")) |v| {
        if (std.mem.startsWith(u8, v, "Bearer ")) return v[7..];
        return v;
    }
    return null;
}
