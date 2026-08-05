const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const db_mod = @import("db_postgres.zig");

pub const model = @import("conversation/model.zig");
pub const persistence = @import("conversation/persistence.zig");
pub const service = @import("conversation/service.zig");

// Backward-compatible re-exports
pub const ConversationType = model.ConversationType;
pub const Conversation = model.Conversation;
pub const ConversationCreateInput = model.ConversationCreateInput;
pub const ConversationUpdateInput = model.ConversationUpdateInput;
pub const VersionKey = model.VersionKey;
pub const ConversationStorage = persistence.ConversationPersistence;

pub const info = zigmodu.api.Module{
    .name = "conversation",
    .description = "Conversation management - CRUD, participants, seq tracking",
    .dependencies = &.{ "user", "db_postgres" },
    .runtime = .{ .max_concurrent = 100 },
};

var g_service: ?service.ConversationService = null;

pub fn init() !void {
    const db = db_mod.getClient();
    g_service = service.ConversationService.init(core.serviceAllocator(), db);
    std.log.info("ConversationModule initialized with PostgreSQL", .{});
}

pub fn deinit() void {
    g_service = null;
    std.log.info("ConversationModule deinitialized", .{});
}

fn svc() *service.ConversationService {
    return &g_service.?;
}

// Public API functions (backward compatible)
pub fn createConversation(input: ConversationCreateInput) !Conversation {
    return svc().create(input);
}

pub fn getConversation(owner_user_id: []const u8, conversation_id: []const u8) !?Conversation {
    return svc().get(owner_user_id, conversation_id);
}

pub fn getConversationsByOwner(owner_user_id: []const u8) ![]Conversation {
    return svc().getByOwner(core.getAllocator(), owner_user_id);
}

pub fn getConversationsByOwnerSince(owner_user_id: []const u8, since_timestamp: i64) ![]Conversation {
    return svc().getByOwnerSince(core.getAllocator(), owner_user_id, since_timestamp);
}

pub fn updateConversation(owner_user_id: []const u8, conversation_id: []const u8, input: ConversationUpdateInput) !?Conversation {
    return svc().update(owner_user_id, conversation_id, input);
}

pub fn deleteConversation(owner_user_id: []const u8, conversation_id: []const u8) bool {
    return svc().delete(owner_user_id, conversation_id);
}

pub fn updateSeq(owner_user_id: []const u8, conversation_id: []const u8, max_seq: i64) !void {
    try svc().updateSeq(owner_user_id, conversation_id, max_seq);
}

pub fn conversationCount() usize {
    return svc().count();
}

pub fn getEncryptionKeys(conversation_id: []const u8, allocator: std.mem.Allocator) ![]VersionKey {
    return svc().getEncryptionKeys(conversation_id, allocator);
}

pub fn genEncryptionKey(conversation_id: []const u8) !void {
    try svc().genEncryptionKey(conversation_id);
}

// Legacy storage accessor (for modules that directly use getStorage())
pub fn getStorage() *ConversationStorage {
    return &g_service.?.pers;
}
