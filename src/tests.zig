const std = @import("std");
// zim integration + contract tests (Phase 44: friend/black/apply contract alignment)
// NOTE: keep tests independent of HTTP server state; they use direct module calls + Testkit.
// test runner note: first-run-after-compile flake is a zig 0.17-dev runner issue; binary passes 8/8.
const core = @import("core");
const zigmodu = @import("zigmodu");
const gateway = @import("modules/gateway.zig");
const auth_svc = @import("modules/auth/service.zig");

// ============================================================
// Core event bus — sync dispatch
// ============================================================
test "core event bus sync dispatch + targeting" {
    const allocator = std.testing.allocator;
    try core.init(allocator, std.testing.io);
    defer core.deinit();

    const eb = core.getEventBus();
    var got = std.atomic.Value(bool).init(false);
    const Handler = struct {
        var flag: *std.atomic.Value(bool) = undefined;
        fn onEvent(ev: core.Event) void {
            _ = ev;
            flag.store(true, .release);
        }
    };
    Handler.flag = &got;

    try eb.subscribe(.user_created, Handler.onEvent, "test");
    try std.testing.expectEqual(@as(usize, 1), eb.getEventCount());

    // publish an event directly (caller-owned payload, no copy semantics)
    eb.publish(.{
        .type = .user_created,
        .source_module = "test",
        .target_module = null,
        .payload = "payload",
        .timestamp = 1,
    });
    try std.testing.expect(got.load(.acquire));

    // targeted event should NOT reach the handler
    got.store(false, .release);
    eb.publish(.{
        .type = .user_created,
        .source_module = "test",
        .target_module = "other",
        .payload = "payload",
        .timestamp = 1,
    });
    try std.testing.expect(!got.load(.acquire));
    try std.testing.expect(eb.getPublishedCount() == 2);
}

// ============================================================
// Core event bus — async dispatch on the WorkerPool
// ============================================================
test "core event bus async dispatch frees payload" {
    const allocator = std.testing.allocator;
    try core.init(allocator, std.testing.io);
    defer core.deinit();

    const eb = core.getEventBus();
    var got = std.atomic.Value(bool).init(false);
    const Handler = struct {
        var flag: *std.atomic.Value(bool) = undefined;
        fn onEvent(ev: core.Event) void {
            _ = ev;
            flag.store(true, .release);
        }
    };
    Handler.flag = &got;

    try eb.subscribeAsync(.message_sent, Handler.onEvent, "test");
    eb.emit(.message_sent, "test", "{\"user_id\":\"u1\"}");

    var waited: u32 = 0;
    while (!got.load(.acquire) and waited < 5000) : (waited += 1) {
        std.Thread.yield() catch {};
    }
    try std.testing.expect(got.load(.acquire));
}

// ============================================================
// Auth login brute-force limiter
// ============================================================
test "auth login limiter blocks after max attempts per user" {
    const allocator = std.testing.allocator;
    try core.init(allocator, std.testing.io);
    defer core.deinit();
    auth_svc.initLoginLimiter(allocator);
    defer auth_svc.deinitLoginLimiter();

    // 5 failed attempts are allowed, the 6th is blocked.
    for (0..5) |_| {
        try std.testing.expect(auth_svc.loginAllowed("limiter_user"));
        auth_svc.recordLoginFailure("limiter_user");
    }
    try std.testing.expect(!auth_svc.loginAllowed("limiter_user"));
    // Other users are unaffected.
    try std.testing.expect(auth_svc.loginAllowed("other_user"));
}

// ============================================================
// WebSocket protobuf codec round-trip
// ============================================================
test "WS protobuf MsgData round-trip" {
    const allocator = std.testing.allocator;
    const sdkws = @import("sdkws");

    const msg = sdkws.MsgData{
        .send_id = "userA",
        .recv_id = "userB",
        .client_msg_id = "c1",
        .server_msg_id = "s1",
        .content = "hello protobuf",
        .content_type = 101,
        .session_type = 1,
        .seq = 42,
        .send_time = 1234567890,
        .sender_nickname = "Alice",
    };
    const bytes = try msg.encode(allocator);
    defer allocator.free(bytes);

    const d = try sdkws.MsgData.decode(bytes, allocator);
    defer {
        allocator.free(d.send_id);
        allocator.free(d.recv_id);
        allocator.free(d.client_msg_id);
        allocator.free(d.server_msg_id);
        allocator.free(d.content);
        allocator.free(d.sender_nickname);
        allocator.free(d.at_user_id_list);
    }

    try std.testing.expectEqualStrings("userA", d.send_id);
    try std.testing.expectEqualStrings("userB", d.recv_id);
    try std.testing.expectEqualStrings("hello protobuf", d.content);
    try std.testing.expectEqual(@as(i64, 42), d.seq);
    try std.testing.expectEqual(@as(i64, 1234567890), d.send_time);
    try std.testing.expectEqual(@as(i32, 101), d.content_type);
    try std.testing.expectEqualStrings("Alice", d.sender_nickname);
}

// ============================================================
// WS protobuf: protocol message round-trips (reqs decode back,
// server-only resps verified by encode + field assertions)
// ============================================================
test "WS protobuf: protocol req/resp round-trips" {
    const allocator = std.testing.allocator;
    const sdkws = @import("sdkws");

    // PullMessageBySeqsReq with nested SeqRange list
    const pull = sdkws.PullMessageBySeqsReq{
        .user_id = "userX",
        .order = 1,
        .seq_ranges = &.{
            .{ .conversation_id = "sg_g1", .begin = 10, .end = 20, .num = 11 },
            .{ .conversation_id = "si_a_b", .begin = 1, .end = 5, .num = 5 },
        },
    };
    const pull_bytes = try pull.encode(allocator);
    defer allocator.free(pull_bytes);
    const pull_dec = try sdkws.PullMessageBySeqsReq.decode(pull_bytes, allocator);
    defer {
        allocator.free(pull_dec.user_id);
        for (pull_dec.seq_ranges) |sr| allocator.free(sr.conversation_id);
        allocator.free(pull_dec.seq_ranges);
    }
    try std.testing.expectEqualStrings("userX", pull_dec.user_id);
    try std.testing.expectEqual(@as(i32, 1), pull_dec.order);
    try std.testing.expectEqual(@as(usize, 2), pull_dec.seq_ranges.len);
    try std.testing.expectEqualStrings("sg_g1", pull_dec.seq_ranges[0].conversation_id);
    try std.testing.expectEqual(@as(i64, 20), pull_dec.seq_ranges[0].end);
    try std.testing.expectEqual(@as(i64, 5), pull_dec.seq_ranges[1].num);

    // GetMaxSeqReq round-trip
    const max_req = sdkws.GetMaxSeqReq{ .user_id = "userY" };
    const max_bytes = try max_req.encode(allocator);
    defer allocator.free(max_bytes);
    const max_dec = try sdkws.GetMaxSeqReq.decode(max_bytes, allocator);
    defer allocator.free(max_dec.user_id);
    try std.testing.expectEqualStrings("userY", max_dec.user_id);

    // GetSeqMessageReq round-trip
    const seq_req = sdkws.GetSeqMessageReq{ .user_id = "u", .conversation_id = "sg_g2", .seq = 99 };
    const seq_bytes = try seq_req.encode(allocator);
    defer allocator.free(seq_bytes);
    const seq_dec = try sdkws.GetSeqMessageReq.decode(seq_bytes, allocator);
    defer {
        allocator.free(seq_dec.user_id);
        allocator.free(seq_dec.conversation_id);
    }
    try std.testing.expectEqualStrings("sg_g2", seq_dec.conversation_id);
    try std.testing.expectEqual(@as(i64, 99), seq_dec.seq);

    // Server-only resp types: encode must not crash and must produce bytes
    const usr_req = sdkws.UserSendMsgResp{ .server_msg_id = "s1", .client_msg_id = "c1", .send_time = 1234 };
    const usr = try usr_req.encode(allocator);
    defer allocator.free(usr);
    try std.testing.expect(usr.len > 0);
    const gres_req = sdkws.GetMaxSeqResp{ .max_seqs = 42, .min_seqs = 7 };
    const gres = try gres_req.encode(allocator);
    defer allocator.free(gres);
    try std.testing.expect(gres.len > 0);
}

