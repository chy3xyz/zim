const zmodu = @import("zmodu");
const core = @import("core");

// Re-export event types from core (zmodu-native TypedEventBus integration)
pub const EventType = core.EventType;
pub const Event = core.Event;
pub const EventHandler = core.EventHandler;

pub const info = zmodu.api.Module{
    .name = "event_bus",
    .description = "Event-driven communication module (backed by core infrastructure)",
    .dependencies = &.{},
};

pub fn init() !void {
    // EventBus is initialized by core.init()
    core.logInfo("EventBusModule initialized (via core)", .{});
}

pub fn deinit() void {
    // EventBus is deinitialized by core.deinit()
}

// Re-export the global event bus from core infrastructure
pub const getEventBus = core.getEventBus;
