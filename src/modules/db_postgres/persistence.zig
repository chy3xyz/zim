const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const c = @import("libpq");
const model = @import("model.zig");

/// Allocate a null-terminated copy (replaces removed allocator.dupeZ in Zig 0.17).
fn dupZ(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const out = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(out[0..s.len], s);
    return out;
}

fn recordResult(rt: ?*zmodu.ModuleRuntime, ok: bool) void {
    if (rt) |r| {
        if (ok) r.recordSuccess() else r.recordFailure();
    }
}

const BuiltParams = struct {
    owned: []?[:0]u8,
    values: []?[*:0]const u8,
    lengths: []c_int,
    formats: []c_int,
    sql_z: [:0]u8,
};

/// Serialize QueryParam values into libpq C arrays (owned strings kept for
/// exact-length freeing). The same routine serves pooled queries and Tx.
fn buildParams(allocator: std.mem.Allocator, sql: []const u8, params: []const model.QueryParam) !BuiltParams {
    const n = params.len;
    const owned = try allocator.alloc(?[:0]u8, n);
    errdefer allocator.free(owned);
    const values = try allocator.alloc(?[*:0]const u8, n);
    errdefer allocator.free(values);
    const lengths = try allocator.alloc(c_int, n);
    errdefer allocator.free(lengths);
    const formats = try allocator.alloc(c_int, n);
    errdefer allocator.free(formats);

    for (params, 0..) |param, i| {
        formats[i] = 0;
        switch (param) {
            .string => |s| {
                const nt = try dupZ(allocator, s);
                owned[i] = nt;
                values[i] = nt.ptr;
                lengths[i] = @intCast(s.len);
            },
            .int => |v| {
                const buf = try std.fmt.allocPrint(allocator, "{d}", .{v});
                defer allocator.free(buf);
                const nt = try dupZ(allocator, buf);
                owned[i] = nt;
                values[i] = nt.ptr;
                lengths[i] = @intCast(buf.len);
            },
            .bigint => |v| {
                const buf = try std.fmt.allocPrint(allocator, "{d}", .{v});
                defer allocator.free(buf);
                const nt = try dupZ(allocator, buf);
                owned[i] = nt;
                values[i] = nt.ptr;
                lengths[i] = @intCast(buf.len);
            },
            .smallint => |v| {
                const buf = try std.fmt.allocPrint(allocator, "{d}", .{v});
                defer allocator.free(buf);
                const nt = try dupZ(allocator, buf);
                owned[i] = nt;
                values[i] = nt.ptr;
                lengths[i] = @intCast(buf.len);
            },
            .bool => |v| {
                owned[i] = null;
                values[i] = if (v) "t" else "f";
                lengths[i] = 1;
            },
            .string_array => |arr| {
                var buf = std.ArrayList(u8).empty;
                try buf.append(allocator, '{');
                for (arr, 0..) |s, j| {
                    if (j > 0) try buf.append(allocator, ',');
                    try buf.append(allocator, '"');
                    for (s) |ch| {
                        if (ch == '"' or ch == '\\') try buf.append(allocator, '\\');
                        try buf.append(allocator, ch);
                    }
                    try buf.append(allocator, '"');
                }
                try buf.append(allocator, '}');
                const arr_str = try buf.toOwnedSlice(allocator);
                const nt = try dupZ(allocator, arr_str);
                allocator.free(arr_str);
                owned[i] = nt;
                values[i] = nt.ptr;
                lengths[i] = @intCast(arr_str.len);
            },
            .null => {
                owned[i] = null;
                values[i] = null;
                lengths[i] = 0;
            },
        }
    }

    const sql_z = try dupZ(allocator, sql);
    errdefer allocator.free(sql_z);
    return .{ .owned = owned, .values = values, .lengths = lengths, .formats = formats, .sql_z = sql_z };
}

fn freeParams(allocator: std.mem.Allocator, p: *const BuiltParams) void {
    for (p.owned) |o| {
        if (o) |os| allocator.free(os);
    }
    allocator.free(p.owned);
    allocator.free(p.values);
    allocator.free(p.lengths);
    allocator.free(p.formats);
    allocator.free(p.sql_z);
}

