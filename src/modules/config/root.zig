const std = @import("std");
const core = @import("core");
const zigmodu = @import("zigmodu");
const service = @import("service.zig");
const model = @import("model.zig");

pub const info = zigmodu.api.Module{
    .name = "config",
    .description = "Configuration loading module",
    .dependencies = &.{},
};

var global_config: model.Config = undefined;
var config_loaded: bool = false;
var g_config_mutex: std.atomic.Mutex = .unlocked;

fn lockConfig() void {
    while (!g_config_mutex.tryLock()) std.atomic.spinLoopHint();
}

pub fn init() !void {
    service.initConfigAllocations(core.getGlobalAllocator());
    // zigmodu YamlParser-backed loader (fallback: defaults)
    global_config = service.ConfigService.loadConfig(core.getGlobalAllocator()) catch service.ConfigService.defaultConfig();
    config_loaded = true;
    std.log.info("ConfigModule initialized (config.yaml via zigmodu YamlParser)", .{});
}

pub fn deinit() void {
    service.deinitConfigAllocations(core.getGlobalAllocator());
    config_loaded = false;
    std.log.info("ConfigModule deinitialized", .{});
}

pub fn getConfig() model.Config {
    lockConfig();
    defer g_config_mutex.unlock();
    if (!config_loaded) {
        global_config = service.ConfigService.defaultConfig();
        config_loaded = true;
    }
    return global_config;
}

/// Hot-reload config.yaml. Values read dynamically at call time (webhook
/// filters, log path, etc.) take effect immediately; connection pools and
/// ports still require a restart. Parse failure falls back to defaults.
pub fn reload() void {
    lockConfig();
    defer g_config_mutex.unlock();
    service.deinitConfigAllocations(core.getGlobalAllocator());
    service.initConfigAllocations(core.getGlobalAllocator());
    global_config = service.ConfigService.loadConfig(core.getGlobalAllocator()) catch service.ConfigService.defaultConfig();
    config_loaded = true;
    core.logInfo("ConfigModule reloaded", .{});
}

const config_paths = [_][]const u8{ "config/config.yaml", "../config/config.yaml" };

/// mtime of the config file (null if unreadable) — for change detection.
pub fn configFileMtime(io: std.Io) ?i128 {
    const dir = std.Io.Dir.cwd();
    for (config_paths) |path| {
        const st = dir.statFile(io, path, .{}) catch continue;
        return st.mtime.nanoseconds;
    }
    return null;
}
