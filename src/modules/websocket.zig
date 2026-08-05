const std = @import("std");
const model = @import("websocket/model.zig");
const root = @import("websocket/root.zig");

pub const WSClient = model.WSClient;
pub const Frame = model.Frame;
pub const OpCode = model.OpCode;

pub const info = root.info;

pub fn setIo(io: std.Io) void {
    root.setIo(io);
}

pub fn init() !void {
    return root.init();
}

pub fn deinit() void {
    root.deinit();
}

pub fn startServer(io: std.Io, allocator: std.mem.Allocator, port: u16) !void {
    return root.startServer(io, allocator, port);
}

pub fn pushToUser(user_id: []const u8, message: []const u8) void {
    root.pushToUser(user_id, message);
}

pub fn pushToUsers(user_ids: []const []const u8, message: []const u8) void {
    root.pushToUsers(user_ids, message);
}

pub fn broadcast(message: []const u8) void {
    root.broadcast(message);
}

pub fn pushMsgProtobuf(user_id: []const u8, msg_data: @import("sdkws").MsgData) void {
    root.pushMsgProtobuf(user_id, msg_data);
}

pub fn pushMsgProtobufToUsers(user_ids: []const []const u8, msg_data: @import("sdkws").MsgData) void {
    root.pushMsgProtobufToUsers(user_ids, msg_data);
}

pub fn kickUser(user_id: []const u8, reason: []const u8) void {
    root.kickUser(user_id, reason);
}

pub fn isUserBackground(user_id: []const u8) bool {
    return root.isUserBackground(user_id);
}

pub fn pushOnlineStatusChange(user_id: []const u8, online: bool, platform_id: i32) void {
    root.pushOnlineStatusChange(user_id, online, platform_id);
}
