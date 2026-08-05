const std = @import("std");
const zigmodu = @import("zigmodu");
const core = @import("core");
const user_mod = @import("../../modules/user.zig");
const model = @import("model.zig");
const persistence = @import("persistence.zig");

fn md5Hex(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var md5 = std.crypto.hash.Md5.init(.{});
    md5.update(input);
    var digest: [16]u8 = undefined;
    md5.final(&digest);
    return try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
}

// ── Login brute-force limiter (per-user, in-memory) ─────────────────
const LoginAttempt = struct {
    count: u32,
    window_start: i64,
};
const MAX_LOGIN_ATTEMPTS = 5;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;

var g_login_attempts: std.StringHashMap(LoginAttempt) = undefined;
var g_login_limiter_init = false;
var g_login_mutex: std.atomic.Mutex = .unlocked;

pub fn initLoginLimiter(allocator: std.mem.Allocator) void {
    if (g_login_limiter_init) return;
    g_login_attempts = std.StringHashMap(LoginAttempt).init(allocator);
    g_login_limiter_init = true;
}

pub fn deinitLoginLimiter() void {
    if (!g_login_limiter_init) return;
    while (!g_login_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer g_login_mutex.unlock();
    var it = g_login_attempts.iterator();
    while (it.next()) |entry| core.getGlobalAllocator().free(entry.key_ptr.*);
    g_login_attempts.deinit();
    g_login_limiter_init = false;
}

pub fn loginAllowed(user_id: []const u8) bool {
    while (!g_login_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer g_login_mutex.unlock();
    const now = core.unixNowMillis();
    if (g_login_attempts.get(user_id)) |entry| {
        if (now - entry.window_start > LOGIN_WINDOW_MS) {
            g_login_attempts.getPtr(user_id).?.window_start = now;
            g_login_attempts.getPtr(user_id).?.count = 0;
            return true;
        }
        return entry.count < MAX_LOGIN_ATTEMPTS;
    }
    return true;
}

pub fn recordLoginFailure(user_id: []const u8) void {
    while (!g_login_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer g_login_mutex.unlock();
    const now = core.unixNowMillis();
    const gop = g_login_attempts.getOrPut(user_id) catch return;
    if (!gop.found_existing) {
        // Take ownership of the key (map outlives the request arena)
        gop.key_ptr.* = core.getGlobalAllocator().dupe(u8, user_id) catch return;
        gop.value_ptr.* = .{ .count = 1, .window_start = now };
        return;
    }
    if (now - gop.value_ptr.window_start > LOGIN_WINDOW_MS) {
        gop.value_ptr.* = .{ .count = 1, .window_start = now };
    } else {
        gop.value_ptr.count += 1;
    }
}

pub const AuthService = struct {
    allocator: std.mem.Allocator,
    secret: []const u8,
    expiry_hours: u32,
    pers: persistence.AuthPersistence,

    pub fn init(allocator: std.mem.Allocator, secret: []const u8, expiry_hours: u32, db: anytype) AuthService {
        return .{
            .allocator = allocator,
            .secret = secret,
            .expiry_hours = expiry_hours,
            .pers = persistence.AuthPersistence.init(allocator, db),
        };
    }

    pub fn register(self: *AuthService, input: model.RegisterInput) !model.TokenInfo {
        const user = try user_mod.createUser(user_mod.UserCreateInput{
            .user_id = input.user_id,
            .nickname = input.nickname,
            .face_url = input.face_url,
            .gender = input.gender,
            .area_code = input.area_code,
            .telephone = input.telephone,
        });

        const token = try self.generateToken(user.user_id, 1);
        self.pers.storeToken(user.user_id, token.token, 1, self.expiry_hours) catch {};

        return token;
    }

    pub fn login(self: *AuthService, input: model.LoginInput) !model.TokenInfo {
        const user = user_mod.getUser(input.user_id) catch null;
        if (user == null) return error.UserNotFound;

        const token = try self.generateToken(input.user_id, input.platform_id);
        self.pers.storeToken(input.user_id, token.token, input.platform_id, self.expiry_hours) catch {};
        user_mod.setOnline(input.user_id, true);

        return token;
    }

    pub fn parseToken(self: *AuthService, token: []const u8) !model.TokenInfo {
        const info = try self.pers.parseToken(token);
        return info;
    }

    pub fn forceLogout(self: *AuthService, user_id: []const u8) void {
        self.pers.deleteByUser(user_id);
        user_mod.setOnline(user_id, false);
    }

    pub fn registerWithPassword(self: *AuthService, nickname: []const u8, password: []const u8, area_code: ?[]const u8, phone_number: ?[]const u8, email: ?[]const u8, account: ?[]const u8) !model.TokenInfo {
        var user_id: []const u8 = "";
        if (account) |a| {
            user_id = a;
        } else if (phone_number) |p| {
            user_id = p;
        } else if (email) |e| {
            user_id = e;
        } else {
            // Generate random user_id
            var bytes: [16]u8 = undefined;
            core.secureRandomBytes(&bytes);
            user_id = try std.fmt.allocPrint(self.allocator, "user_{x}", .{std.mem.readInt(u128, &bytes, .big)});
        }

        // Pass the raw password; UserService.create hashes it once with
        // zigmodu.security.PasswordEncoder (PBKDF2-HMAC-SHA256). Hashing here
        // too would double-hash and break login verification.
        const user = try user_mod.createUser(user_mod.UserCreateInput{
            .user_id = user_id,
            .nickname = nickname,
            .password = password,
            .area_code = area_code orelse "",
            .telephone = phone_number orelse "",
        });

        const token = try self.generateToken(user.user_id, 1);
        self.pers.storeToken(user.user_id, token.token, 1, self.expiry_hours) catch {};
        return token;
    }

    pub fn loginWithPassword(self: *AuthService, user_id: []const u8, password: []const u8, platform_id: i32) !model.TokenInfo {
        if (!loginAllowed(user_id)) return error.TooManyAttempts;
        const user = user_mod.getUser(user_id) catch null;
        if (user == null) return error.UserNotFound;

        const input_hash = try md5Hex(self.allocator, password);
        defer self.allocator.free(input_hash);

        // Support both MD5 hashes (Flutter) and PBKDF2 hashes (web/admin)
        const hash_matches = if (user.?.password_hash.len == 32)
            std.mem.eql(u8, input_hash, user.?.password_hash)
        else
            user_mod.verifyPassword(user_id, password);

        if (!hash_matches) {
            recordLoginFailure(user_id);
            return error.InvalidPassword;
        }

        const token = try self.generateToken(user_id, platform_id);
        self.pers.storeToken(user_id, token.token, platform_id, self.expiry_hours) catch {};
        user_mod.setOnline(user_id, true);
        return token;
    }

    pub fn changePassword(self: *AuthService, user_id: []const u8, current_password: []const u8, new_password: []const u8) !bool {
        const user = user_mod.getUser(user_id) catch null;
        if (user == null) return error.UserNotFound;

        const input_hash = try md5Hex(self.allocator, current_password);
        defer self.allocator.free(input_hash);

        const hash_matches = if (user.?.password_hash.len == 32)
            std.mem.eql(u8, input_hash, user.?.password_hash)
        else
            user_mod.verifyPassword(user_id, current_password);

        if (!hash_matches) return error.InvalidPassword;

        const new_hash = try md5Hex(self.allocator, new_password);
        defer self.allocator.free(new_hash);

        return user_mod.updatePassword(user_id, new_hash);
    }

    pub fn getAdminToken(self: *AuthService, secret: []const u8, user_id: []const u8) !model.TokenInfo {
        if (!std.mem.eql(u8, secret, self.secret)) return error.InvalidSecret;
        return self.generateToken(user_id, 1);
    }

    pub fn sendVerificationCode(self: *AuthService, phone_number: ?[]const u8, email: ?[]const u8, area_code: ?[]const u8) ![]const u8 {
        const code = try self.pers.createVerificationCode(phone_number, email, area_code);
        return code;
    }

    pub fn verifyCode(self: *AuthService, phone_number: ?[]const u8, email: ?[]const u8, code: []const u8) bool {
        return self.pers.checkVerificationCode(phone_number, email, code);
    }

    pub fn resetPassword(self: *AuthService, user_id: []const u8, new_password: []const u8) !bool {
        var encoder = zigmodu.security.PasswordEncoder.init(self.allocator);
        const new_hash = try encoder.encode(new_password);
        defer self.allocator.free(new_hash);
        return user_mod.updatePassword(user_id, new_hash);
    }

    pub fn generateToken(self: *AuthService, user_id: []const u8, platform_id: i32) !model.TokenInfo {
        const now = core.unixNowSeconds();
        const exp = now + (@as(i64, self.expiry_hours) * 3600);

        var random_bytes: [32]u8 = undefined;
        // OS CSPRNG instead of a timestamp-seeded PRNG
        core.secureRandomBytes(&random_bytes);

        const token_hex = try std.fmt.allocPrint(self.allocator, "{x}", .{std.mem.readInt(u256, &random_bytes, .big)});
        const token = try std.fmt.allocPrint(self.allocator, "zim_{s}_{s}", .{ user_id, token_hex });

        return model.TokenInfo{
            .token = token,
            .user_id = try self.allocator.dupe(u8, user_id),
            .expire_time = exp,
            .platform_id = platform_id,
        };
    }
};
