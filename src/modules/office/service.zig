const std = @import("std");
const model = @import("model.zig");
const persistence = @import("persistence.zig");

pub const OfficeService = struct {
    allocator: std.mem.Allocator,
    pers: persistence.OfficePersistence,

    pub fn init(allocator: std.mem.Allocator, db: anytype) OfficeService {
        return .{ .allocator = allocator, .pers = persistence.OfficePersistence.init(allocator, db) };
    }

    pub fn createWorkMoment(self: *OfficeService, input: model.WorkMomentCreateInput) !model.WorkMoment {
        return self.pers.create(input);
    }

    pub fn deleteWorkMoment(self: *OfficeService, moment_id: []const u8, user_id: []const u8) bool {
        return self.pers.delete(moment_id, user_id);
    }

    pub fn getWorkMoment(self: *OfficeService, moment_id: []const u8) !?model.WorkMoment {
        return self.pers.get(moment_id);
    }

    pub fn getRecvWorkMoments(self: *OfficeService, allocator: std.mem.Allocator, user_id: []const u8, page: u32, size: u32) ![]model.WorkMoment {
        return self.pers.getRecvList(allocator, user_id, page, size);
    }

    pub fn getRecvWorkMomentsCount(self: *OfficeService, user_id: []const u8) !u32 {
        return self.pers.getRecvCount(user_id);
    }

    pub fn getSendWorkMoments(self: *OfficeService, allocator: std.mem.Allocator, target_user_id: []const u8, viewer_user_id: []const u8, page: u32, size: u32) ![]model.WorkMoment {
        return self.pers.getSendList(allocator, target_user_id, viewer_user_id, page, size);
    }

    pub fn likeWorkMoment(self: *OfficeService, moment_id: []const u8, user_id: []const u8, nickname: []const u8, face_url: []const u8) bool {
        return self.pers.like(moment_id, user_id, nickname, face_url);
    }

    pub fn unlikeWorkMoment(self: *OfficeService, moment_id: []const u8, user_id: []const u8) bool {
        return self.pers.unlike(moment_id, user_id);
    }

    pub fn addComment(self: *OfficeService, moment_id: []const u8, user_id: []const u8, nickname: []const u8, face_url: []const u8, reply_user_id: ?[]const u8, reply_nickname: ?[]const u8, reply_face_url: ?[]const u8, content: []const u8) bool {
        return self.pers.addComment(moment_id, user_id, nickname, face_url, reply_user_id, reply_nickname, reply_face_url, content);
    }

    pub fn deleteComment(self: *OfficeService, moment_id: []const u8, comment_id: []const u8) bool {
        return self.pers.deleteComment(moment_id, comment_id);
    }

    pub fn getUnreadWorkMomentsCount(self: *OfficeService, user_id: []const u8) u32 {
        return self.pers.getUnreadCount(user_id);
    }

    pub fn clearUnreadWorkMoments(self: *OfficeService, user_id: []const u8, read_type: i32) void {
        self.pers.clearUnread(user_id, read_type);
    }

    pub fn findRelevantWorkMoments(self: *OfficeService, allocator: std.mem.Allocator, user_id: []const u8, page: u32, size: u32) ![]model.WorkMoment {
        return self.pers.findRelevantWorkMoments(allocator, user_id, page, size);
    }

    pub fn getUserReadTime(self: *OfficeService, user_id: []const u8, read_type: model.ReadType) !i64 {
        return self.pers.getUserReadTime(user_id, read_type);
    }

    pub fn getTags(self: *OfficeService, allocator: std.mem.Allocator, user_id: []const u8) ![]model.Tag {
        return self.pers.getTags(allocator, user_id);
    }

    pub fn createTag(self: *OfficeService, input: model.TagCreateInput) !model.Tag {
        return self.pers.createTag(input);
    }

    pub fn deleteTag(self: *OfficeService, tag_id: []const u8) !bool {
        return self.pers.deleteTag(tag_id);
    }

    pub fn updateTag(self: *OfficeService, input: model.TagUpdateInput) !bool {
        return self.pers.updateTag(input);
    }

    pub fn addCollect(self: *OfficeService, user_id: []const u8, collect_type: []const u8, content: []const u8, uuid: []const u8) !model.Collect {
        return self.pers.addCollect(user_id, collect_type, content, uuid);
    }

    pub fn removeCollect(self: *OfficeService, user_id: []const u8, collect_ids: []const []const u8) !bool {
        return self.pers.removeCollect(user_id, collect_ids);
    }

    pub fn getCollects(self: *OfficeService, allocator: std.mem.Allocator, user_id: []const u8, collect_types: []const []const u8, page: u32, size: u32) ![]model.Collect {
        return self.pers.getCollects(allocator, user_id, collect_types, page, size);
    }

    pub fn getClientConfig(self: *OfficeService) !model.ClientConfig {
        return self.pers.getClientConfig();
    }
};
