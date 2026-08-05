const std = @import("std");
const model = @import("model.zig");

// --- Unsigned integer encoding (GOB wire format) ---
fn encodeUint(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, x: u64) !void {
    if (x <= 0x7F) {
        try buf.append(allocator, @intCast(x));
        return;
    }
    var bl: u8 = 1;
    var t2 = x;
    while (t2 > 0xFF) {
        t2 >>= 8;
        bl += 1;
    }
    const prefix: u8 = @intCast(@as(u16, 0x100) - @as(u16, bl));
    try buf.append(allocator, prefix);
    var i: i8 = @intCast(bl - 1);
    while (i >= 0) : (i -= 1) {
        const shift: u6 = @intCast(i * 8);
        try buf.append(allocator, @intCast((x >> shift) & 0xFF));
    }
}

// --- Signed integer encoding (zigzag) ---
fn encodeInt(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, i: i64) !void {
    var x: u64 = undefined;
    if (i < 0) {
        x = @as(u64, @bitCast(~i)) << 1 | 1;
    } else {
        x = @as(u64, @intCast(i)) << 1;
    }
    try encodeUint(buf, allocator, x);
}

fn decodeUint(data: []const u8, offset: *usize) !u64 {
    if (offset.* >= data.len) return error.Truncated;
    const b0 = data[offset.*];
    offset.* += 1;
    if (b0 <= 0x7F) {
        return b0;
    }
    const bl: u8 = @intCast(@as(u16, 0x100) - @as(u16, b0));
    if (offset.* + bl > data.len) return error.Truncated;
    var x: u64 = 0;
    for (0..bl) |_| {
        x = (x << 8) | data[offset.*];
        offset.* += 1;
    }
    return x;
}

fn decodeInt(data: []const u8, offset: *usize) !i64 {
    const x = try decodeUint(data, offset);
    if ((x & 1) != 0) {
        return @bitCast(~(x >> 1));
    } else {
        return @intCast(x >> 1);
    }
}

fn encodeString(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, s: []const u8) !void {
    try encodeUint(buf, allocator, s.len);
    try buf.appendSlice(allocator, s);
}

fn decodeString(data: []const u8, offset: *usize) ![]const u8 {
    const len = try decodeUint(data, offset);
    if (offset.* + len > data.len) return error.Truncated;
    const s = data[offset.* .. offset.* + len];
    offset.* += len;
    return s;
}

fn encodeBytes(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, b: []const u8) !void {
    try encodeUint(buf, allocator, b.len);
    try buf.appendSlice(allocator, b);
}

fn decodeBytes(data: []const u8, offset: *usize, allocator: std.mem.Allocator) ![]u8 {
    const len = try decodeUint(data, offset);
    if (offset.* + len > data.len) return error.Truncated;
    const result = try allocator.dupe(u8, data[offset.* .. offset.* + len]);
    offset.* += len;
    return result;
}

// --- Type description prefixes (hardcoded from Go reference) ---
const req_type_desc = [_]u8{
    0x65, 0x7f, 0x03, 0x01, 0x01, 0x0c, 0x47, 0x65, 0x6e, 0x65, 0x72, 0x61,
    0x6c, 0x57, 0x73, 0x52, 0x65, 0x71, 0x01, 0xff, 0x80, 0x00, 0x01, 0x06,
    0x01, 0x0d, 0x52, 0x65, 0x71, 0x49, 0x64, 0x65, 0x6e, 0x74, 0x69, 0x66,
    0x69, 0x65, 0x72, 0x01, 0x04, 0x00, 0x01, 0x05, 0x54, 0x6f, 0x6b, 0x65,
    0x6e, 0x01, 0x0c, 0x00, 0x01, 0x06, 0x53, 0x65, 0x6e, 0x64, 0x49, 0x44,
    0x01, 0x0c, 0x00, 0x01, 0x0b, 0x4f, 0x70, 0x65, 0x72, 0x61, 0x74, 0x69,
    0x6f, 0x6e, 0x49, 0x44, 0x01, 0x0c, 0x00, 0x01, 0x07, 0x4d, 0x73, 0x67,
    0x49, 0x6e, 0x63, 0x72, 0x01, 0x0c, 0x00, 0x01, 0x04, 0x44, 0x61, 0x74,
    0x61, 0x01, 0x0a, 0x00, 0x00, 0x00,
};

