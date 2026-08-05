const model = @import("queue/model.zig");
const persistence = @import("queue/persistence.zig");
const root = @import("queue/root.zig");

pub const info = root.info;
pub const init = root.init;
pub const deinit = root.deinit;

// Re-export models
pub const QueueMessage = model.QueueMessage;

// Backward-compatible alias
pub const QueueModule = persistence.QueuePersistence;

pub fn getQueue() *persistence.QueuePersistence {
    return &root.getService().pers;
}

// Public API functions
pub fn send(queue_name: []const u8, body: []const u8) !i64 {
    return root.getService().send(queue_name, body);
}

pub fn read(queue_name: []const u8, vt: i32) !?QueueMessage {
    return root.getService().read(queue_name, vt);
}

pub fn delete(queue_name: []const u8, msg_id: i64) !bool {
    return root.getService().delete(queue_name, msg_id);
}

pub fn archive(queue_name: []const u8, msg_id: i64) !bool {
    return root.getService().archive(queue_name, msg_id);
}

pub fn createQueue(queue_name: []const u8) !void {
    return root.getService().createQueue(queue_name);
}

pub fn purge(queue_name: []const u8) !void {
    return root.getService().purge(queue_name);
}

pub fn size(queue_name: []const u8) !usize {
    return root.getService().size(queue_name);
}

// Compatibility wrappers for push.zig
pub fn sendToQueue(queue_name: []const u8, body: []const u8) !i64 {
    return root.getService().send(queue_name, body);
}

pub fn readFromQueue(queue_name: []const u8, vt: i32) !?QueueMessage {
    return root.getService().read(queue_name, vt);
}

pub fn deleteFromQueue(queue_name: []const u8, msg_id: i64) !bool {
    return root.getService().delete(queue_name, msg_id);
}
