const std = @import("std");
const zmodu = @import("zmodu");
const core = @import("core");
const config_mod = @import("../config.zig");
const auth_mod = @import("../auth.zig");
const event_bus_mod = @import("../event_bus.zig");
const sdkws = @import("sdkws");
const gob = @import("../gob.zig");
const model = @import("model.zig");
const service = @import("service.zig");

const WSClient = model.WSClient;

/// OpenIM terminal class for a platform id (see protocol/constant).
pub fn platformClass(platform_id: i32) []const u8 {
    return switch (platform_id) {
        1, 2 => "Mobile",
        3, 4, 7 => "PC",
        5 => "Web",
        6 => "MiniWeb",
        8, 9 => "Pad",
        10 => "Admin",
        11 => "HarmonyOS",
        else => "Other",
    };
}

/// OpenIM multi-terminal login policy (aligned with Go ws_server.go):
/// decides whether an EXISTING connection should be kicked by a new login.
pub fn shouldKickOld(policy: u8, existing_platform: i32, new_platform: i32, same_platform_exists: bool) bool {
    const existing_class = platformClass(existing_platform);
    const new_class = platformClass(new_platform);
    switch (policy) {
        0 => return false, // DefaultNotKick
        1 => return same_platform_exists, // AllLoginButSameTermKick
        2 => return true, // SingleTerminalLogin
        3 => { // WebAndOther: web coexists; non-web kicks old non-PC on same platform
            if (std.mem.eql(u8, new_class, "Web")) return false;
            return same_platform_exists and !std.mem.eql(u8, existing_class, "PC");
        },
        4 => return std.mem.eql(u8, existing_class, new_class), // AllLoginButSameClassKick
        5 => { // PCAndOther: PC coexists; others kick old non-PC on same platform
            if (std.mem.eql(u8, new_class, "PC")) return false;
            return same_platform_exists and !std.mem.eql(u8, existing_class, "PC");
        },
        else => return same_platform_exists, // 6 Customize falls back to same-terminal
    }
}

pub const info: zmodu.api.Module = .{
    .name = "websocket",
    .description = "WebSocket server for real-time IM communication",
    .dependencies = &.{ "config", "auth", "event_bus" },
    .runtime = .{
        .worker_count = 4,
        .max_concurrent = 1000,
    },
};

// Global Io instance
var g_io: std.Io = undefined;
var g_io_set = false;

// Global client registry
var g_clients_mutex: std.atomic.Mutex = .unlocked;
var g_clients: std.StringHashMap(std.ArrayList(*WSClient)) = undefined;
var g_initialized = false;

// Per-IP handshake rate limit (anti connection-flood)
const MAX_HANDSHAKES_PER_IP_WINDOW: u32 = 30; // per second
const HandshakeWindow = struct { count: u32, window: i64 };
var g_hs_windows: std.StringHashMap(HandshakeWindow) = undefined;
var g_hs_init = false;

pub fn allowHandshake(ip: []const u8) bool {
    lockMutex();
    defer g_clients_mutex.unlock();
    if (!g_hs_init) {
        g_hs_windows = std.StringHashMap(HandshakeWindow).init(core.getGlobalAllocator());
        g_hs_init = true;
    }
    const now = core.unixNowSeconds();
    const gop = g_hs_windows.getOrPut(ip) catch return false;
    if (!gop.found_existing) {
        // StringHashMap stores keys by reference — dupe caller-owned ip so
        // deinit can free it (a literal would crash on free).
        gop.key_ptr.* = core.getGlobalAllocator().dupe(u8, ip) catch return false;
        gop.value_ptr.* = .{ .count = 0, .window = now };
    }
    if (gop.value_ptr.window != now) {
        gop.value_ptr.window = now;
        gop.value_ptr.count = 0;
    }
    gop.value_ptr.count += 1;
    return gop.value_ptr.count <= MAX_HANDSHAKES_PER_IP_WINDOW;
}

pub fn setIo(io: std.Io) void {
    g_io = io;
    g_io_set = true;
    model.setIo(io);
}

