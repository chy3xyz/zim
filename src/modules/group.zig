const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const db_mod = @import("db_postgres.zig");
const model = @import("group/model.zig");
const persistence = @import("group/persistence.zig");
const service = @import("group/service.zig");

pub const info = zigmodu.api.Module{
    .name = "group",
    .description = "Group chat - CRUD, member management, roles, applications",
    .dependencies = &.{ "user", "db_postgres" },
    .runtime = .{ .max_concurrent = 100 },
};

// Re-export all model types
pub const GroupStatus = model.GroupStatus;
pub const GroupType = model.GroupType;
pub const MemberRole = model.MemberRole;
pub const Group = model.Group;
pub const DayCount = model.DayCount;
pub const GroupMember = model.GroupMember;
pub const GroupRequest = model.GroupRequest;
pub const GroupCreateInput = model.GroupCreateInput;
pub const GroupUpdateInput = model.GroupUpdateInput;

// Backward-compatible alias
pub const GroupStorage = persistence.GroupPersistence;

var g_service: ?service.GroupService = null;

pub fn init() !void {
    const db = db_mod.getClient();
    g_service = service.GroupService.init(core.serviceAllocator(), db);
    std.log.info("GroupModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    if (g_service) |*s| s.deinit();
    g_service = null;
    std.log.info("GroupModule deinitialized", .{});
}

pub fn getStorage() *GroupStorage {
    return &g_service.?.pers;
}

pub fn createGroup(input: GroupCreateInput) !Group {
    return try g_service.?.createGroup(input);
}

pub fn getGroup(group_id: []const u8) ?Group {
    return g_service.?.getGroup(group_id);
}

pub fn getGroupMembers(group_id: []const u8) ![]GroupMember {
    return g_service.?.getGroupMembers(group_id);
}

pub fn getGroupMembersSince(group_id: []const u8, since: i64) ![]GroupMember {
    return g_service.?.getGroupMembersSince(group_id, since);
}

pub fn getMember(group_id: []const u8, user_id: []const u8) ?GroupMember {
    return g_service.?.getMember(group_id, user_id);
}

pub fn addMember(group_id: []const u8, user_id: []const u8, inviter: []const u8) !void {
    try g_service.?.addMember(group_id, user_id, inviter);
}

/// Batch-invite members atomically (single transaction).
pub fn addMembers(group_id: []const u8, user_ids: []const []const u8, inviter: []const u8) !void {
    try g_service.?.addMembers(group_id, user_ids, inviter);
}

/// Transfer group ownership atomically (validated + transactional).
pub fn transferOwner(group_id: []const u8, old_owner: []const u8, new_owner: []const u8) !void {
    try g_service.?.transferOwner(group_id, old_owner, new_owner);
}

pub fn removeMember(group_id: []const u8, user_id: []const u8) !bool {
    return try g_service.?.removeMember(group_id, user_id);
}

pub fn setMemberRole(group_id: []const u8, user_id: []const u8, role: MemberRole) !bool {
    return try g_service.?.setMemberRole(group_id, user_id, role);
}

pub fn dismissGroup(group_id: []const u8) bool {
    return g_service.?.dismissGroup(group_id);
}

pub fn getJoinedGroups(user_id: []const u8) ![]Group {
    return g_service.?.getJoinedGroups(user_id);
}

pub fn getJoinedGroupsSince(user_id: []const u8, since: i64) ![]Group {
    return g_service.?.getJoinedGroupsSince(user_id, since);
}

pub fn isMember(group_id: []const u8, user_id: []const u8) bool {
    return g_service.?.isMember(group_id, user_id);
}

pub fn groupCount() usize {
    return g_service.?.groupCount();
}

pub fn groupCountSince(start_time: i64, end_time: i64) usize {
    return g_service.?.groupCountSince(start_time, end_time);
}

pub fn groupCountBefore(start_time: i64) usize {
    return g_service.?.groupCountBefore(start_time);
}

pub fn groupCountByDay(allocator: std.mem.Allocator, start_time: i64, end_time: i64) ![]DayCount {
    return g_service.?.groupCountByDay(allocator, start_time, end_time);
}

pub fn activeGroupCount() usize {
    return g_service.?.activeGroupCount();
}

pub fn updateGroup(group_id: []const u8, input: GroupUpdateInput) !?Group {
    return try g_service.?.updateGroup(group_id, input);
}

pub fn setGroupInfo(group_id: []const u8, group_name: ?[]const u8, notification: ?[]const u8, introduction: ?[]const u8, face_url: ?[]const u8) !?Group {
    return try g_service.?.setGroupInfo(group_id, group_name, notification, introduction, face_url);
}

pub fn setGroupInfoEx(group_id: []const u8, ex: []const u8) !?Group {
    return try g_service.?.setGroupInfoEx(group_id, ex);
}

pub fn muteGroup(group_id: []const u8) !bool {
    return try g_service.?.muteGroup(group_id);
}

pub fn cancelMuteGroup(group_id: []const u8) !bool {
    return try g_service.?.cancelMuteGroup(group_id);
}

pub fn muteMember(group_id: []const u8, user_id: []const u8, mute_end_time: i64) !bool {
    return try g_service.?.muteMember(group_id, user_id, mute_end_time);
}

pub fn cancelMuteMember(group_id: []const u8, user_id: []const u8) !bool {
    return try g_service.?.cancelMuteMember(group_id, user_id);
}

pub fn setGroupMemberInfo(group_id: []const u8, user_id: []const u8, nickname: ?[]const u8, face_url: ?[]const u8, role_level: ?i16, ex: ?[]const u8) !bool {
    return try g_service.?.setGroupMemberInfo(group_id, user_id, nickname, face_url, role_level, ex);
}

pub fn deleteGroupRequest(user_id: []const u8, group_id: []const u8) !bool {
    return try g_service.?.deleteGroupRequest(user_id, group_id);
}

pub fn joinGroup(user_id: []const u8, group_id: []const u8, req_msg: []const u8) !void {
    try g_service.?.joinGroup(user_id, group_id, req_msg);
}

pub fn respondGroupRequest(user_id: []const u8, group_id: []const u8, handled_msg: []const u8, accept: bool, handler_user_id: []const u8) !bool {
    return try g_service.?.respondGroupRequest(user_id, group_id, handled_msg, accept, handler_user_id);
}

pub fn getRecvGroupApplications(user_id: []const u8) ![]GroupRequest {
    return try g_service.?.getRecvGroupApplications(user_id);
}

pub fn getUserReqGroupApplications(user_id: []const u8) ![]GroupRequest {
    return try g_service.?.getUserReqGroupApplications(user_id);
}

pub fn getGroupUsersReqApplicationList(group_id: []const u8) ![]GroupRequest {
    return try g_service.?.getGroupUsersReqApplicationList(group_id);
}

pub fn getSpecifiedUserGroupRequestInfo(user_id: []const u8, group_id: []const u8) !?GroupRequest {
    return try g_service.?.getSpecifiedUserGroupRequestInfo(user_id, group_id);
}
