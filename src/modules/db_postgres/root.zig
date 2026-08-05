const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const config_mod = @import("../config.zig");
const persistence = @import("persistence.zig");
const model = @import("model.zig");

pub const info = zigmodu.api.Module{
    .name = "db_postgres",
    .description = "PostgreSQL database module using libpq",
    .dependencies = &.{"config"},
    .runtime = .{
        .max_concurrent = 100,
        .cb_failure_threshold = 10,
        .cb_success_threshold = 2,
        .cb_timeout_seconds = 10,
        .cb_half_open_max_calls = 2,
    },
};

var global_client: ?persistence.PostgresClient = null;
var db_initialized: bool = false;

pub fn initDatabase(allocator: std.mem.Allocator, cfg: config_mod.DatabaseConfig) !void {
    const conn_str = try std.fmt.allocPrint(allocator, "host={s} port={d} dbname={s} user={s} password={s}", .{ cfg.host, cfg.port, cfg.name, cfg.user, cfg.password });

    global_client = persistence.PostgresClient.init(allocator, conn_str, cfg.max_conns);
    try global_client.?.connect();
    db_initialized = true;
}

pub fn getClient() *persistence.PostgresClient {
    return &global_client.?;
}

pub fn isInitialized() bool {
    return db_initialized;
}

fn freeQueryRows(allocator: std.mem.Allocator, result: model.QueryResult) void {
    for (result.rows) |row| {
        for (row) |cell| allocator.free(cell);
        allocator.free(row);
    }
    allocator.free(result.rows);
}

/// Apply pending SQL migrations from the `migrations/` directory and record
/// them in `schema_migrations`. A failed migration aborts startup with a
/// clear message instead of silently running against a stale schema.
pub fn ensureMigrations() !void {
    const io = core.getIo();
    const allocator = core.getGlobalAllocator();
    const client = &global_client.?;

    _ = client.exec("CREATE TABLE IF NOT EXISTS schema_migrations (filename VARCHAR(255) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())") catch {};

    var applied = std.StringHashMap(void).init(allocator);
    defer {
        var it = applied.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        applied.deinit();
    }
    const applied_q = try client.query("SELECT filename FROM schema_migrations");
    for (applied_q.rows) |row| {
        const key = allocator.dupe(u8, row[0]) catch continue;
        const gop = applied.getOrPut(key) catch {
            allocator.free(key);
            continue;
        };
        if (gop.found_existing) allocator.free(key);
    }
    freeQueryRows(allocator, applied_q);

    const cwd = std.Io.Dir.cwd();
    var names = std.ArrayList([]const u8).empty;
    defer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }
    var mig_path: []const u8 = "";
    for ([_][]const u8{ "migrations", "../migrations" }) |candidate| {
        const sub = cwd.openDir(io, candidate, .{ .iterate = true }) catch continue;
        defer sub.close(io);
        var it = std.Io.Dir.iterate(sub);
        while (try it.next(io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".sql")) continue;
            const name_copy = try allocator.dupe(u8, entry.name);
            try names.append(allocator, name_copy);
        }
        mig_path = candidate;
        break;
    }
    if (names.items.len == 0) {
        std.log.warn("[Migrations] migrations/ directory not found — skipping schema check", .{});
        return;
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    var applied_count: usize = 0;
    for (names.items) |name| {
        if (applied.contains(name)) continue;
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ mig_path, name });
        defer allocator.free(path);
        const st = cwd.statFile(io, path, .{}) catch continue;
        const buf = try allocator.alloc(u8, @intCast(st.size));
        defer allocator.free(buf);
        const content = try cwd.readFile(io, path, buf);
        _ = client.exec(content) catch |err| {
            std.log.err("[Migrations] FAILED to apply {s}: {s} — fix the migration or database and restart", .{ name, @errorName(err) });
            return error.MigrationFailed;
        };
        _ = client.execParams("INSERT INTO schema_migrations (filename) VALUES ($1) ON CONFLICT (filename) DO NOTHING", &.{.{ .string = name }}) catch {};
        std.log.info("[Migrations] applied {s}", .{name});
        applied_count += 1;
    }
    std.log.info("[Migrations] schema up to date ({d} applied this run)", .{applied_count});
}

pub fn deinitDatabase() void {
    if (global_client) |*client| {
        client.deinit();
        global_client = null;
    }
    db_initialized = false;
}

pub fn init() !void {
    const cfg = config_mod.getConfig();
    try initDatabase(core.serviceAllocator(), cfg.database);
    global_client.?.runtime = core.getModuleRuntime("db_postgres");
    try ensureMigrations();
    std.log.info("PostgresModule connected to {s}@{s}:{d}/{s}", .{ cfg.database.user, cfg.database.host, cfg.database.port, cfg.database.name });
}

pub fn deinit() void {
    deinitDatabase();
    std.log.info("PostgresModule deinitialized", .{});
}
