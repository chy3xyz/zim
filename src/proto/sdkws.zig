const std = @import("std");
const pb = @import("protobuf.zig");

// OpenIM sdkws protobuf message definitions (lightweight codec).

pub const MsgData = struct {
    send_id: []const u8 = "",
    recv_id: []const u8 = "",
    group_id: []const u8 = "",
    client_msg_id: []const u8 = "",
    server_msg_id: []const u8 = "",
    sender_platform_id: i32 = 0,
    sender_nickname: []const u8 = "",
    sender_face_url: []const u8 = "",
    session_type: i32 = 0,
    msg_from: i32 = 0,
    content_type: i32 = 0,
    content: []const u8 = "",
    seq: i64 = 0,
    send_time: i64 = 0,
    create_time: i64 = 0,
    status: i32 = 0,
    is_read: bool = false,
    at_user_id_list: []const []const u8 = &.{},
    attached_info: []const u8 = "",
    ex: []const u8 = "",
    offline_push_info: ?OfflinePushInfo = null,

    pub fn encode(self: MsgData, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();

        if (self.send_id.len > 0) try enc.encodeString(1, self.send_id);
        if (self.recv_id.len > 0) try enc.encodeString(2, self.recv_id);
        if (self.group_id.len > 0) try enc.encodeString(3, self.group_id);
        if (self.client_msg_id.len > 0) try enc.encodeString(4, self.client_msg_id);
        if (self.server_msg_id.len > 0) try enc.encodeString(5, self.server_msg_id);
        if (self.sender_platform_id != 0) try enc.encodeInt32(6, self.sender_platform_id);
        if (self.sender_nickname.len > 0) try enc.encodeString(7, self.sender_nickname);
        if (self.sender_face_url.len > 0) try enc.encodeString(8, self.sender_face_url);
        if (self.session_type != 0) try enc.encodeInt32(9, self.session_type);
        if (self.msg_from != 0) try enc.encodeInt32(10, self.msg_from);
        if (self.content_type != 0) try enc.encodeInt32(11, self.content_type);
        if (self.content.len > 0) try enc.encodeBytes(12, self.content);
        if (self.seq != 0) try enc.encodeInt64(14, self.seq);
        if (self.send_time != 0) try enc.encodeInt64(15, self.send_time);
        if (self.create_time != 0) try enc.encodeInt64(16, self.create_time);
        if (self.status != 0) try enc.encodeInt32(17, self.status);
        if (self.is_read) try enc.encodeBool(18, self.is_read);
        for (self.at_user_id_list) |uid| try enc.encodeString(21, uid);
        if (self.attached_info.len > 0) try enc.encodeString(22, self.attached_info);
        if (self.ex.len > 0) try enc.encodeString(23, self.ex);
        if (self.offline_push_info) |opi| {
            const sub = try opi.encode(allocator);
            defer allocator.free(sub);
            try enc.encodeEmbedded(20, sub);
        }

        return try allocator.dupe(u8, enc.bytes());
    }

    pub fn decode(data: []const u8, allocator: std.mem.Allocator) !MsgData {
        var msg = MsgData{};
        var at_list = std.ArrayList([]const u8).empty;
        defer at_list.deinit(allocator);

        var dec = pb.Decoder.init(data);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.send_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                2 => msg.recv_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                3 => msg.group_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                4 => msg.client_msg_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                5 => msg.server_msg_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                6 => msg.sender_platform_id = @intCast(try dec.decodeVarint()),
                7 => msg.sender_nickname = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                8 => msg.sender_face_url = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                9 => msg.session_type = @intCast(try dec.decodeVarint()),
                10 => msg.msg_from = @intCast(try dec.decodeVarint()),
                11 => msg.content_type = @intCast(try dec.decodeVarint()),
                12 => msg.content = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                14 => msg.seq = @intCast(try dec.decodeVarint()),
                15 => msg.send_time = @intCast(try dec.decodeVarint()),
                16 => msg.create_time = @intCast(try dec.decodeVarint()),
                17 => msg.status = @intCast(try dec.decodeVarint()),
                18 => msg.is_read = (try dec.decodeVarint()) != 0,
                20 => {
                    const sub = try dec.decodeBytesSlice();
                    msg.offline_push_info = try OfflinePushInfo.decode(sub, allocator);
                },
                21 => try at_list.append(allocator, try allocator.dupe(u8, try dec.decodeBytesSlice())),
                22 => msg.attached_info = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                23 => msg.ex = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                else => try dec.skipField(tag.wire_type),
            }
        }
        msg.at_user_id_list = try at_list.toOwnedSlice(allocator);
        return msg;
    }
};

