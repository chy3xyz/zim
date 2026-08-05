const std = @import("std");

pub const DayCount = struct {
    day: []const u8,
    count: i64,
};

/// Top active entity (user or group) by message count.
pub const TopEntity = struct {
    id: []const u8,
    name: []const u8,
    face_url: []const u8,
    count: i64,
};
const core = @import("core");

pub const SessionType = enum(i16) {
    single = 1,
    group = 2,
    notification = 3,
};

pub const ContentType = enum(i16) {
    text = 101,
    image = 102,
    audio = 103,
    video = 104,
    file = 105,
    at_text = 106,
    merge = 107,
    card = 108,
    location = 109,
    custom = 110,
    recall = 111,
    typing = 113,
    quote = 114,
    custom_face = 115,
    group_announcement = 116,
    group_call = 117,
    system_notification = 1000,
    read_receipt = 2200, // Go constant.HasReadReceipt
};

pub const MessageOptions = struct {
    is_history: bool = true,
    is_persistent: bool = true,
    is_sender_sync: bool = true,
    is_offline_push: bool = true,
    is_unread_count: bool = true,
    is_not_notification: bool = false,
};

pub const Message = struct {
    msg_id: []const u8,
    conversation_id: []const u8,
    sender_id: []const u8,
    receiver_id: []const u8,
    group_id: []const u8,
    client_msg_id: []const u8,
    server_msg_id: []const u8,
    sender_platform_id: i16,
    sender_nickname: []const u8,
    sender_face_url: []const u8,
    session_type: SessionType,
    msg_from: i16,
    content_type: ContentType,
    content: []const u8,
    seq: i64,
    send_time: i64,
    create_time: i64,
    status: i16,
    is_read: bool,
    options: []const u8,
    offline_push: []const u8,
    at_user_id_list: []const u8,
    attached_info: []const u8,
    ex: []const u8,
    key_version: i16,
    is_revoke: bool,
    revoke_content: []const u8,
    is_edit: bool,
    edit_time: i64,
};

pub const GroupMessageReadResult = struct {
    read_num: i64,
    unread_num: i64,
};

pub const MessageSendInput = struct {
    send_id: []const u8,
    recv_id: []const u8 = "",
    group_id: []const u8 = "",
    sender_platform_id: i16 = 0,
    sender_nickname: []const u8 = "",
    sender_face_url: []const u8 = "",
    session_type: SessionType,
    msg_from: i16 = 100,
    content_type: ContentType,
    content: []const u8,
    options: MessageOptions = .{},
    offline_push: ?[]const u8 = null,
    at_user_id_list: ?[]const u8 = null,
    ex: ?[]const u8 = null,
};

/// Generate conversation ID aligned with OpenIM Go server
/// Single: "si_{sorted(send_id, recv_id)}"
/// Group:  "sg_{group_id}"
/// Notification single: "n_{sorted(send_id, recv_id)}"
/// Notification group: "n_{group_id}"
pub fn getConversationID(send_id: []const u8, recv_id: []const u8, group_id: []const u8, session_type: SessionType, is_notification: bool) ![]const u8 {
    const allocator = core.getAllocator();
    switch (session_type) {
        .single, .notification => {
            var ids = [_][]const u8{ send_id, recv_id };
            if (std.mem.order(u8, send_id, recv_id) == .gt) {
                ids[0] = recv_id;
                ids[1] = send_id;
            }
            if (is_notification) {
                return try std.fmt.allocPrint(allocator, "n_{s}_{s}", .{ ids[0], ids[1] });
            } else {
                return try std.fmt.allocPrint(allocator, "si_{s}_{s}", .{ ids[0], ids[1] });
            }
        },
        .group => {
            if (is_notification) {
                return try std.fmt.allocPrint(allocator, "n_{s}", .{group_id});
            } else {
                return try std.fmt.allocPrint(allocator, "sg_{s}", .{group_id});
            }
        },
    }
}