fn queryParamsOn(allocator: std.mem.Allocator, conn: *c.PGconn, sql: []const u8, params: []const model.QueryParam) !model.QueryResult {
    var bp = try buildParams(allocator, sql, params);
    defer freeParams(allocator, &bp);
    const start_ms = zmodu.time.monotonicNowMilliseconds();

    const result = c.PQexecParams(conn, bp.sql_z.ptr, @intCast(params.len), null, bp.values.ptr, bp.lengths.ptr, bp.formats.ptr, 0);
    if (result == null) return error.QueryFailed;
    const status = c.PQresultStatus(result);
    if (status != c.PGRES_TUPLES_OK and status != c.PGRES_COMMAND_OK) {
        const err_msg = c.PQerrorMessage(conn);
        core.logJson(.{ .event = "db_query_failed", .module = "db_postgres", .err = std.mem.span(err_msg) });
        c.PQclear(result);
        return error.QueryFailed;
    }

    const row_count = @as(usize, @intCast(c.PQntuples(result)));
    const col_count = @as(usize, @intCast(c.PQnfields(result)));
    var rows = std.ArrayList([]const []const u8).empty;
    errdefer {
        for (rows.items) |row| allocator.free(row);
        rows.deinit(allocator);
    }
    for (0..row_count) |r| {
        var row = std.ArrayList([]const u8).empty;
        defer row.deinit(allocator);
        for (0..col_count) |c_| {
            const val = c.PQgetvalue(result, @intCast(r), @intCast(c_));
            if (val) |v| {
                // MUST dupe: `PQgetvalue` points into the libpq result, which
                // is freed by `PQclear` below — storing the slice as-is leaves
                // every result string dangling (intermittent garbage reads /
                // parse failures once the freed memory is reused).
                try row.append(allocator, try allocator.dupe(u8, std.mem.span(v)));
            } else {
                try row.append(allocator, "");
            }
        }
        try rows.append(allocator, try row.toOwnedSlice(allocator));
    }
    const cmd_tuples = c.PQcmdTuples(result);
    var affected: usize = 0;
    if (cmd_tuples[0] != 0) {
        affected = std.fmt.parseInt(usize, std.mem.span(cmd_tuples), 10) catch 0;
    }
    const owned_rows = try rows.toOwnedSlice(allocator);
    c.PQclear(result);
    const elapsed_ms = zmodu.time.monotonicNowMilliseconds() - start_ms;
    // Slow-query log (>=200ms) for perf triage.
    core.metricDbDuration(@as(f64, @floatFromInt(elapsed_ms)) / 1000.0);
    if (elapsed_ms >= 200) {
        core.logJson(.{ .event = "db_slow_query", .module = "db_postgres", .duration_ms = elapsed_ms });
    }
    return model.QueryResult{ .rows = owned_rows, .row_count = row_count, .affected_rows = affected };
}

fn execParamsOn(allocator: std.mem.Allocator, conn: *c.PGconn, sql: []const u8, params: []const model.QueryParam) !usize {
    var bp = try buildParams(allocator, sql, params);
    defer freeParams(allocator, &bp);

    const result = c.PQexecParams(conn, bp.sql_z.ptr, @intCast(params.len), null, bp.values.ptr, bp.lengths.ptr, bp.formats.ptr, 0);
    if (result == null) return error.ExecFailed;
    const status = c.PQresultStatus(result);
    if (status != c.PGRES_COMMAND_OK) {
        const err_msg = c.PQerrorMessage(conn);
        core.logJson(.{ .event = "db_exec_failed", .module = "db_postgres", .err = std.mem.span(err_msg) });
        c.PQclear(result);
        return error.ExecFailed;
    }
    const cmd_tuples = c.PQcmdTuples(result);
    var affected: usize = 0;
    if (cmd_tuples[0] != 0) {
        affected = std.fmt.parseInt(usize, std.mem.span(cmd_tuples), 10) catch 0;
    }
    c.PQclear(result);
    return affected;
}

/// A transaction pins one pooled connection for its lifetime.
pub const Tx = struct {
    client: *PostgresClient,
    idx: usize,
    conn: *c.PGconn,
    finished: bool = false,

    pub fn execParams(self: *Tx, sql: []const u8, params: []const model.QueryParam) !usize {
        return execParamsOn(self.client.allocator, self.conn, sql, params);
    }

    pub fn queryParams(self: *Tx, sql: []const u8, params: []const model.QueryParam) !model.QueryResult {
        return queryParamsOn(self.client.allocator, self.conn, sql, params);
    }

    pub fn commit(self: *Tx) !void {
        defer self.finish();
        _ = try self.execParams("COMMIT", &.{});
    }

    pub fn rollback(self: *Tx) void {
        defer self.finish();
        _ = self.execParams("ROLLBACK", &.{}) catch {};
    }

    fn finish(self: *Tx) void {
        if (self.finished) return;
        self.finished = true;
        self.client.release(self.idx);
    }
};

/// Maximum concurrent connections in the pool. Queries run on different
/// connections in parallel; each connection is owned by exactly one caller
/// at a time (busy flags are the pool's lock).
pub const MAX_POOL = 8;