fn lockMutex() void {
    while (!g_clients_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
}

/// Emit user online/offline with the JSON payload shape the async handlers
/// in main.zig expect (`{"user_id":"...","online":true|false}`).
fn emitUserStatus(online: bool, user_id: []const u8) void {
    const payload = std.fmt.allocPrint(core.getAllocator(), "{{\"user_id\":\"{s}\",\"online\":{s}}}", .{ user_id, if (online) "true" else "false" }) catch return;
    defer core.getAllocator().free(payload);
    const eb = event_bus_mod.getEventBus();
    if (online) {
        eb.emit(.user_online, "websocket", payload);
    } else {
        eb.emit(.user_offline, "websocket", payload);
    }
}

pub fn init() !void {
    g_clients = std.StringHashMap(std.ArrayList(*WSClient)).init(core.getAllocator());
    g_initialized = true;
    std.log.info("WebSocketModule initialized", .{});
}

pub fn deinit() void {
    // Release handshake rate-limit state FIRST — it is independent of module
    // init (tests may exercise allowHandshake without starting the server).
    if (g_hs_init) {
        var it = g_hs_windows.iterator();
        while (it.next()) |e| core.getGlobalAllocator().free(e.key_ptr.*);
        g_hs_windows.deinit();
        g_hs_init = false;
    }
    if (!g_initialized) return;

    // Stop the accept loop, join the fiber thread (onClose destroys clients),
    // then release the server.
    if (g_ws_server) |*srv| srv.stop();
    if (g_ws_thread) |t| t.join();
    g_ws_thread = null;
    if (g_ws_server) |*srv| srv.deinit();
    g_ws_server = null;

    lockMutex();
    defer g_clients_mutex.unlock();

    var it = g_clients.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit(core.getAllocator());
    }
    g_clients.deinit();
    g_initialized = false;
    std.log.info("WebSocketModule deinitialized", .{});
}

// ============================================================
// zmodu http.Server + ws_routes transport (replaces the custom
// hand-rolled WebSocket server). The protocol layer below
// (handleClientMessage / handleClientMessageBinary and friends)
// is unchanged; only frame transport is delegated to zmodu.
// ============================================================

var g_ws_server: ?zmodu.http.Server = null;
var g_ws_thread: ?std.Thread = null;

pub fn startServer(io: std.Io, allocator: std.mem.Allocator, port: u16) !void {
    g_ws_server = zmodu.http.Server.init(io, allocator, port);
    var server = &g_ws_server.?;
    // zmodu v0.40 removed Server.group()/RouteGroup — runtime WS registration
    // now rides the ComptimeRouter Scoped face (catalog unused for ws routes).
    const WsState = struct {};
    var ws_state = WsState{};
    var router = zmodu.http.Router(WsState).init(io, allocator, server, &ws_state);
    var scoped = router.scope("");
    try scoped.ws("", onConnect, onMessage, onClose, null);
    g_ws_thread = try server.runInBackground();
    std.log.info("WebSocket server started on ws://0.0.0.0:{d} (zmodu ws_routes)", .{port});
}

