pub const ObjectStorageConfig = struct {
    endpoint: []const u8,
    access_key: []const u8,
    secret_key: []const u8,
    bucket: []const u8,
    region: []const u8,
    use_ssl: bool,
};

pub const LogEntry = struct {
    user_id: []const u8,
    platform: i32,
    file_url: []const u8,
    created_at: i64,
};

pub const WebhookEvent = struct {
    id: i32,
    event_type: []const u8,
    payload: []const u8,
};

pub const SearchLogsResult = struct {
    logs: []LogEntry,
    total: i32,
};

pub const WebhookEventsResult = struct {
    events: []WebhookEvent,
    total: i32,
};
