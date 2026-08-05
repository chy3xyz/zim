pub const HandleResult = enum(i16) {
    pending = 0,
    accepted = 1,
    rejected = -1,
};

pub const Friend = struct {
    owner_user_id: []const u8,
    friend_user_id: []const u8,
    remark: []const u8,
    create_time: i64,
    add_source: i16,
    operator_user_id: []const u8,
    ex: []const u8,
    is_pinned: bool,
};

/// FriendInfo matches Flutter SDK's FriendInfo model (includes user profile)
pub const FriendInfo = struct {
    owner_user_id: []const u8,
    friend_user_id: []const u8,
    nickname: []const u8,
    face_url: []const u8,
    remark: []const u8,
    create_time: i64,
    add_source: i16,
    operator_user_id: []const u8,
    ex: []const u8,
    updated_at: i64,
    is_pinned: bool,
};

/// FriendRequestInfo matches Flutter SDK's FriendApplicationInfo model
pub const FriendRequestInfo = struct {
    from_user_id: []const u8,
    from_nickname: []const u8,
    from_face_url: []const u8,
    to_user_id: []const u8,
    to_nickname: []const u8,
    to_face_url: []const u8,
    handle_result: HandleResult,
    req_msg: []const u8,
    create_time: i64,
    handler_user_id: []const u8,
    handle_msg: []const u8,
    handle_time: i64,
    ex: []const u8,
};

pub const FriendRequest = struct {
    from_user_id: []const u8,
    to_user_id: []const u8,
    handle_result: HandleResult,
    req_msg: []const u8,
    create_time: i64,
    handler_user_id: []const u8,
    handle_msg: []const u8,
    handle_time: i64,
    ex: []const u8,
};

pub const Black = struct {
    owner_user_id: []const u8,
    block_user_id: []const u8,
    create_time: i64,
    add_source: i16,
    operator_user_id: []const u8,
    ex: []const u8,
};

/// BlackInfo matches Flutter SDK's BlacklistInfo model
pub const BlackInfo = struct {
    owner_user_id: []const u8,
    block_user_id: []const u8,
    user_id: []const u8,
    nickname: []const u8,
    face_url: []const u8,
    gender: i16,
    create_time: i64,
    add_source: i16,
    operator_user_id: []const u8,
    ex: []const u8,
    updated_at: i64,
};