pub const OfflinePushInfo = struct {
    title: []const u8 = "",
    desc: []const u8 = "",
    ex: []const u8 = "",
    ios_push_sound: []const u8 = "",
    ios_badge_count: bool = false,
    signal_info: []const u8 = "",

    pub fn encode(self: OfflinePushInfo, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.title.len > 0) try enc.encodeString(1, self.title);
        if (self.desc.len > 0) try enc.encodeString(2, self.desc);
        if (self.ex.len > 0) try enc.encodeString(3, self.ex);
        if (self.ios_push_sound.len > 0) try enc.encodeString(4, self.ios_push_sound);
        if (self.ios_badge_count) try enc.encodeBool(5, self.ios_badge_count);
        if (self.signal_info.len > 0) try enc.encodeString(6, self.signal_info);
        return try allocator.dupe(u8, enc.bytes());
    }

    pub fn decode(data: []const u8, allocator: std.mem.Allocator) !OfflinePushInfo {
        var msg = OfflinePushInfo{};
        var dec = pb.Decoder.init(data);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.title = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                2 => msg.desc = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                3 => msg.ex = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                4 => msg.ios_push_sound = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                5 => msg.ios_badge_count = (try dec.decodeVarint()) != 0,
                6 => msg.signal_info = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                else => try dec.skipField(tag.wire_type),
            }
        }
        return msg;
    }
};

pub const SeqRange = struct {
    conversation_id: []const u8 = "",
    begin: i64 = 0,
    end: i64 = 0,
    num: i64 = 0,

    pub fn encode(self: SeqRange, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.conversation_id.len > 0) try enc.encodeString(1, self.conversation_id);
        if (self.begin != 0) try enc.encodeInt64(2, self.begin);
        if (self.end != 0) try enc.encodeInt64(3, self.end);
        if (self.num != 0) try enc.encodeInt64(4, self.num);
        return try allocator.dupe(u8, enc.bytes());
    }

    pub fn decode(data: []const u8, allocator: std.mem.Allocator) !SeqRange {
        var msg = SeqRange{};
        var dec = pb.Decoder.init(data);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.conversation_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                2 => msg.begin = @intCast(try dec.decodeVarint()),
                3 => msg.end = @intCast(try dec.decodeVarint()),
                4 => msg.num = @intCast(try dec.decodeVarint()),
                else => try dec.skipField(tag.wire_type),
            }
        }
        return msg;
    }
};

pub const PullMessageBySeqsReq = struct {
    user_id: []const u8 = "",
    seq_ranges: []const SeqRange = &.{},
    order: i32 = 0,

    pub fn encode(self: PullMessageBySeqsReq, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.user_id.len > 0) try enc.encodeString(1, self.user_id);
        for (self.seq_ranges) |sr| {
            const sub = try sr.encode(allocator);
            defer allocator.free(sub);
            try enc.encodeEmbedded(2, sub);
        }
        if (self.order != 0) try enc.encodeInt32(3, self.order);
        return try allocator.dupe(u8, enc.bytes());
    }

    pub fn decode(data: []const u8, allocator: std.mem.Allocator) !PullMessageBySeqsReq {
        var msg = PullMessageBySeqsReq{};
        var ranges = std.ArrayList(SeqRange).empty;
        defer ranges.deinit(allocator);

        var dec = pb.Decoder.init(data);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.user_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                2 => {
                    const sub = try dec.decodeBytesSlice();
                    try ranges.append(allocator, try SeqRange.decode(sub, allocator));
                },
                3 => msg.order = @intCast(try dec.decodeVarint()),
                else => try dec.skipField(tag.wire_type),
            }
        }
        msg.seq_ranges = try ranges.toOwnedSlice(allocator);
        return msg;
    }
};

pub const PullMsgs = struct {
    msgs: []const MsgData = &.{},
    is_end: bool = false,
    end_seq: i64 = 0,

    pub fn encode(self: PullMsgs, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        for (self.msgs) |m| {
            const sub = try m.encode(allocator);
            defer allocator.free(sub);
            try enc.encodeEmbedded(1, sub);
        }
        if (self.is_end) try enc.encodeBool(2, self.is_end);
        if (self.end_seq != 0) try enc.encodeInt64(3, self.end_seq);
        return try allocator.dupe(u8, enc.bytes());
    }
};

pub const PullMessageBySeqsResp = struct {
    // Simplified: map<string, PullMsgs> is complex; we use a single conversation for now.

    pub fn encode(self: PullMessageBySeqsResp, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return &[_]u8{};
    }
};

