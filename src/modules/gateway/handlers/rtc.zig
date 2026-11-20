// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: rtc.zig
//
// Phase 84: meeting/participant state moved from in-memory maps to
// PostgreSQL (gateway/rtc_persistence.zig) — rooms survive restarts and
// stale rooms are archived at gateway start. Handler contracts (request /
// response shapes) are unchanged. Error policy: persistence failures surface
// as 500s; "room/participant unknown" stays a 200 no-op like the legacy
// maps, except create which now reports a duplicate room as 409.

const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const ws_module = @import("../../websocket.zig");

const gw_root = @import("../root.zig");
const rtc_pers = @import("../rtc_persistence.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;
const dto = @import("../dto.zig");

pub fn handleRTCMeetingAccept(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const AcceptReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(AcceptReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = rtc_pers.addParticipant(req.roomID, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingClose(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CloseReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(CloseReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    // Host check happens inside the transaction; non-host closes are a
    // silent no-op exactly like the legacy map path.
    _ = rtc_pers.closeMeeting(req.roomID, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingCreate(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const CreateReq = struct {
        hostUserID: []const u8,
        meetingName: []const u8,
    };
    const req = ctx.bindJson(CreateReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const room_id = gw_root.generateRoomID(core.getAllocator()) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_meeting_create, @errorName(err));
    };
    rtc_pers.createMeeting(room_id, req.hostUserID, req.meetingName) catch |err| switch (err) {
        error.RoomExists => return sendFail(ctx, 409, "room already active"),
        else => return sendFail(ctx, core.ErrorCode.rtc_meeting_create, @errorName(err)),
    };
    return sendOk(ctx, .{ .roomID = room_id });
}

pub fn handleRTCMeetingInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const InfoReq = struct {
        roomID: []const u8,
    };
    const req = ctx.bindJson(InfoReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const meeting = rtc_pers.getMeeting(req.roomID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    } orelse return sendFail(ctx, 404, "Not Found");
    // camelCase contract (Go rtc.proto MeetingInfo style) — Phase 85.
    return sendOk(ctx, dto.meetingToJson(meeting));
}

pub fn handleRTCMeetingInvite(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const InviteReq = struct {
        roomID: []const u8,
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(InviteReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const msg = try std.fmt.allocPrint(core.getAllocator(), "{{\"event\":\"rtc_invite\",\"roomID\":\"{s}\"}}", .{req.roomID});
    defer core.getAllocator().free(msg);
    for (req.userIDs) |uid| {
        ws_module.pushToUser(uid, msg);
    }
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingJoin(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const JoinReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(JoinReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    _ = rtc_pers.addParticipant(req.roomID, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingKick(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const KickReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(KickReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    rtc_pers.removeParticipant(req.roomID, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingLeave(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const LeaveReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(LeaveReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    rtc_pers.removeParticipant(req.roomID, req.userID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const list = rtc_pers.listActiveMeetings() catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    var items = std.ArrayList(@TypeOf(dto.meetingToJson(undefined))).empty;
    defer items.deinit(core.getAllocator());
    for (list) |m| {
        items.append(core.getAllocator(), dto.meetingToJson(m)) catch {};
    }
    return sendOk(ctx, .{ .meetings = items.items });
}

pub fn handleRTCMeetingMute(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const MuteReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(MuteReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    rtc_pers.setParticipantFlag(req.roomID, req.userID, "is_muted", true) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingRecordStart(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RecordReq = struct {
        roomID: []const u8,
    };
    const req = ctx.bindJson(RecordReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const rec_id = std.fmt.allocPrint(core.getAllocator(), "rec_{s}", .{req.roomID}) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    rtc_pers.setRecordId(req.roomID, rec_id) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingRecordStop(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RecordReq = struct {
        roomID: []const u8,
    };
    const req = ctx.bindJson(RecordReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    rtc_pers.setRecordId(req.roomID, null) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingReject(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RejectReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(RejectReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const host = rtc_pers.getHostUserId(req.roomID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    } orelse return sendOk(ctx, null);
    const msg = try std.fmt.allocPrint(core.getAllocator(), "{{\"event\":\"rtc_reject\",\"roomID\":\"{s}\",\"userID\":\"{s}\"}}", .{ req.roomID, req.userID });
    defer core.getAllocator().free(msg);
    ws_module.pushToUser(host, msg);
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingSetLayout(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const LayoutReq = struct {
        roomID: []const u8,
        layout: i32,
    };
    const req = ctx.bindJson(LayoutReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    rtc_pers.setLayout(req.roomID, req.layout) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingSignal(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SignalReq = struct {
        roomID: []const u8,
        userID: []const u8,
        signal: []const u8,
    };
    const req = ctx.bindJson(SignalReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const ids = rtc_pers.getParticipantIds(req.roomID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    const msg = try std.fmt.allocPrint(core.getAllocator(), "{{\"event\":\"rtc_signal\",\"roomID\":\"{s}\",\"fromUserID\":\"{s}\",\"signal\":\"{s}\"}}", .{ req.roomID, req.userID, req.signal });
    defer core.getAllocator().free(msg);
    for (ids) |uid| {
        if (!std.mem.eql(u8, uid, req.userID)) {
            ws_module.pushToUser(uid, msg);
        }
    }
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingTransferHost(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const TransferReq = struct {
        roomID: []const u8,
        oldHostUserID: []const u8,
        newHostUserID: []const u8,
    };
    const req = ctx.bindJson(TransferReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    // Ownership is checked in SQL (host_user_id = old). The legacy in-memory
    // path assigned the request-arena string into the global map — a
    // use-after-free once the request ended; persistence removes that class.
    _ = rtc_pers.transferHost(req.roomID, req.oldHostUserID, req.newHostUserID) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingUnmute(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const UnmuteReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(UnmuteReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    rtc_pers.setParticipantFlag(req.roomID, req.userID, "is_muted", false) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingVideoOff(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const VideoReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(VideoReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    rtc_pers.setParticipantFlag(req.roomID, req.userID, "is_video_on", false) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingVideoOn(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const VideoReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(VideoReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    rtc_pers.setParticipantFlag(req.roomID, req.userID, "is_video_on", true) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_base, @errorName(err));
    };
    return sendOk(ctx, null);
}
