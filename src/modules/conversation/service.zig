const std = @import("std");
const core = @import("core");
const event_bus_mod = @import("../../modules/event_bus.zig");
const model = @import("model.zig");
const persistence = @import("persistence.zig");

pub const ConversationService = struct {
    allocator: std.mem.Allocator,
    pers: persistence.ConversationPersistence,

    pub fn init(allocator: std.mem.Allocator, db: anytype) ConversationService {
        return .{ .allocator = allocator, .pers = persistence.ConversationPersistence.init(allocator, db) };
    }

    // ── CRUD ──────────────────────────────────────────────────────

    pub fn create(self: *ConversationService, input: model.ConversationCreateInput) !model.Conversation {
        const conv = try self.pers.create(input);

        const eb = event_bus_mod.getEventBus();
        const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"conversation_id\":\"{s}\",\"owner\":\"{s}\",\"type\":{}}}", .{ conv.conversation_id, conv.owner_user_id, @intFromEnum(conv.conversation_type) });
        defer core.getAllocator().free(payload);
        eb.emit(.conversation_created, "conversation", payload);

        return conv;
    }

    pub fn get(self: *ConversationService, owner_user_id: []const u8, conversation_id: []const u8) !?model.Conversation {
        return self.pers.get(owner_user_id, conversation_id);
    }

    pub fn getByOwner(self: *ConversationService, allocator: std.mem.Allocator, owner_user_id: []const u8) ![]model.Conversation {
        return self.pers.getByOwner(allocator, owner_user_id);
    }

    pub fn getByOwnerSince(self: *ConversationService, allocator: std.mem.Allocator, owner_user_id: []const u8, since_timestamp: i64) ![]model.Conversation {
        return self.pers.getByOwnerSince(allocator, owner_user_id, since_timestamp);
    }

    pub fn update(self: *ConversationService, owner_user_id: []const u8, conversation_id: []const u8, input: model.ConversationUpdateInput) !?model.Conversation {
        const result = try self.pers.update(owner_user_id, conversation_id, input);
        if (result != null) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"conversation_id\":\"{s}\",\"owner\":\"{s}\"}}", .{ conversation_id, owner_user_id });
            defer core.getAllocator().free(payload);
            eb.emit(.conversation_updated, "conversation", payload);
        }
        return result;
    }

    pub fn delete(self: *ConversationService, owner_user_id: []const u8, conversation_id: []const u8) bool {
        const result = self.pers.delete(owner_user_id, conversation_id);
        if (result) {
            const eb = event_bus_mod.getEventBus();
            const payload = try std.fmt.allocPrint(core.getAllocator(), "{{\"conversation_id\":\"{s}\",\"owner\":\"{s}\"}}", .{ conversation_id, owner_user_id });
            defer core.getAllocator().free(payload);
            eb.emit(.conversation_deleted, "conversation", payload);
        }
        return result;
    }

    pub fn updateSeq(self: *ConversationService, owner_user_id: []const u8, conversation_id: []const u8, max_seq: i64) !void {
        try self.pers.updateSeq(owner_user_id, conversation_id, max_seq);
    }

    pub fn count(self: *ConversationService) usize {
        return self.pers.count();
    }

    // ── Encryption keys ───────────────────────────────────────────

    pub fn getEncryptionKeys(self: *ConversationService, conversation_id: []const u8, allocator: std.mem.Allocator) ![]model.VersionKey {
        return self.pers.getEncryptionKeys(conversation_id, allocator);
    }

    pub fn genEncryptionKey(self: *ConversationService, conversation_id: []const u8) !void {
        try self.pers.genEncryptionKey(conversation_id);
    }
};