pub const GetMaxSeqReq = struct {
    user_id: []const u8 = "",

    pub fn encode(self: GetMaxSeqReq, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.user_id.len > 0) try enc.encodeString(1, self.user_id);
        return try allocator.dupe(u8, enc.bytes());
    }

    pub fn decode(data: []const u8, allocator: std.mem.Allocator) !GetMaxSeqReq {
        var msg = GetMaxSeqReq{};
        var dec = pb.Decoder.init(data);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.user_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                else => try dec.skipField(tag.wire_type),
            }
        }
        return msg;
    }
};

pub const GetMaxSeqResp = struct {
    max_seqs: i64 = 0,
    min_seqs: i64 = 0,

    pub fn encode(self: GetMaxSeqResp, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.max_seqs != 0) try enc.encodeInt64(1, self.max_seqs);
        if (self.min_seqs != 0) try enc.encodeInt64(2, self.min_seqs);
        return try allocator.dupe(u8, enc.bytes());
    }
};

pub const UserSendMsgResp = struct {
    server_msg_id: []const u8 = "",
    client_msg_id: []const u8 = "",
    send_time: i64 = 0,

    pub fn encode(self: UserSendMsgResp, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.server_msg_id.len > 0) try enc.encodeString(1, self.server_msg_id);
        if (self.client_msg_id.len > 0) try enc.encodeString(2, self.client_msg_id);
        if (self.send_time != 0) try enc.encodeInt64(3, self.send_time);
        return try allocator.dupe(u8, enc.bytes());
    }
};

pub const GetSeqMessageReq = struct {
    user_id: []const u8 = "",
    conversation_id: []const u8 = "",
    seq: i64 = 0,

    pub fn encode(self: GetSeqMessageReq, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.user_id.len > 0) try enc.encodeString(1, self.user_id);
        if (self.conversation_id.len > 0) try enc.encodeString(2, self.conversation_id);
        if (self.seq != 0) try enc.encodeInt64(3, self.seq);
        return try allocator.dupe(u8, enc.bytes());
    }

    pub fn decode(data: []const u8, allocator: std.mem.Allocator) !GetSeqMessageReq {
        var msg = GetSeqMessageReq{};
        var dec = pb.Decoder.init(data);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.user_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                2 => msg.conversation_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                3 => msg.seq = @intCast(try dec.decodeVarint()),
                else => try dec.skipField(tag.wire_type),
            }
        }
        return msg;
    }
};

pub const GetSeqMessageResp = struct {
    msg: ?MsgData = null,

    pub fn encode(self: GetSeqMessageResp, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.msg) |m| {
            const sub = try m.encode(allocator);
            defer allocator.free(sub);
            try enc.encodeEmbedded(1, sub);
        }
        return try allocator.dupe(u8, enc.bytes());
    }
};

pub const SignalReq = struct {
    room_id: []const u8 = "",
    signal_type: i32 = 0, // 1=invite, 2=accept, 3=reject, 4=hungUp, 5=cancel
    user_id: []const u8 = "",
    data: []const u8 = "",

    pub fn decode(data_bytes: []const u8, allocator: std.mem.Allocator) !SignalReq {
        var msg = SignalReq{};
        var dec = pb.Decoder.init(data_bytes);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.room_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                2 => msg.signal_type = @intCast(try dec.decodeVarint()),
                3 => msg.user_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                4 => msg.data = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                else => try dec.skipField(tag.wire_type),
            }
        }
        return msg;
    }
};

pub const SignalResp = struct {
    room_id: []const u8 = "",
    signal_type: i32 = 0,
    user_id: []const u8 = "",
    data: []const u8 = "",

    pub fn encode(self: SignalResp, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.room_id.len > 0) try enc.encodeString(1, self.room_id);
        if (self.signal_type != 0) try enc.encodeInt32(2, self.signal_type);
        if (self.user_id.len > 0) try enc.encodeString(3, self.user_id);
        if (self.data.len > 0) try enc.encodeString(4, self.data);
        return try allocator.dupe(u8, enc.bytes());
    }
};

pub const GetConvMaxReadSeqReq = struct {
    user_id: []const u8 = "",
    conversation_id: []const u8 = "",

    pub fn decode(data_bytes: []const u8, allocator: std.mem.Allocator) !GetConvMaxReadSeqReq {
        var msg = GetConvMaxReadSeqReq{};
        var dec = pb.Decoder.init(data_bytes);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.user_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                2 => msg.conversation_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                else => try dec.skipField(tag.wire_type),
            }
        }
        return msg;
    }
};

pub const GetConvMaxReadSeqResp = struct {
    max_read_seq: i64 = 0,

    pub fn encode(self: GetConvMaxReadSeqResp, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.max_read_seq != 0) try enc.encodeInt64(1, self.max_read_seq);
        return try allocator.dupe(u8, enc.bytes());
    }
};

