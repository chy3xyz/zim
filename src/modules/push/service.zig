const std = @import("std");
const core = @import("core");
const event_bus_mod = @import("../event_bus.zig");
const user_mod = @import("../user.zig");
const conversation_mod = @import("../conversation.zig");
const ws_module = @import("../websocket.zig");
const model = @import("model.zig");
const persistence = @import("persistence.zig");

pub const PushService = struct {
    allocator: std.mem.Allocator,
    pers: persistence.PushPersistence,

    pub fn init(allocator: std.mem.Allocator) PushService {
        return .{
            .allocator = allocator,
            .pers = persistence.PushPersistence.init(allocator),
        };
    }

    pub fn deinit(self: *PushService) void {
        self.pers.deinit();
    }

    pub fn sendPush(self: *PushService, msg: model.PushMessage) !void {
        // Bulkhead (RuntimeOptions.max_concurrent): reject pushes when the push
        // pipeline is saturated instead of unbounded queue growth.
        if (core.getModuleRuntime("push")) |rt| {
            if (!rt.tryEnter()) return error.PushOverloaded;
            defer rt.release();
        }
        const json = try std.json.Stringify.valueAlloc(self.allocator, .{
            .user_id = msg.user_id,
            .title = msg.title,
            .body = msg.body,
            .payload = msg.payload,
            .badge = msg.badge,
            .sound = msg.sound,
            .provider = @tagName(msg.provider),
        }, .{});
        _ = try self.pers.sendToQueue("push_notification", json);
    }

    pub fn queueOfflinePush(self: *PushService, user_ids: []const []const u8, title: []const u8, body: []const u8, payload: []const u8) !void {
        for (user_ids) |uid| {
            const json = try std.json.Stringify.valueAlloc(self.allocator, .{
                .user_id = uid,
                .title = title,
                .body = body,
                .payload = payload,
                .badge = 1,
                .sound = "default",
                .provider = "fcm",
            }, .{});
            _ = try self.pers.sendToQueue("offline_push", json);
        }
    }

    pub fn processQueue(self: *PushService) !void {
        if (try self.pers.readFromQueue("push_notification", 30)) |queue_msg| {
            defer self.allocator.free(queue_msg.body);
            std.log.info("[Push] Processing push notification: {s}", .{queue_msg.body});
            _ = try self.pers.deleteFromQueue("push_notification", queue_msg.msg_id);
        }

        if (try self.pers.readFromQueue("offline_push", 30)) |queue_msg| {
            defer self.allocator.free(queue_msg.body);
            std.log.info("[Push] Processing offline push: {s}", .{queue_msg.body});
            _ = try self.pers.deleteFromQueue("offline_push", queue_msg.msg_id);
        }
    }
};

/// Check if user is online (has active WebSocket connections)
fn isUserOnline(user_id: []const u8) bool {
    return user_mod.isOnline(user_id);
}

/// Check if user has Do-Not-Disturb enabled for this conversation
fn isDoNotDisturb(user_id: []const u8, conversation_id: []const u8) bool {
    const conv = conversation_mod.getConversation(user_id, conversation_id) catch return false;
    if (conv) |c| {
        return c.recv_msg_opt != 0;
    }
    return false;
}

/// Check if user is in background (all WS clients report background)
fn isBackground(user_id: []const u8) bool {
    return ws_module.isUserBackground(user_id);
}

/// Determine offline push recipients for a message event
pub fn getOfflineRecipients(event_payload: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, event_payload, .{}) catch return allocator.alloc([]const u8, 0);
    defer parsed.deinit();

    const root = parsed.value.object;
    const sender_id = if (root.get("sender_id")) |v| v.string else "";
    const receiver_id = if (root.get("receiver_id")) |v| v.string else "";
    const group_id = if (root.get("group_id")) |v| v.string else "";
    const conversation_id = if (root.get("conversation_id")) |v| v.string else "";
    const session_type = if (root.get("session_type")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => 1,
    } else 1;

    var recipients = std.ArrayList([]const u8).empty;
    defer recipients.deinit(allocator);

    if (session_type == 1) {
        if (!std.mem.eql(u8, receiver_id, "") and
            !std.mem.eql(u8, receiver_id, sender_id) and
            !isUserOnline(receiver_id) and
            !isDoNotDisturb(receiver_id, conversation_id))
        {
            try recipients.append(allocator, try allocator.dupe(u8, receiver_id));
        } else if (!std.mem.eql(u8, receiver_id, "") and
            !std.mem.eql(u8, receiver_id, sender_id) and
            isBackground(receiver_id) and
            !isDoNotDisturb(receiver_id, conversation_id))
        {
            try recipients.append(allocator, try allocator.dupe(u8, receiver_id));
        }
    } else if (session_type == 2) {
        const group_members = @import("../group.zig").getGroupMembers(group_id) catch return allocator.alloc([]const u8, 0);
        defer {
            for (group_members) |m| allocator.free(m.user_id);
            allocator.free(group_members);
        }
        for (group_members) |member| {
            if (std.mem.eql(u8, member.user_id, sender_id)) continue;
            if (isUserOnline(member.user_id) and !isBackground(member.user_id)) continue;
            if (isDoNotDisturb(member.user_id, conversation_id)) continue;
            try recipients.append(allocator, try allocator.dupe(u8, member.user_id));
        }
    }

    return recipients.toOwnedSlice(allocator);
}

// Event handler for message_sent - queue offline pushes
pub fn onMessageSent(event: event_bus_mod.Event) void {
    const allocator = core.getAllocator();
    std.log.info("[Push] Message sent event received", .{});

    const recipients = getOfflineRecipients(event.payload, allocator) catch {
        core.logJson(.{ .event = "push_recipients_failed", .module = "push", .level = "warn" });
        return;
    };
    defer {
        for (recipients) |r| allocator.free(r);
        allocator.free(recipients);
    }

    if (recipients.len == 0) return;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, event.payload, .{}) catch return;
    defer parsed.deinit();
    const root_obj = parsed.value.object;
    const sender_id = if (root_obj.get("sender_id")) |v| v.string else "";
    const content = if (root_obj.get("content")) |v| v.string else "New message";

    const svc = @import("root.zig").getService();
    svc.queueOfflinePush(recipients, "New Message", content, event.payload) catch |e| {
        core.logJson(.{ .event = "push_queue_failed", .module = "push", .level = "warn", .err = @errorName(e) });
    };

    std.log.info("[Push] Queued offline push to {d} recipients from sender {s}", .{ recipients.len, sender_id });
}

// Event handler for message_recalled - push recall notification
pub fn onMessageRecalled(event: event_bus_mod.Event) void {
    const allocator = core.getAllocator();
    std.log.info("[Push] Message recalled event received", .{});

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, event.payload, .{}) catch return;
    defer parsed.deinit();
    const root_obj = parsed.value.object;
    const conversation_id = if (root_obj.get("conversation_id")) |v| v.string else "";
    const seq = if (root_obj.get("seq")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => 0,
    } else 0;

    const recall_json = std.fmt.allocPrint(allocator, "{{\"reqIdentifier\":2001,\"errCode\":0,\"errMsg\":\"\",\"data\":\"{{\\\"conversationID\\\":\\\"{s}\\\",\\\"seq\\\":{d},\\\"isRecall\\\":true}}\"}}", .{ conversation_id, seq }) catch return;
    defer allocator.free(recall_json);

    ws_module.broadcast(recall_json);
}