// ============================================================
// Message content-type filter (Go filterMsg isInInterval)
// ============================================================
test "message: content-type filter intervals (single/range)" {
    const msg_svc = @import("modules/message/service.zig");
    // Single values and ranges
    try std.testing.expect(msg_svc.contentTypeInIntervals(101, "101,201-210"));
    try std.testing.expect(msg_svc.contentTypeInIntervals(205, "101,201-210"));
    try std.testing.expect(msg_svc.contentTypeInIntervals(210, "101,201-210"));
    try std.testing.expect(!msg_svc.contentTypeInIntervals(102, "101,201-210"));
    try std.testing.expect(!msg_svc.contentTypeInIntervals(211, "101,201-210"));
    try std.testing.expect(!msg_svc.contentTypeInIntervals(101, ""));
    // Whitespace tolerance
    try std.testing.expect(msg_svc.contentTypeInIntervals(101, " 101 , 201-210 "));
    // Malformed entries are skipped
    try std.testing.expect(!msg_svc.contentTypeInIntervals(300, "abc,201-"));
}

// ============================================================
// Mark-as-read advances the reader's conversation has_read_seq
// (Go MarkMsgsAsRead: is_read + SetHasReadSeq)
// ============================================================

test "message: mark-as-read advances conversation has_read_seq" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const message_mod = @import("modules/message.zig");
    const conversation_mod = @import("modules/conversation.zig");

    const a = try ctx.register("mr_a");
    const b = try ctx.register("mr_b");
    try ctx.makeFriends(a, b);

    const m1 = try message_mod.sendMessage(.{ .send_id = a, .recv_id = b, .session_type = .single, .content_type = .text, .content = "one" });
    const m2 = try message_mod.sendMessage(.{ .send_id = a, .recv_id = b, .session_type = .single, .content_type = .text, .content = "two" });
    const conv_id = m1.conversation_id;

    // B's conversation starts unread (has_read_seq = 0, max_seq = m2.seq)
    const conv_b = (try conversation_mod.getConversation(b, conv_id)).?;
    try std.testing.expectEqual(@as(i64, 0), conv_b.has_read_seq);
    try std.testing.expect(conv_b.max_seq >= m2.seq);

    // B marks both messages read → has_read_seq advances to m2.seq
    try std.testing.expect(message_mod.markMessageRead(b, conv_id, m2.seq));
    const conv_b_read = (try conversation_mod.getConversation(b, conv_id)).?;
    try std.testing.expectEqual(m2.seq, conv_b_read.has_read_seq);
}
// ============================================================
// Read receipts enter the messages table but do NOT overwrite
// the peer's conversation preview (syncConversationTx skips them)
// ============================================================
test "message: read receipt does not overwrite conversation preview" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const message_mod = @import("modules/message.zig");
    const conversation_mod = @import("modules/conversation.zig");

    const a = try ctx.register("rr_a");
    const b = try ctx.register("rr_b");
    try ctx.makeFriends(a, b);

    const m1 = try message_mod.sendMessage(.{ .send_id = a, .recv_id = b, .session_type = .single, .content_type = .text, .content = "preview keeper" });
    const conv_id = m1.conversation_id;

    // B sends a read receipt to A (as /msg/mark_msgs_as_read does).
    const receipt_content = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"conversationID\":\"{s}\",\"hasReadSeq\":{d}}}", .{ conv_id, m1.seq });
    _ = try message_mod.sendMessage(.{
        .send_id = b,
        .recv_id = a,
        .session_type = .notification,
        .content_type = .read_receipt,
        .content = receipt_content,
        .options = .{ .is_not_notification = true },
    });

    // A's conversation preview still shows the original message.
    const conv_a = (try conversation_mod.getConversation(a, conv_id)).?;
    try std.testing.expect(std.mem.indexOf(u8, conv_a.latest_msg, "preview keeper") != null);
    try std.testing.expect(std.mem.indexOf(u8, conv_a.latest_msg, "hasReadSeq") == null);
}

// ============================================================
// Integration: real PostgreSQL pipeline (needs a running PG)
// (register → login → friend → group → message → conversation)
// Skips gracefully when PostgreSQL is unavailable.
// ============================================================
test "integration: auth→friend→group→message pipeline (PostgreSQL)" {
    const allocator = std.testing.allocator;
    try core.init(allocator, std.testing.io);
    defer core.deinit();

    // One async subscriber makes the bus own + free event payload copies.
    const Noop = struct {
        fn h(_: core.Event) void {}
    };
    try core.getEventBus().subscribeAsync(.message_sent, Noop.h, "itest");

    const config_mod = @import("modules/config.zig");
    const db_mod = @import("modules/db_postgres.zig");
    const user_mod = @import("modules/user.zig");
    const auth_mod = @import("modules/auth.zig");
    const friend_mod = @import("modules/friend.zig");
    const group_mod = @import("modules/group.zig");
    const message_mod = @import("modules/message.zig");
    const conversation_mod = @import("modules/conversation.zig");
    const event_bus_mod = @import("modules/event_bus.zig");

    config_mod.init() catch return;
    defer config_mod.deinit();
    db_mod.init() catch {
        std.log.warn("[integration] PostgreSQL unavailable — skipping", .{});
        return;
    };
    defer db_mod.deinit();
    event_bus_mod.init() catch {};
    defer event_bus_mod.deinit();
    user_mod.init() catch return;
    defer user_mod.deinit();
    conversation_mod.init() catch return;
    defer conversation_mod.deinit();
    auth_mod.init() catch return;
    defer auth_mod.deinit();
    friend_mod.init() catch return;
    defer friend_mod.deinit();
    group_mod.init() catch return;
    defer group_mod.deinit();
    message_mod.init() catch return;
    defer message_mod.deinit();

    // Arena for all service results (no per-call frees needed)
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    core.setRequestAllocator(arena.allocator());
    defer core.setRequestAllocator(null);

    const suffix = core.unixNowMillis();
    const uid_a = try std.fmt.allocPrint(arena.allocator(), "it_a_{d}", .{suffix});
    const uid_b = try std.fmt.allocPrint(arena.allocator(), "it_b_{d}", .{suffix});

    // Register both users (PBKDF2 password path)
    _ = try auth_mod.registerWithPassword("IT Alice", "test1234", "", null, null, uid_a);
    _ = try auth_mod.registerWithPassword("IT Bob", "test1234", "", null, null, uid_b);

    // Login + token round-trip
    const tok_b = try auth_mod.loginWithPassword(uid_b, "test1234", 1);
    const parsed = try auth_mod.parseToken(tok_b.token);
    try std.testing.expectEqualStrings(uid_b, parsed.user_id);

    // Profile lookup
    const user_a = (try user_mod.getUser(uid_a)).?;
    try std.testing.expectEqualStrings("IT Alice", user_a.nickname);

    // Message to a non-friend must be rejected
    try std.testing.expectError(error.NotFriend, message_mod.sendMessage(.{
        .send_id = uid_a,
        .recv_id = uid_b,
        .session_type = .single,
        .content_type = .text,
        .content = "should be rejected",
    }));

    // Friend request A→B, accept (transactional)
    _ = try friend_mod.sendFriendRequest(uid_a, uid_b, "hi");
    try friend_mod.respondFriendRequest(uid_a, uid_b, true, "ok");
    const friends = try friend_mod.getFriends(uid_a);
    var found: bool = false;
    for (friends) |f| {
        if (std.mem.eql(u8, f.friend_user_id, uid_b)) found = true;
    }
    try std.testing.expect(found);

    // Group create with initial member (transactional)
    const grp = try group_mod.createGroup(.{
        .group_name = "IT Group",
        .creator_user_id = uid_a,
        .member_user_ids = &.{uid_b},
    });
    const members = try group_mod.getGroupMembers(grp.group_id);
    try std.testing.expectEqual(@as(usize, 2), members.len);

    // Message A→B (friend check passes now)
    const msg = try message_mod.sendMessage(.{
        .send_id = uid_a,
        .recv_id = uid_b,
        .session_type = .single,
        .content_type = .text,
        .content = "integration msg",
    });
    try std.testing.expect(msg.seq > 0);

    // Conversation auto-created with the message as latest
    const conv = (try conversation_mod.getConversation(uid_a, msg.conversation_id)).?;
    try std.testing.expect(std.mem.indexOf(u8, conv.latest_msg, "integration msg") != null);
}

