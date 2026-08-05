const std = @import("std");

pub const DayCount = struct {
    day: []const u8,
    count: i64,
};
const core = @import("core");

pub const User = struct {
    user_id: []const u8,
    nickname: []const u8,
    face_url: []const u8,
    gender: i16,
    level: i16,
    birth: ?i64,
    area_code: []const u8,
    telephone: []const u8,
    ex: []const u8,
    app_manager_level: i16,
    global_recv_msg_opt: i16,
    register_type: i16,
    password_hash: []const u8,
    create_time: i64,
};

pub const UserCreateInput = struct {
    user_id: ?[]const u8 = null,
    nickname: []const u8,
    face_url: ?[]const u8 = null,
    gender: i16 = 0,
    area_code: []const u8 = "",
    telephone: []const u8 = "",
    ex: []const u8 = "",
    app_manager_level: i16 = 0,
    global_recv_msg_opt: i16 = 0,
    password: ?[]const u8 = null,
};

pub const UserUpdateInput = struct {
    nickname: ?[]const u8 = null,
    face_url: ?[]const u8 = null,
    gender: ?i16 = null,
    birth: ?i64 = null,
    area_code: ?[]const u8 = null,
    telephone: ?[]const u8 = null,
    ex: ?[]const u8 = null,
    global_recv_msg_opt: ?i16 = null,
};

pub const OnlineStatus = struct {
    user_id: []const u8,
    status: i32,
    platform_ids: []const i32,
};

pub const UserCommand = struct {
    command_id: []const u8,
    command_value: []const u8,
    create_time: i64,
};

pub fn generateUserID(allocator: std.mem.Allocator) ![]const u8 {
    var bytes: [16]u8 = undefined;
    core.secureRandomBytes(&bytes);
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    return try std.fmt.allocPrint(allocator, "{x:0>8}-{x:0>4}-4{x:0>3}-{x:0>4}-{x:0>12}", .{
        std.mem.readInt(u32, bytes[0..4], .big),
        std.mem.readInt(u16, bytes[4..6], .big),
        std.mem.readInt(u16, bytes[6..8], .big),
        std.mem.readInt(u16, bytes[8..10], .big),
        std.mem.readInt(u48, bytes[10..16], .big),
    });
}
