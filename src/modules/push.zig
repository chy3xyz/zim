const model = @import("push/model.zig");
const service = @import("push/service.zig");
const persistence = @import("push/persistence.zig");
const root = @import("push/root.zig");

pub const info = root.info;
pub const init = root.init;
pub const deinit = root.deinit;

// Re-export models
pub const PushProvider = model.PushProvider;
pub const PushMessage = model.PushMessage;

// Backward-compatible alias
pub const PushModule = persistence.PushPersistence;

pub fn getPush() *persistence.PushPersistence {
    return &root.getService().pers;
}

// Public API functions
pub fn sendPushNotification(user_id: []const u8, title: []const u8, body: []const u8, payload: []const u8) !void {
    try root.getService().sendPush(model.PushMessage{
        .user_id = user_id,
        .title = title,
        .body = body,
        .payload = payload,
        .badge = 1,
        .sound = "default",
        .provider = .fcm,
    });
}

// Event handlers
pub const onMessageSent = service.onMessageSent;
pub const onMessageRecalled = service.onMessageRecalled;