const resp_type_desc = [_]u8{
    0x69, 0xff, 0x81, 0x03, 0x01, 0x01, 0x0d, 0x47, 0x65, 0x6e, 0x65, 0x72,
    0x61, 0x6c, 0x57, 0x73, 0x52, 0x65, 0x73, 0x70, 0x01, 0xff, 0x82, 0x00,
    0x01, 0x06, 0x01, 0x0d, 0x52, 0x65, 0x71, 0x49, 0x64, 0x65, 0x6e, 0x74,
    0x69, 0x66, 0x69, 0x65, 0x72, 0x01, 0x04, 0x00, 0x01, 0x07, 0x45, 0x72,
    0x72, 0x43, 0x6f, 0x64, 0x65, 0x01, 0x04, 0x00, 0x01, 0x06, 0x45, 0x72,
    0x72, 0x4d, 0x73, 0x67, 0x01, 0x0c, 0x00, 0x01, 0x07, 0x4d, 0x73, 0x67,
    0x49, 0x6e, 0x63, 0x72, 0x01, 0x0c, 0x00, 0x01, 0x0b, 0x4f, 0x70, 0x65,
    0x72, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x49, 0x44, 0x01, 0x0c, 0x00, 0x01,
    0x04, 0x44, 0x61, 0x74, 0x61, 0x01, 0x0a, 0x00, 0x00, 0x00,
};

// --- Encode Req ---
pub fn encodeReq(req: model.GeneralWsReq, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, &req_type_desc);

    var val = std.ArrayList(u8).empty;
    defer val.deinit(allocator);

    try val.appendSlice(allocator, &[_]u8{ 0xff, 0x80 });

    var prev_field: i32 = -1;

    if (req.req_identifier != 0) {
        const delta: i32 = 0 - prev_field;
        try encodeUint(&val, allocator, @intCast(delta));
        try encodeInt(&val, allocator, req.req_identifier);
        prev_field = 0;
    }

    if (req.token.len > 0) {
        const delta: i32 = 1 - prev_field;
        try encodeUint(&val, allocator, @intCast(delta));
        try encodeString(&val, allocator, req.token);
        prev_field = 1;
    }

    if (req.send_id.len > 0) {
        const delta: i32 = 2 - prev_field;
        try encodeUint(&val, allocator, @intCast(delta));
        try encodeString(&val, allocator, req.send_id);
        prev_field = 2;
    }

    if (req.operation_id.len > 0) {
        const delta: i32 = 3 - prev_field;
        try encodeUint(&val, allocator, @intCast(delta));
        try encodeString(&val, allocator, req.operation_id);
        prev_field = 3;
    }

    if (req.msg_incr.len > 0) {
        const delta: i32 = 4 - prev_field;
        try encodeUint(&val, allocator, @intCast(delta));
        try encodeString(&val, allocator, req.msg_incr);
        prev_field = 4;
    }

    if (req.data.len > 0) {
        const delta: i32 = 5 - prev_field;
        try encodeUint(&val, allocator, @intCast(delta));
        try encodeBytes(&val, allocator, req.data);
        prev_field = 5;
    }

    try val.append(allocator, 0);

    if (val.items.len > 128) {
        try encodeUint(&buf, allocator, val.items.len);
    } else {
        try buf.append(allocator, @intCast(val.items.len));
    }
    try buf.appendSlice(allocator, val.items);

    return buf.toOwnedSlice(allocator);
}

// --- Encode Resp ---
pub fn encodeResp(resp: model.GeneralWsResp, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, &resp_type_desc);

    var val = std.ArrayList(u8).empty;
    defer val.deinit(allocator);

    try val.appendSlice(allocator, &[_]u8{ 0xff, 0x82 });

    var prev_field: i32 = -1;

    if (resp.req_identifier != 0) {
        try encodeUint(&val, allocator, @intCast(0 - prev_field));
        try encodeInt(&val, allocator, resp.req_identifier);
        prev_field = 0;
    }

    if (resp.err_code != 0) {
        try encodeUint(&val, allocator, @intCast(1 - prev_field));
        try encodeInt(&val, allocator, resp.err_code);
        prev_field = 1;
    }

    if (resp.err_msg.len > 0) {
        try encodeUint(&val, allocator, @intCast(2 - prev_field));
        try encodeString(&val, allocator, resp.err_msg);
        prev_field = 2;
    }

    if (resp.msg_incr.len > 0) {
        try encodeUint(&val, allocator, @intCast(3 - prev_field));
        try encodeString(&val, allocator, resp.msg_incr);
        prev_field = 3;
    }

    if (resp.operation_id.len > 0) {
        try encodeUint(&val, allocator, @intCast(4 - prev_field));
        try encodeString(&val, allocator, resp.operation_id);
        prev_field = 4;
    }

    if (resp.data.len > 0) {
        try encodeUint(&val, allocator, @intCast(5 - prev_field));
        try encodeBytes(&val, allocator, resp.data);
        prev_field = 5;
    }

    try val.append(allocator, 0);

    if (val.items.len > 128) {
        try encodeUint(&buf, allocator, val.items.len);
    } else {
        try buf.append(allocator, @intCast(val.items.len));
    }
    try buf.appendSlice(allocator, val.items);

    return buf.toOwnedSlice(allocator);
}

