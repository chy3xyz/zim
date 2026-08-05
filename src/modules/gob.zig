const model = @import("gob/model.zig");
const service = @import("gob/service.zig");

// Re-export models
pub const GeneralWsReq = model.GeneralWsReq;
pub const GeneralWsResp = model.GeneralWsResp;

// Re-export service functions
pub const encodeReq = service.encodeReq;
pub const encodeResp = service.encodeResp;
pub const decodeReq = service.decodeReq;
pub const decodeResp = service.decodeResp;
pub const freeReq = service.freeReq;
pub const freeResp = service.freeResp;
