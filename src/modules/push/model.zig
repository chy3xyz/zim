pub const PushProvider = enum {
    fcm,
    apns,
    huawei,
    jpush,
    getui,
};

pub const PushMessage = struct {
    user_id: []const u8,
    title: []const u8,
    body: []const u8,
    payload: []const u8,
    badge: i32,
    sound: []const u8,
    provider: PushProvider,
};
