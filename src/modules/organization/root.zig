const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const db_mod = @import("../db_postgres.zig");
const service = @import("service.zig");

pub const info = zmodu.api.Module{
    .name = "organization",
    .description = "Organization and department management",
    .dependencies = &.{ "user", "db_postgres" },
    .runtime = .{ .max_concurrent = 50 },
};

var g_service: ?service.OrganizationService = null;

pub fn init() !void {
    const db = db_mod.getClient();
    g_service = service.OrganizationService.init(core.serviceAllocator(), db);
    std.log.info("OrganizationModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    if (g_service) |*s| s.pers.deinit();
    g_service = null;
    std.log.info("OrganizationModule deinitialized", .{});
}

pub fn getService() *service.OrganizationService {
    return &g_service.?;
}
