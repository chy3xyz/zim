const model = @import("db_postgres/model.zig");
const persistence = @import("db_postgres/persistence.zig");
const root = @import("db_postgres/root.zig");

pub const info = root.info;
pub const init = root.init;
pub const deinit = root.deinit;

// Re-export models
pub const QueryParam = model.QueryParam;
pub const QueryResult = model.QueryResult;

// Re-export persistence
pub const PostgresClient = persistence.PostgresClient;
pub const Tx = persistence.Tx;

// Re-export root API
pub const initDatabase = root.initDatabase;
pub const getClient = root.getClient;
pub const isInitialized = root.isInitialized;
pub const deinitDatabase = root.deinitDatabase;
