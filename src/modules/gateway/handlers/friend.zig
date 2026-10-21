// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: friend.zig

const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const user_mod = @import("../../user.zig");
const friend_mod = @import("../../friend.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleAddBlack(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const BlackReq = struct {
        ownerUserID: []const u8,
        blockUserID: []const u8,
    };
    const req = ctx.bindJson(BlackReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    friend_mod.addBlack(req.ownerUserID, req.blockUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.add_black, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleAddFriend(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const AddFriendReq = struct {
        fromUserID: []const u8,
        toUserID: []const u8,
        reqMsg: []const u8 = "",
    };
    const req = ctx.bindJson(AddFriendReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = friend_mod.sendFriendRequest(req.fromUserID, req.toUserID, req.reqMsg) catch |err| {
        return sendFail(ctx, core.ErrorCode.add_friend, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleDeleteFriend(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        ownerUserID: []const u8,
        friendUserID: []const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = friend_mod.deleteFriend(req.ownerUserID, req.friendUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_friend, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleDeleteFriendRequestsFromUser(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        fromUserID: []const u8,
        toUserID: []const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = friend_mod.deleteFriendRequest(req.fromUserID, req.toUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_friend_requests_from_user, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleDeleteFriendRequestsToUser(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const DelReq = struct {
        fromUserID: []const u8,
        toUserID: []const u8,
    };
    const req = ctx.bindJson(DelReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = friend_mod.deleteFriendRequest(req.fromUserID, req.toUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.delete_friend_requests_to_user, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleFriendResponse(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RespReq = struct {
        fromUserID: []const u8,
        toUserID: []const u8,
        handleResult: i16,
        handleMsg: []const u8 = "",
    };
    const req = ctx.bindJson(RespReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    friend_mod.respondFriendRequest(req.fromUserID, req.toUserID, req.handleResult == 1, req.handleMsg) catch |err| {
        return sendFail(ctx, core.ErrorCode.friend_response, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleGetBlackList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const blacks = friend_mod.getBlacks(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_black_list, @errorName(err));
    };
    {
        var blacks_json = std.ArrayList(@TypeOf(dto.blackInfoToJson(blacks[0]))).empty;
        defer blacks_json.deinit(core.getAllocator());
        for (blacks) |b| {
            try blacks_json.append(core.getAllocator(), dto.blackInfoToJson(b));
        }
        return sendOk(ctx, .{ .blacks = blacks_json.items, .total = blacks_json.items.len });
    }
}

pub fn handleGetDesignatedFriendApply(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        userID: []const u8,
        friendUserID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const all_requests = friend_mod.getFriendRequests(req.userID, false) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_designated_friend_apply, @errorName(err));
    };
    for (all_requests) |r| {
        if (std.mem.eql(u8, r.from_user_id, req.friendUserID) or std.mem.eql(u8, r.to_user_id, req.friendUserID)) {
            return sendOk(ctx, dto.friendRequestToJson(r));
        }
    }
    return sendFail(ctx, 404, "Not Found");
}

pub fn handleGetDesignatedFriends(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        ownerUserID: []const u8,
        friendUserIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const all_friends = friend_mod.getFriends(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_designated_friends, @errorName(err));
    };
    var filtered = std.ArrayList(friend_mod.FriendInfo).empty;
    defer filtered.deinit(core.getAllocator());
    for (all_friends) |f| {
        for (req.friendUserIDs) |uid| {
            if (std.mem.eql(u8, f.friend_user_id, uid)) {
                try filtered.append(core.getAllocator(), f);
                break;
            }
        }
    }
    return sendOk(ctx, .{ .friendsInfo = filtered.items });
}

pub fn handleGetFriendApplyList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const requests = friend_mod.getFriendRequests(req.userID, false) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_friend_apply_list, @errorName(err));
    };
    var reqs_json = std.ArrayList(@TypeOf(dto.friendRequestToJson(requests[0]))).empty;
    defer reqs_json.deinit(core.getAllocator());
    for (requests) |r| {
        try reqs_json.append(core.getAllocator(), dto.friendRequestToJson(r));
    }
    return sendOk(ctx, .{ .FriendRequests = reqs_json.items, .total = reqs_json.items.len });
}

pub fn handleGetFriendID(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        ownerUserID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const friends = friend_mod.getFriends(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_friend_id, @errorName(err));
    };
    var ids = std.ArrayList([]const u8).empty;
    defer ids.deinit(core.getAllocator());
    for (friends) |f| {
        try ids.append(core.getAllocator(), f.friend_user_id);
    }
    return sendOk(ctx, .{ .friendUserIDs = ids.items });
}

pub fn handleGetFriendList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const friends = friend_mod.getFriends(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_friend_list, @errorName(err));
    };
    {
        var friends_json = std.ArrayList(@TypeOf(dto.friendInfoToJson(friends[0]))).empty;
        defer friends_json.deinit(core.getAllocator());
        for (friends) |f| {
            try friends_json.append(core.getAllocator(), dto.friendInfoToJson(f));
        }
        return sendOk(ctx, .{ .friendsInfo = friends_json.items, .total = friends_json.items.len });
    }
}

pub fn handleGetFullFriendUserIDs(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const friends = friend_mod.getFriends(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_full_friend_user_ids, @errorName(err));
    };
    var ids = std.ArrayList([]const u8).empty;
    defer ids.deinit(core.getAllocator());
    for (friends) |f| {
        try ids.append(core.getAllocator(), f.friend_user_id);
    }
    return sendOk(ctx, .{ .friendUserIDs = ids.items });
}

pub fn handleGetIncrementalBlacks(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const IncReq = struct {
        userID: []const u8,
        sinceTimestamp: i64,
    };
    const req = ctx.bindJson(IncReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const blacks = friend_mod.getBlacksSince(req.userID, req.sinceTimestamp) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_incremental_blacks, @errorName(err));
    };
    {
        var blacks_json = std.ArrayList(@TypeOf(dto.blackInfoToJson(blacks[0]))).empty;
        defer blacks_json.deinit(core.getAllocator());
        for (blacks) |b| {
            try blacks_json.append(core.getAllocator(), dto.blackInfoToJson(b));
        }
        return sendOk(ctx, .{ .blacksInfo = blacks_json.items });
    }
}

pub fn handleGetIncrementalFriends(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const IncReq = struct {
        userID: []const u8,
        sinceTimestamp: i64,
    };
    const req = ctx.bindJson(IncReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const friends = friend_mod.getFriendsSince(req.userID, req.sinceTimestamp) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_incremental_friends, @errorName(err));
    };
    {
        var friends_json = std.ArrayList(@TypeOf(dto.friendInfoToJson(friends[0]))).empty;
        defer friends_json.deinit(core.getAllocator());
        for (friends) |f| {
            try friends_json.append(core.getAllocator(), dto.friendInfoToJson(f));
        }
        return sendOk(ctx, .{ .friendsInfo = friends_json.items });
    }
}

pub fn handleGetSelfApplyList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ListReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(ListReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const requests = friend_mod.getFriendRequests(req.userID, true) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_self_apply_list, @errorName(err));
    };
    var reqs_json = std.ArrayList(@TypeOf(dto.friendRequestToJson(requests[0]))).empty;
    defer reqs_json.deinit(core.getAllocator());
    for (requests) |r| {
        try reqs_json.append(core.getAllocator(), dto.friendRequestToJson(r));
    }
    return sendOk(ctx, .{ .friendRequests = reqs_json.items, .total = reqs_json.items.len });
}

pub fn handleGetSpecifiedBlacks(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        ownerUserID: []const u8,
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const all_blacks = friend_mod.getBlacks(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_specified_blacks, @errorName(err));
    };
    var filtered = std.ArrayList(friend_mod.BlackInfo).empty;
    defer filtered.deinit(core.getAllocator());
    for (all_blacks) |b| {
        for (req.userIDs) |uid| {
            if (std.mem.eql(u8, b.block_user_id, uid)) {
                try filtered.append(core.getAllocator(), b);
                break;
            }
        }
    }
    return sendOk(ctx, .{ .blacks = filtered.items });
}

pub fn handleGetSpecifiedFriendsInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        ownerUserID: []const u8,
        friendUserIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const UserJsonT = @TypeOf(dto.userToJson(@as(user_mod.User, undefined)));
    const FriendJsonT = @TypeOf(dto.friendInfoToJson(@as(friend_mod.FriendInfo, undefined)));
    const BlackJsonT = @TypeOf(dto.blackInfoToJson(@as(friend_mod.BlackInfo, undefined)));
    const SpecInfo = struct {
        userInfo: ?UserJsonT,
        friendInfo: ?FriendJsonT,
        blackInfo: ?BlackJsonT,
    };
    const all_friends = friend_mod.getFriends(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_specified_friends_info, @errorName(err));
    };
    const all_blacks = friend_mod.getBlacks(req.ownerUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_specified_friends_info, @errorName(err));
    };
    var infos = std.ArrayList(SpecInfo).empty;
    defer infos.deinit(core.getAllocator());
    for (req.friendUserIDs) |uid| {
        var friend_json: ?FriendJsonT = null;
        for (all_friends) |f| {
            if (std.mem.eql(u8, f.friend_user_id, uid)) {
                friend_json = dto.friendInfoToJson(f);
                break;
            }
        }
        var black_json: ?BlackJsonT = null;
        for (all_blacks) |b| {
            if (std.mem.eql(u8, b.block_user_id, uid)) {
                black_json = dto.blackInfoToJson(b);
                break;
            }
        }
        const user_info: ?UserJsonT = if (user_mod.getUser(uid) catch null) |u| dto.userToJson(u) else null;
        try infos.append(core.getAllocator(), .{
            .userInfo = user_info,
            .friendInfo = friend_json,
            .blackInfo = black_json,
        });
    }
    return sendOk(ctx, .{ .infos = infos.items });
}

