const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const config_mod = @import("config.zig");
const db_mod = @import("db_postgres.zig");

pub const model = @import("auth/model.zig");
pub const persistence = @import("auth/persistence.zig");
pub const service = @import("auth/service.zig");

// Backward-compatible re-exports
pub const TokenInfo = model.TokenInfo;
pub const LoginInput = model.LoginInput;
pub const RegisterInput = model.RegisterInput;
pub const AuthModule = service.AuthService;

pub const info = zigmodu.api.Module{
    .name = "auth",
    .description = "JWT authentication - login, register, token management",
    .dependencies = &.{ "user", "config", "db_postgres" },
    .runtime = .{
        .max_qps = 300,
        .cb_failure_threshold = 5,
        .cb_timeout_seconds = 15,
    },
};

var g_service: ?service.AuthService = null;

pub fn init() !void {
    const cfg = config_mod.getConfig();
    const db = db_mod.getClient();
    g_service = service.AuthService.init(core.serviceAllocator(), cfg.jwt.secret, cfg.jwt.expiry_hours, db);
    service.initLoginLimiter(core.getGlobalAllocator());
    std.log.info("AuthModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    g_service = null;
    service.deinitLoginLimiter();
    std.log.info("AuthModule deinitialized", .{});
}

fn svc() *service.AuthService {
    return &g_service.?;
}

pub fn getAuth() *service.AuthService {
    return svc();
}

pub fn register(input: RegisterInput) !TokenInfo {
    return svc().register(input);
}

pub fn login(input: LoginInput) !TokenInfo {
    return svc().login(input);
}

pub fn parseToken(token: []const u8) !TokenInfo {
    return svc().parseToken(token);
}

pub fn forceLogout(user_id: []const u8) void {
    svc().forceLogout(user_id);
}

pub fn registerWithPassword(nickname: []const u8, password: []const u8, area_code: ?[]const u8, phone_number: ?[]const u8, email: ?[]const u8, account: ?[]const u8) !TokenInfo {
    return svc().registerWithPassword(nickname, password, area_code, phone_number, email, account);
}

pub fn loginWithPassword(user_id: []const u8, password: []const u8, platform_id: i32) !TokenInfo {
    return svc().loginWithPassword(user_id, password, platform_id);
}

pub fn changePassword(user_id: []const u8, current_password: []const u8, new_password: []const u8) !bool {
    return svc().changePassword(user_id, current_password, new_password);
}

pub fn sendVerificationCode(phone_number: ?[]const u8, email: ?[]const u8, area_code: ?[]const u8) ![]const u8 {
    return svc().sendVerificationCode(phone_number, email, area_code);
}

pub fn verifyCode(phone_number: ?[]const u8, email: ?[]const u8, code: []const u8) bool {
    return svc().verifyCode(phone_number, email, code);
}

pub fn resetPassword(user_id: []const u8, new_password: []const u8) !bool {
    return svc().resetPassword(user_id, new_password);
}

pub fn getAdminToken(secret: []const u8, user_id: []const u8) !TokenInfo {
    return svc().getAdminToken(secret, user_id);
}
