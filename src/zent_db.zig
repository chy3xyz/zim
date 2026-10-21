//! zent ORM DB layer (Phase-0 pilot) — schema graph + pooled client holder.
//!
//! Mirrors the zmshop_zent integration pattern: a `ConnPool(PostgresDriver)`
//! feeds a typed zent client built from `zent_schemas.zig`. Persistence code
//! calls `getClient()` and uses the typed builders (`crud_helpers` sugar) so
//! new tables migrate off the hand-written SQL incrementally, coexisting
//! with the legacy `db_postgres` client on the same database.
//!
//! Concurrency: the client sits on a connection pool (one libpq connection
//! per borrowed operation). A single shared `PostgresDriver` would race the
//! wire protocol under concurrent handlers. `health_check_on_borrow` stays
//! off — ping-under-mutex can deadlock under load; pool max_idle/max_lifetime
//! eviction covers health instead.
//!
//! Config strings are duplicated at init: `[database]` values may be swapped
//! by config hot-reload, and the pool's async reconnect context must not
//! dangle.

const std = @import("std");
const zent = @import("zent");
const schemas = @import("zent_schemas.zig");

const graph = zent.codegen.graph.buildGraph(schemas.all);
pub const ClientType = zent.codegen.client.Client(graph.types);
/// TypeInfo array consumed by `zent.codegen.deinitEntity` when freeing rows.
pub const schema_infos = graph.types;

const Pool = zent.sql_pool.ConnPool(zent.sql_postgres.PostgresDriver);

const ConnectCtx = struct {
    host: []u8,
    port: u16,
    dbname: []u8,
    user: []u8,
    password: []u8,
};

var g_pool: ?*Pool = null;
var g_connect_ctx: ?*ConnectCtx = null;
var g_client: ClientType = undefined;
var g_allocator: std.mem.Allocator = undefined;
var g_initialized = false;

pub fn init(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    dbname: []const u8,
    user: []const u8,
    password: []const u8,
) !void {
    if (g_initialized) return;

    const connect_ctx = try allocator.create(ConnectCtx);
    errdefer allocator.destroy(connect_ctx);
    connect_ctx.* = .{
        .host = try allocator.dupe(u8, host),
        .port = port,
        .dbname = try allocator.dupe(u8, dbname),
        .user = try allocator.dupe(u8, user),
        .password = try allocator.dupe(u8, password),
    };
    errdefer {
        allocator.free(connect_ctx.host);
        allocator.free(connect_ctx.dbname);
        allocator.free(connect_ctx.user);
        allocator.free(connect_ctx.password);
    }

    const pool = try allocator.create(Pool);
    errdefer allocator.destroy(pool);
    pool.* = try Pool.init(allocator, .{
        .min_connections = 1,
        .max_connections = 4,
        .health_check_on_borrow = false,
        .connect_ctx = connect_ctx,
        .connectCtx = struct {
            fn f(ctx: ?*anyopaque, a: std.mem.Allocator) anyerror!zent.sql_postgres.PostgresDriver {
                const c: *const ConnectCtx = @ptrCast(@alignCast(ctx.?));
                return zent.sql_postgres.PostgresDriver.connectDb(a, c.host, c.port, c.dbname, c.user, c.password);
            }
        }.f,
        .max_retries = 4,
        .retry_backoff_ms = 5,
    });
    errdefer pool.deinit();

    g_pool = pool;
    g_connect_ctx = connect_ctx;
    g_client = zent.codegen.client.makeClient(graph.types, allocator, pool.asDriver());
    g_allocator = allocator;
    g_initialized = true;
}

pub fn deinit() void {
    if (!g_initialized) return;
    g_pool.?.deinit();
    g_allocator.destroy(g_pool.?);
    const c = g_connect_ctx.?;
    g_allocator.free(c.host);
    g_allocator.free(c.dbname);
    g_allocator.free(c.user);
    g_allocator.free(c.password);
    g_allocator.destroy(c);
    g_pool = null;
    g_connect_ctx = null;
    g_initialized = false;
}

pub fn getClient() ?*ClientType {
    return if (g_initialized) &g_client else null;
}

/// Pooled driver view (borrows/releases per op) for raw `sql_scan` DTO
/// queries — the pattern used to migrate hand-written row parsing while
/// keeping the SQL itself (see docs/zent-migration.md).
pub fn getDriver() ?zent.sql_driver.Driver {
    return if (g_initialized) g_pool.?.asDriver() else null;
}

pub fn getAllocator() std.mem.Allocator {
    return g_allocator;
}

/// Free one zent-owned row (string fields allocated by the client allocator).
pub fn deinitRow(comptime info: zent.codegen.graph.TypeInfo, row: anytype) void {
    zent.codegen.deinitEntity(schema_infos, info, row, getAllocator());
}
