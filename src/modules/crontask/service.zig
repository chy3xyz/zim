const std = @import("std");
const core = @import("core");
const config_mod = @import("../config.zig");
const third_mod = @import("../third.zig");
const persistence = @import("persistence.zig");

pub const CrontaskService = struct {
    pers: persistence.CrontaskPersistence,

    pub fn init(db: *@import("../db_postgres.zig").PostgresClient) CrontaskService {
        return .{ .pers = persistence.CrontaskPersistence.init(db) };
    }

    pub fn ensureTables(self: *CrontaskService) !void {
        return self.pers.ensureTables();
    }

    pub fn cleanupOldMessages(self: *CrontaskService, retention_days: i32) !usize {
        return self.pers.cleanupOldMessages(retention_days);
    }

    pub fn cleanupRevokedMessages(self: *CrontaskService) !usize {
        return self.pers.cleanupRevokedMessages();
    }

    pub fn queueDepth(self: *CrontaskService) usize {
        return self.pers.queueDepth();
    }
    pub fn cleanupOldAuthTokens(self: *CrontaskService) !usize {
        return self.pers.cleanupOldAuthTokens();
    }
};

/// Deliver pending webhook events via HTTP POST using curl
pub fn deliverWebhookEvents(io: std.Io) !void {
    const cfg = config_mod.getConfig().webhook;
    if (!cfg.enabled or cfg.url.len == 0) return;

    const allocator = core.getAllocator();
    const result = third_mod.getPendingWebhookEvents(allocator, 100) catch |err| {
        std.log.err("[Crontask] Failed to get pending webhook events: {}", .{err});
        return;
    };
    defer {
        for (result.events) |ev| {
            allocator.free(ev.event_type);
            allocator.free(ev.payload);
        }
        allocator.free(result.events);
    }

    if (result.events.len == 0) return;

    std.log.info("[Crontask] Delivering {d} webhook events to {s}", .{ result.events.len, cfg.url });

    for (result.events) |ev| {
        const success = sendWebhookViaCurl(io, cfg.url, cfg.secret, ev.event_type, ev.payload) catch |err| {
            std.log.err("[Crontask] Webhook delivery failed for event {d}: {}", .{ ev.id, err });
            continue;
        };

        if (success) {
            third_mod.markWebhookEventDelivered(ev.id) catch |err| {
                std.log.err("[Crontask] Failed to mark webhook event {d} delivered: {}", .{ ev.id, err });
            };
        } else {
            std.log.warn("[Crontask] Webhook delivery returned non-success for event {d}", .{ev.id});
        }
    }
}

fn sendWebhookViaCurl(io: std.Io, url: []const u8, secret: []const u8, event_type: []const u8, payload: []const u8) !bool {
    const allocator = core.getAllocator();

    var full_payload: [4096]u8 = undefined;
    const body = try std.fmt.bufPrint(&full_payload, "{{'eventType':'{s}','payload':{s},'timestamp':{d}}}", .{ event_type, payload, currentMillis() });

    var headers_arg: [512]u8 = undefined;
    const headers = if (secret.len > 0)
        try std.fmt.bufPrint(&headers_arg, "X-Webhook-Secret: {s}", .{secret})
    else
        null;

    const argv = if (headers) |h|
        &[_][]const u8{
            "curl", "-s",   "-o", "/dev/null", "-w", "%{http_code}",
            "-X",   "POST", "-H", h,           "-H", "Content-Type: application/json",
            "-d",   body,   url,
        }
    else
        &[_][]const u8{
            "curl", "-s",   "-o", "/dev/null",                      "-w", "%{http_code}",
            "-X",   "POST", "-H", "Content-Type: application/json", "-d", body,
            url,
        };

    const result = std.process.run(allocator, io, .{ .argv = argv }) catch |err| {
        std.log.err("[Crontask] Failed to run curl: {}", .{err});
        return false;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.stdout.len >= 1 and result.stdout[0] == '2') {
        return true;
    }
    return false;
}

fn currentMillis() i64 {
    return core.unixNowMillis();
}
