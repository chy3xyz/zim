pub const QueueMessage = struct {
    msg_id: i64,
    read_ct: i32,
    enqueued_at: i64,
    vt: i64,
    body: []const u8,
};
