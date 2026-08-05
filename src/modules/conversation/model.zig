pub const ConversationType = enum(i16) {
    single = 1,
    group = 2,
    notification = 3,
};

pub const Conversation = struct {
    id: []const u8,
    owner_user_id: []const u8,
    conversation_id: []const u8,
    conversation_type: ConversationType,
    user_id: []const u8,
    group_id: []const u8,
    recv_msg_opt: i16,
    is_pinned: bool,
    is_private_chat: bool,
    burn_duration: i32,
    group_at_type: i16,
    attached_info: []const u8,
    ex: []const u8,
    max_seq: i64,
    min_seq: i64,
    has_read_seq: i64,
    latest_msg: []const u8,
    latest_msg_send_time: i64,
    latest_msg_send_id: []const u8,
    latest_msg_content_type: i16,
    create_time: i64,
    update_time: i64,
    is_msg_destruct: bool,
    msg_destruct_time: i64,
};

pub const ConversationCreateInput = struct {
    owner_user_id: []const u8,
    conversation_id: []const u8,
    conversation_type: ConversationType,
    user_id: []const u8 = "",
    group_id: []const u8 = "",
    recv_msg_opt: i16 = 0,
    is_private_chat: bool = false,
    burn_duration: i32 = 30,
    ex: []const u8 = "",
};

pub const ConversationUpdateInput = struct {
    recv_msg_opt: ?i16 = null,
    is_pinned: ?bool = null,
    group_at_type: ?i16 = null,
    attached_info: ?[]const u8 = null,
    ex: ?[]const u8 = null,
    is_msg_destruct: ?bool = null,
    msg_destruct_time: ?i64 = null,
    latest_msg: ?[]const u8 = null,
    latest_msg_send_time: ?i64 = null,
    latest_msg_send_id: ?[]const u8 = null,
    latest_msg_content_type: ?i16 = null,
    has_read_seq: ?i64 = null,
    max_seq: ?i64 = null,
};

pub const VersionKey = struct {
    version: i32,
    key: []const u8,
};
