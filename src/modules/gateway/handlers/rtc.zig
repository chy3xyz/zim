// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: rtc.zig

const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const ws_module = @import("../../websocket.zig");
const model = @import("../model.zig");
const gw_root = @import("../root.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleRTCMeetingAccept(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const AcceptReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(AcceptReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.getPtr(req.roomID)) |list| {
        var found = false;
        for (list.items) |*p| {
            if (std.mem.eql(u8, p.user_id, req.userID)) {
                found = true;
                break;
            }
        }
        if (!found) {
            const user_z = core.getGlobalAllocator().dupe(u8, req.userID) catch return sendFail(ctx, core.ErrorCode.rtc_base, "OOM");
            list.append(core.getGlobalAllocator(), model.RtcParticipant{ .user_id = user_z, .nickname = "", .joined_at = core.unixNowSeconds(), .is_muted = false, .is_video_on = true }) catch {};
        }
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const meetings = gw_root.getRtcMeetings();
    if (meetings.get(req.roomID)) |m| {
        if (std.mem.eql(u8, m.host_user_id, req.userID)) {
            _ = meetings.remove(req.roomID);
            const participants = gw_root.getRtcParticipants();
            _ = participants.remove(req.roomID);
        }
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const room_id = gw_root.generateRoomID(core.getGlobalAllocator()) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_meeting_create, @errorName(err));
    };
    // Note: room_id is owned by the HashMap, do NOT free here. All strings
    // stored in the global RTC maps must be duped to the GLOBAL allocator —
    // the request arena (bindJson) is reclaimed when the request ends.
    const host_z = core.getGlobalAllocator().dupe(u8, req.hostUserID) catch return sendFail(ctx, core.ErrorCode.rtc_meeting_create, "OOM");
    const name_z = core.getGlobalAllocator().dupe(u8, req.meetingName) catch return sendFail(ctx, core.ErrorCode.rtc_meeting_create, "OOM");
    const meetings = gw_root.getRtcMeetings();
    meetings.put(room_id, model.RtcMeeting{ .room_id = room_id, .host_user_id = host_z, .meeting_name = name_z, .status = 1, .create_time = core.unixNowSeconds(), .layout = 0, .record_id = null }) catch |err| {
        return sendFail(ctx, core.ErrorCode.rtc_meeting_create_put, @errorName(err));
    };
    const participants = gw_root.getRtcParticipants();
    var list = std.ArrayList(model.RtcParticipant).empty;
    // Participant user_id must be a SEPARATE dupe — host_z is owned by the
    // meetings map (deinit frees it there; sharing would double-free).
    const host_part_z = core.getGlobalAllocator().dupe(u8, req.hostUserID) catch return sendFail(ctx, core.ErrorCode.rtc_meeting_create, "OOM");
    list.append(core.getGlobalAllocator(), model.RtcParticipant{ .user_id = host_part_z, .nickname = "", .joined_at = core.unixNowSeconds(), .is_muted = false, .is_video_on = true }) catch {};
    participants.put(room_id, list) catch {};
    return sendOk(ctx, .{ .roomID = room_id });
}

