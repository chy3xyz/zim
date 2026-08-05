// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: group.zig

const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const auth_mod = @import("../../auth.zig");
const group_mod = @import("../../group.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;
const getBearerToken = helpers.getBearerToken;

pub fn handleCancelMuteGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CancelReq = struct {
        groupID: []const u8,
    };
    const req = ctx.bindJson(CancelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.cancelMuteGroup(req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.cancel_mute_group, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleCancelMuteGroupMember(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CancelReq = struct {
        groupID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(CancelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.cancelMuteMember(req.groupID, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.cancel_mute_group_member, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleCreateGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CreateReq = struct {
        groupID: ?[]const u8 = null,
        groupName: []const u8,
        notification: ?[]const u8 = null,
        introduction: ?[]const u8 = null,
        faceURL: ?[]const u8 = null,
        ex: ?[]const u8 = null,
        groupType: i16 = 1,
        needVerification: i16 = 0,
        creatorUserID: []const u8,
        memberUserIDs: ?[][]const u8 = null,
    };
    const req = ctx.bindJson(CreateReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const group_type = switch (req.groupType) {
        0 => group_mod.GroupType.working,
        2 => group_mod.GroupType.super,
        else => group_mod.GroupType.ordinary,
    };
    const group = group_mod.createGroup(.{
        .group_id = req.groupID,
        .group_name = req.groupName,
        .notification = req.notification orelse "",
        .introduction = req.introduction orelse "",
        .face_url = req.faceURL orelse "",
        .ex = req.ex orelse "",
        .group_type = group_type,
        .need_verification = req.needVerification,
        .creator_user_id = req.creatorUserID,
        .member_user_ids = req.memberUserIDs orelse &.{},
    }) catch |err| {
        return sendFail(ctx, core.ErrorCode.create_group, @errorName(err));
    };
    return sendOk(ctx, dto.groupToJson(group));
}

pub fn handleDeleteGroupRequestsFromUser(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        userID: []const u8,
        groupID: []const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.deleteGroupRequest(req.userID, req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_group_requests_from_user, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleDeleteGroupRequestsToGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        userID: []const u8,
        groupID: []const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.deleteGroupRequest(req.userID, req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_group_requests_to_group, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleDismissGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DismissReq = struct {
        groupID: []const u8,
    };
    const req = ctx.bindJson(DismissReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.dismissGroup(req.groupID);
    return sendOk(ctx, null);
}

pub fn handleGetFullGroupMemberUserIDs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        groupID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const members = group_mod.getGroupMembers(req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_full_group_member_user_ids, @errorName(err));
    };
    var ids = std.ArrayList([]const u8).empty;
    defer ids.deinit(core.getAllocator());
    for (members) |m| {
        try ids.append(core.getAllocator(), m.user_id);
    }
    return sendOk(ctx, .{ .userIDs = ids.items });
}

pub fn handleGetFullJoinGroupIDs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const groups = group_mod.getJoinedGroups(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_full_join_group_ids, @errorName(err));
    };
    var ids = std.ArrayList([]const u8).empty;
    defer ids.deinit(core.getAllocator());
    for (groups) |g| {
        try ids.append(core.getAllocator(), g.group_id);
    }
    return sendOk(ctx, .{ .groupIDs = ids.items });
}

pub fn handleGetGroupAbstractInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        groupIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const AbstractInfo = struct {
        groupID: []const u8,
        groupMemberNumber: u32,
        groupMemberListHash: u64,
    };
    var infos = std.ArrayList(AbstractInfo).empty;
    defer infos.deinit(core.getAllocator());
    for (req.groupIDs) |gid| {
        const group = group_mod.getGroup(gid);
        if (group == null) continue;
        var hash: u64 = 14695981039346656037; // FNV-1a 64 offset basis
        if (group_mod.getGroupMembers(gid)) |members| {
            for (members) |m| {
                for (m.user_id) |ch| {
                    hash ^= ch;
                    hash *%= 1099511628211;
                }
                hash ^= 0xff;
                hash *%= 1099511628211;
            }
        } else |_| {}
        try infos.append(core.getAllocator(), .{
            .groupID = group.?.group_id,
            .groupMemberNumber = group.?.member_count,
            .groupMemberListHash = hash,
        });
    }
    return sendOk(ctx, .{ .groupAbstractInfos = infos.items });
}

pub fn handleGetGroupMemberList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        groupID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    // look_member_info gates member-list visibility:
    // 0 = everyone, 1 = group members only, 2 = admins/owner only.
    const group = group_mod.getGroup(req.groupID) orelse return sendFail(ctx, 404, "Group Not Found");
    if (group.look_member_info > 0) {
        const token = getBearerToken(ctx) orelse return sendFail(ctx, 401, "Unauthorized");
        const viewer = auth_mod.parseToken(token) catch return sendFail(ctx, 401, "Unauthorized");
        const member = group_mod.getMember(req.groupID, viewer.user_id);
        switch (group.look_member_info) {
            1 => {
                if (member == null) return sendFail(ctx, 403, "Group members only");
            },
            2 => {
                // member=100, admin=60, owner=20 — admin or owner required
                if (member == null or member.?.role_level > 60) return sendFail(ctx, 403, "Group admins only");
            },
            else => {},
        }
    }
    const members = group_mod.getGroupMembers(req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_group_member_list, @errorName(err));
    };
    {
        var members_json = std.ArrayList(@TypeOf(dto.groupMemberToJson(members[0]))).empty;
        defer members_json.deinit(core.getAllocator());
        for (members) |m| {
            try members_json.append(core.getAllocator(), dto.groupMemberToJson(m));
        }
        return sendOk(ctx, .{ .total = members_json.items.len, .members = members_json.items });
    }
}

pub fn handleGetGroupMemberUserIDs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        groupID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const members = group_mod.getGroupMembers(req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_group_member_user_ids, @errorName(err));
    };
    var user_ids = std.ArrayList([]const u8).empty;
    defer user_ids.deinit(core.getAllocator());
    for (members) |m| {
        try user_ids.append(core.getAllocator(), m.user_id);
    }
    return sendOk(ctx, .{ .userIDs = user_ids.items });
}

pub fn handleGetGroupMembersInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        groupID: []const u8,
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var members = std.ArrayList(group_mod.GroupMember).empty;
    defer members.deinit(core.getAllocator());
    for (req.userIDs) |uid| {
        if (group_mod.getMember(req.groupID, uid)) |m| {
            try members.append(core.getAllocator(), m);
        }
    }
    return sendOk(ctx, .{ .members = members.items });
}

