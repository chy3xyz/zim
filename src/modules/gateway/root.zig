const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const db_mod = @import("../db_postgres.zig");

pub const info = zmodu.api.Module{
    .name = "gateway",
    .description = "HTTP + WebSocket gateway for client communication",
    .dependencies = &.{ "config", "auth", "user" },
    .runtime = .{
        .max_concurrent = 500,
        .max_qps = 5000,
    },
};

pub fn currentMillis() i64 {
    return core.unixNowMillis();
}

// RTC meeting state lives in PostgreSQL since Phase 84
// (rtc_persistence.zig) — the former in-memory maps were lost on restart
// and leaked arena pointers across requests.

pub fn generateRoomID(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = currentMillis();
    return try std.fmt.allocPrint(allocator, "room_{d}", .{timestamp});
}

// --------------------------------------------
// Health (zmodu HealthEndpoint)
// --------------------------------------------
var g_health: ?zmodu.HealthEndpoint = null;

fn livenessCheck(_: ?*anyopaque) zmodu.HealthEndpoint.HealthStatus {
    return .UP;
}

fn databaseHealthCheck(ctx: ?*anyopaque) zmodu.HealthEndpoint.HealthStatus {
    const client = ctx orelse return .DOWN;
    const db: *db_mod.PostgresClient = @ptrCast(@alignCast(client));
    return if (db.connected) .UP else .DOWN;
}

pub fn ensureHealth() void {
    if (g_health != null) return;
    var endpoint = zmodu.HealthEndpoint.init(core.getGlobalAllocator());
    endpoint.registerCheck("liveness", "ZIM process is alive", livenessCheck) catch {};
    if (db_mod.isInitialized()) {
        endpoint.registerCheckWithContext("database", "PostgreSQL connectivity", databaseHealthCheck, db_mod.getClient()) catch {};
    } else {
        // Tests / pre-DB startup: report DOWN instead of crashing on null client.
        endpoint.registerCheck("database", "PostgreSQL connectivity", databaseHealthCheck) catch {};
    }
    g_health = endpoint;
}

pub fn healthJson(allocator: std.mem.Allocator) ![]const u8 {
    ensureHealth();
    return g_health.?.toJson(allocator);
}

pub fn deinit() void {
    // RTC state lives in PostgreSQL (rtc_persistence.zig) — nothing to
    // release here beyond the health endpoint.
    if (g_health) |*h| h.deinit();
    g_health = null;
    std.log.info("GatewayModule deinitialized", .{});
}
