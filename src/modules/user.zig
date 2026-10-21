const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const db_mod = @import("db_postgres.zig");

pub const model = @import("user/model.zig");
pub const persistence = @import("user/persistence.zig");
pub const service = @import("user/service.zig");

// Backward-compatible re-exports
pub const User = model.User;
pub const UserCreateInput = model.UserCreateInput;
pub const UserUpdateInput = model.UserUpdateInput;
pub const OnlineStatus = model.OnlineStatus;
pub const UserCommand = model.UserCommand;
pub const UserStorage = persistence.UserPersistence;

pub const info = zmodu.api.Module{
    .name = "user",
    .description = "User management - registration, profile, online status",
    .dependencies = &.{ "config", "db_postgres" },
    .runtime = .{ .max_concurrent = 100 },
};

var g_service: ?service.UserService = null;

pub fn init() !void {
    const db = db_mod.getClient();
    g_service = service.UserService.init(core.serviceAllocator(), db);
    std.log.info("UserModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    g_service = null;
    std.log.info("UserModule deinitialized", .{});
}

fn svc() *service.UserService {
    return &g_service.?;
}

// Public API functions (backward compatible)
pub fn createUser(input: UserCreateInput) !User {
    return svc().create(input);
}

pub fn getUser(user_id: []const u8) !?User {
    return svc().get(user_id);
}

pub fn getUserByTelephone(telephone: []const u8) !?User {
    return svc().getByTelephone(telephone);
}

pub fn updateUser(user_id: []const u8, input: UserUpdateInput) !?User {
    return svc().update(user_id, input);
}

pub fn deleteUser(user_id: []const u8) bool {
    return svc().delete(user_id);
}

pub fn setOnline(user_id: []const u8, online: bool) void {
    return svc().setOnline(user_id, online);
}

pub fn isOnline(user_id: []const u8) bool {
    return svc().isOnline(user_id);
}

pub fn searchUsers(query: []const u8, limit: u32) ![]User {
    return svc().search(query, limit);
}

pub fn userCount() usize {
    return svc().count();
}

pub fn userCountSince(start_time: i64, end_time: i64) usize {
    return svc().countSince(start_time, end_time);
}

pub fn userCountBefore(start_time: i64) usize {
    return svc().countBefore(start_time);
}

pub fn userCountByDay(allocator: std.mem.Allocator, start_time: i64, end_time: i64) ![]model.DayCount {
    return svc().countByDay(allocator, start_time, end_time);
}

pub fn activeUserCount() usize {
    return svc().activeCount();
}

pub fn getAllUserIDs(allocator: std.mem.Allocator) ![]const []const u8 {
    return svc().getAllUserIDs(allocator);
}

pub fn addUserCommand(user_id: []const u8, command_id: []const u8, command_value: []const u8) !void {
    return svc().addCommand(user_id, command_id, command_value);
}

pub fn deleteUserCommand(user_id: []const u8, command_id: []const u8) !void {
    return svc().deleteCommand(user_id, command_id);
}

pub fn getUserCommand(user_id: []const u8, command_id: []const u8, allocator: std.mem.Allocator) !?UserCommand {
    return svc().getCommand(user_id, command_id, allocator);
}

pub fn getAllUserCommands(user_id: []const u8, allocator: std.mem.Allocator) ![]UserCommand {
    return svc().getAllCommands(user_id, allocator);
}

pub fn updatePassword(user_id: []const u8, password_hash: []const u8) bool {
    return svc().updatePassword(user_id, password_hash);
}

pub fn verifyPassword(user_id: []const u8, password: []const u8) bool {
    return svc().verifyPassword(user_id, password);
}

// Legacy storage accessor (for modules that directly use getStorage())
pub fn getStorage() *UserStorage {
    return &g_service.?.pers;
}