pub fn handleImportFriend(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ImportReq = struct {
        ownerUserID: []const u8,
        friendUserIDs: [][]const u8,
    };
    const req = ctx.bindJson(ImportReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const count = friend_mod.importFriends(req.ownerUserID, req.friendUserIDs) catch |err| {
        return sendFail(ctx, core.ErrorCode.import_friend, @errorName(err));
    };
    return sendOk(ctx, .{ .importedCount = count });
}

pub fn handleIsFriend(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const IsFriendReq = struct {
        userID1: []const u8,
        userID2: []const u8,
    };
    const req = ctx.bindJson(IsFriendReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const result = friend_mod.isFriend(req.userID1, req.userID2);
    return sendOk(ctx, .{ .inUserFriends = result });
}

pub fn handleRemoveBlack(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RemoveReq = struct {
        ownerUserID: []const u8,
        blockUserID: []const u8,
    };
    const req = ctx.bindJson(RemoveReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = friend_mod.removeBlack(req.ownerUserID, req.blockUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.remove_black, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleSearchFriendInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SearchReq = struct {
        keyword: []const u8,
        limit: u32 = 20,
    };
    const req = ctx.bindJson(SearchReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const users = user_mod.searchUsers(req.keyword, req.limit) catch |err| {
        return sendFail(ctx, core.ErrorCode.search_friend_info, @errorName(err));
    };
    var users_json = std.ArrayList(@TypeOf(dto.userToJson(users[0]))).empty;
    defer users_json.deinit(core.getAllocator());
    for (users) |u| {
        try users_json.append(core.getAllocator(), dto.userToJson(u));
    }
    return sendOk(ctx, .{ .users = users_json.items });
}

pub fn handleSetFriendRemark(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RemarkReq = struct {
        ownerUserID: []const u8,
        friendUserID: []const u8,
        remark: []const u8,
    };
    const req = ctx.bindJson(RemarkReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = friend_mod.setFriendRemark(req.ownerUserID, req.friendUserID, req.remark) catch |err| {
        return sendFail(ctx, core.ErrorCode.set_friend_remark, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleUpdateFriends(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const UpdateReq = struct {
        ownerUserID: []const u8,
        friendUserIDs: [][]const u8,
        remark: ?[]const u8 = null,
        isPinned: ?bool = null,
        ex: ?[]const u8 = null,
    };
    const req = ctx.bindJson(UpdateReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    for (req.friendUserIDs) |uid| {
        _ = friend_mod.updateFriend(req.ownerUserID, uid, req.remark, req.isPinned, req.ex) catch {};
    }
    return sendOk(ctx, null);
}

pub fn handleGetSelfUnhandledApplyCount(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CountReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(CountReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const requests = friend_mod.getFriendRequests(req.userID, false) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_self_unhandled_apply_count, @errorName(err));
    };
    var count: usize = 0;
    for (requests) |r| {
        if (@backingInt(r.handle_result) == 0) count += 1;
    }
    return sendOk(ctx, .{ .count = count });
}
