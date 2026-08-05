// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: user.zig

const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const user_mod = @import("../../user.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleAccountCheck(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CheckReq = struct {
        checkUserIDs: [][]const u8,
    };
    const req = ctx.bindJson(CheckReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var results = std.ArrayList(struct { userID: []const u8, accountStatus: i32 }).empty;
    defer results.deinit(core.getAllocator());
    for (req.checkUserIDs) |uid| {
        const exists = user_mod.getUser(uid) catch null;
        try results.append(core.getAllocator(), .{ .userID = uid, .accountStatus = if (exists != null) 1 else 0 });
    }
    return sendOk(ctx, .{ .results = results.items });
}

pub fn handleGetAllUsersID(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const user_ids = user_mod.getAllUserIDs(core.getAllocator()) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_all_users_id, @errorName(err));
    };
    defer core.getAllocator().free(user_ids);
    return sendOk(ctx, .{ .userIDs = user_ids });
}

pub fn handleGetSubscribeUsersStatus(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const StatusReq = struct {
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(StatusReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var results = std.ArrayList(struct { userID: []const u8, status: i32 }).empty;
    defer results.deinit(core.getAllocator());
    for (req.userIDs) |uid| {
        const status: i32 = if (user_mod.isOnline(uid)) 1 else 0;
        try results.append(core.getAllocator(), .{ .userID = uid, .status = status });
    }
    return sendOk(ctx, .{ .statusList = results.items });
}

pub fn handleGetUsers(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        pageNumber: u32 = 1,
        showNumber: u32 = 20,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const all_users = user_mod.searchUsers("", req.showNumber) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_users, @errorName(err));
    };
    var users_json = std.ArrayList(@TypeOf(dto.userToJson(all_users[0]))).empty;
    defer users_json.deinit(core.getAllocator());
    for (all_users) |u| {
        try users_json.append(core.getAllocator(), dto.userToJson(u));
    }
    return sendOk(ctx, .{ .users = users_json.items });
}

pub fn handleGetUsersFullInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var users = std.ArrayList(user_mod.User).empty;
    defer users.deinit(core.getAllocator());
    for (req.userIDs) |uid| {
        if (user_mod.getUser(uid) catch null) |u| {
            try users.append(core.getAllocator(), u);
        }
    }
    return sendOk(ctx, .{ .users = users.items });
}

pub fn handleGetUsersInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetUsersInfoReq = struct {
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetUsersInfoReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var users = std.ArrayList(struct {
        userID: []const u8,
        nickname: []const u8,
        faceURL: []const u8,
        gender: i16,
        level: i16,
        birth: ?i64,
        areaCode: []const u8,
        telephone: []const u8,
        ex: []const u8,
        appMangerLevel: i16,
        globalRecvMsgOpt: i16,
        createTime: i64,
    }).empty;
    defer users.deinit(core.getAllocator());
    for (req.userIDs) |uid| {
        if (user_mod.getUser(uid) catch null) |user| {
            try users.append(core.getAllocator(), .{
                .userID = user.user_id,
                .nickname = user.nickname,
                .faceURL = user.face_url,
                .gender = user.gender,
                .level = user.level,
                .birth = user.birth,
                .areaCode = user.area_code,
                .telephone = user.telephone,
                .ex = user.ex,
                .appMangerLevel = user.app_manager_level,
                .globalRecvMsgOpt = user.global_recv_msg_opt,
                .createTime = user.create_time,
            });
        }
    }
    return sendOk(ctx, .{ .usersInfo = users.items });
}

