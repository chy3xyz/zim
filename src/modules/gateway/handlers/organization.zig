// Domain handlers split from gateway/handlers.zig.
// Handler bodies are verbatim copies; routes live in ../handlers.zig.
// File: organization.zig

const std = @import("std");
const core = @import("core");
const zmodu = @import("zmodu");
const http = zmodu.http;
const organization_mod = @import("../../organization.zig");
const dto = @import("../dto.zig");
const GatewayRoutes = @import("../handlers.zig").GatewayRoutes;
const helpers = @import("helpers.zig");
const sendOk = helpers.sendOk;
const sendFail = helpers.sendFail;

pub fn handleGetDepartments(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        departmentIDs: ?[][]const u8 = null,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const depts = organization_mod.getDepartments(core.getAllocator(), req.departmentIDs) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_departments, @errorName(err));
    };
    var depts_json = std.ArrayList(@TypeOf(dto.departmentToJson(depts[0]))).empty;
    defer depts_json.deinit(core.getAllocator());
    for (depts) |d| {
        try depts_json.append(core.getAllocator(), dto.departmentToJson(d));
    }
    return sendOk(ctx, .{ .departments = depts_json.items });
}

pub fn handleGetOrganization(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const org = organization_mod.getOrganization() catch |err| {
        return sendFail(ctx, core.ErrorCode.get_organization, @errorName(err));
    };
    if (org == null) return sendFail(ctx, 404, "Not Found");
    return sendOk(ctx, dto.organizationToJson(org.?));
}

pub fn handleGetSubDepartmentsAndMembers(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        departmentID: ?[]const u8 = null,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const result = organization_mod.getSubDepartmentsAndMembers(core.getAllocator(), req.departmentID) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_sub_departments_and_members, @errorName(err));
    };
    var members_json = std.ArrayList(@TypeOf(dto.orgMemberToJson(result.members[0]))).empty;
    defer members_json.deinit(core.getAllocator());
    for (result.members) |m| {
        try members_json.append(core.getAllocator(), dto.orgMemberToJson(m));
    }
    var sub_depts_json = std.ArrayList(@TypeOf(dto.departmentToJson(result.sub_departments[0]))).empty;
    defer sub_depts_json.deinit(core.getAllocator());
    for (result.sub_departments) |d| {
        try sub_depts_json.append(core.getAllocator(), dto.departmentToJson(d));
    }
    var parents_json = std.ArrayList(@TypeOf(dto.departmentToJson(result.parents[0]))).empty;
    defer parents_json.deinit(core.getAllocator());
    for (result.parents) |d| {
        try parents_json.append(core.getAllocator(), dto.departmentToJson(d));
    }
    return sendOk(ctx, .{
        .department = dto.departmentToJson(result.department),
        .members = members_json.items,
        .subDepartments = sub_depts_json.items,
        .parents = parents_json.items,
    });
}

pub fn handleGetUsersInDepartments(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const GetReq = struct {
        userIDs: [][]const u8,
    };
    const req = ctx.bindJson(GetReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const members = organization_mod.getUsersInDepartments(core.getAllocator(), req.userIDs) catch |err| {
        return sendFail(ctx, core.ErrorCode.get_users_in_departments, @errorName(err));
    };
    var members_json = std.ArrayList(@TypeOf(dto.orgMemberToJson(members[0]))).empty;
    defer members_json.deinit(core.getAllocator());
    for (members) |m| {
        try members_json.append(core.getAllocator(), dto.orgMemberToJson(m));
    }
    return sendOk(ctx, .{ .members = members_json.items });
}

pub fn handleSearchOrganizationUsers(ctx: *http.Context, _: *GatewayRoutes.State) anyerror!void {
    const SearchReq = struct {
        keyword: []const u8,
        pageNumber: u32 = 1,
        showNumber: u32 = 20,
    };
    const req = ctx.bindJson(SearchReq) catch |err| {
        return sendFail(ctx, 400, @errorName(err));
    };
    const users = organization_mod.searchOrganizationUsers(core.getAllocator(), req.keyword, req.pageNumber, req.showNumber) catch |err| {
        return sendFail(ctx, core.ErrorCode.search_organization_users, @errorName(err));
    };
    var users_json = std.ArrayList(@TypeOf(dto.orgMemberToJson(users[0]))).empty;
    defer users_json.deinit(core.getAllocator());
    for (users) |u| {
        try users_json.append(core.getAllocator(), dto.orgMemberToJson(u));
    }
    return sendOk(ctx, .{ .users = users_json.items });
}
