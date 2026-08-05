const std = @import("std");

// Lightweight protobuf v3 encoder/decoder for OpenIM WebSocket protocol.
// Supports: varint, fixed32/64, length-delimited (string/bytes/embedded/repeated), zigzag.

pub const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    length_delimited = 2,
    start_group = 3,
    end_group = 4,
    fixed32 = 5,
};

// ---------- Encoding ----------

pub const Encoder = struct {
    buf: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Encoder {
        return .{ .buf = std.ArrayList(u8).empty, .allocator = allocator };
    }

    pub fn deinit(self: *Encoder) void {
        self.buf.deinit(self.allocator);
    }

    pub fn bytes(self: *const Encoder) []const u8 {
        return self.buf.items;
    }

    pub fn encodeVarint(self: *Encoder, value: u64) !void {
        var v = value;
        while (v >= 0x80) {
            try self.buf.append(self.allocator, @as(u8, @truncate(v & 0x7F)) | 0x80);
            v >>= 7;
        }
        try self.buf.append(self.allocator, @as(u8, @truncate(v)));
    }

    pub fn encodeZigZag64(self: *Encoder, value: i64) !void {
        const zigzag = @as(u64, @bitCast((value << 1) ^ (value >> 63)));
        try self.encodeVarint(zigzag);
    }

    pub fn encodeZigZag32(self: *Encoder, value: i32) !void {
        const zigzag = @as(u32, @bitCast((value << 1) ^ (value >> 31)));
        try self.encodeVarint(zigzag);
    }

    pub fn encodeFixed64(self: *Encoder, value: u64) !void {
        var bytes_le: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes_le, value, .little);
        try self.buf.appendSlice(self.allocator, &bytes_le);
    }

    pub fn encodeFixed32(self: *Encoder, value: u32) !void {
        var bytes_le: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes_le, value, .little);
        try self.buf.appendSlice(self.allocator, &bytes_le);
    }

    pub fn encodeTag(self: *Encoder, field_number: u32, wire_type: WireType) !void {
        const key = (@as(u64, field_number) << 3) | @intFromEnum(wire_type);
        try self.encodeVarint(key);
    }

    pub fn encodeString(self: *Encoder, field_number: u32, value: []const u8) !void {
        try self.encodeTag(field_number, .length_delimited);
        try self.encodeVarint(value.len);
        try self.buf.appendSlice(self.allocator, value);
    }

    pub fn encodeBytes(self: *Encoder, field_number: u32, value: []const u8) !void {
        try self.encodeString(field_number, value);
    }

    pub fn encodeInt32(self: *Encoder, field_number: u32, value: i32) !void {
        try self.encodeTag(field_number, .varint);
        try self.encodeVarint(@as(u64, @intCast(value)));
    }

    pub fn encodeInt64(self: *Encoder, field_number: u32, value: i64) !void {
        try self.encodeTag(field_number, .varint);
        try self.encodeVarint(@as(u64, @intCast(value)));
    }

    pub fn encodeUint32(self: *Encoder, field_number: u32, value: u32) !void {
        try self.encodeTag(field_number, .varint);
        try self.encodeVarint(value);
    }

    pub fn encodeUint64(self: *Encoder, field_number: u32, value: u64) !void {
        try self.encodeTag(field_number, .varint);
        try self.encodeVarint(value);
    }

    pub fn encodeSint32(self: *Encoder, field_number: u32, value: i32) !void {
        try self.encodeTag(field_number, .varint);
        try self.encodeZigZag32(value);
    }

    pub fn encodeSint64(self: *Encoder, field_number: u32, value: i64) !void {
        try self.encodeTag(field_number, .varint);
        try self.encodeZigZag64(value);
    }

    pub fn encodeBool(self: *Encoder, field_number: u32, value: bool) !void {
        try self.encodeTag(field_number, .varint);
        try self.encodeVarint(if (value) 1 else 0);
    }

    pub fn encodeEmbedded(self: *Encoder, field_number: u32, msg_bytes: []const u8) !void {
        try self.encodeTag(field_number, .length_delimited);
        try self.encodeVarint(msg_bytes.len);
        try self.buf.appendSlice(self.allocator, msg_bytes);
    }

    pub fn encodeRepeatedString(self: *Encoder, field_number: u32, items: []const []const u8) !void {
        for (items) |item| {
            try self.encodeString(field_number, item);
        }
    }
};

// ---------- Decoding ----------