pub fn handleGetUsersOnlineStatus(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const OnlineReq = struct {
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(OnlineReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var results = std.ArrayList(struct { userID: []const u8, status: i32, detailPlatformStatus: []const struct { platformID: i32, status: i32 } }).empty;
    defer results.deinit(core.getAllocator());
    for (req.userIDs) |uid| {
        const status: i32 = if (user_mod.isOnline(uid)) 1 else 0;
        try results.append(core.getAllocator(), .{ .userID = uid, .status = status, .detailPlatformStatus = &.{} });
    }
    return sendOk(ctx, .{ .successResult = results.items });
}

pub fn handleGetUsersOnlineTokenDetail(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const OnlineReq = struct {
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(OnlineReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var results = std.ArrayList(struct { userID: []const u8, status: i32, singlePlatformToken: []const struct { platformID: i32, token: []const []const u8, total: i32 } }).empty;
    defer results.deinit(core.getAllocator());
    for (req.userIDs) |uid| {
        const status: i32 = if (user_mod.isOnline(uid)) 1 else 0;
        try results.append(core.getAllocator(), .{ .userID = uid, .status = status, .singlePlatformToken = &.{} });
    }
    return sendOk(ctx, .{ .details = results.items });
}

pub fn handleGetUsersStatus(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const StatusReq = struct {
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(StatusReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var results = std.ArrayList(struct { userID: []const u8, status: i32 }).empty;
    defer results.deinit(core.getAllocator());
    for (req.userIDs) |uid| {
        const status: i32 = if (user_mod.isOnline(uid)) 1 else 0;
        try results.append(core.getAllocator(), .{ .userID = uid, .status = status });
    }
    return sendOk(ctx, .{ .statusList = results.items });
}

pub fn handleProcessUserCommandAdd(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CmdReq = struct {
        userID: []const u8,
        commandID: []const u8,
        commandValue: []const u8,
    };
    const req = ctx.bindJson(CmdReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    user_mod.addUserCommand(req.userID, req.commandID, req.commandValue) catch |err| {
        return sendFail(ctx, core.ErrorCode.process_user_command_add, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleProcessUserCommandDelete(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CmdReq = struct {
        userID: []const u8,
        commandID: []const u8,
    };
    const req = ctx.bindJson(CmdReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    user_mod.deleteUserCommand(req.userID, req.commandID) catch |err| {
        return sendFail(ctx, core.ErrorCode.process_user_command_delete, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleProcessUserCommandGet(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CmdReq = struct {
        userID: []const u8,
        commandID: []const u8,
    };
    const req = ctx.bindJson(CmdReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const cmd = user_mod.getUserCommand(req.userID, req.commandID, core.getAllocator()) catch |err| {
        return sendFail(ctx, core.ErrorCode.process_user_command_get, @errorName(err));
    };
    if (cmd == null) return sendFail(ctx, 404, "Not Found");
    return sendOk(ctx, dto.userCommandToJson(cmd.?));
}

pub fn handleProcessUserCommandGetAll(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CmdReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(CmdReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const cmds = user_mod.getAllUserCommands(req.userID, core.getAllocator()) catch |err| {
        return sendFail(ctx, core.ErrorCode.process_user_command_get_all, @errorName(err));
    };
    var cmds_json = std.ArrayList(@TypeOf(dto.userCommandToJson(cmds[0]))).empty;
    defer cmds_json.deinit(core.getAllocator());
    for (cmds) |c| {
        try cmds_json.append(core.getAllocator(), dto.userCommandToJson(c));
    }
    return sendOk(ctx, .{ .commands = cmds_json.items });
}

pub fn handleProcessUserCommandUpdate(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CmdReq = struct {
        userID: []const u8,
        commandID: []const u8,
        commandValue: []const u8,
    };
    const req = ctx.bindJson(CmdReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    user_mod.deleteUserCommand(req.userID, req.commandID) catch {};
    user_mod.addUserCommand(req.userID, req.commandID, req.commandValue) catch |err| {
        return sendFail(ctx, core.ErrorCode.process_user_command_update, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleSearchUsersFullInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SearchReq = struct {
        keyword: []const u8,
        limit: u32 = 20,
    };
    const req = ctx.bindJson(SearchReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const users = user_mod.searchUsers(req.keyword, req.limit) catch |err| {
        return sendFail(ctx, core.ErrorCode.search_users_full_info, @errorName(err));
    };
    var users_json = std.ArrayList(@TypeOf(dto.userToJson(users[0]))).empty;
    defer users_json.deinit(core.getAllocator());
    for (users) |u| {
        try users_json.append(core.getAllocator(), dto.userToJson(u));
    }
    return sendOk(ctx, .{ .users = users_json.items });
}

pub fn handleSetGlobalRecvMsgOpt(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const OptReq = struct {
        userID: []const u8,
        globalRecvMsgOpt: i16,
    };
    const req = ctx.bindJson(OptReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = user_mod.updateUser(req.userID, .{ .global_recv_msg_opt = req.globalRecvMsgOpt }) catch |err| {
        return sendFail(ctx, core.ErrorCode.set_global_recv_msg_opt, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleSubscribeUsersStatus(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SubReq = struct {
        userIDs: [][]const u8,
        genre: i32 = 1,
    };
    const req = ctx.bindJson(SubReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    var results = std.ArrayList(struct { userID: []const u8, status: i32 }).empty;
    defer results.deinit(core.getAllocator());
    for (req.userIDs) |uid| {
        const status: i32 = if (user_mod.isOnline(uid)) 1 else 0;
        try results.append(core.getAllocator(), .{ .userID = uid, .status = status });
    }
    return sendOk(ctx, .{ .statusList = results.items });
}

pub fn handleUnregisterUser(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const UnregisterReq = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(UnregisterReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = user_mod.deleteUser(req.userID);
    return sendOk(ctx, null);
}

pub fn handleUpdateUserInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const UpdateUserReq = struct {
        userID: []const u8,
        nickname: ?[]const u8 = null,
        faceURL: ?[]const u8 = null,
        gender: ?i16 = null,
        birth: ?i64 = null,
        areaCode: ?[]const u8 = null,
        telephone: ?[]const u8 = null,
        ex: ?[]const u8 = null,
        globalRecvMsgOpt: ?i16 = null,
    };
    const req = ctx.bindJson(UpdateUserReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const user = user_mod.updateUser(req.userID, .{
        .nickname = req.nickname,
        .face_url = req.faceURL,
        .gender = req.gender,
        .birth = req.birth,
        .area_code = req.areaCode,
        .telephone = req.telephone,
        .ex = req.ex,
        .global_recv_msg_opt = req.globalRecvMsgOpt,
    }) catch |err| {
        return sendFail(ctx, core.ErrorCode.update_user_info, @errorName(err));
    };
    if (user == null) return sendFail(ctx, 404, "Not Found");
    return sendOk(ctx, .{
        .userID = user.?.user_id,
        .nickname = user.?.nickname,
        .faceURL = user.?.face_url,
        .gender = user.?.gender,
    });
}

pub fn handleUpdateUserInfoEx(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    // For now, delegate to handleUpdateUserInfo logic
    const UpdateUserExReq = struct {
        userID: []const u8,
        nickname: ?[]const u8 = null,
        faceURL: ?[]const u8 = null,
        gender: ?i16 = null,
        birth: ?i64 = null,
        areaCode: ?[]const u8 = null,
        telephone: ?[]const u8 = null,
        ex: ?[]const u8 = null,
        globalRecvMsgOpt: ?i16 = null,
    };
    const req = ctx.bindJson(UpdateUserExReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const user = user_mod.updateUser(req.userID, .{
        .nickname = req.nickname,
        .face_url = req.faceURL,
        .gender = req.gender,
        .birth = req.birth,
        .area_code = req.areaCode,
        .telephone = req.telephone,
        .ex = req.ex,
        .global_recv_msg_opt = req.globalRecvMsgOpt,
    }) catch |err| {
        return sendFail(ctx, core.ErrorCode.update_user_info_ex, @errorName(err));
    };
    if (user == null) return sendFail(ctx, 404, "Not Found");
    return sendOk(ctx, .{
        .userID = user.?.user_id,
        .nickname = user.?.nickname,
        .faceURL = user.?.face_url,
        .gender = user.?.gender,
    });
}

pub fn handleUserRegister(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const UserRegisterReq = struct {
        users: []struct {
            userID: ?[]const u8 = null,
            nickname: []const u8,
            faceURL: ?[]const u8 = null,
            gender: i16 = 0,
            birth: i64 = 0,
            areaCode: ?[]const u8 = null,
            phoneNumber: ?[]const u8 = null,
            email: ?[]const u8 = null,
            account: ?[]const u8 = null,
            password: ?[]const u8 = null,
        },
    };
    const req = ctx.bindJson(UserRegisterReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    for (req.users) |u| {
        const user_id = u.userID orelse u.account orelse u.phoneNumber orelse u.email orelse return sendFail(ctx, 400, "Missing user identifier");
        _ = user_mod.createUser(.{
            .user_id = user_id,
            .nickname = u.nickname,
            .face_url = u.faceURL,
            .gender = u.gender,
            .area_code = u.areaCode orelse "",
            .telephone = u.phoneNumber orelse "",
            .password = u.password,
        }) catch |err| {
            return sendFail(ctx, core.ErrorCode.user_register, @errorName(err));
        };
    }
    return sendOk(ctx, null);
}

pub fn handleUserRegisterCount(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CountReq = struct {
        startTime: ?i64 = null,
        endTime: ?i64 = null,
    };
    const req = ctx.bindJson(CountReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const count = if (req.startTime != null and req.endTime != null)
        user_mod.userCountSince(req.startTime.?, req.endTime.?)
    else
        user_mod.userCount();
    return sendOk(ctx, .{ .count = count });
}
