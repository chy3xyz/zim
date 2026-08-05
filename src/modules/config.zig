const model = @import("config/model.zig");
const service = @import("config/service.zig");
const root = @import("config/root.zig");

pub const info = root.info;
pub const init = root.init;
pub const deinit = root.deinit;

// Re-export models
pub const DatabaseConfig = model.DatabaseConfig;
pub const GatewayConfig = model.GatewayConfig;
pub const JwtConfig = model.JwtConfig;
pub const RedisConfig = model.RedisConfig;
pub const QueueConfig = model.QueueConfig;
pub const ObjectStorageConfig = model.ObjectStorageConfig;
pub const WebhookConfig = model.WebhookConfig;
pub const Config = model.Config;

// Re-export service API
pub const defaultConfig = service.ConfigService.defaultConfig;
pub const loadConfig = service.ConfigService.loadConfig;
pub const getConfig = root.getConfig;
pub const reload = root.reload;
pub const configFileMtime = root.configFileMtime;
