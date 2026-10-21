const std = @import("std");
const db_mod = @import("../../modules/db_postgres.zig");
const zent = @import("zent");
const zent_db = @import("../../zent_db.zig");
const model = @import("model.zig");

fn freeResult(allocator: std.mem.Allocator, result: db_mod.QueryResult) void {
    for (result.rows) |row| {
        for (row) |cell| allocator.free(cell);
        _ = allocator.free(row);
    }
    _ = allocator.free(result.rows);
}

pub const ThirdPersistence = struct {
    allocator: std.mem.Allocator,
    db: ?*db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: ?*db_mod.PostgresClient) ThirdPersistence {
        return .{ .allocator = allocator, .db = db };
    }

    pub fn saveFCMToken(self: *ThirdPersistence, user_id: []const u8, platform_id: i32, fcm_token: []const u8) !void {
        // zent path (preferred): same upsert through the pooled driver
        // (docs/zent-migration.md); NOW() columns are SQL-computed.
        if (zent_db.getDriver()) |drv| {
            _ = drv.exec(
                "INSERT INTO fcm_tokens (user_id, platform_id, fcm_token, updated_at) " ++
                    "VALUES ($1, $2, $3, NOW()) " ++
                    "ON CONFLICT (user_id, platform_id) DO UPDATE SET fcm_token = EXCLUDED.fcm_token, updated_at = NOW()",
                &.{ .{ .string = user_id }, .{ .int = platform_id }, .{ .string = fcm_token } },
            ) catch |err| {
                std.log.err("Failed to save FCM token: {}", .{err});
                return error.DatabaseError;
            };
            return;
        }
        const db = self.db orelse return error.NotInitialized;
        const sql = "INSERT INTO fcm_tokens (user_id, platform_id, fcm_token, updated_at) " ++
            "VALUES ($1, $2, $3, NOW()) " ++
            "ON CONFLICT (user_id, platform_id) DO UPDATE SET fcm_token = EXCLUDED.fcm_token, updated_at = NOW()";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .int = platform_id },
            .{ .string = fcm_token },
        };
        _ = db.execParams(sql, params) catch |err| {
            std.log.err("Failed to save FCM token: {}", .{err});
            return error.DatabaseError;
        };
    }

    pub fn getFCMToken(self: *ThirdPersistence, user_id: []const u8, platform_id: i32) !?[]const u8 {
        if (zent_db.getDriver()) |drv| {
            const Row = struct { fcm_token: []const u8 };
            const row = (zent.sql_scan.queryOne(
                Row,
                self.allocator,
                drv,
                "SELECT fcm_token FROM fcm_tokens WHERE user_id = $1 AND platform_id = $2 LIMIT 1",
                &.{ .{ .string = user_id }, .{ .int = platform_id } },
            ) catch return null) orelse return null;
            return row.fcm_token;
        }
        const db = self.db orelse return error.NotInitialized;
        const sql = "SELECT fcm_token FROM fcm_tokens WHERE user_id = $1 AND platform_id = $2 LIMIT 1";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .int = platform_id } };
        const result = db.queryParams(sql, params) catch return null;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return null;
        return try self.allocator.dupe(u8, result.rows[0][0]);
    }

    pub fn saveLog(self: *ThirdPersistence, user_id: []const u8, platform: i32, file_url: []const u8) !void {
        if (zent_db.getDriver()) |drv| {
            _ = drv.exec(
                "INSERT INTO app_logs (user_id, platform, file_url, created_at) VALUES ($1, $2, $3, NOW())",
                &.{ .{ .string = user_id }, .{ .int = platform }, .{ .string = file_url } },
            ) catch |err| {
                std.log.err("Failed to save log: {}", .{err});
                return error.DatabaseError;
            };
            return;
        }
        const db = self.db orelse return error.NotInitialized;
        const sql = "INSERT INTO app_logs (user_id, platform, file_url, created_at) VALUES ($1, $2, $3, NOW())";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .int = platform },
            .{ .string = file_url },
        };
        _ = db.execParams(sql, params) catch |err| {
            std.log.err("Failed to save log: {}", .{err});
            return error.DatabaseError;
        };
    }

    pub fn searchLogs(self: *ThirdPersistence, allocator: std.mem.Allocator, user_id: ?[]const u8, platform: ?i32, start_time: ?i64, end_time: ?i64, page_number: i32, show_number: i32) !model.SearchLogsResult {
        const db = self.db orelse return error.NotInitialized;

        var where_clause = std.ArrayList(u8).empty;
        defer where_clause.deinit(allocator);
        try where_clause.appendSlice(allocator, " WHERE 1=1");

        var params = std.ArrayList(db_mod.QueryParam).empty;
        defer params.deinit(allocator);
        var idx: i32 = 1;

        if (user_id) |uid| {
            const clause = try std.fmt.allocPrint(allocator, " AND user_id = ${d}", .{idx});
            defer allocator.free(clause);
            try where_clause.appendSlice(allocator, clause);
            try params.append(allocator, .{ .string = uid });
            idx += 1;
        }
        if (platform) |p| {
            const clause = try std.fmt.allocPrint(allocator, " AND platform = ${d}", .{idx});
            defer allocator.free(clause);
            try where_clause.appendSlice(allocator, clause);
            try params.append(allocator, .{ .int = p });
            idx += 1;
        }
        if (start_time) |st| {
            const clause = try std.fmt.allocPrint(allocator, " AND EXTRACT(EPOCH FROM created_at)::bigint >= ${d}", .{idx});
            defer allocator.free(clause);
            try where_clause.appendSlice(allocator, clause);
            try params.append(allocator, .{ .bigint = st });
            idx += 1;
        }
        if (end_time) |et| {
            const clause = try std.fmt.allocPrint(allocator, " AND EXTRACT(EPOCH FROM created_at)::bigint <= ${d}", .{idx});
            defer allocator.free(clause);
            try where_clause.appendSlice(allocator, clause);
            try params.append(allocator, .{ .bigint = et });
            idx += 1;
        }

        const where_str = try where_clause.toOwnedSlice(allocator);
        defer allocator.free(where_str);

        // Count total
        const count_sql = try std.fmt.allocPrint(allocator, "SELECT COUNT(*) FROM app_logs{s}", .{where_str});
        defer allocator.free(count_sql);

        var total: i32 = 0;
        const count_result = db.queryParams(count_sql, params.items) catch return error.DatabaseError;
        defer freeResult(allocator, count_result);
        if (count_result.row_count > 0) {
            total = std.fmt.parseInt(i32, count_result.rows[0][0], 10) catch 0;
        }

        // Query logs
        const offset = (page_number - 1) * show_number;
        const sql = try std.fmt.allocPrint(allocator, "SELECT user_id, platform, file_url, EXTRACT(EPOCH FROM created_at)::bigint " ++
            "FROM app_logs{s} ORDER BY created_at DESC LIMIT ${d} OFFSET ${d}", .{ where_str, idx, idx + 1 });
        defer allocator.free(sql);
        try params.append(allocator, .{ .int = show_number });
        try params.append(allocator, .{ .int = offset });

        const result = db.queryParams(sql, params.items) catch return error.DatabaseError;
        defer freeResult(allocator, result);

        var logs = try allocator.alloc(model.LogEntry, result.row_count);
        errdefer allocator.free(logs);

        for (0..result.row_count) |i| {
            const row = result.rows[i];
            logs[i] = .{
                .user_id = try allocator.dupe(u8, row[0]),
                .platform = try std.fmt.parseInt(i32, row[1], 10),
                .file_url = try allocator.dupe(u8, row[2]),
                .created_at = try std.fmt.parseInt(i64, row[3], 10),
            };
        }

        return model.SearchLogsResult{ .logs = logs, .total = total };
    }

    pub fn queueWebhookEvent(self: *ThirdPersistence, event_type: []const u8, payload: []const u8) !void {
        if (zent_db.getDriver()) |drv| {
            _ = drv.exec(
                "INSERT INTO webhook_events (event_type, payload, created_at, delivered) VALUES ($1, $2, NOW(), FALSE)",
                &.{ .{ .string = event_type }, .{ .string = payload } },
            ) catch |err| {
                std.log.err("Failed to queue webhook event: {}", .{err});
                return error.DatabaseError;
            };
            return;
        }
        const db = self.db orelse return error.NotInitialized;
        const sql = "INSERT INTO webhook_events (event_type, payload, created_at, delivered) VALUES ($1, $2, NOW(), FALSE)";
        const params = &[_]db_mod.QueryParam{ .{ .string = event_type }, .{ .string = payload } };
        _ = db.execParams(sql, params) catch |err| {
            std.log.err("Failed to queue webhook event: {}", .{err});
            return error.DatabaseError;
        };
    }

    pub fn getPendingWebhookEvents(self: *ThirdPersistence, allocator: std.mem.Allocator, limit: i32) !model.WebhookEventsResult {
        if (zent_db.getDriver()) |drv| {
            var rows = try zent.sql_scan.queryAll(
                model.WebhookEvent,
                allocator,
                drv,
                "SELECT id, event_type, payload FROM webhook_events WHERE delivered = FALSE ORDER BY created_at ASC LIMIT $1",
                &.{.{ .int = limit }},
            );
            const events = try rows.toOwnedSlice();
            return model.WebhookEventsResult{ .events = events, .total = @intCast(events.len) };
        }
        const db = self.db orelse return error.NotInitialized;
        const sql = "SELECT id, event_type, payload FROM webhook_events WHERE delivered = FALSE ORDER BY created_at ASC LIMIT $1";
        const params = &[_]db_mod.QueryParam{.{ .int = limit }};
        const result = db.queryParams(sql, params) catch return error.DatabaseError;
        defer freeResult(allocator, result);

        var events = try allocator.alloc(model.WebhookEvent, result.row_count);
        errdefer allocator.free(events);

        for (0..result.row_count) |i| {
            const row = result.rows[i];
            events[i] = .{
                .id = try std.fmt.parseInt(i32, row[0], 10),
                .event_type = try allocator.dupe(u8, row[1]),
                .payload = try allocator.dupe(u8, row[2]),
            };
        }

        return model.WebhookEventsResult{ .events = events, .total = @as(i32, @intCast(result.row_count)) };
    }

    pub fn markWebhookEventDelivered(self: *ThirdPersistence, event_id: i32) !void {
        if (zent_db.getDriver()) |drv| {
            _ = drv.exec(
                "UPDATE webhook_events SET delivered = TRUE, delivered_at = NOW() WHERE id = $1",
                &.{.{ .int = event_id }},
            ) catch |err| {
                std.log.err("Failed to mark webhook event delivered: {}", .{err});
                return error.DatabaseError;
            };
            return;
        }
        const db = self.db orelse return error.NotInitialized;
        const sql = "UPDATE webhook_events SET delivered = TRUE, delivered_at = NOW() WHERE id = $1";
        const params = &[_]db_mod.QueryParam{.{ .int = event_id }};
        _ = db.execParams(sql, params) catch |err| {
            std.log.err("Failed to mark webhook event delivered: {}", .{err});
            return error.DatabaseError;
        };
    }
};