pub fn handleGetGroupUsersReqApplicationList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        groupID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const requests = group_mod.getGroupUsersReqApplicationList(req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_group_users_req_application_list, @errorName(err));
    };
    {
        var reqs_json = std.ArrayList(@TypeOf(dto.groupRequestToJson(requests[0]))).empty;
        defer reqs_json.deinit(core.getAllocator());
        for (requests) |r| {
            try reqs_json.append(core.getAllocator(), dto.groupRequestToJson(r));
        }
        return sendOk(ctx, .{ .total = reqs_json.items.len, .groupRequests = reqs_json.items });
    }
}

pub fn handleGetGroups(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        groupIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var groups_json = std.ArrayList(@TypeOf(dto.groupToJson(@as(group_mod.Group, undefined)))).empty;
    defer groups_json.deinit(core.getAllocator());
    for (req.groupIDs) |gid| {
        if (group_mod.getGroup(gid)) |g| {
            try groups_json.append(core.getAllocator(), dto.groupToJson(g));
        }
    }
    return sendOk(ctx, .{ .total = groups_json.items.len, .groups = groups_json.items });
}

pub fn handleGetGroupsInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        groupIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var groups_json = std.ArrayList(@TypeOf(dto.groupToJson(@as(group_mod.Group, undefined)))).empty;
    defer groups_json.deinit(core.getAllocator());
    for (req.groupIDs) |gid| {
        if (group_mod.getGroup(gid)) |g| {
            try groups_json.append(core.getAllocator(), dto.groupToJson(g));
        }
    }
    return sendOk(ctx, .{ .groupInfos = groups_json.items });
}

