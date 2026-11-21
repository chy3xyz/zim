const std = @import("std");
const builtin = @import("builtin");
const zmodu = @import("zmodu");

// ============================================
// ZIM Core Infrastructure Module
// Deep integration with zmodu Modulith ecosystem
// Provides: Allocator, DI Container, EventBus, Logger, Validation
// ============================================

var g_initialized: bool = false;
var g_allocator: std.mem.Allocator = undefined;
var g_io: std.Io = undefined;
var g_logger: ?zmodu.observability.StructuredLogger = null;
threadlocal var g_request_allocator: ?std.mem.Allocator = null;

// --------------------------------------------
// DI Container (zmodu native)
// --------------------------------------------
var g_container: ?zmodu.Container = null;

// --------------------------------------------
// EventBus (backed by zmodu ThreadSafeEventBus + WorkerPool)
// The facade keeps the legacy EventBusService API so existing modules stay
// unchanged, while dispatch is delegated to the framework's thread-safe bus.
// Async subscriptions run on a zmodu WorkerPool instead of the publishing
// fiber (per-module QPS Phase 2 feature).
// --------------------------------------------
pub const EventType = enum {
    user_created,
    user_updated,
    user_deleted,
    user_online,
    user_offline,
    conversation_created,
    conversation_updated,
    conversation_deleted,
    message_sent,
    message_received,
    message_recalled,
    message_modified,
    message_deleted,
    group_created,
    group_updated,
    group_deleted,
    group_member_joined,
    group_member_left,
    group_member_role_changed,
    friend_requested,
    friend_accepted,
    friend_declined,
    friend_deleted,
    black_added,
    black_removed,
};

pub const Event = struct {
    type: EventType,
    source_module: []const u8,
    target_module: ?[]const u8,
    payload: []const u8,
    timestamp: i64,
};

pub const EventHandler = *const fn (Event) void;

const Subscription = struct {
    event_type: EventType,
    handler: EventHandler,
    module_name: []const u8,
};

const Bus = zmodu.ThreadSafeEventBus(Event);

var g_bus: ?Bus = null;
var g_subscriptions: std.ArrayList(Subscription) = undefined;
var g_subscriptions_init: bool = false;
var g_async_subscriptions: std.ArrayList(Subscription) = undefined;
var g_async_init: bool = false;
var g_worker_pool: ?zmodu.WorkerPool = null;
var g_published_total: std.atomic.Value(u64) = .init(0);

fn subscriptionMatches(sub: Subscription, event: Event) bool {
    if (sub.event_type != event.type) return false;
    if (event.target_module) |target| {
        if (!std.mem.eql(u8, target, sub.module_name)) return false;
    }
    return true;
}

fn dispatchSync(event: Event) void {
    if (!g_subscriptions_init) return;
    for (g_subscriptions.items) |sub| {
        if (subscriptionMatches(sub, event)) sub.handler(event);
    }
}

fn dispatchAsync(event: Event) void {
    if (g_async_init) {
        for (g_async_subscriptions.items) |sub| {
            if (subscriptionMatches(sub, event)) sub.handler(event);
        }
    }
    // Payloads are duplicated into global memory by emit(); the async worker
    // is the last consumer, so release the copy here.
    if (event.payload.len > 0) {
        g_allocator.free(event.payload);
    }
}

var g_event_bus_instance: EventBusService = .{};

