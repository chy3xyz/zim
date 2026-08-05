const std = @import("std");

pub const model = @import("office/model.zig");
pub const persistence = @import("office/persistence.zig");
pub const service = @import("office/service.zig");
pub const root = @import("office/root.zig");

// Backward-compatible re-exports
pub const WorkMoment = model.WorkMoment;
pub const WorkMomentCreateInput = model.WorkMomentCreateInput;
pub const Comment = model.Comment;
pub const LikeUser = model.LikeUser;
pub const ReadType = model.ReadType;
pub const Tag = model.Tag;
pub const TagCreateInput = model.TagCreateInput;
pub const TagUpdateInput = model.TagUpdateInput;
pub const Collect = model.Collect;
pub const ClientConfig = model.ClientConfig;
pub const OfficeStorage = persistence.OfficePersistence;

pub const info = root.info;

pub fn init() !void {
    return root.init();
}

pub fn deinit() void {
    root.deinit();
}

pub fn getStorage() *OfficeStorage {
    return &root.g_service.?.pers;
}

// Public API functions (backward compatible)
pub fn createWorkMoment(input: WorkMomentCreateInput) !WorkMoment {
    return root.getService().createWorkMoment(input);
}

pub fn deleteWorkMoment(moment_id: []const u8, user_id: []const u8) bool {
    return root.getService().deleteWorkMoment(moment_id, user_id);
}

pub fn getWorkMoment(moment_id: []const u8) !?WorkMoment {
    return root.getService().getWorkMoment(moment_id);
}

pub fn getRecvWorkMoments(allocator: std.mem.Allocator, user_id: []const u8, page: u32, size: u32) ![]WorkMoment {
    return root.getService().getRecvWorkMoments(allocator, user_id, page, size);
}

pub fn getRecvWorkMomentsCount(user_id: []const u8) !u32 {
    return root.getService().getRecvWorkMomentsCount(user_id);
}

pub fn getSendWorkMoments(allocator: std.mem.Allocator, target_user_id: []const u8, viewer_user_id: []const u8, page: u32, size: u32) ![]WorkMoment {
    return root.getService().getSendWorkMoments(allocator, target_user_id, viewer_user_id, page, size);
}

pub fn likeWorkMoment(moment_id: []const u8, user_id: []const u8, nickname: []const u8, face_url: []const u8) bool {
    return root.getService().likeWorkMoment(moment_id, user_id, nickname, face_url);
}

pub fn unlikeWorkMoment(moment_id: []const u8, user_id: []const u8) bool {
    return root.getService().unlikeWorkMoment(moment_id, user_id);
}

pub fn addComment(moment_id: []const u8, user_id: []const u8, nickname: []const u8, face_url: []const u8, reply_user_id: ?[]const u8, reply_nickname: ?[]const u8, reply_face_url: ?[]const u8, content: []const u8) bool {
    return root.getService().addComment(moment_id, user_id, nickname, face_url, reply_user_id, reply_nickname, reply_face_url, content);
}

pub fn deleteComment(moment_id: []const u8, comment_id: []const u8) bool {
    return root.getService().deleteComment(moment_id, comment_id);
}

pub fn getUnreadWorkMomentsCount(user_id: []const u8) u32 {
    return root.getService().getUnreadWorkMomentsCount(user_id);
}

pub fn clearUnreadWorkMoments(user_id: []const u8, read_type: i32) void {
    root.getService().clearUnreadWorkMoments(user_id, read_type);
}

pub fn findRelevantWorkMoments(allocator: std.mem.Allocator, user_id: []const u8, page: u32, size: u32) ![]WorkMoment {
    return root.getService().findRelevantWorkMoments(allocator, user_id, page, size);
}

pub fn getUserReadTime(user_id: []const u8, read_type: ReadType) !i64 {
    return root.getService().getUserReadTime(user_id, read_type);
}

pub fn getTags(allocator: std.mem.Allocator, user_id: []const u8) ![]Tag {
    return root.getService().getTags(allocator, user_id);
}

pub fn createTag(input: TagCreateInput) !Tag {
    return root.getService().createTag(input);
}

pub fn deleteTag(tag_id: []const u8) !bool {
    return root.getService().deleteTag(tag_id);
}

pub fn updateTag(input: TagUpdateInput) !bool {
    return root.getService().updateTag(input);
}

pub fn addCollect(user_id: []const u8, collect_type: []const u8, content: []const u8, uuid: []const u8) !Collect {
    return root.getService().addCollect(user_id, collect_type, content, uuid);
}

pub fn removeCollect(user_id: []const u8, collect_ids: []const []const u8) !bool {
    return root.getService().removeCollect(user_id, collect_ids);
}

pub fn getCollects(allocator: std.mem.Allocator, user_id: []const u8, collect_types: []const []const u8, page: u32, size: u32) ![]Collect {
    return root.getService().getCollects(allocator, user_id, collect_types, page, size);
}

pub fn getClientConfig() !ClientConfig {
    return root.getService().getClientConfig();
}