/// Handshake auth: `ws://host:port/?sendID=xxx&token=xxx&platformID=n`
/// Creates a heap-allocated WSClient (destroyed in onClose) and registers it
/// in the global client registry. Returns the client as the session pointer.
fn onConnect(ctx: *zmodu.http.Context, framer: *anyopaque) ?*anyopaque {
    // Per-IP handshake rate limit — reject floods before token work.
    const client_ip = zmodu.http.RequestUtil.getRealIp(ctx);
    if (!allowHandshake(client_ip)) {
        std.log.warn("[WebSocket] Handshake rate-limited for {s}", .{client_ip});
        return null;
    }
    const stream = ctx.stream orelse return null;
    const token = ctx.queryParam("token") orelse return null;
    const send_id = ctx.queryParam("sendID") orelse return null;
    const claims = auth_mod.parseToken(token) catch return null;
    defer {
        core.getAllocator().free(claims.token);
        core.getAllocator().free(claims.user_id);
    }
    if (!std.mem.eql(u8, claims.user_id, send_id)) return null;
    const platform_id: i32 = if (ctx.queryParam("platformID")) |p|
        std.fmt.parseInt(i32, p, 10) catch 0
    else
        0;

    const client = core.getAllocator().create(WSClient) catch return null;
    client.* = .{
        .stream = stream,
        .framer = framer,
        .platform_id = platform_id,
    };

    const user_id_copy = core.getAllocator().dupe(u8, send_id) catch {
        core.getAllocator().destroy(client);
        return null;
    };

    lockMutex();
    defer g_clients_mutex.unlock();

    const login_policy = config_mod.getConfig().gateway.login_policy;
    var same_platform_exists = false;
    if (g_clients.getPtr(user_id_copy)) |client_list| {
        for (client_list.items) |c| {
            if (c.platform_id == platform_id) {
                same_platform_exists = true;
                break;
            }
        }
    }

    if (g_clients.getPtr(user_id_copy)) |client_list| {
        var i: usize = 0;
        while (i < client_list.items.len) {
            const existing = client_list.items[i];
            if (shouldKickOld(login_policy, existing.platform_id, platform_id, same_platform_exists)) {
                const kick_msg = std.fmt.allocPrint(core.getAllocator(), "{{\"reqIdentifier\":{d},\"errCode\":0,\"errMsg\":\"Kicked by new login\",\"data\":\"\"}}", .{model.WSKickOnlineMsg}) catch "";
                defer core.getAllocator().free(kick_msg);
                existing.sendText(kick_msg) catch {};
                if (existing.framer) |f| {
                    const fr: *zmodu.im.WsFramer = @ptrCast(@alignCast(f));
                    fr.writeClose() catch {};
                }
                core.metricWsConnectionDelta(-1);
                _ = client_list.orderedRemove(i);
                std.log.info("[WebSocket] Kicked old connection for user {s} platform {d}", .{ send_id, platform_id });
                continue;
            }
            i += 1;
        }
    }

    const client_list = g_clients.getPtr(user_id_copy) orelse blk: {
        const new_list: std.ArrayList(*WSClient) = .empty;
        g_clients.put(user_id_copy, new_list) catch {
            core.getAllocator().free(user_id_copy);
            core.getAllocator().destroy(client);
            return null;
        };
        break :blk g_clients.getPtr(user_id_copy).?;
    };

    client_list.append(core.getAllocator(), client) catch {
        core.getAllocator().free(user_id_copy);
        core.getAllocator().destroy(client);
        return null;
    };
    core.metricWsConnectionDelta(1);

    client.user_id = user_id_copy;
    client.is_authenticated = true;
    std.log.info("[WebSocket] User auto-authenticated via handshake token: {s} platform: {d}", .{ send_id, platform_id });

    sendServerConfig(client);

    emitUserStatus(true, user_id_copy);
    return client;
}

fn onMessage(session: ?*anyopaque, msg: []const u8, kind: zmodu.im.WsFrameKind) void {
    const client: *WSClient = @ptrCast(@alignCast(session orelse return));
    switch (kind) {
        .text => {
            if (service.isTextPing(msg)) {
                client.sendText("{\"type\":\"pong\"}") catch {};
            } else {
                // Bulkhead (RuntimeOptions.max_concurrent): shed load when the
                // WS message pipeline saturates instead of unbounded queuing.
                // Pings bypass the gate (heartbeat must always be answered).
                if (core.getModuleRuntime("websocket")) |rt| {
                    if (!rt.tryEnter()) {
                        model.sendError(client, "Server Busy");
                        return;
                    }
                    defer rt.release();
                }
                handleClientMessage(client, msg);
            }
        },
        .binary => {
            client.is_gob_client = true;
            if (core.getModuleRuntime("websocket")) |rt| {
                if (!rt.tryEnter()) return;
                defer rt.release();
            }
            handleClientMessageBinary(client, msg);
        },
    }
}

