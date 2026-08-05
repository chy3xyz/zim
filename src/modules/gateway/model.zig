// Response helper structs
pub const MemberInfo = struct {
    userID: []const u8,
    nickname: []const u8,
    faceURL: []const u8,
    departmentID: []const u8,
    departmentName: []const u8,
};

pub const UserElement = struct {
    user: struct {
        userId: []const u8,
        nickname: []const u8,
        faceUrl: []const u8,
        gender: i32,
    },
    members: []const MemberInfo,
};

pub const MemberUser = struct {
    member: MemberInfo,
    user: struct {
        userId: []const u8,
        nickname: []const u8,
        faceUrl: []const u8,
        gender: i32,
    },
};

pub const SearchResultItem = struct {
    userId: []const u8,
    nickname: []const u8,
    faceUrl: []const u8,
    gender: i32,
    members: []const MemberInfo,
};

// RTC structs
pub const RtcParticipant = struct {
    user_id: []const u8,
    nickname: []const u8,
    joined_at: i64,
    is_muted: bool,
    is_video_on: bool,
};

pub const RtcMeeting = struct {
    room_id: []const u8,
    host_user_id: []const u8,
    meeting_name: []const u8,
    status: i32,
    create_time: i64,
    layout: i32,
    record_id: ?[]const u8,
};
