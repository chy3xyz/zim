const std = @import("std");
const core = @import("core");
const model = @import("model.zig");
const persistence = @import("persistence.zig");

pub const ThirdService = struct {
    allocator: std.mem.Allocator,
    pers: persistence.ThirdPersistence,
    storage_config: model.ObjectStorageConfig,
    inited: bool,

    pub fn init(allocator: std.mem.Allocator) ThirdService {
        return .{
            .allocator = allocator,
            .pers = persistence.ThirdPersistence.init(allocator, null),
            .storage_config = undefined,
            .inited = false,
        };
    }

    pub fn deinit(self: *ThirdService) void {
        _ = self;
    }

    pub fn initStorage(self: *ThirdService, cfg: model.ObjectStorageConfig, db: *@import("../../modules/db_postgres.zig").PostgresClient) void {
        self.storage_config = cfg;
        self.pers = persistence.ThirdPersistence.init(self.allocator, db);
        self.inited = true;
        std.log.info("Third module initialized with RustFS endpoint: {s}", .{cfg.endpoint});
    }

    pub fn isInited(self: *ThirdService) bool {
        return self.inited;
    }

    pub fn getConfig(self: *ThirdService) model.ObjectStorageConfig {
        return self.storage_config;
    }

    // ── FCM Token Management ─────────────────────────────────────

    pub fn saveFCMToken(self: *ThirdService, user_id: []const u8, platform_id: i32, fcm_token: []const u8) !void {
        return self.pers.saveFCMToken(user_id, platform_id, fcm_token);
    }

    pub fn getFCMToken(self: *ThirdService, user_id: []const u8, platform_id: i32) !?[]const u8 {
        return self.pers.getFCMToken(user_id, platform_id);
    }

    // ── Log Management ───────────────────────────────────────────

    pub fn saveLog(self: *ThirdService, user_id: []const u8, platform: i32, file_url: []const u8) !void {
        return self.pers.saveLog(user_id, platform, file_url);
    }

    pub fn searchLogs(self: *ThirdService, allocator: std.mem.Allocator, user_id: ?[]const u8, platform: ?i32, start_time: ?i64, end_time: ?i64, page_number: i32, show_number: i32) !model.SearchLogsResult {
        return self.pers.searchLogs(allocator, user_id, platform, start_time, end_time, page_number, show_number);
    }

    // ── Webhook Event Queue ──────────────────────────────────────

    pub fn queueWebhookEvent(self: *ThirdService, event_type: []const u8, payload: []const u8) !void {
        return self.pers.queueWebhookEvent(event_type, payload);
    }

    pub fn getPendingWebhookEvents(self: *ThirdService, allocator: std.mem.Allocator, limit: i32) !model.WebhookEventsResult {
        return self.pers.getPendingWebhookEvents(allocator, limit);
    }

    pub fn markWebhookEventDelivered(self: *ThirdService, event_id: i32) !void {
        return self.pers.markWebhookEventDelivered(event_id);
    }

    // ── S3-compatible presigned URL (AWS SigV4) ─────────────────

    fn hmacSha256(allocator: std.mem.Allocator, key: []const u8, data: []const u8) ![]const u8 {
        var out: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
        std.crypto.auth.hmac.sha2.HmacSha256.create(&out, data, key);
        return try allocator.dupe(u8, &out);
    }

    fn sha256Hex(data: []const u8) [64]u8 {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
        return std.fmt.bytesToHex(hash, .lower);
    }

    fn getUtcTimeInfo() struct { year: u16, month: u4, day: u5, hour: u5, minute: u6, second: u6 } {
        const secs = @as(u64, @intCast(core.unixNowSeconds()));
        const epoch_sec = std.time.epoch.EpochSeconds{ .secs = secs };
        const epoch_day = epoch_sec.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = epoch_sec.getDaySeconds();
        return .{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
            .hour = day_seconds.getHoursIntoDay(),
            .minute = day_seconds.getMinutesIntoHour(),
            .second = day_seconds.getSecondsIntoMinute(),
        };
    }

    pub fn presignedUrl(self: *ThirdService, allocator: std.mem.Allocator, method: []const u8, object_key: []const u8, expiry_seconds: u32) ![]const u8 {
        const cfg = self.storage_config;
        const t = getUtcTimeInfo();

        var date_buf: [9]u8 = undefined;
        const date_str = try std.fmt.bufPrint(&date_buf, "{d:0>4}{d:0>2}{d:0>2}", .{ t.year, t.month, t.day });

        var time_buf: [17]u8 = undefined;
        const time_str = try std.fmt.bufPrint(&time_buf, "{s}T{d:0>2}{d:0>2}{d:0>2}Z", .{ date_str, t.hour, t.minute, t.second });

        const credential_scope = try std.fmt.allocPrint(allocator, "{s}/{s}/s3/aws4_request", .{ date_str, cfg.region });
        defer allocator.free(credential_scope);

        const credential = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cfg.access_key, credential_scope });
        defer allocator.free(credential);

        const canonical_uri = try std.fmt.allocPrint(allocator, "/{s}/{s}", .{ cfg.bucket, object_key });
        defer allocator.free(canonical_uri);

        const query_str = try std.fmt.allocPrint(allocator, "X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential={s}&X-Amz-Date={s}&X-Amz-Expires={d}&X-Amz-SignedHeaders=host", .{
            credential, time_str, expiry_seconds,
        });
        defer allocator.free(query_str);

        const host = cfg.endpoint;

        const canonical_request = try std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}\nhost:{s}\n\nhost\nUNSIGNED-PAYLOAD", .{
            method, canonical_uri, query_str, host,
        });
        defer allocator.free(canonical_request);

        const canonical_hash_hex = sha256Hex(canonical_request);

        const string_to_sign = try std.fmt.allocPrint(allocator, "AWS4-HMAC-SHA256\n{s}\n{s}\n{s}", .{
            time_str, credential_scope, &canonical_hash_hex,
        });
        defer allocator.free(string_to_sign);

        var aws4_key_buf: [128]u8 = undefined;
        const aws4_key = try std.fmt.bufPrint(&aws4_key_buf, "AWS4{s}", .{cfg.secret_key});

        const k_date = try hmacSha256(allocator, aws4_key, date_str);
        defer allocator.free(k_date);
        const k_region = try hmacSha256(allocator, k_date, cfg.region);
        defer allocator.free(k_region);
        const k_service = try hmacSha256(allocator, k_region, "s3");
        defer allocator.free(k_service);
        const k_signing = try hmacSha256(allocator, k_service, "aws4_request");
        defer allocator.free(k_signing);

        const signature = try hmacSha256(allocator, k_signing, string_to_sign);
        defer allocator.free(signature);
        const sig_hex = std.fmt.bytesToHex(signature[0..32], .lower);

        const protocol = if (cfg.use_ssl) "https" else "http";
        const url = try std.fmt.allocPrint(allocator, "{s}://{s}{s}?{s}&X-Amz-Signature={s}", .{
            protocol, cfg.endpoint, canonical_uri, query_str, &sig_hex,
        });

        return url;
    }

    pub fn accessUrl(self: *ThirdService, allocator: std.mem.Allocator, object_key: []const u8, expiry_seconds: u32) ![]const u8 {
        return self.presignedUrl(allocator, "GET", object_key, expiry_seconds);
    }
};
