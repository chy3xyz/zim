const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const db_mod = @import("../db_postgres.zig");
const config_mod = @import("../config.zig");
const service = @import("service.zig");

pub const info = zigmodu.api.Module{
    .name = "crontask",
    .description = "Background cron tasks: message cleanup, webhook delivery, stats refresh",
    .dependencies = &.{ "db_postgres", "config", "third" },
    .runtime = .{ .max_concurrent = 10 },
};

var g_running: bool = false;
var g_thread: ?std.Thread = null;
var g_io: ?std.Io = null;

pub fn setIo(io: std.Io) void {
    g_io = io;
}

var g_service: ?service.CrontaskService = null;

pub fn init() !void {
    g_running = true;
    const db = db_mod.getClient();
    g_service = service.CrontaskService.init(db);
    g_thread = try std.Thread.spawn(.{}, crontaskLoop, .{});
    std.log.info("Crontask module initialized", .{});
}

pub fn deinit() void {
    g_running = false;
    if (g_thread) |t| {
        t.join();
        g_thread = null;
    }
    std.log.info("Crontask module deinitialized", .{});
}

pub fn getService() *service.CrontaskService {
    return &g_service.?;
}

fn crontaskLoop() void {
    std.log.info("[Crontask] Background task loop started", .{});

    getService().ensureTables() catch {};

    var iteration: u64 = 0;
    var last_cfg_mtime: ?i128 = null;
    // Baseline at startup so any later change is detected on the first pass.
    if (g_io) |io| last_cfg_mtime = config_mod.configFileMtime(io);
    while (g_running) {
        iteration += 1;
        std.log.info("[Crontask] Running scheduled tasks (iteration {d})", .{iteration});

        service.deliverWebhookEvents(g_io orelse continue) catch |err| {
            std.log.err("[Crontask] deliverWebhookEvents failed: {}", .{err});
        };

        if (iteration % 12 == 1) {
            _ = getService().cleanupOldMessages(30) catch |err| {
                std.log.err("[Crontask] cleanupOldMessages failed: {}", .{err});
            };

            _ = getService().cleanupRevokedMessages() catch |err| {
                std.log.err("[Crontask] cleanupRevokedMessages failed: {}", .{err});
            };

            _ = getService().cleanupOldAuthTokens() catch |err| {
                std.log.err("[Crontask] cleanupOldAuthTokens failed: {}", .{err});
            };
        }

        // Report PGMQ queue depth (best-effort; skips when pgmq absent).
        if (getService().queueDepth() > 0) {
            core.metricQueueDepth(@intCast(getService().queueDepth()));
        }

        // 5-minute cadence, but in 1s slices so shutdown (g_running=false)
        // is prompt. Uses zigmodu/Io-native sleep (std.Thread.sleep was
        // removed in Zig 0.17; std.c.nanosleep did not actually sleep here).
        var remaining: u32 = 300;
        var slice: u32 = 0;
        while (remaining > 0 and g_running) : (remaining -= 1) {
            if (g_io) |io| std.Io.sleep(io, .{ .nanoseconds = 1_000_000_000 }, .real) catch {};
            // Config hot-reload: detect config.yaml changes every ~30s and
            // reload values read dynamically (webhook filters, log path).
            slice += 1;
            if (slice % 30 == 0) {
                if (config_mod.configFileMtime(g_io orelse continue)) |mt| {
                    if (last_cfg_mtime) |last| {
                        if (mt != last) {
                            config_mod.reload();
                            std.log.info("[Crontask] Config reloaded (config.yaml changed)", .{});
                        }
                    }
                    last_cfg_mtime = mt;
                }
            }
        }
    }
    std.log.info("[Crontask] Background task loop stopped", .{});
}