// --- Decode Req ---
pub fn decodeReq(data: []const u8, allocator: std.mem.Allocator) !model.GeneralWsReq {
    if (data.len < req_type_desc.len) return error.Truncated;
    if (!std.mem.eql(u8, data[0..req_type_desc.len], &req_type_desc)) {
        return error.InvalidTypeDesc;
    }

    var offset: usize = req_type_desc.len;

    if (offset >= data.len) return error.Truncated;
    const val_len_byte = data[offset];
    offset += 1;
    var val_len: usize = val_len_byte;
    if (val_len_byte > 0x7F) {
        const bl: u8 = @intCast(@as(u16, 0x100) - @as(u16, val_len_byte));
        val_len = 0;
        for (0..bl) |_| {
            if (offset >= data.len) return error.Truncated;
            val_len = (val_len << 8) | data[offset];
            offset += 1;
        }
    }

    if (offset + val_len > data.len) return error.Truncated;
    const val_data = data[offset .. offset + val_len];

    var req = model.GeneralWsReq{};
    var val_offset: usize = 0;

    if (val_offset + 2 > val_data.len or val_data[val_offset] != 0xff or val_data[val_offset + 1] != 0x80) {
        return error.InvalidTypeRef;
    }
    val_offset += 2;

    var prev_field: i32 = -1;
    while (val_offset < val_data.len) {
        const field_delta = try decodeUint(val_data, &val_offset);
        if (field_delta == 0) break;

        const field_idx = prev_field + @as(i32, @intCast(field_delta));
        prev_field = field_idx;

        switch (field_idx) {
            0 => req.req_identifier = @intCast(try decodeInt(val_data, &val_offset)),
            1 => req.token = try decodeString(val_data, &val_offset),
            2 => req.send_id = try decodeString(val_data, &val_offset),
            3 => req.operation_id = try decodeString(val_data, &val_offset),
            4 => req.msg_incr = try decodeString(val_data, &val_offset),
            5 => req.data = try decodeBytes(val_data, &val_offset, allocator),
            else => return error.InvalidField,
        }
    }

    return req;
}

// --- Decode Resp ---
pub fn decodeResp(data: []const u8, allocator: std.mem.Allocator) !model.GeneralWsResp {
    if (data.len < resp_type_desc.len) return error.Truncated;
    if (!std.mem.eql(u8, data[0..resp_type_desc.len], &resp_type_desc)) {
        return error.InvalidTypeDesc;
    }

    var offset: usize = resp_type_desc.len;

    if (offset >= data.len) return error.Truncated;
    const val_len_byte = data[offset];
    offset += 1;
    var val_len: usize = val_len_byte;
    if (val_len_byte > 0x7F) {
        const bl: u8 = @intCast(@as(u16, 0x100) - @as(u16, val_len_byte));
        val_len = 0;
        for (0..bl) |_| {
            if (offset >= data.len) return error.Truncated;
            val_len = (val_len << 8) | data[offset];
            offset += 1;
        }
    }

    if (offset + val_len > data.len) return error.Truncated;
    const val_data = data[offset .. offset + val_len];

    var resp = model.GeneralWsResp{};
    var val_offset: usize = 0;

    if (val_offset + 2 > val_data.len or val_data[val_offset] != 0xff or val_data[val_offset + 1] != 0x82) {
        return error.InvalidTypeRef;
    }
    val_offset += 2;

    var prev_field: i32 = -1;
    while (val_offset < val_data.len) {
        const field_delta = try decodeUint(val_data, &val_offset);
        if (field_delta == 0) break;

        const field_idx = prev_field + @as(i32, @intCast(field_delta));
        prev_field = field_idx;

        switch (field_idx) {
            0 => resp.req_identifier = @intCast(try decodeInt(val_data, &val_offset)),
            1 => resp.err_code = @intCast(try decodeInt(val_data, &val_offset)),
            2 => resp.err_msg = try decodeString(val_data, &val_offset),
            3 => resp.msg_incr = try decodeString(val_data, &val_offset),
            4 => resp.operation_id = try decodeString(val_data, &val_offset),
            5 => resp.data = try decodeBytes(val_data, &val_offset, allocator),
            else => return error.InvalidField,
        }
    }

    return resp;
}

// --- Free decoded structs ---
pub fn freeReq(req: model.GeneralWsReq, allocator: std.mem.Allocator) void {
    if (req.data.len > 0) allocator.free(req.data);
}

pub fn freeResp(resp: model.GeneralWsResp, allocator: std.mem.Allocator) void {
    if (resp.data.len > 0) allocator.free(resp.data);
}