pub const Decoder = struct {
    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) Decoder {
        return .{ .data = data, .pos = 0 };
    }

    pub fn eof(self: *const Decoder) bool {
        return self.pos >= self.data.len;
    }

    pub fn remaining(self: *const Decoder) []const u8 {
        return self.data[self.pos..];
    }

    pub fn decodeVarint(self: *Decoder) !u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        while (true) {
            if (self.pos >= self.data.len) return error.UnexpectedEof;
            const byte = self.data[self.pos];
            self.pos += 1;
            result |= @as(u64, byte & 0x7F) << shift;
            if ((byte & 0x80) == 0) return result;
            shift += 7;
            if (shift > 63) return error.InvalidVarint;
        }
    }

    pub fn decodeZigZag64(self: *Decoder) !i64 {
        const v = try self.decodeVarint();
        return @as(i64, @bitCast((v >> 1) ^ (~(v & 1) + 1)));
    }

    pub fn decodeZigZag32(self: *Decoder) !i32 {
        const v = try self.decodeVarint();
        const u = @as(u32, @truncate(v));
        return @as(i32, @bitCast((u >> 1) ^ (~(u & 1) + 1)));
    }

    pub fn decodeFixed64(self: *Decoder) !u64 {
        if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
        const val = std.mem.readInt(u64, self.data[self.pos..][0..8], .little);
        self.pos += 8;
        return val;
    }

    pub fn decodeFixed32(self: *Decoder) !u32 {
        if (self.pos + 4 > self.data.len) return error.UnexpectedEof;
        const val = std.mem.readInt(u32, self.data[self.pos..][0..4], .little);
        self.pos += 4;
        return val;
    }

    pub fn decodeTag(self: *Decoder) !struct { field_number: u32, wire_type: WireType } {
        const key = try self.decodeVarint();
        const field_number = @as(u32, @intCast(key >> 3));
        const wire = @as(u3, @intCast(key & 0x07));
        const wire_type: WireType = @enumFromInt(wire);
        return .{ .field_number = field_number, .wire_type = wire_type };
    }

    pub fn skipField(self: *Decoder, wire_type: WireType) !void {
        switch (wire_type) {
            .varint => _ = try self.decodeVarint(),
            .fixed64 => self.pos += 8,
            .length_delimited => {
                const len = try self.decodeVarint();
                if (self.pos + len > self.data.len) return error.UnexpectedEof;
                self.pos += @as(usize, @intCast(len));
            },
            .fixed32 => self.pos += 4,
            .start_group, .end_group => return error.UnsupportedGroup,
        }
    }

    pub fn decodeString(self: *Decoder, field_number: u32) !?[]const u8 {
        const tag = try self.decodeTag();
        if (tag.field_number != field_number or tag.wire_type != .length_delimited) {
            // Rewind and let caller handle
            self.pos -= switch (tag.field_number) {
                0...15 => 1,
                16...2047 => 2,
                else => 3,
            };
            return null;
        }
        const len = try self.decodeVarint();
        if (self.pos + len > self.data.len) return error.UnexpectedEof;
        const s = self.data[self.pos..][0..@as(usize, @intCast(len))];
        self.pos += @as(usize, @intCast(len));
        return s;
    }

    pub fn decodeBytesSlice(self: *Decoder) ![]const u8 {
        const len = try self.decodeVarint();
        if (self.pos + len > self.data.len) return error.UnexpectedEof;
        const s = self.data[self.pos..][0..@as(usize, @intCast(len))];
        self.pos += @as(usize, @intCast(len));
        return s;
    }
};

// ---------- Tests ----------

test "varint encode/decode" {
    const allocator = std.testing.allocator;
    var enc = Encoder.init(allocator);
    defer enc.deinit();

    try enc.encodeVarint(1);
    try enc.encodeVarint(150);
    try enc.encodeVarint(0xFFFFFFFFFFFFFFFF);

    var dec = Decoder.init(enc.bytes());
    try std.testing.expectEqual(@as(u64, 1), try dec.decodeVarint());
    try std.testing.expectEqual(@as(u64, 150), try dec.decodeVarint());
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), try dec.decodeVarint());
}

test "string encode/decode" {
    const allocator = std.testing.allocator;
    var enc = Encoder.init(allocator);
    defer enc.deinit();

    try enc.encodeString(1, "hello");

    var dec = Decoder.init(enc.bytes());
    const tag = try dec.decodeTag();
    try std.testing.expectEqual(@as(u32, 1), tag.field_number);
    try std.testing.expectEqual(WireType.length_delimited, tag.wire_type);
    const s = try dec.decodeBytesSlice();
    try std.testing.expectEqualStrings("hello", s);
}
