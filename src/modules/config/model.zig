pub const DatabaseConfig = struct {
    host: []const u8,
    port: u16,
    name: []const u8,
    user: []const u8,
    password: []const u8,
    max_conns: u32,
    min_conns: u32,
};

pub const GatewayConfig = struct {
    host: []const u8,
    http_port: u16,
    ws_port: u16,
    /// OpenIM multi-terminal login policy:
    /// 0=DefaultNotKick 1=AllLoginButSameTermKick 2=SingleTerminalLogin
    /// 3=WebAndOther 4=AllLoginButSameClassKick 5=PCAndOther 6=Customize
    login_policy: u8 = 1,
};

pub const JwtConfig = struct {
    /// When true, startup fails if the JWT secret is still the shipped default.
    require_strong_secret: bool = false,
    secret: []const u8,
    expiry_hours: u32,
};

pub const RedisConfig = struct {
    host: []const u8,
    port: u16,
    password: []const u8,
    db: u32,
};

pub const QueueConfig = struct {
    poll_timeout_ms: u32,
};

pub const ObjectStorageConfig = struct {
    endpoint: []const u8,
    access_key: []const u8,
    secret_key: []const u8,
    bucket: []const u8,
    region: []const u8,
    use_ssl: bool,
};

pub const WebhookConfig = struct {
    url: []const u8,
    secret: []const u8,
    enabled: bool,
    /// Message content-type filter (Go filterMsg): comma-separated single
    /// values or "start-end" intervals, e.g. "101,201-210". Empty = no filter.
    allowed_types: []const u8 = "",
    denied_types: []const u8 = "",
    /// When non-empty, type filtering only applies to messages whose sender
    /// or receiver is in this comma-separated user-id list (Go attentionIds).
    attention_ids: []const u8 = "",
};

pub const Config = struct {
    database: DatabaseConfig,
    gateway: GatewayConfig,
    jwt: JwtConfig,
    redis: RedisConfig,
    queue: QueueConfig,
    object_storage: ObjectStorageConfig,
    webhook: WebhookConfig,
    log: LogConfig = .{},
};

pub const LogConfig = struct {
    /// JSON log file path (empty = stderr only). Rotates to `<file>.1`.
    file: []const u8 = "",
    /// Rotation threshold in bytes.
    max_size: u64 = 64 * 1024 * 1024,
};
