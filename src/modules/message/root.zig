const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const db_mod = @import("../db_postgres.zig");
const service = @import("service.zig");

pub const info = zigmodu.api.Module{
    .name = "message",
    .description = "Message storage - send, recall, delete, pagination, conversation auto-management",
    .dependencies = &.{
        "conversation",
        "group",
        "db_postgres",
    },
    .runtime = .{
        .max_concurrent = 200,
        .cb_failure_threshold = 10,
        .cb_timeout_seconds = 10,
    },
};

var g_service: ?service.MessageService = null;

pub fn init() !void {
    const db = db_mod.getClient();
    g_service = service.MessageService.init(core.serviceAllocator(), db);
    std.log.info("MessageModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    g_service = null;
    std.log.info("MessageModule deinitialized", .{});
}

pub fn getService() *service.MessageService {
    return &g_service.?;
}