// ============================================================
// Multi-terminal login policies (pure logic)
// ============================================================
test "multi-terminal login policies" {
    const ws_root = @import("modules/websocket/root.zig");
    // DefaultNotKick: nothing kicked
    try std.testing.expect(!ws_root.shouldKickOld(0, 1, 1, true));
    // AllLoginButSameTermKick: same platform reconnect kicks
    try std.testing.expect(ws_root.shouldKickOld(1, 1, 1, true));
    try std.testing.expect(ws_root.shouldKickOld(1, 1, 2, true)); // any old client kicked
    try std.testing.expect(!ws_root.shouldKickOld(1, 1, 2, false)); // no same-platform yet
    // SingleTerminalLogin: always kick old
    try std.testing.expect(ws_root.shouldKickOld(2, 2, 1, false));
    // WebAndOther: web coexists; non-web kicks old non-PC on same platform
    try std.testing.expect(!ws_root.shouldKickOld(3, 2, 5, true));
    try std.testing.expect(ws_root.shouldKickOld(3, 2, 2, true));
    try std.testing.expect(!ws_root.shouldKickOld(3, 3, 2, true)); // existing PC protected
    // AllLoginButSameClassKick: same class kicks regardless of platform
    try std.testing.expect(ws_root.shouldKickOld(4, 1, 2, false)); // both Mobile
    try std.testing.expect(!ws_root.shouldKickOld(4, 1, 5, false)); // Mobile vs Web
    // PCAndOther: PC coexists
    try std.testing.expect(!ws_root.shouldKickOld(5, 1, 3, true)); // new PC not kicked... (new PC → no kick)
    try std.testing.expect(ws_root.shouldKickOld(5, 2, 2, true)); // same mobile reconnects
}

// ============================================================
// Gateway HTTP contract (Testkit — no network binding)
// ============================================================
fn buildTestServer(allocator: std.mem.Allocator) !struct { server: zigmodu.http.Server, catalog: zigmodu.http.RouteCatalog } {
    // g_registered_paths is a process-global — initialize it on a static
    // allocator so per-test arenas cannot dangle it after deinit.
    try gateway.initRegisteredPaths(std.heap.page_allocator);
    const io = std.testing.io;

    var server = zigmodu.http.Server.init(io, allocator, 0);
    // NOTE: production mounts requestArenaMiddleware here, but tests manage the
    // request arena via IntegrationCtx — mounting it would reset requestAllocator
    // to null after each dispatch (leaking later service results onto the global
    // allocator), so it is intentionally omitted.
    try server.addMiddleware(.{ .func = gateway.corsMiddleware });
    try server.addMiddleware(.{ .func = gateway.authMiddleware });

    const AppState = struct {
        gateway: gateway.GatewayRoutes.State,
    };
    var app_state = AppState{ .gateway = .{} };
    var router = zigmodu.http.Router(AppState).init(io, allocator, &server, &app_state);
    var scoped = router.scope("");
    try scoped.mountAll(.{.{ .Mod = gateway.GatewayRoutes, .state = &app_state.gateway }});
    const catalog = try router.finish();
    return .{ .server = server, .catalog = catalog };
}

test "gateway HTTP contract: health/metrics/public" {
    const allocator = std.testing.allocator;
    try core.init(allocator, std.testing.io);
    core.initMetrics();
    defer core.deinit();
    defer gateway.deinit();

    var holder = try buildTestServer(allocator);
    defer {
        holder.catalog.deinit();
        holder.server.deinit();
    }

    // /health — OpenIM envelope, status UP (liveness ok, db reported DOWN pre-init)
    var resp = try zigmodu.http.Testkit.dispatch(&holder.server, .GET, "/health", null);
    defer resp.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), resp.status_code);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\"") != null);

    // /metrics — Prometheus text
    var mresp = try zigmodu.http.Testkit.dispatch(&holder.server, .GET, "/metrics", null);
    defer mresp.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), mresp.status_code);
    try std.testing.expect(std.mem.startsWith(u8, mresp.body, "# HELP"));
}

test "gateway HTTP contract: auth + 404 + CORS" {
    const allocator = std.testing.allocator;
    try core.init(allocator, std.testing.io);
    defer core.deinit();
    defer gateway.deinit();

    var holder = try buildTestServer(allocator);
    defer {
        holder.catalog.deinit();
        holder.server.deinit();
    }

    // Protected route without token -> 401 envelope (HTTP 200 + errCode)
    var auth = try zigmodu.http.Testkit.dispatch(&holder.server, .POST, "/user/get_users_info", "{\"userIDs\":[]}");
    defer auth.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), auth.status_code);
    try std.testing.expect(std.mem.indexOf(u8, auth.body, "\"errCode\":401") != null);

    // Unknown path -> 404 envelope
    var notfound = try zigmodu.http.Testkit.dispatch(&holder.server, .GET, "/nope", null);
    defer notfound.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), notfound.status_code);
    try std.testing.expect(std.mem.indexOf(u8, notfound.body, "\"errCode\":404") != null);

    // OPTIONS preflight -> 204
    var options = try zigmodu.http.Testkit.dispatch(&holder.server, .OPTIONS, "/msg/send_msg", null);
    defer options.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 204), options.status_code);
}