fn onClose(session: ?*anyopaque) void {
    const client: *WSClient = @ptrCast(@alignCast(session orelse return));
    if (client.is_authenticated and client.user_id.len > 0) {
        lockMutex();
        defer g_clients_mutex.unlock();
        if (g_clients.getPtr(client.user_id)) |clients| {
            for (clients.items, 0..) |c, i| {
                if (c == client) {
                    _ = clients.orderedRemove(i);
                    core.metricWsConnectionDelta(-1);
                    break;
                }
            }
        }
        emitUserStatus(false, client.user_id);
        client.is_authenticated = false;
    }
    std.log.info("[WebSocket] Client disconnected", .{});
    if (client.user_id.len > 0) core.getAllocator().free(client.user_id);
    core.getAllocator().destroy(client);
}

fn handleClientMessage(client: *WSClient, message: []const u8) void {
    std.log.info("[WebSocket] Received text message: {s}", .{message});

    const parsed = std.json.parseFromSlice(std.json.Value, core.getAllocator(), message, .{}) catch {
        model.sendError(client, "Invalid JSON");
        return;
    };
    defer parsed.deinit();

    const root_val = parsed.value;

    if (root_val.object.get("reqIdentifier")) |req_id_val| {
        const req_id = switch (req_id_val) {
            .integer => |v| @as(i32, @intCast(v)),
            .float => |v| @as(i32, @intFromFloat(v)),
            else => {
                model.sendWSError(client, 0, "", model.WSDataError, "Invalid reqIdentifier", null);
                return;
            },
        };
        const token = if (root_val.object.get("token")) |t| t.string else "";
        const send_id = if (root_val.object.get("sendID")) |s| s.string else "";
        const operation_id = if (root_val.object.get("operationID")) |op| op.string else "";
        const msg_incr = if (root_val.object.get("msgIncr")) |mi| mi.string else "";

        handleReqMessage(client, req_id, token, send_id, operation_id, msg_incr, root_val.object);
        return;
    }

    if (root_val.object.get("reqFuncName")) |func_name| {
        const name = func_name.string;
        if (std.mem.eql(u8, name, "Login")) {
            handleLogin(client, root_val.object);
        } else if (std.mem.eql(u8, name, "SendMsg")) {
            service.handleSendMsg(client, root_val.object);
        } else if (std.mem.eql(u8, name, "PullMsgBySeq")) {
            service.handlePullMsg(client, root_val.object);
        } else if (std.mem.eql(u8, name, "SyncMsg")) {
            service.handleSyncMsg(client, root_val.object);
        } else {
            model.sendError(client, "Unknown function name");
        }
    } else {
        model.sendError(client, "Missing reqFuncName or reqIdentifier");
    }
}

fn handleClientMessageBinary(client: *WSClient, message: []const u8) void {
    std.log.info("[WebSocket] Received binary message ({d} bytes)", .{message.len});

    const req = gob.decodeReq(message, core.getAllocator()) catch |e| {
        std.log.err("[WebSocket] Failed to decode GOB request: {s}", .{@errorName(e)});
        const resp = gob.GeneralWsResp{
            .req_identifier = 0,
            .err_code = model.WSDataError,
            .err_msg = "Invalid GOB request",
            .msg_incr = "",
            .operation_id = "",
            .data = &[_]u8{},
        };
        const encoded = gob.encodeResp(resp, core.getAllocator()) catch return;
        defer core.getAllocator().free(encoded);
        client.sendBinary(encoded) catch {};
        return;
    };
    defer {
        core.getAllocator().free(req.token);
        core.getAllocator().free(req.send_id);
        core.getAllocator().free(req.operation_id);
        core.getAllocator().free(req.msg_incr);
        core.getAllocator().free(req.data);
    }

    std.log.info("[WebSocket] GOB req identifier={d} send_id={s} operation_id={s}", .{ req.req_identifier, req.send_id, req.operation_id });
    handleReqMessageDirect(client, req.req_identifier, req.token, req.send_id, req.operation_id, req.msg_incr, req.data);
}

