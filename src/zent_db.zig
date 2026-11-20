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
const db_mod = @import("modules/db_postgres.zig");

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

/// Legacy-executor adapter: wraps a zent Driver behind the db_postgres
/// executor interface (queryParams/execParams/query) so persistence code
/// written for `*PostgresClient` / `*db_mod.Tx` runs unmodified on the zent
/// pool — inside a TxClient transaction this keeps multi-statement atomicity
/// on one connection while the SQL migrates to typed builders incrementally.
///
/// Result strings are duplicated into `alloc` (the caller's free loops own
/// them) — the zent Rows backing memory dies at rows.deinit(), and handing
/// out borrowed spans would recreate the Phase 60 use-after-free class.
pub const LegacyExecAdapter = struct {
    // sql_driver.Tx and Driver share the query/exec surface; the adapter
    // serves the transaction path, so it binds the Tx handle.
    drv: zent.sql_driver.Tx,
    alloc: std.mem.Allocator,

    fn toValue(p: db_mod.QueryParam) zent.sql.Value {
        return switch (p) {
            .string => |v| .{ .string = v },
            .int, .bigint => |v| .{ .int = v },
            .smallint => |v| .{ .int = v },
            .bool => |v| .{ .bool = v },
            // No caller in the zent-tx slice passes arrays; fail loud rather
            // than silently writing NULL through the adapter.
            .string_array => @panic("string_array unsupported through LegacyExecAdapter"),
            .null => .null,
        };
    }

    fn rowsToResult(self: *const LegacyExecAdapter, rows: *zent.sql_driver.Rows) !db_mod.QueryResult {
        var list = std.ArrayList([]const []const u8).empty;
        errdefer {
            for (list.items) |row| {
                for (row) |cell| self.alloc.free(cell);
                self.alloc.free(row);
            }
            list.deinit(self.alloc);
        }
        while (rows.next()) |row| {
            const n = row.columnCount();
            const cells = try self.alloc.alloc([]const u8, n);
            errdefer self.alloc.free(cells);
            for (0..n) |i| {
                const text = row.getText(i) orelse "";
                cells[i] = try self.alloc.dupe(u8, text);
            }
            try list.append(self.alloc, cells);
        }
        if (rows.nextError()) |err| return err;
        const row_count = list.items.len;
        return db_mod.QueryResult{
            .rows = try list.toOwnedSlice(self.alloc),
            .row_count = row_count,
            .affected_rows = 0,
        };
    }

    pub fn queryParams(self: *const LegacyExecAdapter, sql_text: []const u8, params: []const db_mod.QueryParam) !db_mod.QueryResult {
        const values = try self.alloc.alloc(zent.sql.Value, params.len);
        defer self.alloc.free(values);
        for (params, 0..) |p, i| values[i] = toValue(p);
        var rows = try self.drv.query(sql_text, values);
        defer rows.deinit();
        return rowsToResult(self, &rows);
    }

    pub fn execParams(self: *const LegacyExecAdapter, sql_text: []const u8, params: []const db_mod.QueryParam) !usize {
        const values = try self.alloc.alloc(zent.sql.Value, params.len);
        defer self.alloc.free(values);
        for (params, 0..) |p, i| values[i] = toValue(p);
        const res = try self.drv.exec(sql_text, values);
        return res.rows_affected;
    }

    pub fn query(self: *const LegacyExecAdapter, sql_text: []const u8) !db_mod.QueryResult {
        var rows = try self.drv.query(sql_text, &.{});
        defer rows.deinit();
        return rowsToResult(self, &rows);
    }

    pub fn exec(self: *const LegacyExecAdapter, sql_text: []const u8) !usize {
        const res = try self.drv.exec(sql_text, &.{});
        return res.rows_affected;
    }
};

/// TxClient view for the zent transaction channel (sendInTx slice).
pub const TxClientType = zent.codegen.client.TxClient(schema_infos);

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