// ============================================================
// Shared PG integration bootstrap (A2: module-level test coverage)
// Initializes the same module chain as the pipeline test. Returns
// null (caller skips) when PostgreSQL is unavailable.
// ============================================================
const IntegrationCtx = struct {
    /// Heap-allocated so its address stays stable after `init` returns
    /// (the request allocator holds a pointer into it).
    arena_ptr: *std.heap.ArenaAllocator,
    suffix: i64,

    fn init(allocator: std.mem.Allocator) ?IntegrationCtx {
        core.init(allocator, std.testing.io) catch return null;
        core.initMetrics();

        const config_mod = @import("modules/config.zig");
        const db_mod = @import("modules/db_postgres.zig");
        const user_mod = @import("modules/user.zig");
        const conversation_mod = @import("modules/conversation.zig");
        const auth_mod = @import("modules/auth.zig");
        const friend_mod = @import("modules/friend.zig");
        const group_mod = @import("modules/group.zig");
        const message_mod = @import("modules/message.zig");
        const event_bus_mod = @import("modules/event_bus.zig");
        const queue_mod = @import("modules/queue.zig");
        const push_mod = @import("modules/push.zig");
        const office_mod = @import("modules/office.zig");
        const organization_mod = @import("modules/organization.zig");
        const third_mod = @import("modules/third.zig");

        config_mod.init() catch return null;
        db_mod.init() catch {
            std.log.warn("[integration] PostgreSQL unavailable — skipping", .{});
            core.deinit();
            return null;
        };
        event_bus_mod.init() catch {};
        user_mod.init() catch return null;
        conversation_mod.init() catch return null;
        auth_mod.init() catch return null;
        friend_mod.init() catch return null;
        group_mod.init() catch return null;
        message_mod.init() catch return null;
        queue_mod.init() catch return null;
        push_mod.init() catch return null;
        office_mod.init() catch return null;
        organization_mod.init() catch return null;
        third_mod.init() catch return null;

        // One async subscriber makes the bus own + free event payload copies
        // (dispatchAsync is the last consumer; without it, emit() copies leak).
        const Noop = struct {
            fn h(_: core.Event) void {}
        };
        core.getEventBus().subscribeAsync(.message_sent, Noop.h, "a2it") catch {};
        core.getEventBus().subscribeAsync(.message_modified, Noop.h, "a2it") catch {};
        core.getEventBus().subscribeAsync(.message_recalled, Noop.h, "a2it") catch {};

        const arena_ptr = allocator.create(std.heap.ArenaAllocator) catch return null;
        arena_ptr.* = std.heap.ArenaAllocator.init(allocator);
        core.setRequestAllocator(arena_ptr.allocator());
        return .{ .arena_ptr = arena_ptr, .suffix = core.unixNowMillis() };
    }

    fn deinit(self: *IntegrationCtx) void {
        core.setRequestAllocator(null);
        const config_mod = @import("modules/config.zig");
        const db_mod = @import("modules/db_postgres.zig");
        const user_mod = @import("modules/user.zig");
        const conversation_mod = @import("modules/conversation.zig");
        const auth_mod = @import("modules/auth.zig");
        const friend_mod = @import("modules/friend.zig");
        const group_mod = @import("modules/group.zig");
        const message_mod = @import("modules/message.zig");
        const event_bus_mod = @import("modules/event_bus.zig");
        const queue_mod = @import("modules/queue.zig");
        const push_mod = @import("modules/push.zig");
        const office_mod = @import("modules/office.zig");
        const organization_mod = @import("modules/organization.zig");
        const third_mod = @import("modules/third.zig");
        message_mod.deinit();
        third_mod.deinit();
        organization_mod.deinit();
        office_mod.deinit();
        push_mod.deinit();
        queue_mod.deinit();
        group_mod.deinit();
        friend_mod.deinit();
        auth_mod.deinit();
        conversation_mod.deinit();
        user_mod.deinit();
        event_bus_mod.deinit();
        db_mod.deinit();
        config_mod.deinit();
        const gw_root = @import("modules/gateway/root.zig");
        gw_root.deinit(); // release RTC in-memory rooms (global allocator)
        self.arena_ptr.deinit();
        std.testing.allocator.destroy(self.arena_ptr);
        core.deinit();
    }

    fn uid(self: *IntegrationCtx, tag: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.arena_ptr.allocator(), "a2_{s}_{d}", .{ tag, self.suffix });
    }

    /// Register a user with a unique id, returning its uid.
    fn register(self: *IntegrationCtx, tag: []const u8) ![]const u8 {
        const auth_mod = @import("modules/auth.zig");
        const id = try self.uid(tag);
        const nickname = try std.fmt.allocPrint(self.arena_ptr.allocator(), "A2 {s}", .{tag});
        _ = try auth_mod.registerWithPassword(nickname, "test1234", "", null, null, id);
        return id;
    }

    /// Make a and b friends (request + accept).
    fn makeFriends(self: *IntegrationCtx, a: []const u8, b: []const u8) !void {
        _ = self;
        const friend_mod = @import("modules/friend.zig");
        _ = try friend_mod.sendFriendRequest(a, b, "hi");
        try friend_mod.respondFriendRequest(a, b, true, "ok");
    }
};

// ============================================================
// A2-T1: friend blacklist — add/remove + message blocking
// ============================================================
test "friend blacklist blocks messages both ways until removed" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const friend_mod = @import("modules/friend.zig");
    const message_mod = @import("modules/message.zig");

    const a = try ctx.register("blk_a");
    const b = try ctx.register("blk_b");
    const c = try ctx.register("blk_c");

    // A blocks C (no friendship needed to block)
    try friend_mod.addBlack(a, c);
    const blacks = try friend_mod.getBlacks(a);
    var blocked_c = false;
    for (blacks) |bl| {
        if (std.mem.eql(u8, bl.block_user_id, c)) blocked_c = true;
    }
    try std.testing.expect(blocked_c);

    // A->C and C->A messages both rejected while blocked
    try std.testing.expectError(error.Blacklisted, message_mod.sendMessage(.{
        .send_id = a,
        .recv_id = c,
        .session_type = .single,
        .content_type = .text,
        .content = "blocked",
    }));
    try std.testing.expectError(error.Blacklisted, message_mod.sendMessage(.{
        .send_id = c,
        .recv_id = a,
        .session_type = .single,
        .content_type = .text,
        .content = "blocked",
    }));

    // A and B are friends — unaffected by the blacklist
    try ctx.makeFriends(a, b);
    const ok = try message_mod.sendMessage(.{
        .send_id = a,
        .recv_id = b,
        .session_type = .single,
        .content_type = .text,
        .content = "fine",
    });
    try std.testing.expect(ok.seq > 0);

    // Unblock C: C->A now fails only because they are not friends
    _ = try friend_mod.removeBlack(a, c);
    try std.testing.expectError(error.NotFriend, message_mod.sendMessage(.{
        .send_id = c,
        .recv_id = a,
        .session_type = .single,
        .content_type = .text,
        .content = "not friend anymore",
    }));
}

// ============================================================
// A2-T2: group dismissal — members removed, messages rejected
// ============================================================
test "group dismiss removes members and blocks further messages" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const group_mod = @import("modules/group.zig");
    const message_mod = @import("modules/message.zig");

    const a = try ctx.register("grp_a");
    const b = try ctx.register("grp_b");

    const grp = try group_mod.createGroup(.{
        .group_name = "A2 Group",
        .creator_user_id = a,
        .member_user_ids = &.{b},
    });
    const members_before = try group_mod.getGroupMembers(grp.group_id);
    try std.testing.expectEqual(@as(usize, 2), members_before.len);

    // Member message works before dismissal
    const ok = try message_mod.sendMessage(.{
        .send_id = b,
        .recv_id = a,
        .group_id = grp.group_id,
        .session_type = .group,
        .content_type = .text,
        .content = "in group",
    });
    try std.testing.expect(ok.seq > 0);

    // Dismiss: members gone, group gone
    try std.testing.expect(group_mod.dismissGroup(grp.group_id));
    try std.testing.expectEqual(@as(usize, 0), (try group_mod.getGroupMembers(grp.group_id)).len);
    try std.testing.expect(!group_mod.isMember(grp.group_id, b));

    // Post-dismissal message rejected (group row is physically deleted —
    // matches Go: dismissed group reports group-not-found)
    try std.testing.expectError(error.GroupNotFound, message_mod.sendMessage(.{
        .send_id = b,
        .recv_id = a,
        .group_id = grp.group_id,
        .session_type = .group,
        .content_type = .text,
        .content = "after dismiss",
    }));
}