fn handleReqMessage(client: *WSClient, req_id: i32, token: []const u8, send_id: []const u8, operation_id: []const u8, msg_incr: []const u8, params: std.json.ObjectMap) void {
    const data_b64 = if (params.get("data")) |d| d.string else "";
    var data_buf: [65536]u8 = undefined;
    const data_bytes = blk: {
        if (data_b64.len == 0) break :blk &[_]u8{};
        const decoder = std.base64.url_safe.Decoder;
        const decoded_len = decoder.calcSizeForSlice(data_b64) catch {
            model.sendWSError(client, req_id, msg_incr, model.WSDataError, "Invalid base64 data", operation_id);
            return;
        };
        if (decoded_len > data_buf.len) {
            model.sendWSError(client, req_id, msg_incr, model.WSDataError, "Data too large", operation_id);
            return;
        }
        decoder.decode(data_buf[0..decoded_len], data_b64) catch {
            model.sendWSError(client, req_id, msg_incr, model.WSDataError, "Invalid base64 data", operation_id);
            return;
        };
        break :blk data_buf[0..decoded_len];
    };

    handleReqMessageDirect(client, req_id, token, send_id, operation_id, msg_incr, data_bytes);
}

fn handleReqMessageDirect(client: *WSClient, req_id: i32, token: []const u8, send_id: []const u8, operation_id: []const u8, msg_incr: []const u8, data_bytes: []const u8) void {
    _ = token;
    _ = send_id;

    switch (req_id) {
        model.WSGetNewestSeq => service.handleWSGetMaxSeq(client, req_id, msg_incr, operation_id, data_bytes),
        model.WSPullMsgBySeqList => service.handleWSPullMsgBySeqList(client, req_id, msg_incr, operation_id, data_bytes),
        model.WSSendMsg => service.handleWSSendMsg(client, req_id, msg_incr, operation_id, data_bytes),
        model.WSSendSignalMsg => handleWSSendSignalMsg(client, req_id, msg_incr, operation_id, data_bytes),
        model.WSPullMsg => service.handleWSPullMsg(client, req_id, msg_incr, operation_id, data_bytes),
        model.WSGetConvMaxReadSeq => service.handleWSGetConvMaxReadSeq(client, req_id, msg_incr, operation_id, data_bytes),
        model.WsPullConvLastMessage => service.handleWSPullConvLastMessage(client, req_id, msg_incr, operation_id, data_bytes),
        model.WsLogoutMsg => handleWSLogout(client, req_id, msg_incr, operation_id, data_bytes),
        model.WsSetBackgroundStatus => service.handleWSSetBackgroundStatus(client, req_id, msg_incr, operation_id, data_bytes),
        model.WsSubUserOnlineStatus => handleWSSubUserOnlineStatus(client, req_id, msg_incr, operation_id, data_bytes),
        else => model.sendWSError(client, req_id, msg_incr, model.WSDataError, "Unknown reqIdentifier", operation_id),
    }
}

fn handleWSSendSignalMsg(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    const signal_req = sdkws.SignalReq.decode(data_bytes, core.getAllocator()) catch {
        model.sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to decode SignalReq", operation_id);
        return;
    };
    defer {
        core.getAllocator().free(signal_req.room_id);
        core.getAllocator().free(signal_req.user_id);
        core.getAllocator().free(signal_req.data);
    }

    const resp = sdkws.SignalResp{
        .room_id = signal_req.room_id,
        .signal_type = signal_req.signal_type,
        .user_id = signal_req.user_id,
        .data = signal_req.data,
    };
    const resp_bytes = resp.encode(core.getAllocator()) catch {
        model.sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to encode SignalResp", operation_id);
        return;
    };
    defer core.getAllocator().free(resp_bytes);

    lockMutex();
    defer g_clients_mutex.unlock();
    var it = g_clients.iterator();
    while (it.next()) |entry| {
        const client_list = entry.value_ptr.*;
        for (client_list.items) |other| {
            if (other.is_authenticated and !std.mem.eql(u8, other.user_id, client.user_id)) {
                model.sendWSResponse(other, req_id, "", "", 0, "", resp_bytes);
            }
        }
    }

    model.sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", resp_bytes);
}