pub fn handleRTCMeetingInfo(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const InfoReq = struct {
        roomID: []const u8,
    };
    const req = ctx.bindJson(InfoReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const meetings = gw_root.getRtcMeetings();
    const meeting = meetings.get(req.roomID) orelse return sendFail(ctx, 404, "Not Found");
    return sendOk(ctx, meeting);
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.getPtr(req.roomID)) |list| {
        var found = false;
        for (list.items) |*p| {
            if (std.mem.eql(u8, p.user_id, req.userID)) {
                found = true;
                break;
            }
        }
        if (!found) {
            const user_z = core.getGlobalAllocator().dupe(u8, req.userID) catch return sendFail(ctx, core.ErrorCode.rtc_base, "OOM");
            list.append(core.getGlobalAllocator(), model.RtcParticipant{ .user_id = user_z, .nickname = "", .joined_at = core.unixNowSeconds(), .is_muted = false, .is_video_on = true }) catch {};
        }
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.getPtr(req.roomID)) |list| {
        var i: usize = 0;
        while (i < list.items.len) : (i += 1) {
            if (std.mem.eql(u8, list.items[i].user_id, req.userID)) {
                _ = list.orderedRemove(i);
                break;
            }
        }
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.getPtr(req.roomID)) |list| {
        var i: usize = 0;
        while (i < list.items.len) : (i += 1) {
            if (std.mem.eql(u8, list.items[i].user_id, req.userID)) {
                _ = list.orderedRemove(i);
                break;
            }
        }
    }
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingList(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const meetings = gw_root.getRtcMeetings();
    var list = std.ArrayList(model.RtcMeeting).empty;
    defer list.deinit(core.getAllocator());
    var it = meetings.iterator();
    while (it.next()) |entry| {
        list.append(core.getAllocator(), entry.value_ptr.*) catch {};
    }
    return sendOk(ctx, .{ .meetings = list.items });
}

pub fn handleRTCMeetingMute(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const MuteReq = struct {
        roomID: []const u8,
        userID: []const u8,
    };
    const req = ctx.bindJson(MuteReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.get(req.roomID)) |list| {
        for (list.items) |*p| {
            if (std.mem.eql(u8, p.user_id, req.userID)) {
                p.is_muted = true;
                break;
            }
        }
    }
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingRecordStart(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RecordReq = struct {
        roomID: []const u8,
    };
    const req = ctx.bindJson(RecordReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const meetings = gw_root.getRtcMeetings();
    if (meetings.getPtr(req.roomID)) |m| {
        if (m.record_id) |old| {
            core.getGlobalAllocator().free(old);
        }
        m.record_id = try std.fmt.allocPrint(core.getGlobalAllocator(), "rec_{s}", .{req.roomID});
    }
    return sendOk(ctx, null);
}

pub fn handleRTCMeetingRecordStop(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const RecordReq = struct {
        roomID: []const u8,
    };
    const req = ctx.bindJson(RecordReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const meetings = gw_root.getRtcMeetings();
    if (meetings.getPtr(req.roomID)) |m| {
        if (m.record_id) |rid| {
            core.getGlobalAllocator().free(rid);
            m.record_id = null;
        }
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const meetings = gw_root.getRtcMeetings();
    if (meetings.get(req.roomID)) |m| {
        const msg = try std.fmt.allocPrint(core.getAllocator(), "{{\"event\":\"rtc_reject\",\"roomID\":\"{s}\",\"userID\":\"{s}\"}}", .{ req.roomID, req.userID });
        defer core.getAllocator().free(msg);
        ws_module.pushToUser(m.host_user_id, msg);
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const meetings = gw_root.getRtcMeetings();
    if (meetings.getPtr(req.roomID)) |m| {
        m.layout = req.layout;
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.get(req.roomID)) |list| {
        const msg = try std.fmt.allocPrint(core.getAllocator(), "{{\"event\":\"rtc_signal\",\"roomID\":\"{s}\",\"fromUserID\":\"{s}\",\"signal\":\"{s}\"}}", .{ req.roomID, req.userID, req.signal });
        defer core.getAllocator().free(msg);
        for (list.items) |p| {
            if (!std.mem.eql(u8, p.user_id, req.userID)) {
                ws_module.pushToUser(p.user_id, msg);
            }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const meetings = gw_root.getRtcMeetings();
    if (meetings.getPtr(req.roomID)) |m| {
        if (std.mem.eql(u8, m.host_user_id, req.oldHostUserID)) {
            m.host_user_id = req.newHostUserID;
        }
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.get(req.roomID)) |list| {
        for (list.items) |*p| {
            if (std.mem.eql(u8, p.user_id, req.userID)) {
                p.is_muted = false;
                break;
            }
        }
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.get(req.roomID)) |list| {
        for (list.items) |*p| {
            if (std.mem.eql(u8, p.user_id, req.userID)) {
                p.is_video_on = false;
                break;
            }
        }
    }
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
    gw_root.rtcLock();
    defer gw_root.rtcUnlock();
    const participants = gw_root.getRtcParticipants();
    if (participants.get(req.roomID)) |list| {
        for (list.items) |*p| {
            if (std.mem.eql(u8, p.user_id, req.userID)) {
                p.is_video_on = true;
                break;
            }
        }
    }
    return sendOk(ctx, null);
}