pub const EventBusService = struct {
    pub fn subscribe(_: *EventBusService, event_type: EventType, handler: EventHandler, module_name: []const u8) !void {
        if (!g_subscriptions_init) {
            g_subscriptions = std.ArrayList(Subscription).empty;
            g_subscriptions_init = true;
        }
        try g_subscriptions.append(g_allocator, Subscription{
            .event_type = event_type,
            .handler = handler,
            .module_name = module_name,
        });
    }

    /// Async subscription — events are dispatched on the core WorkerPool
    /// (zmodu WorkerPool feature) instead of the publishing fiber.
    pub fn subscribeAsync(_: *EventBusService, event_type: EventType, handler: EventHandler, module_name: []const u8) !void {
        if (!g_async_init) {
            g_async_subscriptions = std.ArrayList(Subscription).empty;
            g_async_init = true;
        }
        try g_async_subscriptions.append(g_allocator, Subscription{
            .event_type = event_type,
            .handler = handler,
            .module_name = module_name,
        });
        if (g_worker_pool == null) {
            g_worker_pool = try zmodu.WorkerPool.init(g_allocator, g_io, "core-event-bus", 4, 1024);
            try g_bus.?.subscribeAsync(&g_worker_pool.?, dispatchAsync);
        }
    }

    pub fn publish(_: *EventBusService, event: Event) void {
        _ = g_published_total.fetchAdd(1, .monotonic);
        if (g_bus) |*bus| bus.publish(event);
    }

    pub fn emit(_: *EventBusService, event_type: EventType, source_module: []const u8, payload: []const u8) void {
        // Copy payload into global memory: async (WorkerPool) subscribers run
        // after the publishing request's arena has been reclaimed.
        const payload_copy = g_allocator.dupe(u8, payload) catch payload;
        const event = Event{
            .type = event_type,
            .source_module = source_module,
            .target_module = null,
            .payload = payload_copy,
            .timestamp = zmodu.time.monotonicNowSeconds(),
        };
        g_event_bus_instance.publish(event);
    }

    pub fn getEventCount(_: *EventBusService) usize {
        var count: usize = 0;
        if (g_subscriptions_init) count += g_subscriptions.items.len;
        if (g_async_init) count += g_async_subscriptions.items.len;
        return count;
    }

    pub fn getPublishedCount(_: *EventBusService) u64 {
        return g_published_total.load(.monotonic);
    }

    pub fn deinit(_: *EventBusService) void {
        if (g_worker_pool) |*pool| pool.deinit();
        g_worker_pool = null;
        if (g_bus) |*bus| bus.deinit();
        g_bus = null;
        if (g_subscriptions_init) {
            g_subscriptions.deinit(g_allocator);
            g_subscriptions_init = false;
        }
        if (g_async_init) {
            g_async_subscriptions.deinit(g_allocator);
            g_async_init = false;
        }
    }
};

// --------------------------------------------
// Initialization / Deinitialization
// --------------------------------------------

pub fn init(allocator: std.mem.Allocator, io: std.Io) !void {
    if (g_initialized) return;

    g_allocator = allocator;
    g_io = io;

    g_container = zmodu.Container.init(allocator);

    g_bus = Bus.init(allocator, io);
    try g_bus.?.subscribe(dispatchSync);

    g_subscriptions = std.ArrayList(Subscription).empty;
    g_subscriptions_init = true;

    g_initialized = true;

    // Structured JSON logger (stderr). Optional — created best-effort so the
    // test harness (std.testing.io) degrades gracefully.
    g_logger = zmodu.observability.StructuredLogger.init(allocator, io, .INFO, .stderr);

    logInfo("Core infrastructure initialized", .{});
}

pub fn deinit() void {
    if (!g_initialized) return;

    // JSON log file cleanup (rotation state)
    if (g_log_file) |fd| {
        _ = std.posix.system.close(fd);
        g_log_file = null;
    }
    if (g_log_path.len > 0) {
        g_allocator.free(g_log_path);
        g_log_path = "";
    }

    g_event_bus_instance.deinit();
    deinitMetrics();

    if (g_container) |*ct| ct.deinit();

    g_app = null;
    g_initialized = false;
}

// --------------------------------------------
// Public API: Allocator
// --------------------------------------------

pub fn getAllocator() std.mem.Allocator {
    return g_request_allocator orelse g_allocator;
}

pub fn getGlobalAllocator() std.mem.Allocator {
    return g_allocator;
}

pub fn setRequestAllocator(a: ?std.mem.Allocator) void {
    g_request_allocator = a;
}

// --------------------------------------------
// Public API: Request-aware service allocator
// --------------------------------------------
// Services used to capture `core.getAllocator()` at module init, pinning them
// to the global allocator so every request-scoped result leaked. This
// delegating allocator resolves at each call: inside a request it routes to
// the per-request arena (reclaimed when the request ends), elsewhere to the
// global allocator.

