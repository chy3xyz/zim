const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const service = @import("service.zig");

pub const info = zigmodu.api.Module{
    .name = "third",
    .description = "Third-party services: RustFS object storage, FCM tokens, logs",
    .dependencies = &.{ "config", "db_postgres" },
    .runtime = .{
        .cb_failure_threshold = 5,
        .cb_timeout_seconds = 30,
        .cb_half_open_max_calls = 2,
    },
};

var g_service: ?service.ThirdService = null;

pub fn init() !void {
    g_service = service.ThirdService.init(core.serviceAllocator());
    std.log.info("Third module init (deferred to main.zig)", .{});
}

pub fn deinit() void {
    if (g_service) |*s| s.deinit();
    g_service = null;
    std.log.info("Third module deinitialized", .{});
}

pub fn getService() *service.ThirdService {
    return &g_service.?;
}
