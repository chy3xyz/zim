pub const DayCount = struct {
    day: []const u8,
    count: i64,
};

pub const GroupStatus = enum(i16) {
    ok = 0,
    banned = 1,
    dismissed = 2,
    muted = 3,
};

pub const GroupType = enum(i16) {
    working = 0,
    ordinary = 1,
    super = 2,
};

pub const MemberRole = enum(i16) {
    member = 100,
    admin = 60,
    owner = 20,
};

pub const Group = struct {
    group_id: []const u8,
    group_name: []const u8,
    notification: []const u8,
    introduction: []const u8,
    face_url: []const u8,
    ex: []const u8,
    status: GroupStatus,
    creator_user_id: []const u8,
    group_type: GroupType,
    need_verification: i16,
    look_member_info: i16,
    apply_member_friend: i16,
    notification_update_time: i64,
    notification_user_id: []const u8,
    display_is_read: bool,
    member_count: u32,
    create_time: i64,
    updated_at: i64,
};

pub const GroupMember = struct {
    group_id: []const u8,
    user_id: []const u8,
    nickname: []const u8,
    face_url: []const u8,
    app_manager_level: i16,
    role_level: i16,
    join_time: i64,
    join_source: i16,
    inviter_user_id: []const u8,
    operator_user_id: []const u8,
    mute_end_time: i64,
    ex: []const u8,
    updated_at: i64,
};

pub const GroupRequest = struct {
    user_id: []const u8,
    group_id: []const u8,
    handle_result: i16,
    req_msg: []const u8,
    handled_msg: []const u8,
    req_time: i64,
    handle_user_id: []const u8,
    handled_time: i64,
    join_source: i16,
    inviter_user_id: []const u8,
    ex: []const u8,
};

pub const GroupCreateInput = struct {
    group_id: ?[]const u8 = null,
    group_name: []const u8,
    notification: []const u8 = "",
    introduction: []const u8 = "",
    face_url: []const u8 = "",
    ex: []const u8 = "",
    group_type: GroupType = .ordinary,
    need_verification: i16 = 0,
    creator_user_id: []const u8,
    member_user_ids: []const []const u8 = &.{},
};

pub const GroupUpdateInput = struct {
    group_name: ?[]const u8 = null,
    notification: ?[]const u8 = null,
    introduction: ?[]const u8 = null,
    face_url: ?[]const u8 = null,
    ex: ?[]const u8 = null,
    need_verification: ?i16 = null,
    look_member_info: ?i16 = null,
    apply_member_friend: ?i16 = null,
};
