//! RTC meeting persistence (Phase 84) — PostgreSQL-backed meeting state.
//!
//! Replaces the in-memory StringHashMap storage whose entire state was lost
//! on process restart. Semantics kept identical to the legacy maps (same
//! handler contracts, same field shapes); new capabilities on top:
//! - meetings/participants survive restarts
//! - stale `active` meetings are archived at gateway start (a restart ends
//!   every room — no zombie meetings answered after downtime)
//! - create/close run in a zent TxClient transaction (meeting + host
//!   participant row are atomic; so are the two deletes on close)
//!
//! Storage choice per zent BEST_PRACTICES §1: the meeting table uses the
//! typed builder (single-table CRUD, caller-provided text pk); participant
//! rows are small single-statement writes with a (room_id, user_id) business
//! conflict target — raw exec. All reads go through sql_scan DTOs mapped
//! onto the existing model structs.

const std = @import("std");
const core = @import("core");
const zent = @import("zent");
const zent_db = @import("../../zent_db.zig");
const model = @import("model.zig");

const MeetingRow = struct {
    room_id: []const u8,
    host_user_id: []const u8,
    meeting_name: []const u8,
    status: i64,
    layout: i64,
    record_id: ?[]const u8,
    create_time: i64,
};

fn toModel(row: MeetingRow) model.RtcMeeting {
    return .{
        .room_id = row.room_id,
        .host_user_id = row.host_user_id,
        .meeting_name = row.meeting_name,
        .status = @intCast(row.status),
        .create_time = row.create_time,
        .layout = @intCast(row.layout),
        .record_id = row.record_id,
    };
}

/// Archive every meeting still marked active from a previous process run.
/// Called once from gateway start: a restart ends all rooms — participants
/// are left in place for the audit trail (left_at is not tracked; the
/// participant rows die with the room on close/delete).
pub fn archiveStaleMeetings() void {
    const drv = zent_db.getDriver() orelse return;
    _ = drv.exec(
        "UPDATE rtc_meetings SET status = 2, ended_at = $1 WHERE status = 1",
        &.{.{ .int = core.unixNowSeconds() }},
    ) catch |err| {
        core.logJson(.{ .event = "rtc_archive_failed", .err = @errorName(err) });
    };
}

/// Create a meeting + its host participant row atomically (TxClient).
/// Returns error.RoomExists when the room_id is already active.
pub fn createMeeting(room_id: []const u8, host_user_id: []const u8, meeting_name: []const u8) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    const infos = zent_db.schema_infos;
    var tx = try zent.codegen.beginTxFromDriver(infos, drv, core.getAllocator());
    defer tx.deinit();
    errdefer tx.rollback() catch {};

    // Unique-violation on the pk reads as "room already active".
    var b = try tx.client.rtc_meeting.Create();
    defer b.deinit();
    _ = try b.setFieldValue("room_id", room_id);
    _ = try b.setFieldValue("host_user_id", host_user_id);
    _ = try b.setFieldValue("meeting_name", meeting_name);
    _ = try b.setFieldValue("status", @as(i64, 1));
    _ = try b.setFieldValue("layout", @as(i64, 0));
    _ = try b.setFieldValue("create_time", core.unixNowSeconds());
    _ = b.Save() catch |err| switch (err) {
        error.UniqueViolation => return error.RoomExists,
        else => return err,
    };

    _ = try tx.client.driver.exec(
        "INSERT INTO rtc_participants (room_id, user_id, joined_at) VALUES ($1, $2, $3) ON CONFLICT (room_id, user_id) DO NOTHING",
        &.{ .{ .string = room_id }, .{ .string = host_user_id }, .{ .int = core.unixNowSeconds() } },
    );
    try tx.commit();
}

/// Close a room: only the host may close; meeting + participant rows are
/// removed atomically. Returns false when the room does not exist or the
/// closer is not the host (same semantics as the legacy in-memory path).
pub fn closeMeeting(room_id: []const u8, user_id: []const u8) !bool {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    const meeting = try getMeeting(room_id);
    if (meeting == null) return false;
    // meeting strings are scanner-duplicated into the request arena — no
    // deinitRow (that contract is for zent entities, not sql_scan DTOs).
    if (!std.mem.eql(u8, meeting.?.host_user_id, user_id)) return false;

    const infos = zent_db.schema_infos;
    var tx = try zent.codegen.beginTxFromDriver(infos, drv, core.getAllocator());
    defer tx.deinit();
    errdefer tx.rollback() catch {};

    _ = try tx.client.driver.exec("DELETE FROM rtc_participants WHERE room_id = $1", &.{.{ .string = room_id }});
    _ = try tx.client.driver.exec("DELETE FROM rtc_meetings WHERE room_id = $1", &.{.{ .string = room_id }});
    try tx.commit();
    return true;
}

