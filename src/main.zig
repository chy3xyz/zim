const std = @import("std");
const zigmodu = @import("zigmodu");
const sdkws = @import("sdkws");
const core = @import("core");

// Module imports
const config = @import("modules/config.zig");
const event_bus = @import("modules/event_bus.zig");
const db_postgres = @import("modules/db_postgres.zig");
const user = @import("modules/user.zig");
const auth = @import("modules/auth.zig");
const conversation = @import("modules/conversation.zig");
const message = @import("modules/message.zig");
const group = @import("modules/group.zig");
const friend = @import("modules/friend.zig");
const queue = @import("modules/queue.zig");
const push = @import("modules/push.zig");
const ws_module = @import("modules/websocket.zig");
const gateway = @import("modules/gateway.zig");
const office = @import("modules/office.zig");
const organization = @import("modules/organization.zig");
const third = @import("modules/third.zig");
const crontask = @import("modules/crontask.zig");

// Event handler functions (using core.Event for zigmodu-native TypedEventBus)
fn onUserCreated(ev: core.Event) void {
    core.logInfo("[EventBus] User created: {s}", .{ev.payload});
}

fn onUserOnline(ev: core.Event) void {
    core.logInfo("[EventBus] User online: {s}", .{ev.payload});
    const allocator = core.getAllocator();
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, ev.payload, .{}) catch return;
    defer parsed.deinit();
    const root = parsed.value.object;
    const user_id = if (root.get("user_id")) |v| v.string else "";
    const platform_id: i32 = if (root.get("platform_id")) |v| switch (v) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(f),
        else => 0,
    } else 0;
    if (user_id.len > 0) {
        ws_module.pushOnlineStatusChange(user_id, true, platform_id);
    }
}

fn onUserOffline(ev: core.Event) void {
    core.logInfo("[EventBus] User offline: {s}", .{ev.payload});
    const allocator = core.getAllocator();
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, ev.payload, .{}) catch return;
    defer parsed.deinit();
    const root = parsed.value.object;
    const user_id = if (root.get("user_id")) |v| v.string else "";
    if (user_id.len > 0) {
        ws_module.pushOnlineStatusChange(user_id, false, 0);
    }
}

fn onMessageSent(ev: core.Event) void {
    core.logInfo("[EventBus] Message sent: {s}", .{ev.payload});
    const allocator = core.getAllocator();

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, ev.payload, .{}) catch {
        push.onMessageSent(ev);
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;
    const sender_id = if (root.get("sender_id")) |v| v.string else "";
    const receiver_id = if (root.get("receiver_id")) |v| v.string else "";
    const group_id = if (root.get("group_id")) |v| v.string else "";
    const content = if (root.get("content")) |v| v.string else "";
    const server_msg_id = if (root.get("server_msg_id")) |v| v.string else "";
    const client_msg_id = if (root.get("client_msg_id")) |v| v.string else "";
    const seq = if (root.get("seq")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => 0,
    } else 0;
    const send_time = if (root.get("send_time")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => 0,
    } else 0;
    const content_type = if (root.get("content_type")) |v| switch (v) {
        .integer => |i| @as(i32, @intCast(i)),
        .float => |f| @as(i32, @intFromFloat(f)),
        else => 101,
    } else 101;
    const session_type = if (root.get("session_type")) |v| switch (v) {
        .integer => |i| @as(i32, @intCast(i)),
        .float => |f| @as(i32, @intFromFloat(f)),
        else => 1,
    } else 1;

    const msg_data = sdkws.MsgData{
        .send_id = sender_id,
        .recv_id = receiver_id,
        .group_id = group_id,
        .server_msg_id = server_msg_id,
        .client_msg_id = client_msg_id,
        .content = content,
        .seq = seq,
        .send_time = send_time,
        .content_type = content_type,
        .session_type = session_type,
    };

    switch (session_type) {
        1 => { // Single chat
            if (!std.mem.eql(u8, receiver_id, "")) {
                ws_module.pushMsgProtobuf(receiver_id, msg_data);
            }
        },
        2 => { // Group chat
            const members = group.getGroupMembers(group_id) catch |e| {
                core.logWarn("Failed to get group members for push: {s}", .{@errorName(e)});
                return;
            };
            defer {
                for (members) |m| allocator.free(m.user_id);
                allocator.free(members);
            }
            for (members) |member| {
                if (!std.mem.eql(u8, member.user_id, sender_id)) {
                    ws_module.pushMsgProtobuf(member.user_id, msg_data);
                }
            }
        },
        else => {},
    }

    push.onMessageSent(ev);

    third.queueWebhookEvent("message_sent", ev.payload) catch |e| {
        core.logWarn("[Webhook] Failed to queue message_sent event: {s}", .{@errorName(e)});
    };
}

