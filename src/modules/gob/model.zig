pub const GeneralWsReq = struct {
    req_identifier: i32 = 0,
    token: []const u8 = &.{},
    send_id: []const u8 = &.{},
    operation_id: []const u8 = &.{},
    msg_incr: []const u8 = &.{},
    data: []const u8 = &.{},
};

pub const GeneralWsResp = struct {
    req_identifier: i32 = 0,
    err_code: i32 = 0,
    err_msg: []const u8 = &.{},
    msg_incr: []const u8 = &.{},
    operation_id: []const u8 = &.{},
    data: []const u8 = &.{},
};
