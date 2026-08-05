const std = @import("std");
const db_mod = @import("db_postgres.zig");

pub const model = @import("third/model.zig");
pub const persistence = @import("third/persistence.zig");
pub const service = @import("third/service.zig");
const root = @import("third/root.zig");

// Backward-compatible re-exports
pub const ObjectStorageConfig = model.ObjectStorageConfig;
pub const LogEntry = model.LogEntry;
pub const WebhookEvent = model.WebhookEvent;
pub const ThirdStorage = persistence.ThirdPersistence;

pub const info = root.info;
pub const init = root.init;
pub const deinit = root.deinit;

pub fn getStorage() *ThirdStorage {
    return &root.getService().pers;
}

pub fn initStorage(cfg: ObjectStorageConfig, db: *db_mod.PostgresClient, allocator: std.mem.Allocator) void {
    _ = allocator;
    root.getService().initStorage(cfg, db);
}

pub fn isInited() bool {
    return root.getService().isInited();
}

pub fn getConfig() ObjectStorageConfig {
    return root.getService().getConfig();
}

pub fn presignedUrl(allocator: std.mem.Allocator, method: []const u8, object_key: []const u8, expiry_seconds: u32) ![]const u8 {
    return root.getService().presignedUrl(allocator, method, object_key, expiry_seconds);
}

pub fn accessUrl(allocator: std.mem.Allocator, object_key: []const u8, expiry_seconds: u32) ![]const u8 {
    return root.getService().accessUrl(allocator, object_key, expiry_seconds);
}

pub fn saveFCMToken(user_id: []const u8, platform_id: i32, fcm_token: []const u8) !void {
    return root.getService().saveFCMToken(user_id, platform_id, fcm_token);
}

pub fn getFCMToken(user_id: []const u8, platform_id: i32) !?[]const u8 {
    return root.getService().getFCMToken(user_id, platform_id);
}

pub fn saveLog(user_id: []const u8, platform: i32, file_url: []const u8) !void {
    return root.getService().saveLog(user_id, platform, file_url);
}

pub fn searchLogs(allocator: std.mem.Allocator, user_id: ?[]const u8, platform: ?i32, start_time: ?i64, end_time: ?i64, page_number: i32, show_number: i32) !model.SearchLogsResult {
    return root.getService().searchLogs(allocator, user_id, platform, start_time, end_time, page_number, show_number);
}

pub fn queueWebhookEvent(event_type: []const u8, payload: []const u8) !void {
    return root.getService().queueWebhookEvent(event_type, payload);
}

pub fn getPendingWebhookEvents(allocator: std.mem.Allocator, limit: i32) !model.WebhookEventsResult {
    return root.getService().getPendingWebhookEvents(allocator, limit);
}

pub fn markWebhookEventDelivered(event_id: i32) !void {
    return root.getService().markWebhookEventDelivered(event_id);
}