fn handleWSLogout(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    _ = data_bytes;

    if (client.is_authenticated and client.user_id.len > 0) {
        lockMutex();
        defer g_clients_mutex.unlock();

        if (g_clients.getPtr(client.user_id)) |clients| {
            for (clients.items, 0..) |c, i| {
                if (c == client) {
                    _ = clients.orderedRemove(i);
                    core.metricWsConnectionDelta(-1);
                    break;
                }
            }
        }

        emitUserStatus(false, client.user_id);

        client.is_authenticated = false;
    }

    model.sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", &[_]u8{});
}

fn sendServerConfig(client: *WSClient) void {
    const allocator = core.getAllocator();
    const config = sdkws.ServerConfig{ .is_encryption = false };
    const pb_bytes = config.encode(allocator) catch return;
    defer allocator.free(pb_bytes);

    if (client.is_gob_client) {
        const resp = gob.GeneralWsResp{
            .req_identifier = model.WSServerConfigMsg,
            .err_code = 0,
            .err_msg = "",
            .msg_incr = "",
            .operation_id = "",
            .data = pb_bytes,
        };
        const encoded = gob.encodeResp(resp, allocator) catch return;
        defer allocator.free(encoded);
        client.sendBinary(encoded) catch {};
    } else {
        const encoder = std.base64.url_safe.Encoder;
        var b64_buf: [4096]u8 = undefined;
        const b64_data = encoder.encode(&b64_buf, pb_bytes);

        const response = std.fmt.allocPrint(allocator, "{{\"reqIdentifier\":{d},\"msgIncr\":\"\",\"operationID\":\"\",\"errCode\":0,\"errMsg\":\"\",\"data\":\"{s}\"}}", .{ model.WSServerConfigMsg, b64_data }) catch return;
        defer allocator.free(response);
        client.sendText(response) catch {};
    }
    std.log.info("[WebSocket] Sent server config to {s}", .{client.user_id});
}

// Online status subscribers
var g_online_subscribers_mutex: std.atomic.Mutex = .unlocked;
var g_online_subscribers: std.StringHashMap(std.ArrayList([]const u8)) = undefined;
var g_online_subscribers_initialized = false;

