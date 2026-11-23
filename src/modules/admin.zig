const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const config_mod = @import("config.zig");

pub const persistence = @import("admin/persistence.zig");

pub const info = zmodu.api.Module{
    .name = "admin",
    .description = "Admin surface: registration toggle, user blocks (Go open-im-chat aligned)",
    .dependencies = &.{ "config", "db_postgres" },
};

pub fn init() !void {
    ensureAdminSeed() catch |err| {
        std.log.warn("[Admin] admin account seed failed: {s}", .{@errorName(err)});
    };
    std.log.info("AdminModule initialized", .{});
}

/// Seed/promote the built-in admin account (user_id `admin`, password =
/// [jwt] secret — the operator already holds it, and rotating the secret
/// rotates the admin password on next restart).
fn ensureAdminSeed() !void {
    const cfg = config_mod.getConfig();
    if (cfg.jwt.secret.len == 0) return;
    var enc = zmodu.security.PasswordEncoder.init(core.getGlobalAllocator(), core.getIo());
    const hash = enc.encode(cfg.jwt.secret) catch return;
    defer core.getGlobalAllocator().free(hash);
    try persistence.ensureAdminUser("admin", hash);
}

pub fn deinit() void {
    std.log.info("AdminModule deinitialized", .{});
}

pub fn isBlocked(user_id: []const u8) bool {
    return persistence.isBlocked(user_id);
}

pub fn getAllowRegister() bool {
    return persistence.getAllowRegister();
}
