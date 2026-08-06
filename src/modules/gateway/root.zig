const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const db_mod = @import("../db_postgres.zig");
const model = @import("model.zig");

pub const info = zigmodu.api.Module{
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

// RTC Meeting in-memory storage
var rtc_meetings: ?std.StringHashMap(model.RtcMeeting) = null;
var rtc_participants: ?std.StringHashMap(std.ArrayList(model.RtcParticipant)) = null;
var rtc_mutex: std.atomic.Mutex = .unlocked;

pub fn rtcLock() void {
    while (!rtc_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}

pub fn rtcUnlock() void {
    rtc_mutex.unlock();
}

pub fn getRtcMeetings() *std.StringHashMap(model.RtcMeeting) {
    if (rtc_meetings == null) {
        rtc_meetings = std.StringHashMap(model.RtcMeeting).init(core.getGlobalAllocator());
    }
    return &rtc_meetings.?;
}

pub fn getRtcParticipants() *std.StringHashMap(std.ArrayList(model.RtcParticipant)) {
    if (rtc_participants == null) {
        rtc_participants = std.StringHashMap(std.ArrayList(model.RtcParticipant)).init(core.getGlobalAllocator());
    }
    return &rtc_participants.?;
}

pub fn generateRoomID(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = currentMillis();
    return try std.fmt.allocPrint(allocator, "room_{d}", .{timestamp});
}

// --------------------------------------------
// Health (zigmodu HealthEndpoint)
// --------------------------------------------
var g_health: ?zigmodu.HealthEndpoint = null;

fn livenessCheck(_: ?*anyopaque) zigmodu.HealthEndpoint.HealthStatus {
    return .UP;
}

fn databaseHealthCheck(ctx: ?*anyopaque) zigmodu.HealthEndpoint.HealthStatus {
    const client = ctx orelse return .DOWN;
    const db: *db_mod.PostgresClient = @ptrCast(@alignCast(client));
    return if (db.connected) .UP else .DOWN;
}

pub fn ensureHealth() void {
    if (g_health != null) return;
    var endpoint = zigmodu.HealthEndpoint.init(core.getGlobalAllocator());
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
    // Release RTC in-memory rooms (map + owned strings).
    if (rtc_meetings) |*m| {
        var it = m.iterator();
        while (it.next()) |e| {
            // `e.value_ptr.room_id` aliases the map key (same pointer) — freed
            // via the key; freeing both would double-free.
            core.getGlobalAllocator().free(e.key_ptr.*);
            core.getGlobalAllocator().free(e.value_ptr.host_user_id);
            core.getGlobalAllocator().free(e.value_ptr.meeting_name);
        }
        m.deinit();
        rtc_meetings = null;
    }
    if (rtc_participants) |*p| {
        var it = p.iterator();
        while (it.next()) |e| {
            // NOTE: `e.key_ptr.*` aliases the meetings map key (same room_id
            // pointer) — freed there; do NOT free it again here.
            for (e.value_ptr.items) |pt| {
                core.getGlobalAllocator().free(pt.user_id);
                core.getGlobalAllocator().free(pt.nickname);
            }
            e.value_ptr.deinit(core.getGlobalAllocator());
        }
        p.deinit();
        rtc_participants = null;
    }
    if (g_health) |*h| h.deinit();
    g_health = null;
    std.log.info("GatewayModule deinitialized", .{});
}