fn onMessageRecalled(ev: core.Event) void {
    core.logInfo("[EventBus] Message recalled: {s}", .{ev.payload});
    const allocator = core.getAllocator();
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, ev.payload, .{}) catch {
        push.onMessageRecalled(ev);
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;
    const conversation_id = if (root.get("conversation_id")) |v| v.string else "";
    const seq = if (root.get("seq")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => 0,
    } else 0;

    const recall_json = std.fmt.allocPrint(allocator, "{{\"reqIdentifier\":2001,\"errCode\":0,\"errMsg\":\"\",\"data\":\"{{\\\"conversationID\\\":\\\"{s}\\\",\\\"seq\\\":{d},\\\"isRecall\\\":true}}\"}}", .{ conversation_id, seq }) catch return;
    defer allocator.free(recall_json);
    ws_module.broadcast(recall_json);

    push.onMessageRecalled(ev);
}

fn onMessageDeleted(ev: core.Event) void {
    core.logInfo("[EventBus] Message deleted: {s}", .{ev.payload});
}

fn onConversationCreated(ev: core.Event) void {
    core.logInfo("[EventBus] Conversation created: {s}", .{ev.payload});
}

fn onGroupCreated(ev: core.Event) void {
    core.logInfo("[EventBus] Group created: {s}", .{ev.payload});
}

fn onGroupMemberJoined(ev: core.Event) void {
    core.logInfo("[EventBus] Group member joined: {s}", .{ev.payload});
}

fn onGroupMemberLeft(ev: core.Event) void {
    core.logInfo("[EventBus] Group member left: {s}", .{ev.payload});
}

fn onGroupMemberRoleChanged(ev: core.Event) void {
    core.logInfo("[EventBus] Group member role changed: {s}", .{ev.payload});
}

fn onFriendRequested(ev: core.Event) void {
    core.logInfo("[EventBus] Friend requested: {s}", .{ev.payload});
}

fn onFriendAccepted(ev: core.Event) void {
    core.logInfo("[EventBus] Friend accepted: {s}", .{ev.payload});
}

fn onFriendDeclined(ev: core.Event) void {
    core.logInfo("[EventBus] Friend declined: {s}", .{ev.payload});
}

fn onFriendDeleted(ev: core.Event) void {
    core.logInfo("[EventBus] Friend deleted: {s}", .{ev.payload});
}

fn onBlackAdded(ev: core.Event) void {
    core.logInfo("[EventBus] User blacklisted: {s}", .{ev.payload});
}

fn onBlackRemoved(ev: core.Event) void {
    core.logInfo("[EventBus] User removed from blacklist: {s}", .{ev.payload});
}