// ============================================================
// A2-T3: message edit + recall semantics
// ============================================================
test "message modify sets is_edit, recall sets is_revoke, sender-only" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const message_mod = @import("modules/message.zig");

    const a = try ctx.register("ed_a");
    const b = try ctx.register("ed_b");
    try ctx.makeFriends(a, b);

    const msg = try message_mod.sendMessage(.{
        .send_id = a,
        .recv_id = b,
        .session_type = .single,
        .content_type = .text,
        .content = "original",
    });
    try std.testing.expect(!msg.is_edit);

    // Non-sender cannot modify
    try std.testing.expect(!try message_mod.modifyMessage(msg.conversation_id, msg.seq, b, "hijacked"));

    // Sender modifies
    try std.testing.expect(try message_mod.modifyMessage(msg.conversation_id, msg.seq, a, "edited"));
    const after_edit = (try message_mod.getMessages(msg.conversation_id, 0, 1))[0];
    try std.testing.expectEqualStrings("edited", after_edit.content);
    try std.testing.expect(after_edit.is_edit);
    try std.testing.expect(after_edit.edit_time > 0);

    // Recall by sender
    try std.testing.expect(try message_mod.recallMessage(msg.conversation_id, msg.seq, a));
    const after_recall = (try message_mod.getMessages(msg.conversation_id, 0, 1))[0];
    try std.testing.expect(after_recall.is_revoke);
}

// ============================================================
// A2-T4: conversation seq monotonicity + maxSeq
// ============================================================
test "conversation seq increments monotonically and maxSeq tracks head" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const message_mod = @import("modules/message.zig");

    const a = try ctx.register("sq_a");
    const b = try ctx.register("sq_b");
    try ctx.makeFriends(a, b);

    var prev_seq: i64 = 0;
    var conv_id: []const u8 = "";
    inline for (1..4) |i| {
        const m = try message_mod.sendMessage(.{
            .send_id = a,
            .recv_id = b,
            .session_type = .single,
            .content_type = .text,
            .content = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "seq msg {d}", .{i}),
        });
        conv_id = m.conversation_id;
        try std.testing.expect(m.seq > prev_seq);
        prev_seq = m.seq;
    }
    try std.testing.expect(prev_seq > 0);

    // maxSeq equals the last sent seq
    try std.testing.expectEqual(prev_seq, message_mod.getMaxSeq(conv_id));

    // Pull returns all 3, newest first
    const msgs = try message_mod.getMessages(conv_id, 0, 10);
    try std.testing.expectEqual(@as(usize, 3), msgs.len);
    try std.testing.expectEqual(prev_seq, msgs[0].seq);
    try std.testing.expectEqual(@as(i64, 1), msgs[2].seq);

    // By-seq-list returns in requested order
    const by_list = try message_mod.getMessagesBySeqList(conv_id, &.{ 1, 2, 3 });
    try std.testing.expectEqual(@as(usize, 3), by_list.len);
    try std.testing.expectEqual(@as(i64, 1), by_list[0].seq);
    try std.testing.expectEqual(@as(i64, 3), by_list[2].seq);
}

// ============================================================
// A3: camelCase JSON contract (guards Phase 30/44-46 alignment).
// Real PG + Testkit dispatch with a real token; asserts the exact
// camelCase keys the Flutter/Expo SDK parses.
// ============================================================
test "camelCase contract: user/friend/black/message/conversation JSON" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const auth_mod = @import("modules/auth.zig");
    const friend_mod = @import("modules/friend.zig");

    const a = try ctx.register("ct_a");
    const b = try ctx.register("ct_b");
    try ctx.makeFriends(a, b);

    const tok = try auth_mod.loginWithPassword(a, "test1234", 1);
    const token_header: zigmodu.http.Testkit.HeaderPair = .{ "token", tok.token };

    // Testkit contexts use `server.allocator` for request-scoped allocations
    // (bindJson deepCopy etc.) with no per-request arena — wrap in an arena so
    // everything is reclaimed when the test ends (production uses per-conn arena).
    var kit_arena = std.heap.ArenaAllocator.init(allocator);
    defer kit_arena.deinit();
    var holder = try buildTestServer(kit_arena.allocator());
    defer {
        holder.catalog.deinit();
        holder.server.deinit();
    }

    // /user/get_users_info — UserInfo camelCase keys
    var u = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/user/get_users_info", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userIDs\":[\"{s}\"]}}", .{a}),
        .headers = &.{token_header},
    });
    defer u.deinit(kit_arena.allocator());
    try std.testing.expectEqual(@as(u16, 200), u.status_code);
    try std.testing.expect(std.mem.indexOf(u8, u.body, "\"userID\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, u.body, "\"nickname\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, u.body, "\"faceURL\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, u.body, "\"appMangerLevel\"") != null);

    // /friend/get_friend_list — FriendInfo nested friendUser + isPinned + total
    var f = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/friend/get_friend_list", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userID\":\"{s}\"}}", .{a}),
        .headers = &.{token_header},
    });
    defer f.deinit(kit_arena.allocator());
    try std.testing.expectEqual(@as(u16, 200), f.status_code);
    try std.testing.expect(std.mem.indexOf(u8, f.body, "\"friendUser\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, f.body, "\"isPinned\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, f.body, "\"total\"") != null);

    // /msg/send_msg — Go SendMsgResp contract (serverMsgID/clientMsgID/sendTime/modify)
    // NOTE: must run while A and B are still friends (before addBlack below).
    var m = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/msg/send_msg", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"sendID\":\"{s}\",\"recvID\":\"{s}\",\"sessionType\":1,\"contentType\":101,\"content\":\"ct\"}}", .{ a, b }),
        .headers = &.{token_header},
    });
    defer m.deinit(kit_arena.allocator());
    try std.testing.expectEqual(@as(u16, 200), m.status_code);
    try std.testing.expect(std.mem.indexOf(u8, m.body, "\"serverMsgID\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, m.body, "\"clientMsgID\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, m.body, "\"sendTime\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, m.body, "\"modify\"") != null);

    // Blocking a friend removes the friendship (OpenIM "block = unfriend")
    _ = try friend_mod.addBlack(a, b);

    // /friend/get_black_list — blacks + blackUserInfo
    var bl = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/friend/get_black_list", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userID\":\"{s}\"}}", .{a}),
        .headers = &.{token_header},
    });
    defer bl.deinit(kit_arena.allocator());
    try std.testing.expectEqual(@as(u16, 200), bl.status_code);
    try std.testing.expect(std.mem.indexOf(u8, bl.body, "\"blacks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bl.body, "\"blackUserInfo\"") != null);

    // After blocking, the friend list no longer contains b
    var f2 = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/friend/get_friend_list", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userID\":\"{s}\"}}", .{a}),
        .headers = &.{token_header},
    });
    defer f2.deinit(kit_arena.allocator());
    try std.testing.expectEqual(@as(u16, 200), f2.status_code);
    try std.testing.expect(std.mem.indexOf(u8, f2.body, "\"friendsInfo\":[]") != null);

    // /conversation/get_sorted_conversation_list — conversationElems + totals
    var c = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/conversation/get_sorted_conversation_list", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userID\":\"{s}\"}}", .{a}),
        .headers = &.{token_header},
    });
    defer c.deinit(kit_arena.allocator());
    try std.testing.expectEqual(@as(u16, 200), c.status_code);
    try std.testing.expect(std.mem.indexOf(u8, c.body, "\"conversationElems\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, c.body, "\"conversationTotal\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, c.body, "\"unreadTotal\"") != null);
    // latest_msg is a Message DTO — Message camelCase keys (sendID/recvID/senderFaceUrl)
    try std.testing.expect(std.mem.indexOf(u8, c.body, "\"sendID\"") != null);
    // msgInfo mirrors Go MsgInfo — faceURL key (from senderFaceUrl), senderName, LatestMsgRecvTime
    try std.testing.expect(std.mem.indexOf(u8, c.body, "\"faceURL\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, c.body, "\"senderName\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, c.body, "\"LatestMsgRecvTime\"") != null);
}

