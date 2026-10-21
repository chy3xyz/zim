// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: auth.zig

const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const auth_mod = @import("../../auth.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleForceLogout(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const LogoutReq = struct {
        userID: []const u8,
        platformID: i32,
    };
    const req = ctx.bindJson(LogoutReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    auth_mod.forceLogout(req.userID);
    return sendOk(ctx, null);
}

pub fn handleGetAdminToken(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const AdminTokenReq = struct {
        secret: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(AdminTokenReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const token_info = auth_mod.getAdminToken(req.secret, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_admin_token, @errorName(err));
    };
    return sendOk(ctx, .{
        .imToken = token_info.token,
        .chatToken = token_info.token,
        .userID = token_info.user_id,
    });
}

pub fn handleGetUserToken(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const UserTokenReq = struct {
        userID: []const u8,
        platformID: i32,
    };
    const req = ctx.bindJson(UserTokenReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const token_info = auth_mod.login(.{ .user_id = req.userID, .platform_id = req.platformID }) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_user_token, @errorName(err));
    };
    return sendOk(ctx, .{
        .imToken = token_info.token,
        .chatToken = token_info.token,
        .userID = token_info.user_id,
    });
}

pub fn handleParseToken(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const ParseTokenReq = struct {
        token: []const u8,
    };
    const req = ctx.bindJson(ParseTokenReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const token_info = auth_mod.parseToken(req.token) catch |err| {
        return sendFail(ctx, core.ErrorCode.parse_token, @errorName(err));
    };
    return sendOk(ctx, .{
        .userID = token_info.user_id,
        .platformID = token_info.platform_id,
    });
}
