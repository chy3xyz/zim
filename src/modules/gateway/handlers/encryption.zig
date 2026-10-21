// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: encryption.zig

const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const conversation_mod = @import("../../conversation.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleGenEncryptionKey(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GenReq = struct {
        conversationID: []const u8,
    };
    const req = ctx.bindJson(GenReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    conversation_mod.genEncryptionKey(req.conversationID) catch |err| {
        return sendFail(ctx, core.ErrorCode.gen_encryption_key, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleGetEncryptionKey(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        conversationID: []const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const keys = conversation_mod.getEncryptionKeys(req.conversationID, core.getAllocator()) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_encryption_key, @errorName(err));
    };
    return sendOk(ctx, .{ .keys = keys });
}