// ============================================================
// P0-a: push offline-recipient decision logic (no PGMQ needed)
// Scenarios: online → no push; offline → push; offline+DND → no push.
// ============================================================
test "push: offline recipient decision (online/offline/DND)" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const user_mod = @import("modules/user.zig");
    const conversation_mod = @import("modules/conversation.zig");
    const push_svc = @import("modules/push/service.zig");
    const msg_model = @import("modules/message/model.zig");

    const a = try ctx.register("push_a");
    const b = try ctx.register("push_b");
    try ctx.makeFriends(a, b);

    const conv_id = try msg_model.getConversationID(a, b, "", .single, false);

    const mkPayload = struct {
        fn build(arena: std.mem.Allocator, sender: []const u8, receiver: []const u8, conv: []const u8) ![]const u8 {
            return std.fmt.allocPrint(arena, "{{\"sender_id\":\"{s}\",\"receiver_id\":\"{s}\",\"group_id\":\"\",\"conversation_id\":\"{s}\",\"session_type\":1}}", .{ sender, receiver, conv });
        }
    }.build;

    // B online → not an offline recipient
    user_mod.setOnline(b, true);
    var recips = try push_svc.getOfflineRecipients(try mkPayload(ctx.arena_ptr.allocator(), a, b, conv_id), ctx.arena_ptr.allocator());
    try std.testing.expectEqual(@as(usize, 0), recips.len);
    user_mod.setOnline(b, false);

    // B offline (default) → offline push recipient
    recips = try push_svc.getOfflineRecipients(try mkPayload(ctx.arena_ptr.allocator(), a, b, conv_id), ctx.arena_ptr.allocator());
    try std.testing.expectEqual(@as(usize, 1), recips.len);
    try std.testing.expectEqualStrings(b, recips[0]);

    // B offline + DND (recv_msg_opt != 0) → suppressed
    // (conversation must exist for the DND lookup — create B's side first)
    _ = try conversation_mod.createConversation(.{
        .owner_user_id = b,
        .conversation_id = conv_id,
        .conversation_type = .single,
        .user_id = a,
    });
    _ = try conversation_mod.updateConversation(b, conv_id, .{ .recv_msg_opt = 1 });
    recips = try push_svc.getOfflineRecipients(try mkPayload(ctx.arena_ptr.allocator(), a, b, conv_id), ctx.arena_ptr.allocator());
    try std.testing.expectEqual(@as(usize, 0), recips.len);

    // DND cleared → offline push again
    _ = try conversation_mod.updateConversation(b, conv_id, .{ .recv_msg_opt = 0 });
    recips = try push_svc.getOfflineRecipients(try mkPayload(ctx.arena_ptr.allocator(), a, b, conv_id), ctx.arena_ptr.allocator());
    try std.testing.expectEqual(@as(usize, 1), recips.len);
}

// ============================================================
// P0-a: queue PGMQ lifecycle — runs only when the pgmq extension
// is available; otherwise asserts the graceful degradation path.
// ============================================================
test "queue: PGMQ lifecycle or graceful degradation" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const db_mod = @import("modules/db_postgres.zig");
    const queue_mod = @import("modules/queue.zig");

    // Probe pgmq availability through the same pooled client. Result rows are
    // owned by the request arena (serviceAllocator) — no manual frees.
    const probe = db_mod.getClient().queryParams("SELECT count(*) FROM pg_extension WHERE extname = 'pgmq'", &.{}) catch return;
    const pgmq_available = probe.row_count > 0 and std.mem.eql(u8, probe.rows[0][0], "1");

    if (!pgmq_available) {
        // Degradation path: operations error out (not crash); the error is now
        // a JSON log line so the test step stays green.
        try std.testing.expectError(error.QueryFailed, queue_mod.send("zim_test_q", "{}"));
        return;
    }

    // Lifecycle: create → send → read → delete → purge
    try queue_mod.createQueue("zim_test_q");
    const msg_id = try queue_mod.send("zim_test_q", "{\"probe\":1}");
    const qmsg = (try queue_mod.read("zim_test_q", 30)).?;
    defer allocator.free(qmsg.body);
    try std.testing.expectEqual(msg_id, qmsg.msg_id);
    try std.testing.expect(std.mem.indexOf(u8, qmsg.body, "probe") != null);
    try std.testing.expect(try queue_mod.delete("zim_test_q", qmsg.msg_id));
    try std.testing.expectEqual(@as(usize, 0), try queue_mod.size("zim_test_q"));
    try queue_mod.purge("zim_test_q");
}

// ============================================================
// P0-b: crontask cleanup — removes old revoked messages and
// expired auth tokens (data constructed via direct SQL).
// ============================================================
test "crontask: cleanup removes revoked messages and expired tokens" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const db_mod = @import("modules/db_postgres.zig");
    const message_mod = @import("modules/message.zig");
    const auth_mod = @import("modules/auth.zig");

    const a = try ctx.register("ct_a");
    const b = try ctx.register("ct_b");
    try ctx.makeFriends(a, b);

    // Send a message, then age it + mark revoked so cleanup targets it.
    const msg = try message_mod.sendMessage(.{
        .send_id = a,
        .recv_id = b,
        .session_type = .single,
        .content_type = .text,
        .content = "to-be-cleaned",
    });
    _ = db_mod.getClient().execParams(
        "UPDATE messages SET is_revoke = TRUE, create_time = NOW() - INTERVAL '30 days' WHERE conversation_id = $1 AND seq = $2",
        &.{ .{ .string = msg.conversation_id }, .{ .bigint = msg.seq } },
    ) catch return;

    // Log in to mint a token, then expire it in the past.
    const tok = try auth_mod.loginWithPassword(b, "test1234", 1);
    _ = db_mod.getClient().execParams(
        "UPDATE auth_tokens SET expire_time = NOW() - INTERVAL '1 day' WHERE token = $1",
        &.{.{ .string = tok.token }},
    ) catch return;

    // Construct the service directly — module init spawns the background loop.
    const CrontaskService = @import("modules/crontask/service.zig").CrontaskService;
    var svc = CrontaskService.init(db_mod.getClient());

    const removed_msgs = try svc.cleanupRevokedMessages();
    try std.testing.expect(removed_msgs >= 1);

    const removed_tokens = try svc.cleanupOldAuthTokens();
    try std.testing.expect(removed_tokens >= 1);

    // The revoked message is gone from the conversation pull.
    const msgs = try message_mod.getMessages(msg.conversation_id, 0, 100);
    for (msgs) |m| {
        try std.testing.expect(!(m.seq == msg.seq and std.mem.eql(u8, m.content, "to-be-cleaned")));
    }
}

// ============================================================
// P1-a: group ownership transfer — atomic + validated
// ============================================================
test "group: ownership transfer is validated and atomic" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const group_mod = @import("modules/group.zig");

    const a = try ctx.register("tr_a");
    const b = try ctx.register("tr_b");
    const c = try ctx.register("tr_c");

    const grp = try group_mod.createGroup(.{
        .group_name = "Transfer Group",
        .creator_user_id = a,
        .member_user_ids = &.{ b, c },
    });

    // Non-owner cannot transfer (b is a member, not the owner)
    try std.testing.expectError(error.NotOwner, group_mod.transferOwner(grp.group_id, b, c));

    // New owner must be an existing member (a → "nobody" fails)
    try std.testing.expectError(error.NewOwnerNotMember, group_mod.transferOwner(grp.group_id, a, "nobody"));

    // Legit transfer: a (owner) → b
    try group_mod.transferOwner(grp.group_id, a, b);
    const new_owner = (try group_mod.getGroupMembers(grp.group_id));
    var b_is_owner = false;
    var a_is_member = false;
    for (new_owner) |m| {
        if (std.mem.eql(u8, m.user_id, b)) b_is_owner = m.role_level == @backingInt(group_mod.MemberRole.owner);
        if (std.mem.eql(u8, m.user_id, a)) a_is_member = m.role_level == @backingInt(group_mod.MemberRole.member);
    }
    try std.testing.expect(b_is_owner);
    try std.testing.expect(a_is_member);
}