pub fn getMeeting(room_id: []const u8) !?model.RtcMeeting {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    const row = (zent.sql_scan.queryOne(
        MeetingRow,
        core.getAllocator(),
        drv,
        "SELECT room_id, host_user_id, meeting_name, status, layout, record_id, create_time FROM rtc_meetings WHERE room_id = $1 AND status = 1",
        &.{.{ .string = room_id }},
    ) catch return null) orelse return null;
    return toModel(row);
}

pub fn listActiveMeetings() ![]model.RtcMeeting {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    var rows = try zent.sql_scan.queryAll(
        MeetingRow,
        core.getAllocator(),
        drv,
        "SELECT room_id, host_user_id, meeting_name, status, layout, record_id, create_time FROM rtc_meetings WHERE status = 1 ORDER BY create_time DESC",
        &.{},
    );
    defer rows.deinit();
    const list = try core.getAllocator().alloc(model.RtcMeeting, rows.items.len);
    for (rows.items, 0..) |row, i| list[i] = toModel(row);
    return list;
}

/// Add a participant (idempotent). Returns false when the room is unknown.
pub fn addParticipant(room_id: []const u8, user_id: []const u8) !bool {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    const meeting = try getMeeting(room_id);
    if (meeting == null) return false;
    _ = try drv.exec(
        "INSERT INTO rtc_participants (room_id, user_id, joined_at) VALUES ($1, $2, $3) ON CONFLICT (room_id, user_id) DO NOTHING",
        &.{ .{ .string = room_id }, .{ .string = user_id }, .{ .int = core.unixNowSeconds() } },
    );
    return true;
}

/// Remove a participant (leave/kick — same effect, caller validates host
/// rights). No-op when the room or the row is unknown.
pub fn removeParticipant(room_id: []const u8, user_id: []const u8) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    _ = try drv.exec(
        "DELETE FROM rtc_participants WHERE room_id = $1 AND user_id = $2",
        &.{ .{ .string = room_id }, .{ .string = user_id } },
    );
}

pub fn setParticipantFlag(room_id: []const u8, user_id: []const u8, comptime flag: []const u8, value: bool) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    _ = try drv.exec(
        "UPDATE rtc_participants SET " ++ flag ++ " = $1 WHERE room_id = $2 AND user_id = $3",
        &.{ .{ .bool = value }, .{ .string = room_id }, .{ .string = user_id } },
    );
}

pub fn setLayout(room_id: []const u8, layout: i32) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    _ = try drv.exec(
        "UPDATE rtc_meetings SET layout = $1 WHERE room_id = $2 AND status = 1",
        &.{ .{ .int = layout }, .{ .string = room_id } },
    );
}

pub fn setRecordId(room_id: []const u8, record_id: ?[]const u8) !void {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    _ = try drv.exec(
        "UPDATE rtc_meetings SET record_id = $1 WHERE room_id = $2 AND status = 1",
        &.{ if (record_id) |r| zent.sql.Value{ .string = r } else zent.sql.Value.null, .{ .string = room_id } },
    );
}

/// Transfer host authority. Returns false when the room is unknown or the
/// caller is not the current host (ownership checked in SQL, so the
/// request-arena string never reaches persistent storage — the legacy
/// in-memory path had a use-after-free here).
pub fn transferHost(room_id: []const u8, old_host: []const u8, new_host: []const u8) !bool {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    const res = try drv.exec(
        "UPDATE rtc_meetings SET host_user_id = $1 WHERE room_id = $2 AND host_user_id = $3 AND status = 1",
        &.{ .{ .string = new_host }, .{ .string = room_id }, .{ .string = old_host } },
    );
    return res.rows_affected > 0;
}

pub fn getHostUserId(room_id: []const u8) !?[]const u8 {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    const Row = struct { host_user_id: []const u8 };
    const row = (zent.sql_scan.queryOne(
        Row,
        core.getAllocator(),
        drv,
        "SELECT host_user_id FROM rtc_meetings WHERE room_id = $1 AND status = 1",
        &.{.{ .string = room_id }},
    ) catch return null) orelse return null;
    return row.host_user_id;
}

/// Participant user ids for signal fan-out (arena-owned strings).
pub fn getParticipantIds(room_id: []const u8) ![]const []const u8 {
    const drv = zent_db.getDriver() orelse return error.DbNotInitialized;
    const Row = struct { user_id: []const u8 };
    var rows = try zent.sql_scan.queryAll(
        Row,
        core.getAllocator(),
        drv,
        "SELECT user_id FROM rtc_participants WHERE room_id = $1",
        &.{.{ .string = room_id }},
    );
    defer rows.deinit();
    const ids = try core.getAllocator().alloc([]const u8, rows.items.len);
    for (rows.items, 0..) |row, i| ids[i] = row.user_id;
    return ids;
}
