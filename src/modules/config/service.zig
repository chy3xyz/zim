const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const model = @import("model.zig");

// Track heap-allocated config strings so the module can release them on
// shutdown (SafeAllocator reports them as leaks otherwise).
var g_cfg_allocations: ?std.ArrayList([]const u8) = null;

pub fn initConfigAllocations(allocator: std.mem.Allocator) void {
    _ = allocator;
    if (g_cfg_allocations != null) return;
    g_cfg_allocations = std.ArrayList([]const u8).empty;
}

pub fn deinitConfigAllocations(allocator: std.mem.Allocator) void {
    if (g_cfg_allocations) |*list| {
        for (list.items) |s| {
            if (s.len > 0) allocator.free(s);
        }
        list.deinit(allocator);
    }
    g_cfg_allocations = null;
}

fn dupeStr(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const d = try allocator.dupe(u8, s);
    if (g_cfg_allocations) |*list| {
        list.append(allocator, d) catch {};
    }
    return d;
}

pub const ConfigService = struct {
    pub fn defaultConfig() model.Config {
        return model.Config{
            .database = .{
                .host = "localhost",
                .port = 5432,
                .name = "zim",
                .user = "n0x",
                .password = "",
                .max_conns = 100,
                .min_conns = 10,
            },
            .gateway = .{
                .host = "0.0.0.0",
                .http_port = 10000,
                .ws_port = 10001,
                .login_policy = 1,
            },
            .jwt = .{
                .secret = "zim-secret-change-in-production",
                .expiry_hours = 7 * 24,
            },
            .redis = .{
                .host = "localhost",
                .port = 6379,
                .password = "",
                .db = 0,
            },
            .queue = .{
                .poll_timeout_ms = 5000,
            },
            .object_storage = .{
                .endpoint = "localhost:9000",
                .access_key = "zim",
                .secret_key = "zim-secret",
                .bucket = "zim-files",
                .region = "us-east-1",
                .use_ssl = false,
            },
            .webhook = .{
                .url = "",
                .secret = "",
                .enabled = false,
                .allowed_types = "",
                .denied_types = "",
                .attention_ids = "",
            },
        };
    }

    pub fn loadConfig(allocator: std.mem.Allocator) !model.Config {
        const paths = &[_][]const u8{ "config/config.yaml", "../config/config.yaml" };
        var content: ?[]u8 = null;
        const io = core.getIo();
        const dir = std.Io.Dir.cwd();
        for (paths) |path| {
            const st = dir.statFile(io, path, .{}) catch continue;
            if (st.size > 1024 * 64) continue;
            const buf = allocator.alloc(u8, @intCast(st.size)) catch continue;
            const read = dir.readFile(io, path, buf) catch {
                allocator.free(buf);
                continue;
            };
            if (read.len != st.size) {
                allocator.free(buf);
                continue;
            }
            content = buf;
            break;
        }
        if (content == null) {
            std.log.warn("Config file not found, using defaults", .{});
            return defaultConfig();
        }
        const c = content.?;
        defer allocator.free(c);

        var cfg = defaultConfig();
        // zigmodu YamlParser — INI-style `[section]` headers (canonical)
        if (!try applyYaml(allocator, c, &cfg)) {
            // Legacy fallback: indented YAML sections
            try applyLegacy(allocator, c, &cfg);
        }
        return cfg;
    }
};