pub const PostgresClient = struct {
    allocator: std.mem.Allocator,
    conn_str: []const u8,
    connections: [MAX_POOL]?*c.PGconn = @splat(null),
    conn_busy: [MAX_POOL]bool = @splat(false),
    pool_size: usize = 1,
    connected: bool,
    /// Per-module runtime (bulkhead + circuit breaker), set by db_postgres/root.zig.
    runtime: ?*zmodu.ModuleRuntime = null,
    /// Guards pool-wide state (connect/close/pool_size). Individual queries
    /// acquire a private connection slot and do not hold this mutex.
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(allocator: std.mem.Allocator, conn_str: []const u8, pool_size: usize) PostgresClient {
        const size = @min(@max(pool_size, 1), MAX_POOL);
        return PostgresClient{
            .allocator = allocator,
            .conn_str = conn_str,
            .pool_size = size,
            .connected = false,
        };
    }

    fn acquire(self: *PostgresClient) usize {
        while (true) {
            for (0..self.pool_size) |i| {
                if (!self.conn_busy[i]) {
                    self.conn_busy[i] = true;
                    return i;
                }
            }
            std.atomic.spinLoopHint();
        }
    }

    fn release(self: *PostgresClient, idx: usize) void {
        self.conn_busy[idx] = false;
    }

    /// Return a healthy connection for slot `idx`, reconnecting if the
    /// server dropped it (libpq PQreset, no-op when the connection is fine).
    fn ensureHealthy(self: *PostgresClient, idx: usize) !*c.PGconn {
        const conn = self.connections[idx] orelse return error.NotConnected;
        if (c.PQstatus(conn) != c.CONNECTION_OK) {
            c.PQreset(conn);
            if (c.PQstatus(conn) != c.CONNECTION_OK) return error.NotConnected;
        }
        return conn;
    }

    pub fn connect(self: *PostgresClient) !void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        std.log.info("PostgreSQL connecting (pool size {d})...", .{self.pool_size});
        for (0..self.pool_size) |i| {
            const conn = c.PQconnectdb(self.conn_str.ptr);
            if (conn == null or c.PQstatus(conn) != c.CONNECTION_OK) {
                if (conn) |bad| {
                    core.logJson(.{ .event = "db_conn_failed", .module = "db_postgres", .err = std.mem.span(c.PQerrorMessage(bad)) });
                    c.PQfinish(bad);
                }
                for (0..i) |j| {
                    if (self.connections[j]) |good| c.PQfinish(good);
                    self.connections[j] = null;
                }
                self.connected = false;
                return error.ConnectionFailed;
            }
            self.connections[i] = conn;
        }
        self.connected = true;
        std.log.info("PostgreSQL pool ready ({d} connections)", .{self.pool_size});
    }

    pub fn close(self: *PostgresClient) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        for (0..self.pool_size) |i| {
            if (self.connections[i]) |conn| {
                c.PQfinish(conn);
                self.connections[i] = null;
            }
        }
        self.connected = false;
        std.log.info("PostgreSQL connection closed", .{});
    }

    pub fn query(self: *PostgresClient, sql: []const u8) !model.QueryResult {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        if (self.runtime) |rt| {
            if (!rt.tryEnter()) return error.DatabaseBusy;
            defer rt.release();
        }
        errdefer recordResult(self.runtime, false);
        if (!self.connected) return error.NotConnected;
        const pool_idx = self.acquire();
        defer self.release(pool_idx);
        const conn = try self.ensureHealthy(pool_idx);

        // PQexec needs a NUL-terminated C string; allocPrint'd SQL is not.
        const sql_z = try dupZ(self.allocator, sql);
        defer self.allocator.free(sql_z);
        const start_ms = zmodu.time.monotonicNowMilliseconds();
        const result = c.PQexec(conn, sql_z.ptr);
        if (result == null) {
            return error.QueryFailed;
        }

        const status = c.PQresultStatus(result);
        if (status != c.PGRES_TUPLES_OK and status != c.PGRES_COMMAND_OK) {
            const err_msg = c.PQerrorMessage(conn);
            core.logJson(.{ .event = "db_query_failed", .module = "db_postgres", .err = std.mem.span(err_msg) });
            c.PQclear(result);
            return error.QueryFailed;
        }
        const row_count = @as(usize, @intCast(c.PQntuples(result)));
        const col_count = @as(usize, @intCast(c.PQnfields(result)));
        var rows = std.ArrayList([]const []const u8).empty;
        errdefer {
            for (rows.items) |row| {
                self.allocator.free(row);
            }
            rows.deinit(self.allocator);
        }

        for (0..row_count) |r| {
            var row = std.ArrayList([]const u8).empty;
            defer row.deinit(self.allocator);
            for (0..col_count) |c_| {
                const val = c.PQgetvalue(result, @as(c_int, @intCast(r)), @as(c_int, @intCast(c_)));
                if (val) |v| {
                    // dupe out of libpq result memory — freed by PQclear below.
                    try row.append(self.allocator, try self.allocator.dupe(u8, std.mem.span(v)));
                } else {
                    try row.append(self.allocator, "");
                }
            }
            try rows.append(self.allocator, try row.toOwnedSlice(self.allocator));
        }

        const cmd_tuples = c.PQcmdTuples(result);
        var affected: usize = 0;
        if (cmd_tuples[0] != 0) {
            affected = std.fmt.parseInt(usize, std.mem.span(cmd_tuples), 10) catch 0;
        }
        const owned_rows = try rows.toOwnedSlice(self.allocator);
        c.PQclear(result);
        recordResult(self.runtime, true);
        const elapsed_ms = zmodu.time.monotonicNowMilliseconds() - start_ms;
        core.metricDbDuration(@as(f64, @floatFromInt(elapsed_ms)) / 1000.0);
        if (elapsed_ms >= 200) {
            core.logJson(.{ .event = "db_slow_query", .module = "db_postgres", .duration_ms = elapsed_ms });
        }

        return model.QueryResult{
            .rows = owned_rows,
            .row_count = row_count,
            .affected_rows = affected,
        };
    }

    pub fn exec(self: *PostgresClient, sql: []const u8) !usize {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        if (self.runtime) |rt| {
            if (!rt.tryEnter()) return error.DatabaseBusy;
            defer rt.release();
        }
        errdefer recordResult(self.runtime, false);
        if (!self.connected) return error.NotConnected;
        const pool_idx = self.acquire();
        defer self.release(pool_idx);
        const conn = try self.ensureHealthy(pool_idx);
        const sql_z = try dupZ(self.allocator, sql);
        defer self.allocator.free(sql_z);
        const start_ms = zmodu.time.monotonicNowMilliseconds();
        const result = c.PQexec(conn, sql_z.ptr);
        if (result == null) {
            return error.ExecFailed;
        }

        const status = c.PQresultStatus(result);
        if (status != c.PGRES_COMMAND_OK) {
            const err_msg = c.PQerrorMessage(conn);
            core.logJson(.{ .event = "db_exec_failed", .module = "db_postgres", .err = std.mem.span(err_msg) });
            c.PQclear(result);
            return error.ExecFailed;
        }

        const cmd_tuples = c.PQcmdTuples(result);
        var affected: usize = 0;
        if (cmd_tuples[0] != 0) {
            affected = std.fmt.parseInt(usize, std.mem.span(cmd_tuples), 10) catch 0;
        }
        c.PQclear(result);
        recordResult(self.runtime, true);
        const elapsed_ms = zmodu.time.monotonicNowMilliseconds() - start_ms;
        core.metricDbDuration(@as(f64, @floatFromInt(elapsed_ms)) / 1000.0);
        if (elapsed_ms >= 200) {
            core.logJson(.{ .event = "db_slow_exec", .module = "db_postgres", .duration_ms = elapsed_ms });
        }
        return affected;
    }

    /// Start a transaction — pins one pooled connection until commit/rollback.
    pub fn begin(self: *PostgresClient) !Tx {
        if (!self.connected) return error.NotConnected;
        const idx = self.acquire();
        errdefer self.release(idx);
        const conn = try self.ensureHealthy(idx);
        _ = c.PQexec(conn, "BEGIN");
        if (c.PQstatus(conn) != c.CONNECTION_OK) return error.TxBeginFailed;
        return Tx{ .client = self, .idx = idx, .conn = conn };
    }

    pub fn queryParams(self: *PostgresClient, sql: []const u8, params: []const model.QueryParam) !model.QueryResult {
        if (!self.connected) return error.NotConnected;
        const pool_idx = self.acquire();
        defer self.release(pool_idx);
        const conn = try self.ensureHealthy(pool_idx);
        return queryParamsOn(self.allocator, conn, sql, params);
    }

    pub fn execParams(self: *PostgresClient, sql: []const u8, params: []const model.QueryParam) !usize {
        if (!self.connected) return error.NotConnected;
        const pool_idx = self.acquire();
        defer self.release(pool_idx);
        const conn = try self.ensureHealthy(pool_idx);
        return execParamsOn(self.allocator, conn, sql, params);
    }

    pub fn deinit(self: *PostgresClient) void {
        if (self.connected) self.close();
        if (self.conn_str.len > 0) self.allocator.free(self.conn_str);
    }
};
