//! In-process load benchmark against PostgreSQL (requires a running PG).
//! Run: `zig build bench`
const std = @import("std");
const core = @import("core");

const config_mod = @import("modules/config.zig");
const db_mod = @import("modules/db_postgres.zig");
const user_mod = @import("modules/user.zig");
const auth_mod = @import("modules/auth.zig");
const friend_mod = @import("modules/friend.zig");
const group_mod = @import("modules/group.zig");
const message_mod = @import("modules/message.zig");
const conversation_mod = @import("modules/conversation.zig");
const event_bus_mod = @import("modules/event_bus.zig");

const Noop = struct {
    fn h(_: core.Event) void {}
};

fn initModules() !void {
    config_mod.init() catch {};
    db_mod.init() catch |e| {
        std.log.err("benchmark needs a running PostgreSQL: {s}", .{@errorName(e)});
        return e;
    };
    event_bus_mod.init() catch {};
    user_mod.init() catch {};
    conversation_mod.init() catch {};
    auth_mod.init() catch {};
    friend_mod.init() catch {};
    group_mod.init() catch {};
    message_mod.init() catch {};
}

fn deinitModules() void {
    message_mod.deinit();
    group_mod.deinit();
    friend_mod.deinit();
    auth_mod.deinit();
    conversation_mod.deinit();
    user_mod.deinit();
    event_bus_mod.deinit();
    db_mod.deinit();
    config_mod.deinit();
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    try core.init(allocator, init.io);
    defer core.deinit();
    try core.getEventBus().subscribeAsync(.message_sent, Noop.h, "bench");

    try initModules();
    defer deinitModules();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    core.setRequestAllocator(arena.allocator());
    defer core.setRequestAllocator(null);

    const iterations: usize = if (init.environ_map.get("BENCH_ITERS")) |v|
        std.fmt.parseInt(usize, v, 10) catch 200
    else
        200;

    const suffix = core.unixNowMillis();
    const uid_a = try std.fmt.allocPrint(arena.allocator(), "bench_a_{d}", .{suffix});
    const uid_b = try std.fmt.allocPrint(arena.allocator(), "bench_b_{d}", .{suffix});

    // Register users once (registration is idempotency-limited by PK)
    _ = try auth_mod.registerWithPassword("Bench A", "test1234", "", null, null, uid_a);
    _ = try auth_mod.registerWithPassword("Bench B", "test1234", "", null, null, uid_b);

    // ── login benchmark ────────────────────────────────────────
    {
        const start = core.unixNowMillis();
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            _ = try auth_mod.loginWithPassword(uid_a, "test1234", 1);
        }
        const elapsed_s = @as(f64, @floatFromInt(core.unixNowMillis() - start)) / 1000.0;
        std.debug.print("login: {d} ops in {d:.3}s = {d:.0} ops/s\n", .{ iterations, elapsed_s, @as(f64, @floatFromInt(iterations)) / elapsed_s });
    }

    // ── friend request benchmark ───────────────────────────────
    {
        const start = core.unixNowMillis();
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            _ = try friend_mod.sendFriendRequest(uid_a, uid_b, "bench");
        }
        const elapsed_s = @as(f64, @floatFromInt(core.unixNowMillis() - start)) / 1000.0;
        std.debug.print("friend request: {d} ops in {d:.3}s = {d:.0} ops/s\n", .{ iterations, elapsed_s, @as(f64, @floatFromInt(iterations)) / elapsed_s });
    }

    // ── group create benchmark (transactional) ─────────────────
    {
        const start = core.unixNowMillis();
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            const gid = try std.fmt.allocPrint(arena.allocator(), "bench_g_{d}_{d}", .{ suffix, i });
            _ = try group_mod.createGroup(.{ .group_id = gid, .group_name = "Bench Group", .creator_user_id = uid_a });
        }
        const elapsed_s = @as(f64, @floatFromInt(core.unixNowMillis() - start)) / 1000.0;
        std.debug.print("group create: {d} ops in {d:.3}s = {d:.0} ops/s\n", .{ iterations, elapsed_s, @as(f64, @floatFromInt(iterations)) / elapsed_s });
    }

    // ── message send benchmark (needs friendship) ──────────────
    try friend_mod.respondFriendRequest(uid_a, uid_b, true, "ok");
    {
        const start = core.unixNowMillis();
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            _ = try message_mod.sendMessage(.{
                .send_id = uid_a,
                .recv_id = uid_b,
                .session_type = .single,
                .content_type = .text,
                .content = "benchmark message",
            });
        }
        const elapsed_s = @as(f64, @floatFromInt(core.unixNowMillis() - start)) / 1000.0;
        std.debug.print("message send: {d} ops in {d:.3}s = {d:.0} ops/s\n", .{ iterations, elapsed_s, @as(f64, @floatFromInt(iterations)) / elapsed_s });
    }

    std.debug.print("benchmark done ({d} iterations each)\n", .{iterations});
}
