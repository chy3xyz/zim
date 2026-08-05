pub const Organization = struct {
    id: []const u8,
    logo_url: []const u8,
    name: []const u8,
    homepage: []const u8,
    introduction: []const u8,
    create_time: i64,
};

pub const Department = struct {
    department_id: []const u8,
    name: []const u8,
    face_url: []const u8,
    parent_department_id: []const u8,
    order: i32,
    create_time: i64,
    sub_department_num: i32,
    member_num: i32,
};

pub const DepartmentMember = struct {
    user_id: []const u8,
    department_id: []const u8,
    department_name: []const u8,
    nickname: []const u8,
    face_url: []const u8,
    position: []const u8,
    station: []const u8,
    order: i32,
    entry_time: ?i64,
    termination_time: ?i64,
};

pub const DeptMemberAndSubDept = struct {
    department: Department,
    members: []const DepartmentMember,
    sub_departments: []const Department,
    parents: []const Department,
};