const service_vtable = std.mem.Allocator.VTable{
    .alloc = serviceAlloc,
    .resize = serviceResize,
    .remap = serviceRemap,
    .free = serviceFree,
};

fn serviceAlloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    return getAllocator().rawAlloc(len, alignment, ret_addr);
}

fn serviceResize(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    return getAllocator().rawResize(memory, alignment, new_len, ret_addr);
}

fn serviceRemap(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    return getAllocator().rawRemap(memory, alignment, new_len, ret_addr);
}

fn serviceFree(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    getAllocator().rawFree(memory, alignment, ret_addr);
}

/// Allocator for long-lived services: per-request arena inside a request,
/// global allocator everywhere else.
pub fn serviceAllocator() std.mem.Allocator {
    return .{ .ptr = undefined, .vtable = &service_vtable };
}

pub fn getIo() std.Io {
    return g_io;
}

/// Structured JSON logger (stderr) — null when unavailable.
pub fn getLogger() ?*zmodu.observability.StructuredLogger {
    if (g_logger) |*l| return l;
    return null;
}

// --------------------------------------------
// Public API: DI Container
// --------------------------------------------

pub fn getContainer() *zmodu.Container {
    return &g_container.?;
}

pub fn registerService(comptime T: type, name: []const u8, instance: *T) !void {
    try getContainer().register(T, name, instance);
}

pub fn getService(comptime T: type, name: []const u8) ?*T {
    return getContainer().get(T, name);
}

// --------------------------------------------
// Public API: EventBus
// --------------------------------------------

pub fn getEventBus() *EventBusService {
    return &g_event_bus_instance;
}

// --------------------------------------------
// Public API: Time (zmodu.time + wall-clock helper)
// --------------------------------------------

/// Monotonic seconds since an arbitrary epoch (zmodu.time).
pub fn monotonicNowSeconds() i64 {
    return zmodu.time.monotonicNowSeconds();
}

/// Wall-clock UNIX seconds — used for token expiry and verification codes.
pub fn unixNowSeconds() i64 {
    var tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&tv, null);
    return @as(i64, tv.sec);
}

/// Wall-clock UNIX milliseconds.
pub fn unixNowMillis() i64 {
    var tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&tv, null);
    return @as(i64, tv.sec) * 1000 + @divTrunc(@as(i64, tv.usec), 1000);
}

/// Fill `buf` with cryptographically secure random bytes (OS entropy when
/// available; ChaCha CSPRNG fallback otherwise).
pub fn secureRandomBytes(buf: []u8) void {
    if (comptime builtin.os.tag.isDarwin()) {
        std.c.arc4random_buf(buf.ptr, buf.len);
    } else if (comptime builtin.os.tag == .linux) {
        _ = std.os.linux.getrandom(buf.ptr, buf.len, 0);
    } else {
        var seed: [32]u8 = undefined;
        std.mem.writeInt(u64, seed[0..8], @intCast(monotonicNowSeconds()), .little);
        std.mem.writeInt(u64, seed[8..16], @intFromPtr(buf.ptr), .little);
        std.mem.writeInt(u64, seed[16..24], @intFromPtr(&seed), .little);
        std.mem.writeInt(u64, seed[24..32], 0x5E5E5E5E5E5E5E5E, .little);
        var csprng = std.Random.DefaultCsprng.init(seed);
        csprng.random().bytes(buf);
    }
}

// --------------------------------------------
// Public API: Metrics (zmodu PrometheusMetrics)
// --------------------------------------------

const PrometheusMetrics = zmodu.observability.PrometheusMetrics;

var g_metrics: ?PrometheusMetrics = null;
var g_metric_http_reqs: ?*PrometheusMetrics.Counter = null;
var g_metric_ws_conns: ?*PrometheusMetrics.Gauge = null;
var g_metric_msgs_sent: ?*PrometheusMetrics.Counter = null;
var g_metric_http_duration: ?*PrometheusMetrics.Histogram = null;
var g_metric_push_sent: ?*PrometheusMetrics.Counter = null;
var g_metric_push_failed: ?*PrometheusMetrics.Counter = null;
var g_metric_queue_depth: ?*PrometheusMetrics.Gauge = null;
var g_metric_db_duration: ?*PrometheusMetrics.Histogram = null;

