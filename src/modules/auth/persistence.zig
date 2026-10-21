const std = @import("std");
const core = @import("core");
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

pub const AuthPersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) AuthPersistence {
        return .{ .allocator = allocator, .db = db };
    }

    pub fn storeToken(self: *AuthPersistence, user_id: []const u8, token: []const u8, platform_id: i32, expiry_hours: u32) !void {
        // zent path (preferred): same statement through the pooled driver
        // (expire_time is SQL-computed, so raw exec beats the entity builder);
        // legacy db_postgres branch stays as fallback (docs/zent-migration.md).
        if (zent_db.getDriver()) |drv| {
            _ = try drv.exec(
                "INSERT INTO auth_tokens (user_id, token, platform_id, expire_time) VALUES ($1, $2, $3, NOW() + INTERVAL '1 hours' * $4)",
                &.{ .{ .string = user_id }, .{ .string = token }, .{ .int = platform_id }, .{ .int = expiry_hours } },
            );
            return;
        }
        const sql = "INSERT INTO auth_tokens (user_id, token, platform_id, expire_time) VALUES ($1, $2, $3, NOW() + INTERVAL '1 hours' * $4)";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .string = token },
            .{ .int = platform_id },
            .{ .int = expiry_hours },
        };
        _ = try self.db.execParams(sql, params);
    }

    pub fn parseToken(self: *AuthPersistence, token: []const u8) !model.TokenInfo {
        // zent path (preferred): DTO scanning by column name into TokenInfo.
        if (zent_db.getDriver()) |drv| {
            return (zent.sql_scan.queryOne(
                model.TokenInfo,
                self.allocator,
                drv,
                "SELECT user_id, token, platform_id, EXTRACT(EPOCH FROM expire_time)::bigint AS expire_time FROM auth_tokens WHERE token = $1 AND expire_time > NOW() LIMIT 1",
                &.{.{ .string = token }},
            ) catch return error.InvalidToken) orelse error.InvalidToken;
        }
        const sql = "SELECT user_id, token, platform_id, EXTRACT(EPOCH FROM expire_time)::bigint FROM auth_tokens WHERE token = $1 AND expire_time > NOW() LIMIT 1";
        const params = &[_]db_mod.QueryParam{.{ .string = token }};
        const result = self.db.queryParams(sql, params) catch return error.InvalidToken;
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return error.InvalidToken;
        const row = result.rows[0];
        return model.TokenInfo{
            .token = try self.allocator.dupe(u8, row[1]),
            .user_id = try self.allocator.dupe(u8, row[0]),
            .expire_time = try std.fmt.parseInt(i64, row[3], 10),
            .platform_id = try std.fmt.parseInt(i32, row[2], 10),
        };
    }

    pub fn deleteByUser(self: *AuthPersistence, user_id: []const u8) void {
        if (zent_db.getDriver()) |drv| {
            _ = drv.exec("DELETE FROM auth_tokens WHERE user_id = $1", &.{.{ .string = user_id }}) catch {};
            return;
        }
        const sql = "DELETE FROM auth_tokens WHERE user_id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        _ = self.db.execParams(sql, params) catch {};
    }

    pub fn createVerificationCode(self: *AuthPersistence, phone_number: ?[]const u8, email: ?[]const u8, area_code: ?[]const u8) ![]const u8 {
        const key = if (phone_number) |p| try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ area_code orelse "", p }) else if (email) |e| try self.allocator.dupe(u8, e) else return error.InvalidTarget;
        defer self.allocator.free(key);

        if (zent_db.getDriver()) |drv| {
            // Rate limit: one code per target per 60 seconds (SMS/email abuse guard)
            const Recent = struct { recent: bool };
            const recent = zent.sql_scan.queryOne(
                Recent,
                self.allocator,
                drv,
                "SELECT CASE WHEN NOW() - created_at < INTERVAL '60 seconds' THEN TRUE ELSE FALSE END AS recent FROM auth_verification_codes WHERE target = $1",
                &.{.{ .string = key }},
            ) catch null;
            if (recent) |r| {
                if (r.recent) return error.CodeTooFrequent;
            }

            // Generate 6-digit code with OS CSPRNG
            var code_bytes: [4]u8 = undefined;
            core.secureRandomBytes(&code_bytes);
            const code_num = std.mem.readInt(u32, &code_bytes, .little) % 1000000;
            const code = try std.fmt.allocPrint(self.allocator, "{d:0>6}", .{code_num});
            const expire_time = core.unixNowSeconds() + 300; // 5 minutes

            // Persist in PostgreSQL (survives restarts, one-time use on verify)
            _ = drv.exec(
                "INSERT INTO auth_verification_codes (target, code, expire_time) VALUES ($1, $2, $3) " ++
                    "ON CONFLICT (target) DO UPDATE SET code = EXCLUDED.code, expire_time = EXCLUDED.expire_time, created_at = NOW()",
                &.{ .{ .string = key }, .{ .string = code }, .{ .int = expire_time } },
            ) catch |err| {
                std.log.err("Failed to persist verification code: {}", .{err});
                return error.DatabaseError;
            };

            std.log.info("Verification code for {s}: {s}", .{ key, code });
            return code;
        }

        // Rate limit: one code per target per 60 seconds (SMS/email abuse guard)
        const check_sql = "SELECT CASE WHEN NOW() - created_at < INTERVAL '60 seconds' THEN 1 ELSE 0 END FROM auth_verification_codes WHERE target = $1";
        const check_result = try self.db.queryParams(check_sql, &.{.{ .string = key }});
        defer freeResult(self.allocator, check_result);
        if (check_result.row_count > 0 and check_result.rows[0][0][0] == '1') {
            return error.CodeTooFrequent;
        }

        // Generate 6-digit code with OS CSPRNG
        var code_bytes: [4]u8 = undefined;
        core.secureRandomBytes(&code_bytes);
        const code_num = std.mem.readInt(u32, &code_bytes, .little) % 1000000;
        const code = try std.fmt.allocPrint(self.allocator, "{d:0>6}", .{code_num});
        const expire_time = core.unixNowSeconds() + 300; // 5 minutes

        // Persist in PostgreSQL (survives restarts, one-time use on verify)
        const sql = "INSERT INTO auth_verification_codes (target, code, expire_time) VALUES ($1, $2, $3) " ++
            "ON CONFLICT (target) DO UPDATE SET code = EXCLUDED.code, expire_time = EXCLUDED.expire_time, created_at = NOW()";
        _ = try self.db.execParams(sql, &.{
            .{ .string = key },
            .{ .string = code },
            .{ .bigint = expire_time },
        });

        std.log.info("Verification code for {s}: {s}", .{ key, code });
        return code;
    }

    pub fn checkVerificationCode(self: *AuthPersistence, phone_number: ?[]const u8, email: ?[]const u8, area_code: ?[]const u8, code: []const u8) bool {
        // Key must match createVerificationCode: "{areaCode}:{phone}" / email.
        const key = if (phone_number) |p| std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ area_code orelse "", p }) catch return false else if (email) |e| self.allocator.dupe(u8, e) catch return false else return false;
        defer self.allocator.free(key);

        if (zent_db.getDriver()) |drv| {
            const StoredCode = struct { code: []const u8, expire_time: i64 };
            const stored = (zent.sql_scan.queryOne(
                StoredCode,
                self.allocator,
                drv,
                "SELECT code, expire_time FROM auth_verification_codes WHERE target = $1",
                &.{.{ .string = key }},
            ) catch return false) orelse return false;
            defer zent.sql_scan.freeDto(StoredCode, self.allocator, &stored);
            if (core.unixNowSeconds() > stored.expire_time) return false;
            if (!std.mem.eql(u8, stored.code, code)) return false;

            // One-time use: consume the code on successful verification
            _ = drv.exec("DELETE FROM auth_verification_codes WHERE target = $1", &.{.{ .string = key }}) catch {};
            return true;
        }

        const sql = "SELECT code, expire_time FROM auth_verification_codes WHERE target = $1";
        const result = self.db.queryParams(sql, &.{.{ .string = key }}) catch return false;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return false;
        const row = result.rows[0];
        const expire_time = std.fmt.parseInt(i64, row[1], 10) catch return false;
        if (core.unixNowSeconds() > expire_time) return false;
        if (!std.mem.eql(u8, row[0], code)) return false;

        // One-time use: consume the code on successful verification
        _ = self.db.execParams("DELETE FROM auth_verification_codes WHERE target = $1", &.{.{ .string = key }}) catch {};
        return true;
    }
};
