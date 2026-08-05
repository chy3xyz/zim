const std = @import("std");
const core = @import("core");
const event_bus_mod = @import("../event_bus.zig");
const model = @import("model.zig");
const persistence = @import("persistence.zig");

pub const GroupService = struct {
    allocator: std.mem.Allocator,
    pers: persistence.GroupPersistence,

    pub fn init(allocator: std.mem.Allocator, db: *@import("../db_postgres.zig").PostgresClient) GroupService {
        return GroupService{
            .allocator = allocator,
            .pers = persistence.GroupPersistence.init(allocator, db),
        };
    }

    pub fn deinit(self: *GroupService) void {
        self.pers.deinit();
    }

    pub fn createGroup(self: *GroupService, input: model.GroupCreateInput) !model.Group {
        const group = try self.pers.create(input);

        const eb = event_bus_mod.getEventBus();
        const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"group_id\":\"{s}\",\"name\":\"{s}\",\"creator\":\"{s}\"}}", .{ group.group_id, group.group_name, group.creator_user_id });
        defer core.getAllocator().free(payload);
        eb.emit(.group_created, "group", payload);

        return group;
    }

    pub fn getGroup(self: *GroupService, group_id: []const u8) ?model.Group {
        return self.pers.get(group_id);
    }

    pub fn getGroupMembers(self: *GroupService, group_id: []const u8) ![]model.GroupMember {
        return self.pers.getMembers(core.getAllocator(), group_id);
    }

    pub fn getGroupMembersSince(self: *GroupService, group_id: []const u8, since: i64) ![]model.GroupMember {
        return self.pers.getMembersSince(core.getAllocator(), group_id, since);
    }

    pub fn addMember(self: *GroupService, group_id: []const u8, user_id: []const u8, inviter: []const u8) !void {
        try self.pers.addMember(group_id, user_id, inviter);
        const eb = event_bus_mod.getEventBus();
        const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"group_id\":\"{s}\",\"user_id\":\"{s}\"}}", .{ group_id, user_id });
        defer core.getAllocator().free(payload);
        eb.emit(.group_member_joined, "group", payload);
    }

    /// Batch-invite members in one transaction: all rows commit or none do.
    pub fn addMembers(self: *GroupService, group_id: []const u8, user_ids: []const []const u8, inviter: []const u8) !void {
        if (user_ids.len == 0) return;
        var tx = try self.pers.db.begin();
        errdefer tx.rollback();
        try self.pers.addMembersTx(&tx, group_id, user_ids, inviter);
        try tx.commit();
        // Events fire after the commit; each payload is freed immediately.
        for (user_ids) |uid| {
            const eb = event_bus_mod.getEventBus();
            const payload = std.fmt.allocPrint(core.getAllocator(), "{{\"group_id\":\"{s}\",\"user_id\":\"{s}\"}}", .{ group_id, uid }) catch continue;
            eb.emit(.group_member_joined, "group", payload);
            core.getAllocator().free(payload);
        }
    }

    pub fn removeMember(self: *GroupService, group_id: []const u8, user_id: []const u8) !bool {
        const result = try self.pers.removeMember(group_id, user_id);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"group_id\":\"{s}\",\"user_id\":\"{s}\"}}", .{ group_id, user_id });
            defer core.getAllocator().free(payload);
            eb.emit(.group_member_left, "group", payload);
        }
        return result;
    }

    pub fn setMemberRole(self: *GroupService, group_id: []const u8, user_id: []const u8, role: model.MemberRole) !bool {
        const result = try self.pers.setMemberRole(group_id, user_id, role);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"group_id\":\"{s}\",\"user_id\":\"{s}\",\"role\":{}}}", .{ group_id, user_id, @intFromEnum(role) });
            defer core.getAllocator().free(payload);
            eb.emit(.group_member_role_changed, "group", payload);
        }
        return result;
    }

    /// Transfer ownership atomically with validation: only the current owner
    /// may transfer, the new owner must be an existing member.
    pub fn transferOwner(self: *GroupService, group_id: []const u8, old_owner: []const u8, new_owner: []const u8) !void {
        if (std.mem.eql(u8, old_owner, new_owner)) return error.SameUser;
        const old = self.pers.getMember(group_id, old_owner) orelse return error.NotGroupMember;
        if (old.role_level != @intFromEnum(model.MemberRole.owner)) return error.NotOwner;
        _ = self.pers.getMember(group_id, new_owner) orelse return error.NewOwnerNotMember;

        var tx = try self.pers.db.begin();
        errdefer tx.rollback();
        try self.pers.transferOwnerTx(&tx, group_id, old_owner, new_owner);
        try tx.commit();

        // Role-change events fire after the commit.
        const eb = event_bus_mod.getEventBus();
        inline for (.{ .{ old_owner, @intFromEnum(model.MemberRole.member) }, .{ new_owner, @intFromEnum(model.MemberRole.owner) } }) |pair| {
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"group_id\":\"{s}\",\"user_id\":\"{s}\",\"role\":{d}}}", .{ group_id, pair[0], pair[1] });
            eb.emit(.group_member_role_changed, "group", payload);
            core.getAllocator().free(payload);
        }
    }

    pub fn dismissGroup(self: *GroupService, group_id: []const u8) bool {
        const result = self.pers.dismiss(group_id);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            if (std.fmt.allocPrint(core.getAllocator(), "{{\"group_id\":\"{s}\"}}", .{group_id})) |payload| {
                defer core.getAllocator().free(payload);
                eb.emit(.group_deleted, "group", payload);
            } else |_| {}
        }
        return result;
    }

    pub fn getJoinedGroups(self: *GroupService, user_id: []const u8) ![]model.Group {
        return self.pers.getJoinedGroups(core.getAllocator(), user_id);
    }

    pub fn getJoinedGroupsSince(self: *GroupService, user_id: []const u8, since: i64) ![]model.Group {
        return self.pers.getJoinedGroupsSince(core.getAllocator(), user_id, since);
    }

    pub fn getMember(self: *GroupService, group_id: []const u8, user_id: []const u8) ?model.GroupMember {
        return self.pers.getMember(group_id, user_id);
    }

    pub fn isMember(self: *GroupService, group_id: []const u8, user_id: []const u8) bool {
        return self.pers.isMember(group_id, user_id);
    }

    pub fn groupCount(self: *GroupService) usize {
        return self.pers.count();
    }

    pub fn groupCountSince(self: *GroupService, start_time: i64, end_time: i64) usize {
        return self.pers.countSince(start_time, end_time);
    }

    pub fn groupCountBefore(self: *GroupService, start_time: i64) usize {
        return self.pers.countBefore(start_time);
    }

    pub fn groupCountByDay(self: *GroupService, allocator: std.mem.Allocator, start_time: i64, end_time: i64) ![]model.DayCount {
        return self.pers.countByDay(allocator, start_time, end_time);
    }

    pub fn activeGroupCount(self: *GroupService) usize {
        return self.pers.activeCount();
    }

    pub fn updateGroup(self: *GroupService, group_id: []const u8, input: model.GroupUpdateInput) !?model.Group {
        return try self.pers.update(group_id, input);
    }

    pub fn setGroupInfo(self: *GroupService, group_id: []const u8, group_name: ?[]const u8, notification: ?[]const u8, introduction: ?[]const u8, face_url: ?[]const u8) !?model.Group {
        return try self.pers.update(group_id, .{
            .group_name = group_name,
            .notification = notification,
            .introduction = introduction,
            .face_url = face_url,
        });
    }

    pub fn setGroupInfoEx(self: *GroupService, group_id: []const u8, ex: []const u8) !?model.Group {
        return try self.pers.update(group_id, .{ .ex = ex });
    }

    pub fn muteGroup(self: *GroupService, group_id: []const u8) !bool {
        return try self.pers.muteGroup(group_id, true);
    }

    pub fn cancelMuteGroup(self: *GroupService, group_id: []const u8) !bool {
        return try self.pers.muteGroup(group_id, false);
    }

    pub fn muteMember(self: *GroupService, group_id: []const u8, user_id: []const u8, mute_end_time: i64) !bool {
        return try self.pers.muteMember(group_id, user_id, mute_end_time);
    }

    pub fn cancelMuteMember(self: *GroupService, group_id: []const u8, user_id: []const u8) !bool {
        return try self.pers.muteMember(group_id, user_id, 0);
    }

    pub fn setGroupMemberInfo(self: *GroupService, group_id: []const u8, user_id: []const u8, nickname: ?[]const u8, face_url: ?[]const u8, role_level: ?i16, ex: ?[]const u8) !bool {
        return try self.pers.setMemberInfo(group_id, user_id, nickname, face_url, role_level, ex);
    }

    pub fn deleteGroupRequest(self: *GroupService, user_id: []const u8, group_id: []const u8) !bool {
        return try self.pers.deleteGroupRequest(user_id, group_id);
    }

    pub fn joinGroup(self: *GroupService, user_id: []const u8, group_id: []const u8, req_msg: []const u8) !void {
        const group = self.pers.get(group_id) orelse return error.GroupNotFound;
        switch (group.need_verification) {
            0 => {
                // No verification required: join directly (no pending request).
                try self.addMember(group_id, user_id, "");
            },
            1 => {
                // Requires admin approval: create a pending request.
                try self.pers.addGroupRequest(user_id, group_id, req_msg);
            },
            2 => {
                // All join requests rejected.
                return error.GroupJoinRejected;
            },
            else => try self.pers.addGroupRequest(user_id, group_id, req_msg),
        }
    }

    pub fn respondGroupRequest(self: *GroupService, user_id: []const u8, group_id: []const u8, handled_msg: []const u8, accept: bool, handler_user_id: []const u8) !bool {
        return try self.pers.respondGroupRequest(user_id, group_id, handled_msg, accept, handler_user_id);
    }

    pub fn getRecvGroupApplications(self: *GroupService, user_id: []const u8) ![]model.GroupRequest {
        return try self.pers.getGroupRequests(core.getAllocator(), null, user_id, 0);
    }

    pub fn getUserReqGroupApplications(self: *GroupService, user_id: []const u8) ![]model.GroupRequest {
        return try self.pers.getGroupRequests(core.getAllocator(), null, user_id, null);
    }

    pub fn getGroupUsersReqApplicationList(self: *GroupService, group_id: []const u8) ![]model.GroupRequest {
        return try self.pers.getGroupRequests(core.getAllocator(), group_id, null, 0);
    }

    pub fn getSpecifiedUserGroupRequestInfo(self: *GroupService, user_id: []const u8, group_id: []const u8) !?model.GroupRequest {
        const list = try self.pers.getGroupRequests(core.getAllocator(), group_id, user_id, null);
        if (list.len == 0) return null;
        return list[0];
    }
};
