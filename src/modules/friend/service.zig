const std = @import("std");
const core = @import("core");
const event_bus_mod = @import("../event_bus.zig");
const db_mod = @import("../db_postgres.zig");
const persistence = @import("persistence.zig");
const model = @import("model.zig");

pub const FriendService = struct {
    pers: persistence.FriendPersistence,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) FriendService {
        return FriendService{
            .pers = persistence.FriendPersistence.init(allocator, db),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FriendService) void {
        self.pers.deinit();
    }

    pub fn sendFriendRequest(self: *FriendService, from_user_id: []const u8, to_user_id: []const u8, req_msg: []const u8) !model.FriendRequest {
        const req = try self.pers.addFriendRequest(from_user_id, to_user_id, req_msg);
        const eb = event_bus_mod.getEventBus();
        const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"from\":\"{s}\",\"to\":\"{s}\"}}", .{ from_user_id, to_user_id });
        defer core.getAllocator().free(payload);
        eb.emit(.friend_requested, "friend", payload);
        return req;
    }

    pub fn respondFriendRequest(self: *FriendService, from_user_id: []const u8, to_user_id: []const u8, accept: bool, handle_msg: []const u8) !void {
        try self.pers.respondFriendRequest(from_user_id, to_user_id, accept, handle_msg);
        const eb = event_bus_mod.getEventBus();
        const event_type: event_bus_mod.EventType = if (accept) .friend_accepted else .friend_declined;
        const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"from\":\"{s}\",\"to\":\"{s}\",\"accepted\":{s}}}", .{ from_user_id, to_user_id, if (accept) "true" else "false" });
        defer core.getAllocator().free(payload);
        eb.emit(event_type, "friend", payload);
    }

    pub fn getFriends(self: *FriendService, user_id: []const u8) ![]model.FriendInfo {
        return self.pers.getFriends(core.getAllocator(), user_id);
    }

    pub fn getFriendsSince(self: *FriendService, user_id: []const u8, since: i64) ![]model.FriendInfo {
        return self.pers.getFriendsSince(core.getAllocator(), user_id, since);
    }

    pub fn getFriendRequests(self: *FriendService, user_id: []const u8, as_sender: bool) ![]model.FriendRequestInfo {
        return self.pers.getFriendRequests(core.getAllocator(), user_id, as_sender);
    }

    pub fn deleteFriend(self: *FriendService, owner_user_id: []const u8, friend_user_id: []const u8) !bool {
        const result = try self.pers.deleteFriend(owner_user_id, friend_user_id);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"owner\":\"{s}\",\"friend\":\"{s}\"}}", .{ owner_user_id, friend_user_id });
            defer core.getAllocator().free(payload);
            eb.emit(.friend_deleted, "friend", payload);
        }
        return result;
    }

    pub fn addBlack(self: *FriendService, owner_user_id: []const u8, block_user_id: []const u8) !void {
        try self.pers.addBlack(owner_user_id, block_user_id);
        const eb = event_bus_mod.getEventBus();
        const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"owner\":\"{s}\",\"block\":\"{s}\"}}", .{ owner_user_id, block_user_id });
        // emit() copies the payload for async consumers; release the caller-owned
        // copy here (arena no-op under request-scoped allocation).
        defer core.getAllocator().free(payload);
        eb.emit(.black_added, "friend", payload);
    }

    pub fn removeBlack(self: *FriendService, owner_user_id: []const u8, block_user_id: []const u8) !bool {
        const result = try self.pers.removeBlack(owner_user_id, block_user_id);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"owner\":\"{s}\",\"block\":\"{s}\"}}", .{ owner_user_id, block_user_id });
            defer core.getAllocator().free(payload);
            eb.emit(.black_removed, "friend", payload);
        }
        return result;
    }

    pub fn getBlacks(self: *FriendService, user_id: []const u8) ![]model.BlackInfo {
        return self.pers.getBlacks(core.getAllocator(), user_id);
    }

    pub fn getBlacksSince(self: *FriendService, user_id: []const u8, since: i64) ![]model.BlackInfo {
        return self.pers.getBlacksSince(core.getAllocator(), user_id, since);
    }

    pub fn setFriendRemark(self: *FriendService, owner_user_id: []const u8, friend_user_id: []const u8, remark: []const u8) !bool {
        return try self.pers.setRemark(owner_user_id, friend_user_id, remark);
    }

    pub fn updateFriend(self: *FriendService, owner_user_id: []const u8, friend_user_id: []const u8, remark: ?[]const u8, is_pinned: ?bool, ex: ?[]const u8) !bool {
        return try self.pers.updateFriend(owner_user_id, friend_user_id, remark, is_pinned, ex);
    }

    pub fn isFriend(self: *FriendService, user_id_1: []const u8, user_id_2: []const u8) bool {
        return self.pers.isFriend(user_id_1, user_id_2);
    }

    pub fn isBlack(self: *FriendService, owner_user_id: []const u8, block_user_id: []const u8) bool {
        return self.pers.isBlack(owner_user_id, block_user_id);
    }

    pub fn importFriends(self: *FriendService, owner_user_id: []const u8, friend_user_ids: []const []const u8) !usize {
        return try self.pers.importFriends(owner_user_id, friend_user_ids);
    }

    pub fn deleteFriendRequest(self: *FriendService, from_user_id: []const u8, to_user_id: []const u8) !bool {
        return try self.pers.deleteFriendRequest(from_user_id, to_user_id);
    }
};