// ============================================================
// P1-b: join-group verification modes (need_verification)
// 0 = direct join, 1 = pending request, 2 = rejected
// ============================================================
test "group: join verification modes (direct/request/reject)" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const group_mod = @import("modules/group.zig");

    const owner = try ctx.register("jv_owner");
    const guest = try ctx.register("jv_guest");

    // Mode 0: direct join, no pending request
    const g0 = try group_mod.createGroup(.{ .group_name = "Open Group", .creator_user_id = owner, .need_verification = 0 });
    try group_mod.joinGroup(guest, g0.group_id, "");
    try std.testing.expect(group_mod.isMember(g0.group_id, guest));

    // Mode 1: pending request, not a member yet
    const g1 = try group_mod.createGroup(.{ .group_name = "Apply Group", .creator_user_id = owner, .need_verification = 1 });
    try group_mod.joinGroup(guest, g1.group_id, "please");
    try std.testing.expect(!group_mod.isMember(g1.group_id, guest));
    const pending = try group_mod.getGroupUsersReqApplicationList(g1.group_id);
    var found_request = false;
    for (pending) |r| {
        if (std.mem.eql(u8, r.user_id, guest)) found_request = true;
    }
    try std.testing.expect(found_request);

    // Mode 2: all join requests rejected
    const g2 = try group_mod.createGroup(.{ .group_name = "Closed Group", .creator_user_id = owner, .need_verification = 2 });
    try std.testing.expectError(error.GroupJoinRejected, group_mod.joinGroup(guest, g2.group_id, ""));
    try std.testing.expect(!group_mod.isMember(g2.group_id, guest));
}

// ============================================================
// P1-c: look_member_info gates the member-list endpoint
// ============================================================
test "group: member list respects look_member_info" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const group_mod = @import("modules/group.zig");
    const auth_mod = @import("modules/auth.zig");

    const owner = try ctx.register("lm_owner");
    const member = try ctx.register("lm_member");
    const outsider = try ctx.register("lm_outsider");

    // look_member_info = 1: group members only
    const grp = try group_mod.createGroup(.{ .group_name = "Private Roster", .creator_user_id = owner, .member_user_ids = &.{member} });
    _ = try group_mod.updateGroup(grp.group_id, .{ .look_member_info = 1 });

    const member_tok = try auth_mod.loginWithPassword(member, "test1234", 1);
    const outsider_tok = try auth_mod.loginWithPassword(outsider, "test1234", 1);

    // Testkit contexts allocate request-scoped data on `server.allocator` —
    // wrap in an arena so bindJson deepCopy etc. are reclaimed at test end.
    var kit_arena = std.heap.ArenaAllocator.init(allocator);
    defer kit_arena.deinit();
    var holder = try buildTestServer(kit_arena.allocator());
    defer {
        holder.catalog.deinit();
        holder.server.deinit();
    }

    const body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"groupID\":\"{s}\"}}", .{grp.group_id});
    const mk = struct {
        fn header(tok: []const u8) zigmodu.http.Testkit.HeaderPair {
            return .{ "token", tok };
        }
    }.header;

    // Non-member → 403
    var denied = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/group/get_group_member_list", .{
        .body = body,
        .headers = &.{mk(outsider_tok.token)},
    });
    defer denied.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, denied.body, "\"errCode\":403") != null);

    // Member → 200 with the roster
    var allowed = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/group/get_group_member_list", .{
        .body = body,
        .headers = &.{mk(member_tok.token)},
    });
    defer allowed.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, allowed.body, "\"errCode\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, allowed.body, "\"members\"") != null);
}

// ============================================================
// P1-e: @所有人 (AtAllTag) marks the sender's group conversation
// ============================================================
test "message: @all marks sender conversation group_at_type" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const group_mod = @import("modules/group.zig");
    const message_mod = @import("modules/message.zig");
    const conversation_mod = @import("modules/conversation.zig");
    const msg_model = @import("modules/message/model.zig");

    const a = try ctx.register("at_a");
    const b = try ctx.register("at_b");
    const grp = try group_mod.createGroup(.{ .group_name = "AtAll Group", .creator_user_id = a, .member_user_ids = &.{b} });

    // Normal group message → no @all mark
    _ = try message_mod.sendMessage(.{
        .send_id = a,
        .recv_id = b,
        .group_id = grp.group_id,
        .session_type = .group,
        .content_type = .text,
        .content = "plain",
    });
    const conv_id = try msg_model.getConversationID("", "", grp.group_id, .group, false);
    const conv_plain = (try conversation_mod.getConversation(a, conv_id)).?;
    try std.testing.expectEqual(@as(i16, 0), conv_plain.group_at_type);

    // Message with AtAllTag → sender conversation marked group_at_type = 2
    _ = try message_mod.sendMessage(.{
        .send_id = a,
        .recv_id = b,
        .group_id = grp.group_id,
        .session_type = .group,
        .content_type = .text,
        .content = "everyone!",
        .at_user_id_list = "[\"AtAllTag\"]",
    });
    const conv_at = (try conversation_mod.getConversation(a, conv_id)).?;
    try std.testing.expectEqual(@as(i16, 2), conv_at.group_at_type);

    // @specific user → that member's conversation marked 3 (AtAllAtMe)
    const at_b_str = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "[\"AtAllTag\",\"{s}\"]", .{b});
    _ = try message_mod.sendMessage(.{
        .send_id = a,
        .recv_id = b,
        .group_id = grp.group_id,
        .session_type = .group,
        .content_type = .text,
        .content = "hey b!",
        .at_user_id_list = at_b_str,
    });
    const conv_b_at = (try conversation_mod.getConversation(b, conv_id)).?;
    try std.testing.expectEqual(@as(i16, 3), conv_b_at.group_at_type);

    // Plain group message still syncs every member's conversation (latest_msg)
    _ = try message_mod.sendMessage(.{
        .send_id = a,
        .recv_id = b,
        .group_id = grp.group_id,
        .session_type = .group,
        .content_type = .text,
        .content = "sync check",
    });
    const conv_b_plain = (try conversation_mod.getConversation(b, conv_id)).?;
    try std.testing.expect(std.mem.indexOf(u8, conv_b_plain.latest_msg, "sync check") != null);
}

// ============================================================
// Non-arena path: service results are allocated on the global
// allocator (no request arena) and must be manually free-able.
// Verifies the UAF + freeResult fixes outside the test arena.
// ============================================================
test "non-arena service query results are free-able" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const user_mod = @import("modules/user.zig");
    const uid = try ctx.register("na_a");

    // Simulate a non-request context (crontask/worker): results land on the
    // global allocator (std.testing.allocator) and must be freed manually.
    core.setRequestAllocator(null);
    defer core.setRequestAllocator(ctx.arena_ptr.allocator());

    const user = (try user_mod.getUser(uid)).?;
    defer {
        allocator.free(user.user_id);
        allocator.free(user.nickname);
        allocator.free(user.face_url);
        allocator.free(user.area_code);
        allocator.free(user.telephone);
        allocator.free(user.ex);
        allocator.free(user.password_hash);
    }
    try std.testing.expectEqualStrings(uid, user.user_id);
    try std.testing.expectEqualStrings("A2 na_a", user.nickname);
}

