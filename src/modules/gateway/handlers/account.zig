// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: account.zig

const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const auth_mod = @import("../../auth.zig");
const user_mod = @import("../../user.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;
const getBearerToken = helpers.getBearerToken;

pub fn handleAccountInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const token = getBearerToken(ctx) orelse return sendFail(ctx, 401, "Unauthorized");
    const token_info = auth_mod.parseToken(token) catch |err| {
        return sendFail(ctx, core.ErrorCode.internal_error, @errorName(err));
    };
    const user = user_mod.getUser(token_info.user_id) catch |err| {
        return sendFail(ctx, core.ErrorCode.internal_error, @errorName(err));
    };
    if (user == null) return sendFail(ctx, 404, "Not Found");
    return sendOk(ctx, dto.userToJson(user.?));
}

pub fn handleAccountLogin(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const LoginReq = struct {
        areaCode: ?[]const u8 = null,
        account: ?[]const u8 = null,
        phoneNumber: ?[]const u8 = null,
        email: ?[]const u8 = null,
        password: []const u8,
        platform: i32 = 1, // default like RegisterReq; some SDKs omit it
        verifyCode: ?[]const u8 = null,
    };
    const req = ctx.bindJson(LoginReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    if (req.password.len < 6) return sendFail(ctx, 400, "password too short");
    const user_id = req.account orelse req.phoneNumber orelse req.email orelse return sendFail(ctx, 400, "Missing user identifier");
    const token_info = auth_mod.loginWithPassword(user_id, req.password, req.platform) catch |err| {
        return sendFail(ctx, core.ErrorCode.internal_error, @errorName(err));
    };
    return sendOk(ctx, .{
        .imToken = token_info.token,
        .chatToken = token_info.token,
        .userID = token_info.user_id,
    });
}

pub fn handleAccountRegister(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RegisterReq = struct {
        deviceID: ?[]const u8 = null,
        verifyCode: ?[]const u8 = null,
        platform: i32 = 1,
        invitationCode: ?[]const u8 = null,
        autoLogin: bool = true,
        user: struct {
            nickname: []const u8,
            faceURL: ?[]const u8 = null,
            birth: i64 = 0,
            gender: i16 = 1,
            email: ?[]const u8 = null,
            areaCode: ?[]const u8 = null,
            phoneNumber: ?[]const u8 = null,
            account: ?[]const u8 = null,
            password: []const u8,
        },
    };
    const req = ctx.bindJson(RegisterReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    if (req.user.nickname.len == 0) return sendFail(ctx, 400, "nickname required");
    if (req.user.password.len < 6) return sendFail(ctx, 400, "password too short");
    const user_id = req.user.account orelse req.user.phoneNumber orelse req.user.email orelse blk: {
        var bytes: [16]u8 = undefined;
        core.secureRandomBytes(&bytes);
        break :blk try std.fmt.allocPrint(core.getAllocator(), "user_{x}", .{std.mem.readInt(u128, &bytes, .big)});
    };
    defer if (req.user.account == null and req.user.phoneNumber == null and req.user.email == null) core.getAllocator().free(user_id);

    const user = user_mod.createUser(user_mod.UserCreateInput{
        .user_id = user_id,
        .nickname = req.user.nickname,
        .face_url = req.user.faceURL,
        .gender = req.user.gender,
        .area_code = req.user.areaCode orelse "",
        .telephone = req.user.phoneNumber orelse "",
        .password = req.user.password,
    }) catch |err| {
        return sendFail(ctx, core.ErrorCode.internal_error, @errorName(err));
    };
    const token_info = auth_mod.login(.{ .user_id = user.user_id, .platform_id = req.platform }) catch |err| {
        return sendFail(ctx, core.ErrorCode.internal_error, @errorName(err));
    };
    return sendOk(ctx, .{
        .imToken = token_info.token,
        .chatToken = token_info.token,
        .userID = token_info.user_id,
    });
}

pub fn handleChangePassword(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ChangePwdReq = struct {
        userID: []const u8,
        currentPassword: []const u8,
        newPassword: []const u8,
    };
    const req = ctx.bindJson(ChangePwdReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const success = auth_mod.changePassword(req.userID, req.currentPassword, req.newPassword) catch |err| {
        return sendFail(ctx, core.ErrorCode.change_password, @errorName(err));
    };
    return sendOk(ctx, .{ .success = success });
}

pub fn handleResetPassword(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ResetPwdReq = struct {
        userID: []const u8,
        newPassword: []const u8,
    };
    const req = ctx.bindJson(ResetPwdReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const success = auth_mod.resetPassword(req.userID, req.newPassword) catch |err| {
        return sendFail(ctx, core.ErrorCode.reset_password, @errorName(err));
    };
    return sendOk(ctx, .{ .success = success });
}

pub fn handleSendVerificationCode(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SendCodeReq = struct {
        phoneNumber: ?[]const u8 = null,
        email: ?[]const u8 = null,
        areaCode: ?[]const u8 = null,
    };
    const req = ctx.bindJson(SendCodeReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const code = auth_mod.sendVerificationCode(req.phoneNumber, req.email, req.areaCode) catch |err| {
        return sendFail(ctx, core.ErrorCode.send_verification_code, @errorName(err));
    };
    return sendOk(ctx, .{ .code = code });
}

pub fn handleVerifyCode(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const VerifyCodeReq = struct {
        phoneNumber: ?[]const u8 = null,
        email: ?[]const u8 = null,
        verifyCode: []const u8,
    };
    const req = ctx.bindJson(VerifyCodeReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const valid = auth_mod.verifyCode(req.phoneNumber, req.email, req.verifyCode);
    return sendOk(ctx, .{ .valid = valid });
}
