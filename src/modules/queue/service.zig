const std = @import("std");
const persistence = @import("persistence.zig");

pub const QueueService = struct {
    pers: persistence.QueuePersistence,

    pub fn init(allocator: std.mem.Allocator, db: *@import("../db_postgres.zig").PostgresClient) QueueService {
        return .{ .pers = persistence.QueuePersistence.init(allocator, db) };
    }

    pub fn deinit(self: *QueueService) void {
        self.pers.deinit();
    }

    pub fn createQueue(self: *QueueService, queue_name: []const u8) !void {
        return self.pers.createQueue(queue_name);
    }

    pub fn send(self: *QueueService, queue_name: []const u8, body: []const u8) !i64 {
        return self.pers.send(queue_name, body);
    }

    pub fn read(self: *QueueService, queue_name: []const u8, vt: i32) !?@import("model.zig").QueueMessage {
        return self.pers.read(queue_name, vt);
    }

    pub fn delete(self: *QueueService, queue_name: []const u8, msg_id: i64) !bool {
        return self.pers.delete(queue_name, msg_id);
    }

    pub fn archive(self: *QueueService, queue_name: []const u8, msg_id: i64) !bool {
        return self.pers.archive(queue_name, msg_id);
    }

    pub fn purge(self: *QueueService, queue_name: []const u8) !void {
        return self.pers.purge(queue_name);
    }

    pub fn size(self: *QueueService, queue_name: []const u8) !usize {
        return self.pers.size(queue_name);
    }
};
