const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const auth_mod = @import("auth.zig");
const gw_root = @import("gateway/root.zig");
const h = @import("gateway/handlers.zig");

// Re-export public API
pub const info = gw_root.info;
pub const GatewayRoutes = h.GatewayRoutes;

const http = zigmodu.http;

var g_server: ?http.Server = null;
var g_server_thread: ?std.Thread = null;
var g_catalog: ?http.RouteCatalog = null;
var g_slot: http.CatalogSlot = .{};

const AppState = struct {
    gateway: h.GatewayRoutes.State,
};
var g_app_state: ?AppState = null;

pub fn deinit() void {
    // Stop the accept loop first so the background thread can exit, then join.
    if (g_server) |*srv| srv.stop();
    if (g_server_thread) |t| t.join();
    g_server_thread = null;
    if (g_server) |*srv| {
        srv.deinit();
    }
    g_server = null;
    // g_slot owns the catalog (set() takes ownership); free it exactly once.
    g_slot.deinit();
    g_catalog = null;
    if (g_registered_paths_init) {
        g_registered_paths.deinit();
        g_registered_paths_init = false;
    }
    g_app_state = null;
    gw_root.deinit();
}

// ============================================================
// HTTP transport — zigmodu http.Server + ComptimeRouter
// Handlers + route table live in gateway/handlers.zig.
// ============================================================

/// Routes per-request allocations to the connection arena so service results
/// (via `core.serviceAllocator()`) are reclaimed when the request ends.
pub fn requestArenaMiddleware(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
    core.setRequestAllocator(ctx.arenaAlloc());
    defer core.setRequestAllocator(null);
    const start_ms = zigmodu.time.monotonicNowMilliseconds();
    defer {
        const elapsed_ms = zigmodu.time.monotonicNowMilliseconds() - start_ms;
        core.metricHttpDuration(@as(f64, @floatFromInt(elapsed_ms)) / 1000.0);
        // Structured access log — one readable JSON line per request.
        core.logJson(.{
            .event = "http_request",
            .method = @tagName(ctx.method),
            .path = ctx.path,
            .status = ctx.status_code,
            .duration_ms = elapsed_ms,
        });
    }
    // Per-module bulkhead (RuntimeOptions.max_concurrent) — reject when full
    if (core.getModuleRuntime("gateway")) |rt| {
        if (!rt.tryEnter()) {
            return h.sendFail(ctx, 503, "Server Busy");
        }
        defer rt.release();
    }
    return next(ctx);
}

pub fn corsMiddleware(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
    core.metricHttpRequest();
    try ctx.setHeader("Access-Control-Allow-Origin", "*");
    try ctx.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    try ctx.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, token");
    try ctx.setHeader("Access-Control-Max-Age", "86400");
    if (ctx.method == .OPTIONS) {
        ctx.status_code = 204;
        ctx.responded = true;
        return;
    }
    return next(ctx);
}

pub fn authMiddleware(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
    // Unknown paths -> 404 (matches the legacy router behavior)
    if (g_registered_paths.get(ctx.path) == null) {
        return h.sendFail(ctx, 404, "Not Found");
    }
    if (h.isPublicPath(ctx.path)) return next(ctx);
    const token = h.getBearerToken(ctx) orelse {
        return h.sendFail(ctx, 401, "Unauthorized");
    };
    _ = auth_mod.parseToken(token) catch {
        return h.sendFail(ctx, 401, "Unauthorized");
    };
    return next(ctx);
}

var g_registered_paths: std.StringHashMap(void) = undefined;
var g_registered_paths_init = false;

/// Index registered paths for the auth middleware (404 on unknown paths).
pub fn initRegisteredPaths(allocator: std.mem.Allocator) !void {
    if (g_registered_paths_init) return;
    g_registered_paths = std.StringHashMap(void).init(allocator);
    inline for (h.GatewayRoutes.routes) |r| {
        try g_registered_paths.put(r.path, {});
    }
    try g_registered_paths.put("/openapi.json", {});
    g_registered_paths_init = true;
}

pub fn startHttpServer(io: std.Io, allocator: std.mem.Allocator, port: u16) !void {
    g_server = http.Server.init(io, allocator, port);
    var server = &g_server.?;
    server.withGracefulDrain(zigmodu.getInFlightCounter());
    try server.addMiddleware(.{ .func = requestArenaMiddleware });
    try server.addMiddleware(.{ .func = corsMiddleware });
    // Production security headers (HSTS, frame/type protections, referrer policy)
    try server.addMiddleware(zigmodu.http.http_middleware.securityHeaders(null));
    try server.addMiddleware(.{ .func = authMiddleware });

    g_app_state = AppState{ .gateway = .{} };
    var router = http.Router(AppState).init(io, allocator, server, &g_app_state.?);
    var scoped = router.scope("");
    try scoped.mountAll(.{.{ .Mod = h.GatewayRoutes, .state = &g_app_state.?.gateway }});
    g_catalog = try router.finish();
    g_slot.set(g_catalog.?);

    // OpenAPI 3.x document generated from the route catalog
    try server.addRoute(.{
        .method = .GET,
        .path = "openapi.json",
        .handler = http.openApiFromCatalog(&g_slot, .{
            .title = "ZIM Server API",
            .version = "0.4.0",
            .description = "OpenIM-compatible IM server rewritten in Zig on zigmodu",
        }),
    });

    try initRegisteredPaths(allocator);

    g_server_thread = try server.runInBackground();
    std.log.info("HTTP server started on http://0.0.0.0:{d} (zigmodu http.Server + ComptimeRouter)", .{port});
}
