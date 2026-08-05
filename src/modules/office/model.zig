pub const WorkMoment = struct {
    id: []const u8,
    user_id: []const u8,
    face_url: []const u8,
    nickname: []const u8,
    content: []const u8,
    metas: []const u8,
    permission: []const u8,
    at_user_ids: []const u8,
    permission_user_ids: []const u8,
    like_users: []const u8,
    comments: []const u8,
    create_time: i64,
};

pub const WorkMomentCreateInput = struct {
    user_id: []const u8,
    content: []const u8,
    metas: ?[]const u8,
    permission: ?[]const u8,
    at_user_ids: ?[]const u8,
    permission_user_ids: ?[]const u8,
};

pub const Comment = struct {
    comment_id: []const u8,
    user_id: []const u8,
    nickname: []const u8,
    face_url: []const u8,
    reply_user_id: []const u8,
    reply_nickname: []const u8,
    reply_face_url: []const u8,
    content: []const u8,
    create_time: i64,
};

pub const LikeUser = struct {
    user_id: []const u8,
    nickname: []const u8,
    face_url: []const u8,
    create_time: i64,
};

pub const ReadType = enum { count, list };

pub const Tag = struct {
    id: []const u8,
    user_id: []const u8,
    tag_name: []const u8,
    user_id_list: []const []const u8,
    create_time: i64,
};

pub const TagCreateInput = struct {
    user_id: []const u8,
    tag_name: []const u8,
    user_ids: []const []const u8,
};

pub const TagUpdateInput = struct {
    tag_id: []const u8,
    tag_name: ?[]const u8 = null,
    add_user_ids: []const []const u8 = &.{},
    del_user_ids: []const []const u8 = &.{},
};

pub const Collect = struct {
    id: []const u8,
    user_id: []const u8,
    collect_type: []const u8,
    content: []const u8,
    uuid: []const u8,
    create_time: i64,
};

pub const ClientConfig = struct {
    key: []const u8,
    value: []const u8,
    update_time: i64,
};
