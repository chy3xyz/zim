const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const db_mod = @import("../db_postgres.zig");
const service = @import("service.zig");

pub const info = zigmodu.api.Module{
    .name = "office",
    .description = "Work moments and social features",
    .dependencies = &.{ "user", "db_postgres" },
    .runtime = .{ .max_concurrent = 50 },
};

pub var g_service: ?service.OfficeService = null;

pub fn init() !void {
    const db = db_mod.getClient();
    g_service = service.OfficeService.init(core.serviceAllocator(), db);
    std.log.info("OfficeModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    g_service = null;
    std.log.info("OfficeModule deinitialized", .{});
}

pub fn getService() *service.OfficeService {
    return &g_service.?;
}
