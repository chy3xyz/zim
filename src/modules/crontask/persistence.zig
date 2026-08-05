const std = @import("std");
const core = @import("core");
const db_mod = @import("../db_postgres.zig");

pub const CrontaskPersistence = struct {
    db: *db_mod.PostgresClient,

    pub fn init(db: *db_mod.PostgresClient) CrontaskPersistence {
        return CrontaskPersistence{ .db = db };
    }

    pub fn ensureTables(self: *CrontaskPersistence) !void {
        const sql =
            "CREATE TABLE IF NOT EXISTS webhook_events (" ++
            "  id SERIAL PRIMARY KEY," ++
            "  event_type VARCHAR(64) NOT NULL," ++
            "  payload TEXT NOT NULL," ++
            "  created_at TIMESTAMP NOT NULL DEFAULT NOW()," ++
            "  delivered BOOLEAN NOT NULL DEFAULT FALSE," ++
            "  delivered_at TIMESTAMP" ++
            ")";

        _ = self.db.exec(sql) catch |err| {
            core.logJson(.{ .event = "crontask_init_failed", .module = "crontask", .level = "error", .err = @errorName(err) });
            return err;
        };
    }

    pub fn cleanupOldMessages(self: *CrontaskPersistence, retention_days: i32) !usize {
        const sql = try std.fmt.allocPrint(core.getAllocator(), "DELETE FROM messages WHERE create_time < NOW() - INTERVAL '{d} days' AND is_revoke = TRUE", .{retention_days});
        defer core.getAllocator().free(sql);

        const affected = self.db.exec(sql) catch |err| {
            std.log.err("[Crontask] Failed to cleanup old messages: {}", .{err});
            return err;
        };
        return affected;
    }

    pub fn cleanupRevokedMessages(self: *CrontaskPersistence) !usize {
        const sql = "DELETE FROM messages WHERE is_revoke = TRUE AND create_time < NOW() - INTERVAL '7 days'";
        const affected = self.db.exec(sql) catch |err| {
            std.log.err("[Crontask] Failed to cleanup revoked messages: {}", .{err});
            return err;
        };
        return affected;
    }

    pub fn cleanupOldAuthTokens(self: *CrontaskPersistence) !usize {
        const sql = "DELETE FROM auth_tokens WHERE expire_time < NOW()";
        const affected = self.db.exec(sql) catch |err| {
            std.log.err("[Crontask] Failed to cleanup old auth tokens: {}", .{err});
            return err;
        };
        return affected;
    }
};
