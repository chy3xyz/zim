const std = @import("std");
const model = @import("message/model.zig");
const persistence = @import("message/persistence.zig");
const root = @import("message/root.zig");

pub const info = root.info;
pub const init = root.init;
pub const deinit = root.deinit;

// Re-export models
pub const SessionType = model.SessionType;
pub const ContentType = model.ContentType;
pub const MessageOptions = model.MessageOptions;
pub const Message = model.Message;
pub const MessageSendInput = model.MessageSendInput;
pub const DayCount = model.DayCount;
pub const TopEntity = model.TopEntity;
pub const getConversationID = model.getConversationID;

// Legacy storage alias
pub const MessageStorage = persistence.MessagePersistence;

pub fn getStorage() *persistence.MessagePersistence {
    return &root.getService().pers;
}

// Re-export service API
pub fn sendMessage(input: MessageSendInput) !Message {
    return root.getService().sendMessage(input);
}
pub fn getMessages(conversation_id: []const u8, offset: i64, limit: i64) ![]Message {
    return root.getService().getMessages(conversation_id, offset, limit);
}
pub fn getMessagesBySeqRange(conversation_id: []const u8, begin_seq: i64, end_seq: i64, limit: i64, ascending: bool) ![]Message {
    return root.getService().getMessagesBySeqRange(conversation_id, begin_seq, end_seq, limit, ascending);
}
pub fn getMessagesBySeqList(conversation_id: []const u8, seqs: []const i64) ![]Message {
    return root.getService().getMessagesBySeqList(conversation_id, seqs);
}
pub fn recallMessage(conversation_id: []const u8, seq: i64, user_id: []const u8) !bool {
    return root.getService().recallMessage(conversation_id, seq, user_id);
}
pub fn modifyMessage(conversation_id: []const u8, seq: i64, user_id: []const u8, new_content: []const u8) !bool {
    return root.getService().modifyMessage(conversation_id, seq, user_id, new_content);
}
pub fn deleteMessages(conversation_id: []const u8, seqs: []const i64, user_id: []const u8) !usize {
    return root.getService().deleteMessages(conversation_id, seqs, user_id);
}
pub fn markMessageRead(owner_user_id: []const u8, conversation_id: []const u8, seq: i64) bool {
    return root.getService().markMessageRead(owner_user_id, conversation_id, seq);
}
pub fn getMaxSeq(conversation_id: []const u8) i64 {
    return root.getService().getMaxSeq(conversation_id);
}
pub fn messageCount() usize {
    return root.getService().messageCount();
}
pub fn activeMsgCount(start_time: i64, end_time: i64, group_mode: bool) usize {
    return root.getService().activeMsgCount(start_time, end_time, group_mode);
}
pub fn activeEntityCount(start_time: i64, end_time: i64, group_mode: bool) usize {
    return root.getService().activeEntityCount(start_time, end_time, group_mode);
}
pub fn activeDateCount(allocator: std.mem.Allocator, start_time: i64, end_time: i64, group_mode: bool) ![]DayCount {
    return root.getService().activeDateCount(allocator, start_time, end_time, group_mode);
}
pub fn activeTopEntities(allocator: std.mem.Allocator, start_time: i64, end_time: i64, group_mode: bool, limit: i64) ![]TopEntity {
    return root.getService().activeTopEntities(allocator, start_time, end_time, group_mode, limit);
}
pub fn clearConversationMessages(conversation_id: []const u8) !void {
    return root.getService().clearConversationMessages(conversation_id);
}
pub fn clearAllMessages(user_id: []const u8) !void {
    return root.getService().clearAllMessages(user_id);
}
pub fn searchMessages(conversation_id: []const u8, keyword: []const u8, limit: i64) ![]Message {
    return root.getService().searchMessages(conversation_id, keyword, limit);
}
pub fn checkMsgSendSuccess(client_msg_id: []const u8) bool {
    return root.getService().checkMsgSendSuccess(client_msg_id);
}
pub fn getClientMsgIdBySeq(conversation_id: []const u8, seq: i64) ?[]const u8 {
    return root.getService().getClientMsgIdBySeq(conversation_id, seq);
}
pub fn trackGroupMessageRead(conversation_id: []const u8, client_msg_id: []const u8, user_id: []const u8) void {
    root.getService().trackGroupMessageRead(conversation_id, client_msg_id, user_id);
}
pub fn getGroupMessageReadNum(conversation_id: []const u8, client_msg_id: []const u8) model.GroupMessageReadResult {
    return root.getService().getGroupMessageReadNum(conversation_id, client_msg_id);
}
pub fn getGroupMessageHasRead(conversation_id: []const u8, client_msg_id: []const u8, user_id: []const u8) bool {
    return root.getService().getGroupMessageHasRead(conversation_id, client_msg_id, user_id);
}
pub fn sendBusinessNotification(recv_id: []const u8, content: []const u8) !Message {
    return root.getService().sendBusinessNotification(recv_id, content);
}
pub fn deleteMsgPhysical(conversation_id: []const u8, msg_ids: []const []const u8) !usize {
    return root.getService().deleteMsgPhysical(conversation_id, msg_ids);
}
