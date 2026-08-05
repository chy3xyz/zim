const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const db_mod = @import("db_postgres.zig");

const model = @import("friend/model.zig");
const persistence = @import("friend/persistence.zig");
const service = @import("friend/service.zig");

pub const info = zigmodu.api.Module{
    .name = "friend",
    .description = "Friend relationships - requests, accept/decline, blacklist",
    .dependencies = &.{ "user", "db_postgres" },
    .runtime = .{ .max_concurrent = 100 },
};

// Re-exports from model
pub const HandleResult = model.HandleResult;
pub const Friend = model.Friend;
pub const FriendInfo = model.FriendInfo;
pub const FriendRequestInfo = model.FriendRequestInfo;
pub const FriendRequest = model.FriendRequest;
pub const Black = model.Black;
pub const BlackInfo = model.BlackInfo;

// Backward-compatible alias
pub const FriendStorage = persistence.FriendPersistence;

var g_service: ?service.FriendService = null;

pub fn init() !void {
    const db = db_mod.getClient();
    g_service = service.FriendService.init(core.serviceAllocator(), db);
    std.log.info("FriendModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    if (g_service) |*s| s.deinit();
    g_service = null;
    std.log.info("FriendModule deinitialized", .{});
}

pub fn getStorage() *FriendStorage {
    return &g_service.?.pers;
}

pub fn sendFriendRequest(from_user_id: []const u8, to_user_id: []const u8, req_msg: []const u8) !FriendRequest {
    return try g_service.?.sendFriendRequest(from_user_id, to_user_id, req_msg);
}

pub fn respondFriendRequest(from_user_id: []const u8, to_user_id: []const u8, accept: bool, handle_msg: []const u8) !void {
    try g_service.?.respondFriendRequest(from_user_id, to_user_id, accept, handle_msg);
}

pub fn getFriends(user_id: []const u8) ![]FriendInfo {
    return g_service.?.getFriends(user_id);
}

pub fn getFriendsSince(user_id: []const u8, since: i64) ![]FriendInfo {
    return g_service.?.getFriendsSince(user_id, since);
}

pub fn getFriendRequests(user_id: []const u8, as_sender: bool) ![]FriendRequestInfo {
    return g_service.?.getFriendRequests(user_id, as_sender);
}

pub fn deleteFriend(owner_user_id: []const u8, friend_user_id: []const u8) !bool {
    return try g_service.?.deleteFriend(owner_user_id, friend_user_id);
}

pub fn addBlack(owner_user_id: []const u8, block_user_id: []const u8) !void {
    try g_service.?.addBlack(owner_user_id, block_user_id);
}

pub fn removeBlack(owner_user_id: []const u8, block_user_id: []const u8) !bool {
    return try g_service.?.removeBlack(owner_user_id, block_user_id);
}

pub fn getBlacks(user_id: []const u8) ![]BlackInfo {
    return g_service.?.getBlacks(user_id);
}

pub fn getBlacksSince(user_id: []const u8, since: i64) ![]BlackInfo {
    return g_service.?.getBlacksSince(user_id, since);
}

pub fn setFriendRemark(owner_user_id: []const u8, friend_user_id: []const u8, remark: []const u8) !bool {
    return try g_service.?.setFriendRemark(owner_user_id, friend_user_id, remark);
}

pub fn updateFriend(owner_user_id: []const u8, friend_user_id: []const u8, remark: ?[]const u8, is_pinned: ?bool, ex: ?[]const u8) !bool {
    return try g_service.?.updateFriend(owner_user_id, friend_user_id, remark, is_pinned, ex);
}

pub fn isFriend(user_id_1: []const u8, user_id_2: []const u8) bool {
    return g_service.?.isFriend(user_id_1, user_id_2);
}

pub fn isBlack(owner_user_id: []const u8, block_user_id: []const u8) bool {
    return g_service.?.isBlack(owner_user_id, block_user_id);
}

pub fn importFriends(owner_user_id: []const u8, friend_user_ids: []const []const u8) !usize {
    return try g_service.?.importFriends(owner_user_id, friend_user_ids);
}

pub fn deleteFriendRequest(from_user_id: []const u8, to_user_id: []const u8) !bool {
    return try g_service.?.deleteFriendRequest(from_user_id, to_user_id);
}
