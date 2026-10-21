// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: health.zig

const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const gw_root = @import("../root.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;

pub fn handleHealth(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const json = try gw_root.healthJson(ctx.arenaAlloc());
    ctx.status_code = 200;
    try ctx.setHeader("Content-Type", "application/json");
    try ctx.response_body.appendSlice(ctx.arenaAlloc(), json);
    ctx.responded = true;
    ctx.arenaAlloc().free(json);
}

pub fn handlePrometheusMetrics(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const body = try core.renderMetrics(ctx.arenaAlloc());
    ctx.status_code = 200;
    try ctx.setHeader("Content-Type", "text/plain; version=0.0.4");
    try ctx.response_body.appendSlice(ctx.arenaAlloc(), body);
    ctx.responded = true;
    ctx.arenaAlloc().free(body);
}
