const std = @import("std");
const db_mod = @import("../db_postgres.zig");
const model = @import("model.zig");

pub const QueuePersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,
    queues: std.StringHashMap(bool),

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) QueuePersistence {
        return QueuePersistence{
            .allocator = allocator,
            .db = db,
            .queues = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *QueuePersistence) void {
        var it = self.queues.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.queues.deinit();
    }

    pub fn createQueue(self: *QueuePersistence, queue_name: []const u8) !void {
        const sql = "SELECT pgmq.create($1)";
        const params = &[_]db_mod.QueryParam{.{ .string = queue_name }};
        _ = self.db.queryParams(sql, params) catch |e| {
            std.log.warn("Queue create failed (may already exist): {s}", .{@errorName(e)});
        };
        try self.queues.put(try self.allocator.dupe(u8, queue_name), true);
        std.log.info("Queue created: {s}", .{queue_name});
    }

    pub fn send(self: *QueuePersistence, queue_name: []const u8, body: []const u8) !i64 {
        const sql = "SELECT pgmq.send($1, $2)";
        const params = &[_]db_mod.QueryParam{
            .{ .string = queue_name },
            .{ .string = body },
        };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return error.QueryFailed;
        return std.fmt.parseInt(i64, result.rows[0][0], 10) catch error.InvalidResult;
    }

    pub fn read(self: *QueuePersistence, queue_name: []const u8, vt: i32) !?model.QueueMessage {
        const sql = "SELECT msg_id, read_ct, enqueued_at, vt, message FROM pgmq.read($1, $2, 1)";
        const params = &[_]db_mod.QueryParam{
            .{ .string = queue_name },
            .{ .int = vt },
        };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return null;
        const row = result.rows[0];
        return model.QueueMessage{
            .msg_id = try std.fmt.parseInt(i64, row[0], 10),
            .read_ct = try std.fmt.parseInt(i32, row[1], 10),
            .enqueued_at = 0,
            .vt = try std.fmt.parseInt(i64, row[3], 10),
            .body = try self.allocator.dupe(u8, row[4]),
        };
    }

    pub fn delete(self: *QueuePersistence, queue_name: []const u8, msg_id: i64) !bool {
        const sql = "SELECT pgmq.delete($1, $2)";
        const params = &[_]db_mod.QueryParam{
            .{ .string = queue_name },
            .{ .bigint = msg_id },
        };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return false;
        return std.mem.eql(u8, result.rows[0][0], "t") or std.mem.eql(u8, result.rows[0][0], "true");
    }

    pub fn archive(self: *QueuePersistence, queue_name: []const u8, msg_id: i64) !bool {
        const sql = "SELECT pgmq.archive($1, $2)";
        const params = &[_]db_mod.QueryParam{
            .{ .string = queue_name },
            .{ .bigint = msg_id },
        };
        const result = try self.db.queryParams(sql, params);
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return false;
        return std.mem.eql(u8, result.rows[0][0], "t") or std.mem.eql(u8, result.rows[0][0], "true");
    }

    pub fn purge(self: *QueuePersistence, queue_name: []const u8) !void {
        const sql = "SELECT pgmq.purge_queue($1)";
        const params = &[_]db_mod.QueryParam{.{ .string = queue_name }};
        _ = self.db.queryParams(sql, params) catch {};
    }

    pub fn size(self: *QueuePersistence, queue_name: []const u8) !usize {
        const sql = "SELECT queue_length FROM pgmq.metrics($1)";
        const params = &[_]db_mod.QueryParam{.{ .string = queue_name }};
        const result = self.db.queryParams(sql, params) catch return 0;
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(usize, result.rows[0][0], 10) catch 0;
    }
};