fn lockSubMutex() void {
    while (!g_online_subscribers_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
}

fn handleWSSubUserOnlineStatus(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, data_bytes: []const u8) void {
    const req = sdkws.SubUserOnlineStatus.decode(data_bytes, core.getAllocator()) catch {
        model.sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to decode SubUserOnlineStatus", operation_id);
        return;
    };

    const allocator = core.getAllocator();
    lockSubMutex();
    defer g_online_subscribers_mutex.unlock();

    if (!g_online_subscribers_initialized) {
        g_online_subscribers = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
        g_online_subscribers_initialized = true;
    }

    for (req.subscribe_user_id) |target_uid| {
        const entry = g_online_subscribers.getPtr(target_uid) orelse blk: {
            const new_list = std.ArrayList([]const u8).empty;
            g_online_subscribers.put(target_uid, new_list) catch break :blk null;
            break :blk g_online_subscribers.getPtr(target_uid).?;
        };
        if (entry) |list| {
            var already = false;
            for (list.items) |sub| {
                if (std.mem.eql(u8, sub, client.user_id)) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                list.append(allocator, allocator.dupe(u8, client.user_id) catch continue) catch {};
            }
        }
    }

    for (req.unsubscribe_user_id) |target_uid| {
        if (g_online_subscribers.getPtr(target_uid)) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (std.mem.eql(u8, list.items[i], client.user_id)) {
                    allocator.free(list.items[i]);
                    _ = list.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    var elems = std.ArrayList(sdkws.SubUserOnlineStatusElem).empty;
    defer {
        for (elems.items) |e| {
            allocator.free(e.user_id);
            allocator.free(e.online_platform_ids);
        }
        elems.deinit(allocator);
    }

    for (req.subscribe_user_id) |target_uid| {
        lockMutex();
        const is_online = g_clients.contains(target_uid);
        g_clients_mutex.unlock();

        if (is_online) {
            var pids = std.ArrayList(i32).empty;
            defer pids.deinit(allocator);
            if (g_clients.get(target_uid)) |clients| {
                for (clients.items) |c| {
                    var found = false;
                    for (pids.items) |pid| {
                        if (pid == c.platform_id) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) pids.append(allocator, c.platform_id) catch {};
                }
            }
            const elem = sdkws.SubUserOnlineStatusElem{
                .user_id = allocator.dupe(u8, target_uid) catch continue,
                .online_platform_ids = pids.toOwnedSlice(allocator) catch continue,
            };
            elems.append(allocator, elem) catch {};
        }
    }

    const tips = sdkws.SubUserOnlineStatusTips{
        .subscribers = elems.items,
    };
    const tips_bytes = tips.encode(allocator) catch {
        model.sendWSError(client, req_id, msg_incr, model.WSDataError, "Failed to encode SubUserOnlineStatusTips", operation_id);
        return;
    };
    defer allocator.free(tips_bytes);

    model.sendWSResponse(client, req_id, msg_incr, operation_id, 0, "", tips_bytes);
}

pub fn isUserBackground(user_id: []const u8) bool {
    lockMutex();
    defer g_clients_mutex.unlock();
    if (g_clients.get(user_id)) |clients| {
        for (clients.items) |client| {
            if (!client.is_background) return false;
        }
        return clients.items.len > 0;
    }
    return false;
}

pub fn pushOnlineStatusChange(user_id: []const u8, online: bool, platform_id: i32) void {
    lockSubMutex();
    defer g_online_subscribers_mutex.unlock();

    if (!g_online_subscribers_initialized) return;

    const allocator = core.getAllocator();
    if (g_online_subscribers.getPtr(user_id)) |subscribers| {
        var pids = std.ArrayList(i32).empty;
        defer pids.deinit(allocator);
        if (online) {
            pids.append(allocator, platform_id) catch {};
        }
        const elem = sdkws.SubUserOnlineStatusElem{
            .user_id = allocator.dupe(u8, user_id) catch return,
            .online_platform_ids = if (online) pids.toOwnedSlice(allocator) catch &[_]i32{} else &[_]i32{},
        };
        defer allocator.free(elem.user_id);
        defer if (online) allocator.free(elem.online_platform_ids);

        const tips = sdkws.SubUserOnlineStatusTips{
            .subscribers = &[_]sdkws.SubUserOnlineStatusElem{elem},
        };
        const tips_bytes = tips.encode(allocator) catch return;
        defer allocator.free(tips_bytes);

        for (subscribers.items) |sub_id| {
            lockMutex();
            defer g_clients_mutex.unlock();
            if (g_clients.get(sub_id)) |clients| {
                for (clients.items) |client| {
                    model.sendWSResponse(client, model.WsSubUserOnlineStatus, "", "", 0, "", tips_bytes);
                }
            }
        }
    }
}

fn handleLogin(client: *WSClient, params: std.json.ObjectMap) void {
    const user_id = params.get("userID") orelse {
        model.sendError(client, "Missing userID");
        return;
    };
    const token = params.get("token") orelse {
        model.sendError(client, "Missing token");
        return;
    };

    const claims = auth_mod.parseToken(token.string) catch {
        model.sendError(client, "Invalid token");
        return;
    };

    lockMutex();
    defer g_clients_mutex.unlock();

    const user_id_copy = core.getAllocator().dupe(u8, user_id.string) catch {
        model.sendError(client, "Memory error");
        return;
    };

    const client_list = g_clients.getPtr(user_id_copy) orelse blk: {
        const new_list: std.ArrayList(*WSClient) = .empty;
        g_clients.put(user_id_copy, new_list) catch {
            model.sendError(client, "Memory error");
            return;
        };
        break :blk g_clients.getPtr(user_id_copy).?;
    };

    client_list.append(core.getAllocator(), client) catch {
        model.sendError(client, "Memory error");
        return;
    };
    core.metricWsConnectionDelta(1);

    client.user_id = user_id_copy;
    client.is_authenticated = true;

    const response = std.fmt.allocPrint(core.getAllocator(), "{{\"errCode\":0,\"errMsg\":\"\",\"data\":{{\"userID\":\"{s}\"}}}}", .{claims.user_id}) catch return;
    defer core.getAllocator().free(response);
    client.sendText(response) catch {};

    std.log.info("[WebSocket] User logged in: {s}", .{claims.user_id});

    emitUserStatus(true, user_id_copy);
}

// Push message to specific user if online (legacy text push)
pub fn pushToUser(user_id: []const u8, message: []const u8) void {
    lockMutex();
    defer g_clients_mutex.unlock();

    if (g_clients.get(user_id)) |clients| {
        for (clients.items) |client| {
            client.sendText(message) catch {};
        }
        std.log.info("[WebSocket] Pushed message to user {s} ({d} clients)", .{ user_id, clients.items.len });
    }
}

pub fn pushToUsers(user_ids: []const []const u8, message: []const u8) void {
    for (user_ids) |user_id| {
        pushToUser(user_id, message);
    }
}

pub fn broadcast(message: []const u8) void {
    lockMutex();
    defer g_clients_mutex.unlock();

    var it = g_clients.iterator();
    while (it.next()) |entry| {
        for (entry.value_ptr.items) |client| {
            client.sendText(message) catch {};
        }
    }
}

pub fn pushMsgProtobuf(user_id: []const u8, msg_data: sdkws.MsgData) void {
    const allocator = core.getAllocator();

    const pull_msgs = sdkws.PullMsgs{
        .msgs = &[_]sdkws.MsgData{msg_data},
        .is_end = true,
        .end_seq = msg_data.seq,
    };

    const push_msgs = sdkws.PushMessages{
        .msgs = pull_msgs,
        .notification_msgs = .{},
    };

    const pb_bytes = push_msgs.encode(allocator) catch |e| {
        std.log.err("[WebSocket] Failed to encode PushMsg protobuf: {s}", .{@errorName(e)});
        return;
    };
    defer allocator.free(pb_bytes);

    pushMsgProtobufBytes(user_id, pb_bytes, msg_data.seq);
}

fn pushMsgProtobufBytes(user_id: []const u8, pb_bytes: []const u8, seq: i64) void {
    _ = seq;
    lockMutex();
    defer g_clients_mutex.unlock();

    if (g_clients.get(user_id)) |clients| {
        for (clients.items) |client| {
            model.sendWSResponse(client, model.WSPushMsg, "", "", 0, "", pb_bytes);
        }
        std.log.info("[WebSocket] Pushed protobuf message to user {s} ({d} clients)", .{ user_id, clients.items.len });
    }
}

pub fn pushMsgProtobufToUsers(user_ids: []const []const u8, msg_data: sdkws.MsgData) void {
    for (user_ids) |user_id| {
        pushMsgProtobuf(user_id, msg_data);
    }
}

pub fn kickUser(user_id: []const u8, reason: []const u8) void {
    lockMutex();
    defer g_clients_mutex.unlock();

    if (g_clients.get(user_id)) |clients| {
        for (clients.items) |client| {
            model.sendWSResponse(client, model.WSKickOnlineMsg, "", "", 0, reason, &[_]u8{});
            if (client.framer) |f| {
                const fr: *zmodu.im.WsFramer = @ptrCast(@alignCast(f));
                fr.writeClose() catch {};
            }
        }
        std.log.info("[WebSocket] Kicked user {s} ({d} clients)", .{ user_id, clients.items.len });
    }
}
