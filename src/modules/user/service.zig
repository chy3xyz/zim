const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const event_bus_mod = @import("../../modules/event_bus.zig");
const model = @import("model.zig");
const persistence = @import("persistence.zig");

pub const UserService = struct {
    allocator: std.mem.Allocator,
    pers: persistence.UserPersistence,

    pub fn init(allocator: std.mem.Allocator, db: anytype) UserService {
        return .{ .allocator = allocator, .pers = persistence.UserPersistence.init(allocator, db) };
    }

    // ── CRUD ──────────────────────────────────────────────────────

    pub fn create(self: *UserService, input: model.UserCreateInput) !model.User {
        var password_hash: []const u8 = "";
        if (input.password) |pwd| {
            // zmodu.security.PasswordEncoder — PBKDF2-HMAC-SHA256, 100k iterations
            var encoder = zmodu.security.PasswordEncoder.init(self.allocator, core.getIo());
            password_hash = try encoder.encode(pwd);
        }
        const user = try self.pers.create(input, password_hash);

        const eb = event_bus_mod.getEventBus();
        const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"user_id\":\"{s}\",\"nickname\":\"{s}\"}}", .{ user.user_id, user.nickname });
        defer core.getAllocator().free(payload);
        eb.emit(.user_created, "user", payload);

        return user;
    }

    pub fn get(self: *UserService, user_id: []const u8) !?model.User {
        return self.pers.get(user_id);
    }

    pub fn getByTelephone(self: *UserService, telephone: []const u8) !?model.User {
        return self.pers.getByTelephone(telephone);
    }

    pub fn update(self: *UserService, user_id: []const u8, input: model.UserUpdateInput) !?model.User {
        const result = try self.pers.update(user_id, input);
        if (result != null) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"user_id\":\"{s}\"}}", .{user_id});
            defer core.getAllocator().free(payload);
            eb.emit(.user_updated, "user", payload);
        }
        return result;
    }

    pub fn delete(self: *UserService, user_id: []const u8) bool {
        const result = self.pers.delete(user_id);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            const payload = std.fmt.allocPrint(core.getAllocator(), "{{\"user_id\":\"{s}\"}}", .{user_id}) catch return result;
            defer core.getAllocator().free(payload);
            eb.emit(.user_deleted, "user", payload);
        }
        return result;
    }

    pub fn search(self: *UserService, query: []const u8, limit: u32) ![]model.User {
        return self.pers.search(query, limit);
    }

    pub fn count(self: *UserService) usize {
        return self.pers.count();
    }

    pub fn countSince(self: *UserService, start_time: i64, end_time: i64) usize {
        return self.pers.countSince(start_time, end_time);
    }

    pub fn countBefore(self: *UserService, start_time: i64) usize {
        return self.pers.countBefore(start_time);
    }

    pub fn countByDay(self: *UserService, allocator: std.mem.Allocator, start_time: i64, end_time: i64) ![]model.DayCount {
        return self.pers.countByDay(allocator, start_time, end_time);
    }

    pub fn activeCount(self: *UserService) usize {
        return self.pers.activeCount();
    }

    pub fn getAllUserIDs(self: *UserService, allocator: std.mem.Allocator) ![]const []const u8 {
        return self.pers.getAllUserIDs(allocator);
    }

    // ── Online status ─────────────────────────────────────────────

    pub fn setOnline(self: *UserService, user_id: []const u8, online: bool) void {
        const status: i32 = if (online) 1 else 0;
        self.pers.setOnline(user_id, status);
        const eb = event_bus_mod.getEventBus();
        const event_type: event_bus_mod.EventType = if (online) .user_online else .user_offline;
        const payload = std.fmt.allocPrint(core.getAllocator(), "{{\"user_id\":\"{s}\",\"online\":{s}}}", .{ user_id, if (online) "true" else "false" }) catch return;
        defer core.getAllocator().free(payload);
        eb.emit(event_type, "user", payload);
    }

    pub fn isOnline(self: *UserService, user_id: []const u8) bool {
        return self.pers.isOnline(user_id);
    }

    pub fn getOnlineUsers(self: *UserService) ![]const []const u8 {
        return self.pers.getOnlineUsers();
    }

    // ── User commands ─────────────────────────────────────────────

    pub fn addCommand(self: *UserService, user_id: []const u8, command_id: []const u8, command_value: []const u8) !void {
        return self.pers.addCommand(user_id, command_id, command_value);
    }

    pub fn deleteCommand(self: *UserService, user_id: []const u8, command_id: []const u8) !void {
        return self.pers.deleteCommand(user_id, command_id);
    }

    pub fn getCommand(self: *UserService, user_id: []const u8, command_id: []const u8, allocator: std.mem.Allocator) !?model.UserCommand {
        return self.pers.getCommand(user_id, command_id, allocator);
    }

    pub fn getAllCommands(self: *UserService, user_id: []const u8, allocator: std.mem.Allocator) ![]model.UserCommand {
        return self.pers.getAllCommands(user_id, allocator);
    }

    // ── Auth helpers ──────────────────────────────────────────────

    pub fn updatePassword(self: *UserService, user_id: []const u8, password_hash: []const u8) bool {
        return self.pers.updatePassword(user_id, password_hash) catch false;
    }

    pub fn verifyPassword(self: *UserService, user_id: []const u8, password: []const u8) bool {
        const user = self.get(user_id) catch return false;
        if (user == null) return false;
        if (user.?.password_hash.len == 0) return false;

        var encoder = zmodu.security.PasswordEncoder.init(core.getAllocator(), core.getIo());
        // MalformedStoredHash (corrupt row) reads as "no match" — auth fails
        // closed rather than erroring the login path.
        return encoder.matches(password, user.?.password_hash) catch false;
    }
};