pub fn initMetrics() void {
    if (g_metrics != null) return;
    var metrics = PrometheusMetrics.init(g_allocator);
    g_metric_http_reqs = metrics.createCounter("zim_http_requests_total", "Total HTTP requests handled") catch null;
    g_metric_ws_conns = metrics.createGauge("zim_ws_connections", "Currently connected WebSocket clients") catch null;
    g_metric_msgs_sent = metrics.createCounter("zim_messages_sent_total", "Messages sent via the gateway") catch null;
    g_metric_http_duration = metrics.createHistogram("zim_http_request_duration_seconds", "HTTP request duration in seconds", &.{ 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5 }) catch null;
    g_metric_push_sent = metrics.createCounter("zim_push_sent_total", "Push notifications sent (online+offline)") catch null;
    g_metric_push_failed = metrics.createCounter("zim_push_failed_total", "Push notification failures") catch null;
    g_metric_queue_depth = metrics.createGauge("zim_queue_depth", "Pending messages in PGMQ queues") catch null;
    g_metric_db_duration = metrics.createHistogram("zim_db_query_duration_seconds", "PostgreSQL query duration in seconds", &.{ 0.001, 0.01, 0.05, 0.1, 0.5, 1 }) catch null;
    g_metrics = metrics;
}

pub fn metricPushSent() void {
    if (g_metric_push_sent) |c| c.inc();
}

pub fn metricPushFailed() void {
    if (g_metric_push_failed) |c| c.inc();
}

pub fn metricQueueDepth(depth: i64) void {
    if (g_metric_queue_depth) |g| g.set(@floatFromInt(depth));
}

pub fn metricDbDuration(seconds: f64) void {
    if (g_metric_db_duration) |h| h.observe(seconds);
}

pub fn metricHttpRequest() void {
    if (g_metric_http_reqs) |c| c.inc();
}

pub fn metricWsConnectionDelta(delta: f64) void {
    if (g_metric_ws_conns) |g| g.add(delta);
}

pub fn metricMessageSent() void {
    if (g_metric_msgs_sent) |c| c.inc();
}

pub fn metricHttpDuration(seconds: f64) void {
    if (g_metric_http_duration) |h| h.observe(seconds);
}

pub fn renderMetrics(allocator: std.mem.Allocator) ![]const u8 {
    if (g_metrics) |*m| return try m.toPrometheusFormat(allocator);
    return try allocator.dupe(u8, "# zim metrics not initialized\n");
}

pub fn deinitMetrics() void {
    g_metric_http_reqs = null;
    g_metric_ws_conns = null;
    g_metric_msgs_sent = null;
    g_metric_http_duration = null;
    g_metric_push_sent = null;
    g_metric_push_failed = null;
    g_metric_queue_depth = null;
    g_metric_db_duration = null;
    if (g_metrics) |*m| m.deinit();
    g_metrics = null;
}

// --------------------------------------------
// Public API: Application runtime (per-module isolation)
// --------------------------------------------

var g_app: ?*zmodu.Application = null;

pub fn setApp(app: *zmodu.Application) void {
    g_app = app;
}

pub fn getApp() ?*zmodu.Application {
    return g_app;
}

/// Access the per-module ModuleRuntime (bulkhead / rate limiter / circuit
/// breaker / worker pool) provisioned by zmodu from `info.runtime`.
pub fn getModuleRuntime(name: []const u8) ?*zmodu.ModuleRuntime {
    const app = g_app orelse return null;
    return app.getModuleRuntime(name);
}

// --------------------------------------------
// Public API: Logger (convenience wrappers around std.log)
// Modules use std.log scopes; zmodu ships log/StructuredLogger.zig for
// JSON-formatted logging if a structured sink is needed later.
// --------------------------------------------

pub fn logDebug(comptime message: []const u8, args: anytype) void {
    std.log.debug(message, args);
}