// PushMessages wraps PullMsgs grouped by conversation (used for server push 2001)
pub const PushMessages = struct {
    // Simplified: single conversation push for now
    msgs: PullMsgs = .{},
    notification_msgs: PullMsgs = .{},

    pub fn encode(self: PushMessages, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        const msgs_sub = try self.msgs.encode(allocator);
        defer allocator.free(msgs_sub);
        try enc.encodeEmbedded(1, msgs_sub);
        const notif_sub = try self.notification_msgs.encode(allocator);
        defer allocator.free(notif_sub);
        try enc.encodeEmbedded(2, notif_sub);
        return try allocator.dupe(u8, enc.bytes());
    }
};

// ServerConfig sent immediately after WS connection upgrade (req 2100)
pub const ServerConfig = struct {
    is_encryption: bool = false,

    pub fn encode(self: ServerConfig, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.is_encryption) try enc.encodeBool(1, self.is_encryption);
        return try allocator.dupe(u8, enc.bytes());
    }
};

// SubUserOnlineStatusElem represents a single user's online status
pub const SubUserOnlineStatusElem = struct {
    user_id: []const u8 = "",
    online_platform_ids: []const i32 = &.{},

    pub fn encode(self: SubUserOnlineStatusElem, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.user_id.len > 0) try enc.encodeString(1, self.user_id);
        for (self.online_platform_ids) |pid| {
            try enc.encodeInt32(2, pid);
        }
        return try allocator.dupe(u8, enc.bytes());
    }
};

// SubUserOnlineStatusTips pushed to subscribers when tracked users change status
pub const SubUserOnlineStatusTips = struct {
    subscribers: []const SubUserOnlineStatusElem = &.{},

    pub fn encode(self: SubUserOnlineStatusTips, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        for (self.subscribers) |sub| {
            const sub_bytes = try sub.encode(allocator);
            defer allocator.free(sub_bytes);
            try enc.encodeEmbedded(1, sub_bytes);
        }
        return try allocator.dupe(u8, enc.bytes());
    }
};

// SubUserOnlineStatus request (subscribe/unsubscribe user IDs)
pub const SubUserOnlineStatus = struct {
    subscribe_user_id: []const []const u8 = &.{},
    unsubscribe_user_id: []const []const u8 = &.{},

    pub fn decode(data: []const u8, allocator: std.mem.Allocator) !SubUserOnlineStatus {
        var msg = SubUserOnlineStatus{};
        var sub_list = std.ArrayList([]const u8).empty;
        defer sub_list.deinit(allocator);
        var unsub_list = std.ArrayList([]const u8).empty;
        defer unsub_list.deinit(allocator);
        var dec = pb.Decoder.init(data);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => try sub_list.append(allocator, try allocator.dupe(u8, try dec.decodeBytesSlice())),
                2 => try unsub_list.append(allocator, try allocator.dupe(u8, try dec.decodeBytesSlice())),
                else => try dec.skipField(tag.wire_type),
            }
        }
        msg.subscribe_user_id = try sub_list.toOwnedSlice(allocator);
        msg.unsubscribe_user_id = try unsub_list.toOwnedSlice(allocator);
        return msg;
    }
};

// GetLastMessageReq (1007) - request last message per conversation
pub const GetLastMessageReq = struct {
    user_id: []const u8 = "",
    conversation_ids: []const []const u8 = &.{},

    pub fn decode(data: []const u8, allocator: std.mem.Allocator) !GetLastMessageReq {
        var msg = GetLastMessageReq{};
        var ids = std.ArrayList([]const u8).empty;
        defer ids.deinit(allocator);
        var dec = pb.Decoder.init(data);
        while (!dec.eof()) {
            const tag = dec.decodeTag() catch break;
            switch (tag.field_number) {
                1 => msg.user_id = try allocator.dupe(u8, try dec.decodeBytesSlice()),
                2 => try ids.append(allocator, try allocator.dupe(u8, try dec.decodeBytesSlice())),
                else => try dec.skipField(tag.wire_type),
            }
        }
        msg.conversation_ids = try ids.toOwnedSlice(allocator);
        return msg;
    }
};

// GetLastMessageResp (1007) - map of conversationID -> MsgData
pub const GetLastMessageResp = struct {
    // Simplified: encode single conversation preview for now
    conversation_id: []const u8 = "",
    msg: ?MsgData = null,

    pub fn encode(self: GetLastMessageResp, allocator: std.mem.Allocator) ![]u8 {
        var enc = pb.Encoder.init(allocator);
        defer enc.deinit();
        if (self.conversation_id.len > 0) try enc.encodeString(1, self.conversation_id);
        if (self.msg) |m| {
            const sub = try m.encode(allocator);
            defer allocator.free(sub);
            try enc.encodeEmbedded(2, sub);
        }
        return try allocator.dupe(u8, enc.bytes());
    }
};