/// zigmodu YamlParser path: flat `section.key` -> config value.
fn applyYaml(allocator: std.mem.Allocator, content: []const u8, cfg: *model.Config) !bool {
    var parser = zigmodu.YamlParser.init(allocator);
    var map = parser.parse(content) catch return false;
    defer parser.deinitMap(&map);
    if (map.count() == 0) return false;

    if (map.get("database.host")) |v| cfg.database.host = try dupeStr(allocator, v);
    if (map.get("database.port")) |v| cfg.database.port = parseUInt(u16, v, cfg.database.port);
    if (map.get("database.name")) |v| cfg.database.name = try dupeStr(allocator, v);
    if (map.get("database.user")) |v| cfg.database.user = try dupeStr(allocator, v);
    if (map.get("database.password")) |v| cfg.database.password = try dupeStr(allocator, v);
    if (map.get("database.max_conns")) |v| cfg.database.max_conns = parseUInt(u32, v, cfg.database.max_conns);
    if (map.get("database.min_conns")) |v| cfg.database.min_conns = parseUInt(u32, v, cfg.database.min_conns);

    if (map.get("gateway.host")) |v| cfg.gateway.host = try dupeStr(allocator, v);
    if (map.get("gateway.http_port")) |v| cfg.gateway.http_port = parseUInt(u16, v, cfg.gateway.http_port);
    if (map.get("gateway.ws_port")) |v| cfg.gateway.ws_port = parseUInt(u16, v, cfg.gateway.ws_port);
    if (map.get("gateway.login_policy")) |v| cfg.gateway.login_policy = parseUInt(u8, v, cfg.gateway.login_policy);

    if (map.get("jwt.secret")) |v| cfg.jwt.secret = try dupeStr(allocator, v);
    if (map.get("jwt.expiry_hours")) |v| cfg.jwt.expiry_hours = parseUInt(u32, v, cfg.jwt.expiry_hours);

    if (map.get("redis.host")) |v| cfg.redis.host = try dupeStr(allocator, v);
    if (map.get("redis.port")) |v| cfg.redis.port = parseUInt(u16, v, cfg.redis.port);
    if (map.get("redis.password")) |v| cfg.redis.password = try allocator.dupe(u8, v);
    if (map.get("redis.db")) |v| cfg.redis.db = parseUInt(u32, v, cfg.redis.db);

    if (map.get("queue.poll_timeout_ms")) |v| cfg.queue.poll_timeout_ms = parseUInt(u32, v, cfg.queue.poll_timeout_ms);

    if (map.get("object_storage.endpoint")) |v| cfg.object_storage.endpoint = try dupeStr(allocator, v);
    if (map.get("object_storage.access_key")) |v| cfg.object_storage.access_key = try dupeStr(allocator, v);
    if (map.get("object_storage.secret_key")) |v| cfg.object_storage.secret_key = try dupeStr(allocator, v);
    if (map.get("object_storage.bucket")) |v| cfg.object_storage.bucket = try dupeStr(allocator, v);
    if (map.get("object_storage.region")) |v| cfg.object_storage.region = try dupeStr(allocator, v);
    if (map.get("object_storage.use_ssl")) |v| cfg.object_storage.use_ssl = std.mem.eql(u8, std.mem.trim(u8, v, " \t\r\n"), "true");

    if (map.get("webhook.url")) |v| cfg.webhook.url = try dupeStr(allocator, v);
    if (map.get("webhook.secret")) |v| cfg.webhook.secret = try dupeStr(allocator, v);
    if (map.get("webhook.enabled")) |v| cfg.webhook.enabled = std.mem.eql(u8, std.mem.trim(u8, v, " \t\r\n"), "true");
    if (map.get("webhook.allowed_types")) |v| cfg.webhook.allowed_types = try dupeStr(allocator, v);
    if (map.get("webhook.denied_types")) |v| cfg.webhook.denied_types = try dupeStr(allocator, v);
    if (map.get("webhook.attention_ids")) |v| cfg.webhook.attention_ids = try dupeStr(allocator, v);
    if (map.get("log.file")) |v| cfg.log.file = try dupeStr(allocator, v);
    if (map.get("log.max_size")) |v| cfg.log.max_size = std.fmt.parseInt(u64, std.mem.trim(u8, v, " \t\r\n"), 10) catch cfg.log.max_size;

    return true;
}

fn parseUInt(comptime T: type, v: []const u8, default: T) T {
    return std.fmt.parseInt(T, std.mem.trim(u8, v, " \t\r\n\"'"), 10) catch default;
}

