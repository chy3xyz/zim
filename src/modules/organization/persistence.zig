const std = @import("std");
const db_mod = @import("../../modules/db_postgres.zig");
const model = @import("model.zig");

pub const OrganizationPersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) OrganizationPersistence {
        return OrganizationPersistence{
            .allocator = allocator,
            .db = db,
        };
    }

    pub fn deinit(self: *OrganizationPersistence) void {
        _ = self;
    }

    pub fn getOrganization(self: *OrganizationPersistence) !?model.Organization {
        const sql = "SELECT id, logo_url, name, homepage, introduction, EXTRACT(EPOCH FROM create_time)::bigint FROM organizations LIMIT 1";
        const result = self.db.query(sql) catch return null;
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        if (result.row_count == 0) return null;

        const row = result.rows[0];
        return model.Organization{
            .id = try self.allocator.dupe(u8, row[0]),
            .logo_url = try self.allocator.dupe(u8, row[1]),
            .name = try self.allocator.dupe(u8, row[2]),
            .homepage = try self.allocator.dupe(u8, row[3]),
            .introduction = try self.allocator.dupe(u8, row[4]),
            .create_time = try std.fmt.parseInt(i64, row[5], 10),
        };
    }

    pub fn getDepartments(self: *OrganizationPersistence, allocator: std.mem.Allocator, department_ids: ?[]const []const u8) ![]model.Department {
        if (department_ids) |ids| {
            if (ids.len > 0) {
                const sql = "SELECT department_id, name, face_url, parent_department_id, order_val, EXTRACT(EPOCH FROM create_time)::bigint, (SELECT COUNT(*) FROM departments WHERE parent_department_id = d.department_id), (SELECT COUNT(*) FROM department_members WHERE department_id = d.department_id) FROM departments d WHERE department_id = ANY($1) ORDER BY order_val";
                const params = &[_]db_mod.QueryParam{.{ .string_array = ids }};
                const result = self.db.queryParams(sql, params) catch return &[_]model.Department{};
                defer {
                    for (result.rows) |row| {
                        _ = self.allocator.free(row);
                    }
                    _ = self.allocator.free(result.rows);
                }
                var list = std.ArrayList(model.Department).empty;
                defer list.deinit(allocator);
                for (result.rows) |row| {
                    try list.append(allocator, model.Department{
                        .department_id = try allocator.dupe(u8, row[0]),
                        .name = try allocator.dupe(u8, row[1]),
                        .face_url = try allocator.dupe(u8, row[2]),
                        .parent_department_id = try allocator.dupe(u8, row[3]),
                        .order = try std.fmt.parseInt(i32, row[4], 10),
                        .create_time = try std.fmt.parseInt(i64, row[5], 10),
                        .sub_department_num = try std.fmt.parseInt(i32, row[6], 10),
                        .member_num = try std.fmt.parseInt(i32, row[7], 10),
                    });
                }
                return list.toOwnedSlice(allocator);
            }
        }
        const sql = "SELECT department_id, name, face_url, parent_department_id, order_val, EXTRACT(EPOCH FROM create_time)::bigint FROM departments ORDER BY order_val";
        const result = self.db.query(sql) catch return &[_]model.Department{};
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.Department).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.Department{
                .department_id = try allocator.dupe(u8, row[0]),
                .name = try allocator.dupe(u8, row[1]),
                .face_url = try allocator.dupe(u8, row[2]),
                .parent_department_id = try allocator.dupe(u8, row[3]),
                .order = try std.fmt.parseInt(i32, row[4], 10),
                .create_time = try std.fmt.parseInt(i64, row[5], 10),
                .sub_department_num = try std.fmt.parseInt(i32, row[6], 10),
                .member_num = try std.fmt.parseInt(i32, row[7], 10),
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getAllDepartments(self: *OrganizationPersistence, allocator: std.mem.Allocator) ![]model.Department {
        return self.getDepartments(allocator, null);
    }

    pub fn getDepartmentMembers(self: *OrganizationPersistence, allocator: std.mem.Allocator, department_id: []const u8) ![]model.DepartmentMember {
        const sql = "SELECT dm.user_id, dm.department_id, d.name, u.nickname, u.face_url, dm.position, dm.station, dm.order_val, " ++
            "EXTRACT(EPOCH FROM dm.entry_time)::bigint, EXTRACT(EPOCH FROM dm.termination_time)::bigint " ++
            "FROM department_members dm JOIN users u ON dm.user_id = u.user_id JOIN departments d ON dm.department_id = d.department_id " ++
            "WHERE dm.department_id = $1 ORDER BY dm.order_val";
        const params = &[_]db_mod.QueryParam{.{ .string = department_id }};
        const result = self.db.queryParams(sql, params) catch return &[_]model.DepartmentMember{};
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.DepartmentMember).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.DepartmentMember{
                .user_id = try allocator.dupe(u8, row[0]),
                .department_id = try allocator.dupe(u8, row[1]),
                .department_name = try allocator.dupe(u8, row[2]),
                .nickname = try allocator.dupe(u8, row[3]),
                .face_url = try allocator.dupe(u8, row[4]),
                .position = try allocator.dupe(u8, row[5]),
                .station = try allocator.dupe(u8, row[6]),
                .order = try std.fmt.parseInt(i32, row[7], 10),
                .entry_time = if (row[8].len > 0) try std.fmt.parseInt(i64, row[8], 10) else null,
                .termination_time = if (row[9].len > 0) try std.fmt.parseInt(i64, row[9], 10) else null,
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getUsersInDepartments(self: *OrganizationPersistence, allocator: std.mem.Allocator, user_ids: []const []const u8) ![]model.DepartmentMember {
        if (user_ids.len == 0) return &[_]model.DepartmentMember{};

        const sql = "SELECT dm.user_id, dm.department_id, d.name, u.nickname, u.face_url, dm.position, dm.station, dm.order_val, " ++
            "EXTRACT(EPOCH FROM dm.entry_time)::bigint, EXTRACT(EPOCH FROM dm.termination_time)::bigint " ++
            "FROM department_members dm JOIN users u ON dm.user_id = u.user_id JOIN departments d ON dm.department_id = d.department_id " ++
            "WHERE dm.user_id = ANY($1) ORDER BY dm.order_val";
        const params = &[_]db_mod.QueryParam{.{ .string_array = user_ids }};
        const result = self.db.queryParams(sql, params) catch return &[_]model.DepartmentMember{};
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.DepartmentMember).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.DepartmentMember{
                .user_id = try allocator.dupe(u8, row[0]),
                .department_id = try allocator.dupe(u8, row[1]),
                .department_name = try allocator.dupe(u8, row[2]),
                .nickname = try allocator.dupe(u8, row[3]),
                .face_url = try allocator.dupe(u8, row[4]),
                .position = try allocator.dupe(u8, row[5]),
                .station = try allocator.dupe(u8, row[6]),
                .order = try std.fmt.parseInt(i32, row[7], 10),
                .entry_time = if (row[8].len > 0) try std.fmt.parseInt(i64, row[8], 10) else null,
                .termination_time = if (row[9].len > 0) try std.fmt.parseInt(i64, row[9], 10) else null,
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getSubDepartmentsAndMembers(self: *OrganizationPersistence, allocator: std.mem.Allocator, department_id: ?[]const u8) !model.DeptMemberAndSubDept {
        const dept_id = if (department_id) |id| if (id.len > 0) id else "dept_root" else "dept_root";

        // Get department
        const dept_sql = "SELECT department_id, name, face_url, parent_department_id, order_val, EXTRACT(EPOCH FROM create_time)::bigint FROM departments WHERE department_id = $1";
        const dept_params = &[_]db_mod.QueryParam{.{ .string = dept_id }};
        const dept_result = self.db.queryParams(dept_sql, dept_params) catch {
            return model.DeptMemberAndSubDept{
                .department = model.Department{
                    .department_id = try allocator.dupe(u8, dept_id),
                    .name = try allocator.dupe(u8, ""),
                    .face_url = try allocator.dupe(u8, ""),
                    .parent_department_id = try allocator.dupe(u8, ""),
                    .order = 0,
                    .create_time = 0,
                    .sub_department_num = 0,
                    .member_num = 0,
                },
                .members = &[_]model.DepartmentMember{},
                .sub_departments = &[_]model.Department{},
                .parents = &[_]model.Department{},
            };
        };
        defer {
            for (dept_result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(dept_result.rows);
        }

        const department = if (dept_result.row_count > 0) blk: {
            const row = dept_result.rows[0];
            break :blk model.Department{
                .department_id = try allocator.dupe(u8, row[0]),
                .name = try allocator.dupe(u8, row[1]),
                .face_url = try allocator.dupe(u8, row[2]),
                .parent_department_id = try allocator.dupe(u8, row[3]),
                .order = try std.fmt.parseInt(i32, row[4], 10),
                .create_time = try std.fmt.parseInt(i64, row[5], 10),
                .sub_department_num = try std.fmt.parseInt(i32, row[6], 10),
                .member_num = try std.fmt.parseInt(i32, row[7], 10),
            };
        } else model.Department{
            .department_id = try allocator.dupe(u8, dept_id),
            .name = try allocator.dupe(u8, ""),
            .face_url = try allocator.dupe(u8, ""),
            .parent_department_id = try allocator.dupe(u8, ""),
            .order = 0,
            .create_time = 0,
            .sub_department_num = 0,
            .member_num = 0,
        };

        // Get members
        const members = self.getDepartmentMembers(allocator, dept_id) catch &[_]model.DepartmentMember{};

        // Get sub departments
        const sub_sql = "SELECT department_id, name, face_url, parent_department_id, order_val, EXTRACT(EPOCH FROM create_time)::bigint FROM departments WHERE parent_department_id = $1 ORDER BY order_val";
        const sub_params = &[_]db_mod.QueryParam{.{ .string = dept_id }};
        const sub_result = self.db.queryParams(sub_sql, sub_params) catch {
            return model.DeptMemberAndSubDept{
                .department = department,
                .members = members,
                .sub_departments = &[_]model.Department{},
                .parents = &[_]model.Department{},
            };
        };
        defer {
            for (sub_result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(sub_result.rows);
        }

        var sub_list = std.ArrayList(model.Department).empty;
        defer sub_list.deinit(allocator);

        for (sub_result.rows) |row| {
            try sub_list.append(allocator, model.Department{
                .department_id = try allocator.dupe(u8, row[0]),
                .name = try allocator.dupe(u8, row[1]),
                .face_url = try allocator.dupe(u8, row[2]),
                .parent_department_id = try allocator.dupe(u8, row[3]),
                .order = try std.fmt.parseInt(i32, row[4], 10),
                .create_time = try std.fmt.parseInt(i64, row[5], 10),
                .sub_department_num = try std.fmt.parseInt(i32, row[6], 10),
                .member_num = try std.fmt.parseInt(i32, row[7], 10),
            });
        }

        // Get parent departments
        var parent_list = std.ArrayList(model.Department).empty;
        defer parent_list.deinit(allocator);

        var current_parent_id = department.parent_department_id;
        while (current_parent_id.len > 0 and !std.mem.eql(u8, current_parent_id, "")) {
            const parent_sql = "SELECT department_id, name, face_url, parent_department_id, order_val, EXTRACT(EPOCH FROM create_time)::bigint FROM departments WHERE department_id = $1";
            const parent_params = &[_]db_mod.QueryParam{.{ .string = current_parent_id }};
            const parent_result = self.db.queryParams(parent_sql, parent_params) catch break;
            defer {
                for (parent_result.rows) |row| {
                    _ = self.allocator.free(row);
                }
                _ = self.allocator.free(parent_result.rows);
            }

            if (parent_result.row_count > 0) {
                const row = parent_result.rows[0];
                try parent_list.append(allocator, model.Department{
                    .department_id = try allocator.dupe(u8, row[0]),
                    .name = try allocator.dupe(u8, row[1]),
                    .face_url = try allocator.dupe(u8, row[2]),
                    .parent_department_id = try allocator.dupe(u8, row[3]),
                    .order = try std.fmt.parseInt(i32, row[4], 10),
                    .create_time = try std.fmt.parseInt(i64, row[5], 10),
                    .sub_department_num = try std.fmt.parseInt(i32, row[6], 10),
                    .member_num = try std.fmt.parseInt(i32, row[7], 10),
                });
                current_parent_id = row[3];
            } else {
                break;
            }
        }

        return model.DeptMemberAndSubDept{
            .department = department,
            .members = members,
            .sub_departments = try sub_list.toOwnedSlice(allocator),
            .parents = try parent_list.toOwnedSlice(allocator),
        };
    }

    pub fn searchOrganizationUsers(self: *OrganizationPersistence, allocator: std.mem.Allocator, keyword: []const u8, page: u32, size: u32) ![]model.DepartmentMember {
        const offset = (if (page > 0) page - 1 else 0) * size;
        const sql = "SELECT dm.user_id, dm.department_id, d.name, u.nickname, u.face_url, dm.position, dm.station, dm.order_val, " ++
            "EXTRACT(EPOCH FROM dm.entry_time)::bigint, EXTRACT(EPOCH FROM dm.termination_time)::bigint " ++
            "FROM department_members dm JOIN users u ON dm.user_id = u.user_id JOIN departments d ON dm.department_id = d.department_id " ++
            "WHERE u.nickname LIKE '%' || $1 || '%' ORDER BY dm.order_val LIMIT $2 OFFSET $3";
        const params = &[_]db_mod.QueryParam{
            .{ .string = keyword },
            .{ .int = size },
            .{ .int = offset },
        };
        const result = self.db.queryParams(sql, params) catch return &[_]model.DepartmentMember{};
        defer {
            for (result.rows) |row| {
                _ = self.allocator.free(row);
            }
            _ = self.allocator.free(result.rows);
        }

        var list = std.ArrayList(model.DepartmentMember).empty;
        defer list.deinit(allocator);

        for (result.rows) |row| {
            try list.append(allocator, model.DepartmentMember{
                .user_id = try allocator.dupe(u8, row[0]),
                .department_id = try allocator.dupe(u8, row[1]),
                .department_name = try allocator.dupe(u8, row[2]),
                .nickname = try allocator.dupe(u8, row[3]),
                .face_url = try allocator.dupe(u8, row[4]),
                .position = try allocator.dupe(u8, row[5]),
                .station = try allocator.dupe(u8, row[6]),
                .order = try std.fmt.parseInt(i32, row[7], 10),
                .entry_time = if (row[8].len > 0) try std.fmt.parseInt(i64, row[8], 10) else null,
                .termination_time = if (row[9].len > 0) try std.fmt.parseInt(i64, row[9], 10) else null,
            });
        }
        return list.toOwnedSlice(allocator);
    }
};
