const std = @import("std");
const root = @import("organization/root.zig");
const model = @import("organization/model.zig");
const persistence = @import("organization/persistence.zig");
const service = @import("organization/service.zig");

// Backward-compatible re-exports
pub const Organization = model.Organization;
pub const Department = model.Department;
pub const DepartmentMember = model.DepartmentMember;
pub const DeptMemberAndSubDept = model.DeptMemberAndSubDept;
pub const OrganizationStorage = persistence.OrganizationPersistence;

pub const info = root.info;

var g_service: ?service.OrganizationService = null;

pub fn init() !void {
    try root.init();
    g_service = root.getService().*;
}

pub fn deinit() void {
    root.deinit();
    g_service = null;
}

pub fn getStorage() *OrganizationStorage {
    return &g_service.?.pers;
}

// Public API functions (backward compatible)
pub fn getOrganization() !?Organization {
    return root.getService().getOrganization();
}

pub fn getDepartments(allocator: std.mem.Allocator, department_ids: ?[]const []const u8) ![]Department {
    return root.getService().getDepartments(allocator, department_ids);
}

pub fn getAllDepartments(allocator: std.mem.Allocator) ![]Department {
    return root.getService().getAllDepartments(allocator);
}

pub fn getDepartmentMembers(allocator: std.mem.Allocator, department_id: []const u8) ![]DepartmentMember {
    return root.getService().getDepartmentMembers(allocator, department_id);
}

pub fn getUsersInDepartments(allocator: std.mem.Allocator, user_ids: []const []const u8) ![]DepartmentMember {
    return root.getService().getUsersInDepartments(allocator, user_ids);
}

pub fn getSubDepartmentsAndMembers(allocator: std.mem.Allocator, department_id: ?[]const u8) !DeptMemberAndSubDept {
    return root.getService().getSubDepartmentsAndMembers(allocator, department_id);
}

pub fn searchOrganizationUsers(allocator: std.mem.Allocator, keyword: []const u8, page: u32, size: u32) ![]DepartmentMember {
    return root.getService().searchOrganizationUsers(allocator, keyword, page, size);
}