var g_log_file: ?std.posix.fd_t = null;
var g_log_file_size: u64 = 0;
var g_log_max_size: u64 = 64 * 1024 * 1024;
var g_log_path: []const u8 = "";
var g_log_mutex: std.atomic.Mutex = .unlocked;
// libc rename — std.Io.Dir.renameAbsolute needs an Io (cross-thread risk);
// low-level libc keeps rotation working from any worker thread.
extern "c" fn rename(old_path: [*:0]const u8, new_path: [*:0]const u8) c_int;
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
// macOS flags: O_RDWR=0x0002, O_CREAT=0x0200, O_APPEND=0x0008 (project is macOS-only)
// O_RDWR | O_CREAT | O_APPEND — the raw values differ per libc (macOS
// O_CREAT=0x0200/O_APPEND=0x0008, Linux O_CREAT=0x40/O_APPEND=0x400). The
// macOS-only constant made open() return ENOENT on Linux for a missing
// file (CI-caught; local mac had a leftover file masking it).
const O_RDWR_CREAT_APPEND: c_int = switch (@import("builtin").os.tag) {
    .macos => 0x0002 | 0x0200 | 0x0008,
    else => 0x0002 | 0x0040 | 0x0400,
};

/// Enable JSON log file output with size-based rotation (`<path>.1`).
/// Call once at startup; threads-safe for concurrent logJson writers.
pub fn initLogFile(path: []const u8, max_size: u64) !void {
    while (!g_log_mutex.tryLock()) std.atomic.spinLoopHint();
    defer g_log_mutex.unlock();
    const path_z = tryZ(path) orelse return error.OpenFailed;
    defer g_allocator.free(path_z);
    const fd = open(path_z.ptr, O_RDWR_CREAT_APPEND, @as(c_uint, 0o644));
    if (fd < 0) {
        // Surface errno on the failing path — Linux/macOS differ in what
        // makes libc open fail here (CI caught it; macOS passes).
        const errno_ptr = std.c._errno();
        std.log.err("initLogFile open failed: errno={d} path={s}", .{ errno_ptr.*, path });
        return error.OpenFailed;
    }
    g_log_file = @intCast(fd);
    g_log_file_size = 0; // count this session's writes; rotation threshold is per-session
    g_log_max_size = if (max_size > 0) max_size else g_log_max_size;
    g_log_path = try g_allocator.dupe(u8, path);
}

fn tryZ(s: []const u8) ?[:0]u8 {
    const buf = g_allocator.allocSentinel(u8, s.len, 0) catch return null;
    @memcpy(buf[0..s.len], s);
    return buf[0..s.len :0];
}

fn rotateLogLocked() void {
    if (g_log_file) |fd| {
        _ = std.posix.system.close(fd);
        g_log_file = null;
    }
    if (g_log_path.len > 0) {
        const rotated = std.fmt.allocPrint(g_allocator, "{s}.1", .{g_log_path}) catch return;
        defer g_allocator.free(rotated);
        const old_z = tryZ(g_log_path) orelse return;
        defer g_allocator.free(old_z);
        const new_z = tryZ(rotated) orelse return;
        defer g_allocator.free(new_z);
        _ = rename(old_z.ptr, new_z.ptr);
        const pz = tryZ(g_log_path) orelse return;
        defer g_allocator.free(pz);
        const fd = open(pz.ptr, O_RDWR_CREAT_APPEND, @as(c_uint, 0o644));
        if (fd >= 0) g_log_file = @intCast(fd);
    }
    g_log_file_size = 0;
}

/// Structured JSON log line (std.log sink, thread-safe, no std.Io dependency).
/// Callers pass the full field set, e.g. core.logJson(.{ .event = "x", .k = v }).
/// Strings are serialized readably (unlike zmodu StructuredLogger's `{any}`
/// byte-array formatting until the `{s}` patch is applied).
pub fn logJson(fields: anytype) void {
    const json = std.json.Stringify.valueAlloc(g_allocator, fields, .{}) catch return;
    defer g_allocator.free(json);
    std.log.info("{s}", .{json});
    while (!g_log_mutex.tryLock()) std.atomic.spinLoopHint();
    defer g_log_mutex.unlock();
    if (g_log_file) |_| {
        if (g_log_file_size > g_log_max_size) rotateLogLocked();
        if (g_log_file) |f| {
            _ = std.posix.system.write(f, json.ptr, json.len);
            _ = std.posix.system.write(f, "\n".ptr, 1);
            g_log_file_size += json.len + 1;
        }
    }
}