/// Legacy fallback: hand-rolled parsing of indented YAML sections.
fn applyLegacy(allocator: std.mem.Allocator, c: []const u8, cfg: *model.Config) !void {
    if (parseString(c, "host:", "database")) |v| cfg.database.host = try dupeStr(allocator, v);
    if (parseString(c, "port:", "database")) |v| {
        cfg.database.port = std.fmt.parseInt(u16, std.mem.trim(u8, v, " \t\r\n"), 10) catch cfg.database.port;
    }
    if (parseString(c, "name:", "database")) |v| cfg.database.name = try dupeStr(allocator, v);
    if (parseString(c, "user:", "database")) |v| cfg.database.user = try dupeStr(allocator, v);
    if (parseString(c, "password:", "database")) |v| cfg.database.password = try dupeStr(allocator, v);

    if (parseString(c, "http_port:", "gateway")) |v| {
        cfg.gateway.http_port = std.fmt.parseInt(u16, std.mem.trim(u8, v, " \t\r\n"), 10) catch cfg.gateway.http_port;
    }
    if (parseString(c, "ws_port:", "gateway")) |v| {
        cfg.gateway.ws_port = std.fmt.parseInt(u16, std.mem.trim(u8, v, " \t\r\n"), 10) catch cfg.gateway.ws_port;
    }
    if (parseString(c, "login_policy:", "gateway")) |v| {
        cfg.gateway.login_policy = std.fmt.parseInt(u8, std.mem.trim(u8, v, " \t\r\n"), 10) catch cfg.gateway.login_policy;
    }

    if (parseString(c, "secret:", "jwt")) |v| cfg.jwt.secret = try dupeStr(allocator, v);

    if (parseString(c, "endpoint:", "object_storage")) |v| cfg.object_storage.endpoint = try dupeStr(allocator, v);
    if (parseString(c, "access_key:", "object_storage")) |v| cfg.object_storage.access_key = try dupeStr(allocator, v);
    if (parseString(c, "secret_key:", "object_storage")) |v| cfg.object_storage.secret_key = try dupeStr(allocator, v);
    if (parseString(c, "bucket:", "object_storage")) |v| cfg.object_storage.bucket = try dupeStr(allocator, v);
    if (parseString(c, "region:", "object_storage")) |v| cfg.object_storage.region = try dupeStr(allocator, v);
    if (parseString(c, "use_ssl:", "object_storage")) |v| {
        const trimmed = std.mem.trim(u8, v, " \t\r\n");
        cfg.object_storage.use_ssl = std.mem.eql(u8, trimmed, "true");
    }

    if (parseString(c, "url:", "webhook")) |v| cfg.webhook.url = try dupeStr(allocator, v);
    if (parseString(c, "secret:", "webhook")) |v| cfg.webhook.secret = try dupeStr(allocator, v);
    if (parseString(c, "allowed_types:", "webhook")) |v| cfg.webhook.allowed_types = try dupeStr(allocator, v);
    if (parseString(c, "denied_types:", "webhook")) |v| cfg.webhook.denied_types = try dupeStr(allocator, v);
    if (parseString(c, "attention_ids:", "webhook")) |v| cfg.webhook.attention_ids = try dupeStr(allocator, v);
    if (parseString(c, "file:", "log")) |v| cfg.log.file = try dupeStr(allocator, v);
    if (parseString(c, "max_size:", "log")) |v| cfg.log.max_size = std.fmt.parseInt(u64, std.mem.trim(u8, v, " \t\r\n"), 10) catch cfg.log.max_size;
    if (parseString(c, "enabled:", "webhook")) |v| {
        const trimmed = std.mem.trim(u8, v, " \t\r\n");
        cfg.webhook.enabled = std.mem.eql(u8, trimmed, "true");
    }
}

fn parseString(content: []const u8, key: []const u8, section: []const u8) ?[]const u8 {
    const section_start = std.mem.indexOf(u8, content, section) orelse return null;
    const search_area = content[section_start..];
    const key_pos = std.mem.indexOf(u8, search_area, key) orelse return null;
    const value_start = key_pos + key.len;
    const line_end = std.mem.indexOf(u8, search_area[value_start..], "\n") orelse search_area.len - value_start;
    return std.mem.trim(u8, search_area[value_start .. value_start + line_end], " \t\r\n\"'");
}
