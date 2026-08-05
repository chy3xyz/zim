const std = @import("std");
const queue_mod = @import("../queue.zig");

pub const PushPersistence = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PushPersistence {
        return PushPersistence{ .allocator = allocator };
    }

    pub fn deinit(self: *PushPersistence) void {
        _ = self;
    }

    pub fn sendToQueue(self: *PushPersistence, queue_name: []const u8, body: []const u8) !i64 {
        _ = self;
        return queue_mod.sendToQueue(queue_name, body);
    }

    pub fn readFromQueue(self: *PushPersistence, queue_name: []const u8, vt: i32) !?queue_mod.QueueMessage {
        _ = self;
        return queue_mod.readFromQueue(queue_name, vt);
    }

    pub fn deleteFromQueue(self: *PushPersistence, queue_name: []const u8, msg_id: i64) !bool {
        _ = self;
        return queue_mod.deleteFromQueue(queue_name, msg_id);
    }
};