pub fn handleGetIncrementalGroupMembers(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const IncReq = struct {
        groupID: []const u8,
        sinceTimestamp: i64,
    };
    const req = ctx.bindJson(IncReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const members = group_mod.getGroupMembersSince(req.groupID, req.sinceTimestamp) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_incremental_group_members, @errorName(err));
    };
    {
        var members_json = std.ArrayList(@TypeOf(dto.groupMemberToJson(members[0]))).empty;
        defer members_json.deinit(core.getAllocator());
        for (members) |m| {
            try members_json.append(core.getAllocator(), dto.groupMemberToJson(m));
        }
        return sendOk(ctx, .{ .members = members_json.items });
    }
}

pub fn handleGetIncrementalGroupMembersBatch(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const IncReq = struct {
        groupIDs: [][]const u8,
        sinceTimestamp: i64,
    };
    const req = ctx.bindJson(IncReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var all_members = std.ArrayList(group_mod.GroupMember).empty;
    defer all_members.deinit(core.getAllocator());
    for (req.groupIDs) |gid| {
        const members = group_mod.getGroupMembersSince(gid, req.sinceTimestamp) catch continue;
        for (members) |m| {
            try all_members.append(core.getAllocator(), m);
        }
    }
    return sendOk(ctx, .{ .members = all_members.items });
}

pub fn handleGetIncrementalJoinGroups(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const IncReq = struct {
        userID: []const u8,
        sinceTimestamp: i64,
    };
    const req = ctx.bindJson(IncReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const groups = group_mod.getJoinedGroupsSince(req.userID, req.sinceTimestamp) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_incremental_join_groups, @errorName(err));
    };
    {
        var groups_json = std.ArrayList(@TypeOf(dto.groupToJson(groups[0]))).empty;
        defer groups_json.deinit(core.getAllocator());
        for (groups) |g| {
            try groups_json.append(core.getAllocator(), dto.groupToJson(g));
        }
        return sendOk(ctx, .{ .groups = groups_json.items });
    }
}

pub fn handleGetJoinedGroupList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const groups = group_mod.getJoinedGroups(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_joined_group_list, @errorName(err));
    };
    {
        var groups_json = std.ArrayList(@TypeOf(dto.groupToJson(groups[0]))).empty;
        defer groups_json.deinit(core.getAllocator());
        for (groups) |g| {
            try groups_json.append(core.getAllocator(), dto.groupToJson(g));
        }
        return sendOk(ctx, .{ .total = groups_json.items.len, .groups = groups_json.items });
    }
}

pub fn handleGetRecvGroupApplications(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const requests = group_mod.getRecvGroupApplications(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_recv_group_applications, @errorName(err));
    };
    {
        var reqs_json = std.ArrayList(@TypeOf(dto.groupRequestToJson(requests[0]))).empty;
        defer reqs_json.deinit(core.getAllocator());
        for (requests) |r| {
            try reqs_json.append(core.getAllocator(), dto.groupRequestToJson(r));
        }
        return sendOk(ctx, .{ .total = reqs_json.items.len, .groupRequests = reqs_json.items });
    }
}

pub fn handleGetSpecifiedUserGroupRequestInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        userID: []const u8,
        groupID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const req_info = group_mod.getSpecifiedUserGroupRequestInfo(req.userID, req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_specified_user_group_request_info, @errorName(err));
    };
    return sendOk(ctx, dto.groupRequestToJson(req_info.?));
}

pub fn handleGetUserReqGroupApplications(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const requests = group_mod.getUserReqGroupApplications(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_user_req_group_applications, @errorName(err));
    };
    {
        var reqs_json = std.ArrayList(@TypeOf(dto.groupRequestToJson(requests[0]))).empty;
        defer reqs_json.deinit(core.getAllocator());
        for (requests) |r| {
            try reqs_json.append(core.getAllocator(), dto.groupRequestToJson(r));
        }
        return sendOk(ctx, .{ .total = reqs_json.items.len, .groupRequests = reqs_json.items });
    }
}

