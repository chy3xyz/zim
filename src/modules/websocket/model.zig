const std = @import("std");
const core = @import("core");
const gob = @import("../gob.zig");

// OpenIM WebSocket protocol constants
pub const WSGetNewestSeq = 1001;
pub const WSPullMsgBySeqList = 1002;
pub const WSSendMsg = 1003;
pub const WSSendSignalMsg = 1004;
pub const WSPullMsg = 1005;
pub const WSGetConvMaxReadSeq = 1006;
pub const WsPullConvLastMessage = 1007;
pub const WSPushMsg = 2001;
pub const WSKickOnlineMsg = 2002;
pub const WsLogoutMsg = 2003;
pub const WsSetBackgroundStatus = 2004;
pub const WsSubUserOnlineStatus = 2005;
pub const WSServerConfigMsg = 2100;
pub const WSDataError = 3001;

// WebSocket frame opcodes
pub const OpCode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

// Client connection
pub const WSClient = struct {
    stream: std.Io.net.Stream,
    /// zigmodu WsFramer pointer — set for zigmodu-managed connections.
    /// When set, all frame writes go through the framer (text/binary aware).
    framer: ?*anyopaque = null,
    user_id: []const u8 = "",
    is_authenticated: bool = false,
    platform_id: i32 = 0,
    is_background: bool = false,
    is_gob_client: bool = false,

    pub fn sendText(self: *WSClient, payload: []const u8) !void {
        try self.sendFrame(0x1, payload);
    }

    pub fn sendBinary(self: *WSClient, payload: []const u8) !void {
        try self.sendFrame(0x2, payload);
    }

    pub fn sendFrame(self: *WSClient, opcode: u8, payload: []const u8) !void {
        if (self.framer) |f| {
            const framer: *@import("zigmodu").im.WsFramer = @ptrCast(@alignCast(f));
            if (opcode == 0x2) return framer.writeBinary(payload);
            return framer.writeText(payload);
        }
        var header_buf: [14]u8 = undefined;
        var header_len: usize = 2;

        header_buf[0] = 0x80 | opcode; // FIN = 1

        if (payload.len < 126) {
            header_buf[1] = @intCast(payload.len);
        } else if (payload.len < 65536) {
            header_buf[1] = 126;
            std.mem.writeInt(u16, header_buf[2..4], @intCast(payload.len), .big);
            header_len = 4;
        } else {
            header_buf[1] = 127;
            std.mem.writeInt(u64, header_buf[2..10], payload.len, .big);
            header_len = 10;
        }

        var write_buf: [4096]u8 = undefined;
        var w = self.stream.writer(g_io, &write_buf);
        try w.interface.writeAll(header_buf[0..header_len]);
        try w.interface.writeAll(payload);
    }

    pub fn close(self: *WSClient) void {
        // zigmodu's connection fiber owns the socket; it closes on disconnect.
        if (self.framer != null) return;
        self.stream.close(g_io);
    }
};

pub const Frame = struct {
    opcode: u8,
    payload: []const u8,
};

// Global Io instance (needed by WSClient.sendFrame)
var g_io: std.Io = undefined;
var g_io_set = false;

pub fn setIo(io: std.Io) void {
    g_io = io;
    g_io_set = true;
}

pub fn isIoSet() bool {
    return g_io_set;
}

pub fn getIo() std.Io {
    return g_io;
}

// Send WebSocket response (GOB or JSON depending on client type)
pub fn sendWSResponse(client: *WSClient, req_id: i32, msg_incr: []const u8, operation_id: []const u8, err_code: i32, err_msg: []const u8, data_bytes: []const u8) void {
    if (client.is_gob_client) {
        // GOB response: data contains raw protobuf bytes
        const resp = gob.GeneralWsResp{
            .req_identifier = req_id,
            .err_code = err_code,
            .err_msg = err_msg,
            .msg_incr = msg_incr,
            .operation_id = operation_id,
            .data = data_bytes,
        };
        const encoded = gob.encodeResp(resp, core.getAllocator()) catch {
            std.log.err("[WebSocket] Failed to encode GOB response", .{});
            return;
        };
        defer core.getAllocator().free(encoded);
        client.sendBinary(encoded) catch {};
    } else {
        // JSON response: data contains base64-encoded protobuf
        const encoder = std.base64.url_safe.Encoder;
        var b64_buf: [65536]u8 = undefined;
        const b64_data = encoder.encode(&b64_buf, data_bytes);

        const response = std.fmt.allocPrint(core.getAllocator(), "{{\"reqIdentifier\":{d},\"msgIncr\":\"{s}\",\"operationID\":\"{s}\",\"errCode\":{d},\"errMsg\":\"{s}\",\"data\":\"{s}\"}}", .{ req_id, msg_incr, operation_id, err_code, err_msg, b64_data }) catch return;
        defer core.getAllocator().free(response);

        client.sendText(response) catch {};
    }
}

pub fn sendWSError(client: *WSClient, req_id: i32, msg_incr: []const u8, err_code: i32, err_msg: []const u8, operation_id: ?[]const u8) void {
    const op_id = operation_id orelse "";
    sendWSResponse(client, req_id, msg_incr, op_id, err_code, err_msg, &[_]u8{});
}

pub fn sendError(client: *WSClient, err_msg: []const u8) void {
    const response = std.fmt.allocPrint(core.getAllocator(), "{{\"errCode\":500,\"errMsg\":\"{s}\",\"data\":null}}", .{err_msg}) catch return;
    defer core.getAllocator().free(response);
    client.sendText(response) catch {};
}