pub fn logInfo(comptime message: []const u8, args: anytype) void {
    std.log.info(message, args);
}
pub fn logWarn(comptime message: []const u8, args: anytype) void {
    std.log.warn(message, args);
}

pub fn logErr(comptime message: []const u8, args: anytype) void {
    std.log.err(message, args);
}

// --------------------------------------------
// Public API: Error Codes
// --------------------------------------------

pub const ErrorCode = struct {
    pub const ok: i32 = 0;
    pub const unknown: i32 = 10000;
    pub const bad_request: i32 = 10001;
    pub const unauthorized: i32 = 10002;
    pub const not_found: i32 = 10003;
    pub const internal_error: i32 = 10004;
    pub const forbidden: i32 = 10005;
    pub const timeout: i32 = 10006;
    pub const invalid_param: i32 = 10007;
    pub const db_error: i32 = 10008;

    // Gateway handler error codes (10006-10123)
    pub const change_password: i32 = 10006;
    pub const get_admin_token: i32 = 10007;
    pub const get_user_token: i32 = 10008;
    pub const parse_token: i32 = 10009;
    pub const reset_password: i32 = 10010;
    pub const send_verification_code: i32 = 10011;
    pub const get_all_users_id: i32 = 10012;
    pub const update_user_info: i32 = 10013;
    pub const update_user_info_ex: i32 = 10014;
    pub const user_register: i32 = 10015;
    pub const send_message: i32 = 10016;
    pub const revoke_msg: i32 = 10017;
    pub const delete_msgs: i32 = 10018;
    pub const clear_conversation_msg: i32 = 10019;
    pub const user_clear_all_msg: i32 = 10020;
    pub const search_msg: i32 = 10021;
    pub const delete_msg_physical: i32 = 10022;
    pub const send_business_notification: i32 = 10023;
    pub const modify_message: i32 = 10024;
    pub const get_conversation: i32 = 10025;
    pub const get_all_conversations: i32 = 10026;
    pub const get_incremental_conversations: i32 = 10027;
    pub const get_sorted_conversation_list: i32 = 10028;
    pub const set_conversations: i32 = 10029;
    pub const get_owner_conversation: i32 = 10030;
    pub const add_friend: i32 = 10031;
    pub const friend_response: i32 = 10032;
    pub const get_friend_list: i32 = 10033;
    pub const get_friend_apply_list: i32 = 10034;
    pub const get_self_apply_list: i32 = 10035;
    pub const delete_friend: i32 = 10036;
    pub const set_friend_remark: i32 = 10037;
    pub const add_black: i32 = 10038;
    pub const get_black_list: i32 = 10039;
    pub const remove_black: i32 = 10040;
    pub const import_friend: i32 = 10041;
    pub const create_group: i32 = 10042;
    pub const get_group_member_list: i32 = 10043;
    pub const invite_to_group: i32 = 10044;
    pub const kick_from_group: i32 = 10045;
    pub const quit_group: i32 = 10046;
    pub const get_joined_group_list: i32 = 10047;
    pub const transfer_group: i32 = 10048;
    pub const transfer_group_owner: i32 = 10049;
    pub const set_group_member_info: i32 = 10050;
    pub const mute_group_member: i32 = 10051;
    pub const cancel_mute_group_member: i32 = 10052;
    pub const mute_group: i32 = 10053;
    pub const cancel_mute_group: i32 = 10054;
    pub const join_group: i32 = 10055;
    pub const group_application_response: i32 = 10056;
    pub const get_recv_group_applications: i32 = 10057;
    pub const get_user_req_group_applications: i32 = 10058;
    pub const set_group_info: i32 = 10059;
    pub const set_group_info_ex: i32 = 10060;
    pub const fcm_update_token: i32 = 10061;
    pub const upload_logs: i32 = 10062;
    pub const search_logs: i32 = 10063;
    pub const object_auth_sign: i32 = 10064;
    pub const object_access_url: i32 = 10065;
    pub const create_work_moment: i32 = 10066;
    pub const get_work_moment: i32 = 10067;
    pub const get_recv_work_moments: i32 = 10068;
    pub const get_send_work_moments: i32 = 10069;
    pub const get_organization: i32 = 10070;
    pub const get_departments: i32 = 10071;
    pub const get_sub_departments_and_members: i32 = 10072;
    pub const add_favorite_message: i32 = 10073;
    pub const remove_favorite_message: i32 = 10074;
    pub const get_favorite_messages: i32 = 10075;
    pub const get_encryption_key: i32 = 10076;
    pub const gen_encryption_key: i32 = 10077;
    pub const process_user_command_add: i32 = 10078;
    pub const process_user_command_delete: i32 = 10079;
    pub const process_user_command_get: i32 = 10080;
    pub const process_user_command_get_all: i32 = 10081;
    pub const create_tag: i32 = 10082;
    pub const delete_tag: i32 = 10083;
    pub const get_user_tags: i32 = 10084;
    pub const get_group_users_req_application_list: i32 = 10085;
    pub const get_specified_user_group_request_info: i32 = 10086;
    pub const get_users_in_departments: i32 = 10087;
    pub const search_organization_users: i32 = 10088;
    pub const get_work_moment_logs: i32 = 10089;
    pub const get_group_member_user_ids: i32 = 10090;
    pub const delete_friend_requests_from_user: i32 = 10091;
    pub const delete_friend_requests_to_user: i32 = 10092;
    pub const get_incremental_blacks: i32 = 10093;
    pub const get_incremental_friends: i32 = 10094;
    pub const get_incremental_group_members: i32 = 10095;
    pub const get_incremental_join_groups: i32 = 10096;
    pub const pull_msg_by_seqs: i32 = 10097;
    pub const get_specified_blacks: i32 = 10098;
    pub const get_designated_friends: i32 = 10099;
    pub const get_designated_friend_apply: i32 = 10100;
    pub const get_specified_friends_info: i32 = 10101;
    pub const get_friend_id: i32 = 10102;
    pub const search_friend_info: i32 = 10103;
    pub const get_full_friend_user_ids: i32 = 10104;
    pub const get_full_join_group_ids: i32 = 10105;
    pub const get_full_group_member_user_ids: i32 = 10106;
    pub const get_full_conversation_ids: i32 = 10107;
    pub const get_not_notify_conversation_ids: i32 = 10108;
    pub const get_pinned_conversation_ids: i32 = 10109;
    pub const delete_group_requests_from_user: i32 = 10110;
    pub const delete_group_requests_to_group: i32 = 10111;
    pub const delete_msg_physical_by_seq: i32 = 10112;
    pub const get_users: i32 = 10113;
    pub const mark_conversation_as_read: i32 = 10114;
    pub const mark_conversation_read: i32 = 10115;
    pub const set_conversation_has_read_seq: i32 = 10116;
    pub const rtc_meeting_create: i32 = 10117;
    pub const rtc_meeting_create_put: i32 = 10118;
    pub const search_users_full_info: i32 = 10119;
    pub const get_group_application_unhandled_count: i32 = 10120;
    pub const get_self_unhandled_apply_count: i32 = 10121;
    pub const process_user_command_update: i32 = 10122;
    pub const set_global_recv_msg_opt: i32 = 10123;

    // Module-specific bases (allocated in blocks of 100)
    pub const auth_base: i32 = 10100;
    pub const user_base: i32 = 10200;
    pub const message_base: i32 = 10300;
    pub const conversation_base: i32 = 10400;
    pub const friend_base: i32 = 10500;
    pub const group_base: i32 = 10600;
    pub const office_base: i32 = 10700;
    pub const organization_base: i32 = 10800;
    pub const third_base: i32 = 10900;
    pub const rtc_base: i32 = 11000;
    pub const statistics_base: i32 = 11100;

    pub fn moduleError(base: i32, offset: i32) i32 {
        return base + offset;
    }
};

// --------------------------------------------
// Public API: ModuleBoundary Validation
// Compile-time checks for Modulith best practices
// --------------------------------------------