fn subscribeEvents() !void {
    const eb = core.getEventBus();

    try eb.subscribe(.user_created, onUserCreated, "gateway");
    // High-volume handlers dispatch on the zigmodu WorkerPool (async bus)
    try eb.subscribeAsync(.user_online, onUserOnline, "gateway");
    try eb.subscribeAsync(.user_offline, onUserOffline, "gateway");
    try eb.subscribeAsync(.message_sent, onMessageSent, "push");
    try eb.subscribeAsync(.message_recalled, onMessageRecalled, "push");
    try eb.subscribe(.message_deleted, onMessageDeleted, "push");
    try eb.subscribe(.conversation_created, onConversationCreated, "gateway");
    try eb.subscribe(.group_created, onGroupCreated, "gateway");
    try eb.subscribe(.group_member_joined, onGroupMemberJoined, "gateway");
    try eb.subscribe(.group_member_left, onGroupMemberLeft, "gateway");
    try eb.subscribe(.group_member_role_changed, onGroupMemberRoleChanged, "gateway");
    try eb.subscribe(.friend_requested, onFriendRequested, "gateway");
    try eb.subscribe(.friend_accepted, onFriendAccepted, "gateway");
    try eb.subscribe(.friend_declined, onFriendDeclined, "gateway");
    try eb.subscribe(.friend_deleted, onFriendDeleted, "gateway");
    try eb.subscribe(.black_added, onBlackAdded, "gateway");
    try eb.subscribe(.black_removed, onBlackRemoved, "gateway");
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Initialize core infrastructure first (before zigmodu Application)
    try core.init(allocator, init.io);
    core.initMetrics();

    core.logInfo("========================================", .{});
    core.logInfo("  ZIM Server v0.4.0 (Modulith)", .{});
    core.logInfo("  OpenIM Server Rewrite in Zig", .{});
    core.logInfo("  Framework: zigmodu v0.15.9", .{});
    core.logInfo("  Mode: Deep Integration (ThreadSafeEventBus + WorkerPool + RuntimeOptions)", .{});
    core.logInfo("========================================", .{});

    // Structured startup event (readable JSON) — same sink as access logs.
    core.logJson(.{ .event = "zim_startup", .version = "0.4.0", .framework = "zigmodu-0.15.10", .mode = "modulith" });

    // Initialize Application using the zigmodu ApplicationBuilder (fluent API)
    var app_builder = zigmodu.builder(allocator, init.io);
    var app = try app_builder
        .withName("zim")
        .withValidation(true)
        .withAutoDocs(true)
        .withDocsPath("modules.puml")
        .build(.{
        config,
        event_bus,
        db_postgres,
        user,
        auth,
        conversation,
        message,
        group,
        friend,
        office,
        organization,
        queue,
        push,
        third,
        crontask,
        ws_module,
        gateway,
    });
    core.setApp(&app);
    defer {
        app.deinit();
        core.deinit();
    }

    // Start all modules (calls init() in dependency order)
    try app.start();
    core.logInfo("All modules started", .{});

    // Report per-module runtime resource usage (zigmodu ModuleRuntime)
    for ([_][]const u8{ "gateway", "websocket", "push", "db_postgres", "auth", "message", "crontask" }) |name| {
        if (core.getModuleRuntime(name)) |rt| {
            if (rt.getWorkerPoolStats()) |stats| {
                core.logInfo("[Runtime] module '{s}': worker pool {d} workers, {d} pending, {d} completed, {d} rejected", .{
                    name, stats.total_workers, stats.pending_count, stats.completed_tasks, stats.rejected_tasks,
                });
            }
        }
    }

    // JSON log file output (with rotation) when configured
    const cfg = config.getConfig();
    if (cfg.log.file.len > 0) {
        core.initLogFile(cfg.log.file, cfg.log.max_size) catch {
            core.logWarn("Failed to open JSON log file {s} — stderr only", .{cfg.log.file});
        };
    }

    // Initialize third-party services (RustFS object storage)
    // Warn loudly when the JWT secret is still the shipped default.
    if (std.mem.eql(u8, cfg.jwt.secret, "zim-secret-change-in-production") or
        std.mem.eql(u8, cfg.jwt.secret, "zim-secret"))
    {
        core.logWarn("JWT secret is the default value — set [jwt] secret in config.yaml before production!", .{});
    }
    third.initStorage(.{
        .endpoint = cfg.object_storage.endpoint,
        .access_key = cfg.object_storage.access_key,
        .secret_key = cfg.object_storage.secret_key,
        .bucket = cfg.object_storage.bucket,
        .region = cfg.object_storage.region,
        .use_ssl = cfg.object_storage.use_ssl,
    }, db_postgres.getClient(), allocator);

    // Pass Io to crontask for webhook delivery
    crontask.setIo(init.io);

    // Subscribe to cross-module events
    try subscribeEvents();
    const eb = core.getEventBus();
    core.logInfo("EventBus: {d} subscriptions active, {d} events published", .{ eb.getEventCount(), eb.getPublishedCount() });

    // Log module status
    core.logInfo("Users: {d} registered", .{user.userCount()});
    core.logInfo("Conversations: {d} active", .{conversation.conversationCount()});
    core.logInfo("Messages: {d} stored", .{message.messageCount()});
    core.logInfo("Groups: {d} created", .{group.groupCount()});

    // Start HTTP + WebSocket servers (non-blocking)
    try gateway.startHttpServer(init.io, allocator, config.getConfig().gateway.http_port);
    try ws_module.startServer(init.io, allocator, config.getConfig().gateway.ws_port);

    core.logInfo("========================================", .{});
    core.logInfo("  Server ready!", .{});
    core.logInfo("  HTTP: http://0.0.0.0:{d}", .{config.getConfig().gateway.http_port});
    core.logInfo("  WS:   ws://0.0.0.0:{d}", .{config.getConfig().gateway.ws_port});
    core.logInfo("========================================", .{});

    // Run with graceful shutdown (SIGINT/SIGTERM handling)
    try app.run();
}
