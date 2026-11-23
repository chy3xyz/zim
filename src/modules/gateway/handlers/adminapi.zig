// Domain handlers: admin surface (Phase 89 — Go open-im-chat aligned).
// Routes live in ../handlers.zig `admin_routes`.
//
// Auth model: these routes are NOT in the public whitelist, so authMiddleware
// already requires a valid token; on top of that every handler verifies the
// `X-Admin-Secret` header against the server's [jwt] secret — the same
// admin credential the admin panel already holds for /auth/get_admin_token.

const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const admin_mod = @import("../../admin.zig");
const auth_mod = @import("../../auth.zig");
const config_mod = @import("../../config.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

/// Admin gate: valid token (authMiddleware) + admin secret header.
fn requireAdmin(ctx: *http.Context) bool {
    const cfg = config_mod.getConfig();
    const provided = ctx.header("X-Admin-Secret") orelse return false;
    return std.mem.eql(u8, provided, cfg.jwt.secret);
}

pub fn handleAdminLogin(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const LoginReq = struct {
        adminUserID: []const u8,
        secret: []const u8,
    };
    const req = ctx.bindJson(LoginReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    if (!requireAdmin(ctx)) return sendFail(ctx, core.ErrorCode.unauthorized, "admin secret required");
    const token_info = auth_mod.loginWithPassword(req.adminUserID, req.secret, 1) catch |err| {
        return sendFail(ctx, core.ErrorCode.unauthorized, @errorName(err));
    };
    return sendOk(ctx, .{
        .imToken = token_info.token,
        .userID = token_info.user_id,
    });
}

pub fn handleGetAllowRegister(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    if (!requireAdmin(ctx)) return sendFail(ctx, core.ErrorCode.unauthorized, "admin secret required");
    return sendOk(ctx, .{ .allowRegister = admin_mod.getAllowRegister() });
}

pub fn handleSetAllowRegister(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const Req = struct {
        allowRegister: bool,
    };
    const req = ctx.bindJson(Req) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    if (!requireAdmin(ctx)) return sendFail(ctx, core.ErrorCode.unauthorized, "admin secret required");
    admin_mod.persistence.setAllowRegister(req.allowRegister) catch |err| {
        return sendFail(ctx, core.ErrorCode.db_error, @errorName(err));
    };
    return sendOk(ctx, .{ .allowRegister = req.allowRegister });
}

pub fn handleBlockAdd(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const Req = struct {
        userID: []const u8,
        reason: []const u8 = "",
        operatorUserID: []const u8 = "",
    };
    const req = ctx.bindJson(Req) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    if (!requireAdmin(ctx)) return sendFail(ctx, core.ErrorCode.unauthorized, "admin secret required");
    admin_mod.persistence.blockUser(req.userID, req.reason, req.operatorUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.db_error, @errorName(err));
    };
    // Kick live sessions so the ban takes effect immediately.
    @import("../../websocket.zig").kickUser(req.userID, "account blocked by admin");
    return sendOk(ctx, null);
}

pub fn handleBlockDel(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const Req = struct {
        userID: []const u8,
    };
    const req = ctx.bindJson(Req) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    if (!requireAdmin(ctx)) return sendFail(ctx, core.ErrorCode.unauthorized, "admin secret required");
    admin_mod.persistence.unblockUser(req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.db_error, @errorName(err));
    };
    return sendOk(ctx, null);
}

/// Go BlockUserInfo camelCase shape with pagination totals.
const BlockUserView = struct {
    userID: []const u8,
    nickname: []const u8,
    faceURL: []const u8,
    gender: i64,
    reason: []const u8,
    operatorUserID: []const u8,
    createTime: i64,
};

pub fn handleBlockSearch(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const Req = struct {
        pageNumber: i32 = 1,
        showNumber: i32 = 20,
    };
    const req = ctx.bindJson(Req) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    if (!requireAdmin(ctx)) return sendFail(ctx, core.ErrorCode.unauthorized, "admin secret required");

    const offset: i64 = (@as(i64, req.pageNumber) - 1) * req.showNumber;
    const rows = admin_mod.persistence.searchBlocks(core.getAllocator(), offset, req.showNumber) catch |err| {
        return sendFail(ctx, core.ErrorCode.db_error, @errorName(err));
    };
    const total = admin_mod.persistence.countBlocks();

    var items = std.ArrayList(BlockUserView).empty;
    defer items.deinit(core.getAllocator());
    for (rows) |r| {
        items.append(core.getAllocator(), .{
            .userID = r.user_id,
            .nickname = r.nickname,
            .faceURL = r.face_url,
            .gender = r.gender,
            .reason = r.reason,
            .operatorUserID = r.operator_user_id,
            .createTime = r.create_time,
        }) catch {};
    }
    return sendOk(ctx, .{ .total = total, .blockInfos = items.items });
}

/// Registration toggle enforcement, called from handleAccountRegister.
pub fn checkRegisterAllowed(ctx: *http.Context) bool {
    if (admin_mod.getAllowRegister()) return true;
    sendFail(ctx, core.ErrorCode.forbidden, "registration is disabled");
    return false;
}
