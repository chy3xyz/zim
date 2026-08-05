const std = @import("std");
const service = @import("crontask/service.zig");
const root = @import("crontask/root.zig");

pub const info = root.info;
pub const init = root.init;
pub const deinit = root.deinit;

// Re-export public functions
pub fn setIo(io: std.Io) void {
    root.setIo(io);
}

pub fn getService() *service.CrontaskService {
    return root.getService();
}