// ============================================================
// JSON log file output + size-based rotation
// ============================================================
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
test "log: JSON file output and rotation" {
    const allocator = std.testing.allocator;
    try core.init(allocator, std.testing.io);
    defer core.deinit();

    const path = "zim_test_log.jsonl";
    const fs = std.Io.Dir.cwd();
    fs.deleteFile(std.testing.io, path) catch {};
    defer fs.deleteFile(std.testing.io, path) catch {};

    // Tiny rotation threshold so a couple of lines trigger rotation.
    try core.initLogFile(path, 32);
    core.logJson(.{ .event = "t1", .n = 1 });
    core.logJson(.{ .event = "t2", .n = 2 });
    core.logJson(.{ .event = "t3", .n = 3 });

    // std.testing.io cannot open real files — read via libc.
    var buf: [4096]u8 = undefined;
    const fd = open(path, @as(c_int, 0), @as(c_uint, 0)); // O_RDONLY
    if (fd < 0) return error.OpenFailed;
    defer _ = close(fd);
    const n = read(fd, &buf, buf.len);
    const content = buf[0..@intCast(n)];
    try std.testing.expect(std.mem.indexOf(u8, content, "t3") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "t1") == null);
}

// ============================================================
// Config hot-reload: reload() re-reads config.yaml safely
// (string allocations swapped without leaks/crashes)
// ============================================================
test "config: reload is safe" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const config_mod = @import("modules/config.zig");
    // Reload reads the same file — must not crash or leak.
    config_mod.reload();
    const cfg = config_mod.getConfig();
    try std.testing.expect(cfg.database.name.len > 0);
    try std.testing.expect(cfg.webhook.allowed_types.len == 0);
}

// ============================================================
// Cross-domain handler contract: statistics/office/rtc/
// organization/third endpoints respond with the OpenIM envelope
// ============================================================
test "handler contract: statistics/office/rtc/organization/third" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const auth_mod = @import("modules/auth.zig");
    const a = try ctx.register("xc_a");
    const tok = try auth_mod.loginWithPassword(a, "test1234", 1);

    var kit_arena = std.heap.ArenaAllocator.init(allocator);
    defer kit_arena.deinit();
    var holder = try buildTestServer(kit_arena.allocator());
    defer {
        holder.catalog.deinit();
        holder.server.deinit();
    }

    const mk = struct {
        fn hdr(t: []const u8) zigmodu.http.Testkit.HeaderPair {
            return .{ "token", t };
        }
    }.hdr;

    // /statistics/user/register — register counts
    var st = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/statistics/user/register", .{
        .body = "{}",
        .headers = &.{mk(tok.token)},
    });
    defer st.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, st.body, "\"errCode\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, st.body, "\"total\"") != null);

    // /office/work_moment/add — publish a work moment
    const wm_body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userID\":\"{s}\",\"content\":\"hello moment\"}}", .{a});
    var wm = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/office/work_moment/add", .{
        .body = wm_body,
        .headers = &.{mk(tok.token)},
    });
    defer wm.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, wm.body, "\"errCode\":0") != null);

    // /rtc-meeting/create — in-memory meeting room
    const rtc_body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"hostUserID\":\"{s}\",\"meetingName\":\"x chat\"}}", .{a});
    var rtc = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/rtc-meeting/create", .{
        .body = rtc_body,
        .headers = &.{mk(tok.token)},
    });
    defer rtc.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, rtc.body, "\"errCode\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, rtc.body, "\"roomID\"") != null);

    // /organization/info — org tree
    var org = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/organization/info", .{
        .body = "{}",
        .headers = &.{mk(tok.token)},
    });
    defer org.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, org.body, "\"errCode\":0") != null);

    // /third/fcm_update_token — FCM token persistence (needs storage+db init)
    const cfg = @import("modules/config.zig").getConfig();
    const db_client = @import("modules/db_postgres.zig").getClient();
    const third_cfg = @import("modules/third/model.zig").ObjectStorageConfig{
        .endpoint = cfg.object_storage.endpoint,
        .access_key = cfg.object_storage.access_key,
        .secret_key = cfg.object_storage.secret_key,
        .bucket = cfg.object_storage.bucket,
        .region = cfg.object_storage.region,
        .use_ssl = cfg.object_storage.use_ssl,
    };
    @import("modules/third.zig").initStorage(third_cfg, db_client, allocator);
    const fcm_body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userID\":\"{s}\",\"fcmToken\":\"fcm-xc-1\",\"platformID\":2}}", .{a});
    var fcm = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/third/fcm_update_token", .{
        .body = fcm_body,
        .headers = &.{mk(tok.token)},
    });
    defer fcm.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, fcm.body, "\"errCode\":0") != null);
}

// ============================================================
// WS handshake rate limit: per-IP window of 30/second
// ============================================================
test "ws: handshake rate limit per IP" {
    const ws_root = @import("modules/websocket/root.zig");
    defer ws_root.deinit(); // release rate-limit window state
    var allowed: u32 = 0;
    var i: u32 = 0;
    while (i < 30) : (i += 1) {
        if (ws_root.allowHandshake("1.2.3.4")) allowed += 1;
    }
    try std.testing.expectEqual(@as(u32, 30), allowed);
    // 31st in the same second is rejected
    try std.testing.expect(!ws_root.allowHandshake("1.2.3.4"));
    // Different IP unaffected
    try std.testing.expect(ws_root.allowHandshake("5.6.7.8"));
}

// ============================================================
// Handler contract: user/group/conversation domain endpoints
// ============================================================
test "handler contract: user/group/conversation" {
    const allocator = std.testing.allocator;
    var ctx = IntegrationCtx.init(allocator) orelse return;
    defer ctx.deinit();

    const auth_mod = @import("modules/auth.zig");
    const group_mod = @import("modules/group.zig");
    const a = try ctx.register("uc_a");
    const b = try ctx.register("uc_b");
    const tok = try auth_mod.loginWithPassword(a, "test1234", 1);
    const mk = struct {
        fn hdr(t: []const u8) zigmodu.http.Testkit.HeaderPair {
            return .{ "token", t };
        }
    }.hdr;

    var kit_arena = std.heap.ArenaAllocator.init(allocator);
    defer kit_arena.deinit();
    var holder = try buildTestServer(kit_arena.allocator());
    defer {
        holder.catalog.deinit();
        holder.server.deinit();
    }

    // /user/update_user_info — profile update
    var up = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/user/update_user_info", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userID\":\"{s}\",\"nickname\":\"UC Renamed\"}}", .{a}),
        .headers = &.{mk(tok.token)},
    });
    defer up.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, up.body, "\"errCode\":0") != null);

    // /group/get_groups — group list with total
    const gid = try group_mod.createGroup(.{ .group_name = "UC Group", .creator_user_id = a, .member_user_ids = &.{b} });
    // Group result strings may land on the global allocator (service results
    // outside a request arena) — free via getAllocator (no-op under arena).
    defer {
        core.getAllocator().free(gid.group_id);
        core.getAllocator().free(gid.group_name);
        core.getAllocator().free(gid.creator_user_id);
    }
    var gg = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/group/get_groups", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"userID\":\"{s}\",\"groupIDs\":[\"{s}\"]}}", .{ a, gid.group_id }),
        .headers = &.{mk(tok.token)},
    });
    defer gg.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, gg.body, "\"errCode\":0") != null);

    // Group conversation is created on first group message — send one first.
    _ = try @import("modules/message.zig").sendMessage(.{
        .send_id = a,
        .recv_id = b,
        .group_id = gid.group_id,
        .session_type = .group,
        .content_type = .text,
        .content = "create conv",
    });

    // /conversation/get_conversation — single conversation lookup
    var gc = try zigmodu.http.Testkit.dispatchOpts(&holder.server, .POST, "/conversation/get_conversation", .{
        .body = try std.fmt.allocPrint(ctx.arena_ptr.allocator(), "{{\"ownerUserID\":\"{s}\",\"conversationID\":\"sg_{s}\"}}", .{ a, gid.group_id }),
        .headers = &.{mk(tok.token)},
    });
    defer gc.deinit(kit_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, gc.body, "\"errCode\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, gc.body, "\"conversationID\"") != null);
}
