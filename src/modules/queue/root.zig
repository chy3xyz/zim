const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const db_mod = @import("../db_postgres.zig");
const service = @import("service.zig");

pub const info = zigmodu.api.Module{
    .name = "queue",
    .description = "PGMQ message queue wrapper",
    .dependencies = &.{"db_postgres"},
    .runtime = .{ .max_concurrent = 50 },
};

var g_service: ?service.QueueService = null;

pub fn init() !void {
    const db = db_mod.getClient();
    g_service = service.QueueService.init(core.serviceAllocator(), db);
    std.log.info("QueueModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    if (g_service) |*s| s.deinit();
    g_service = null;
    std.log.info("QueueModule deinitialized", .{});
}

pub fn getService() *service.QueueService {
    return &g_service.?;
}
