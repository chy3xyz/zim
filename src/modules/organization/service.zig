const std = @import("std");
const model = @import("model.zig");
const persistence = @import("persistence.zig");

pub const OrganizationService = struct {
    allocator: std.mem.Allocator,
    pers: persistence.OrganizationPersistence,

    pub fn init(allocator: std.mem.Allocator, db: anytype) OrganizationService {
        return .{
            .allocator = allocator,
            .pers = persistence.OrganizationPersistence.init(allocator, db),
        };
    }

    pub fn getOrganization(self: *OrganizationService) !?model.Organization {
        return self.pers.getOrganization();
    }

    pub fn getDepartments(self: *OrganizationService, allocator: std.mem.Allocator, department_ids: ?[]const []const u8) ![]model.Department {
        return self.pers.getDepartments(allocator, department_ids);
    }

    pub fn getAllDepartments(self: *OrganizationService, allocator: std.mem.Allocator) ![]model.Department {
        return self.pers.getAllDepartments(allocator);
    }

    pub fn getDepartmentMembers(self: *OrganizationService, allocator: std.mem.Allocator, department_id: []const u8) ![]model.DepartmentMember {
        return self.pers.getDepartmentMembers(allocator, department_id);
    }

    pub fn getUsersInDepartments(self: *OrganizationService, allocator: std.mem.Allocator, user_ids: []const []const u8) ![]model.DepartmentMember {
        return self.pers.getUsersInDepartments(allocator, user_ids);
    }

    pub fn getSubDepartmentsAndMembers(self: *OrganizationService, allocator: std.mem.Allocator, department_id: ?[]const u8) !model.DeptMemberAndSubDept {
        return self.pers.getSubDepartmentsAndMembers(allocator, department_id);
    }

    pub fn searchOrganizationUsers(self: *OrganizationService, allocator: std.mem.Allocator, keyword: []const u8, page: u32, size: u32) ![]model.DepartmentMember {
        return self.pers.searchOrganizationUsers(allocator, keyword, page, size);
    }
};