pub fn handleGroupApplicationResponse(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RespReq = struct {
        userID: []const u8,
        groupID: []const u8,
        handledMsg: []const u8 = "",
        handleResult: i16,
    };
    const req = ctx.bindJson(RespReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const token = getBearerToken(ctx) orelse return sendFail(ctx, 401, "Unauthorized");
    const token_info = auth_mod.parseToken(token) catch return sendFail(ctx, 401, "Unauthorized");
    _ = group_mod.respondGroupRequest(req.userID, req.groupID, req.handledMsg, req.handleResult == 1, token_info.user_id) catch |err| {
        return sendFail(ctx, core.ErrorCode.group_application_response, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleInviteToGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const InviteReq = struct {
        groupID: []const u8,
        invitedUserIDs: [][]const u8,
        reason: []const u8 = "",
    };
    const req = ctx.bindJson(InviteReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    // Batch-invite in one transaction: partial failures roll back the whole invite.
    group_mod.addMembers(req.groupID, req.invitedUserIDs, "") catch |err| {
        return sendFail(ctx, core.ErrorCode.invite_to_group, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleJoinGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const JoinReq = struct {
        userID: []const u8,
        groupID: []const u8,
        reqMsg: []const u8 = "",
    };
    const req = ctx.bindJson(JoinReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    group_mod.joinGroup(req.userID, req.groupID, req.reqMsg) catch |err| {
        return sendFail(ctx, core.ErrorCode.join_group, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleKickFromGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const KickReq = struct {
        groupID: []const u8,
        kickedUserIDs: [][]const u8,
        reason: []const u8 = "",
    };
    const req = ctx.bindJson(KickReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    for (req.kickedUserIDs) |uid| {
        _ = group_mod.removeMember(req.groupID, uid) catch |err| {
            return sendFail(ctx, core.ErrorCode.kick_from_group, @errorName(err));
        };
    }
    return sendOk(ctx, null);
}

pub fn handleMuteGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const MuteReq = struct {
        groupID: []const u8,
    };
    const req = ctx.bindJson(MuteReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.muteGroup(req.groupID) catch |err| {
        return sendFail(ctx, core.ErrorCode.mute_group, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleMuteGroupMember(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const MuteReq = struct {
        groupID: []const u8,
        userID: []const u8,
        mutedSeconds: i64 = 3600,
    };
    const req = ctx.bindJson(MuteReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const mute_end = core.unixNowSeconds() + req.mutedSeconds;
    _ = group_mod.muteMember(req.groupID, req.userID, mute_end) catch |err| {
        return sendFail(ctx, core.ErrorCode.mute_group_member, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleQuitGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const QuitReq = struct {
        groupID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(QuitReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.removeMember(req.groupID, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.quit_group, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleSetGroupInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SetReq = struct {
        groupID: []const u8,
        groupName: ?[]const u8 = null,
        notification: ?[]const u8 = null,
        introduction: ?[]const u8 = null,
        faceURL: ?[]const u8 = null,
    };
    const req = ctx.bindJson(SetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.setGroupInfo(req.groupID, req.groupName, req.notification, req.introduction, req.faceURL) catch |err| {
        return sendFail(ctx, core.ErrorCode.set_group_info, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleSetGroupInfoEx(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SetReq = struct {
        groupID: []const u8,
        ex: []const u8,
    };
    const req = ctx.bindJson(SetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.setGroupInfoEx(req.groupID, req.ex) catch |err| {
        return sendFail(ctx, core.ErrorCode.set_group_info_ex, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleSetGroupMemberInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SetReq = struct {
        groupID: []const u8,
        userID: []const u8,
        nickname: ?[]const u8 = null,
        faceURL: ?[]const u8 = null,
        roleLevel: ?i16 = null,
        ex: ?[]const u8 = null,
    };
    const req = ctx.bindJson(SetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = group_mod.setGroupMemberInfo(req.groupID, req.userID, req.nickname, req.faceURL, req.roleLevel, req.ex) catch |err| {
        return sendFail(ctx, core.ErrorCode.set_group_member_info, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleTransferGroup(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const TransferReq = struct {
        groupID: []const u8,
        oldOwnerUserID: []const u8,
        newOwnerUserID: []const u8,
    };
    const req = ctx.bindJson(TransferReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    // Atomic transfer (validated + transactional) — a mid-transfer failure
    // never leaves the group without an owner.
    group_mod.transferOwner(req.groupID, req.oldOwnerUserID, req.newOwnerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.transfer_group_owner, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleGetGroupApplicationUnheandledCount(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CountReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(CountReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const requests = group_mod.getRecvGroupApplications(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_group_application_unhandled_count, @errorName(err));
    };
    var count: usize = 0;
    for (requests) |r| {
        if (r.handle_result == 0) count += 1;
    }
    return sendOk(ctx, .{ .count = count });
}
