pub const TokenInfo = struct {
    token: []const u8,
    user_id: []const u8,
    expire_time: i64,
    platform_id: i32,
};

pub const LoginInput = struct {
    user_id: []const u8,
    platform_id: i32,
};

pub const RegisterInput = struct {
    user_id: ?[]const u8 = null,
    nickname: []const u8,
    face_url: ?[]const u8 = null,
    gender: i16 = 0,
    area_code: []const u8 = "",
    telephone: []const u8 = "",
};
