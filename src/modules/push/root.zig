const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const service = @import("service.zig");

pub const info = zmodu.api.Module{
    .name = "push",
    .description = "Push notification worker - online filter, DND filter, FCM/APNs offline push queue",
    .dependencies = &.{
        "queue",
        "user",
        "conversation",
    },
    .runtime = .{
        .worker_count = 2,
        .max_concurrent = 100,
    },
};

var g_service: ?service.PushService = null;

pub fn init() !void {
    g_service = service.PushService.init(core.serviceAllocator());
    std.log.info("PushModule initialized", .{});
}

pub fn deinit() void {
    if (g_service) |*p| p.deinit();
    g_service = null;
    std.log.info("PushModule deinitialized", .{});
}

pub fn getService() *service.PushService {
    return &g_service.?;
}
