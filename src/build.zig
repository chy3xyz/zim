const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add zmodu dependency (formerly zmodu)
    const zmodu_dep = b.dependency("zmodu", .{
        .target = target,
        .optimize = optimize,
    });

    // Add zent dependency (ORM layer, PostgreSQL via libpq)
    const zent_dep = b.dependency("zent", .{
        .target = target,
        .optimize = optimize,
    });

    // Translate libpq C header -> Zig module (Zig 0.17 removed the @cImport builtin).
    // Include dir discovery mirrors zent/build.zig: pg_config first (Linux
    // distros, Homebrew Postgres), Homebrew keg fallback second — no hardcoded
    // machine-specific path.
    const pg_translate = b.addTranslateC(.{
        .root_source_file = b.path("modules/db_postgres/libpq_include.h"),
        .target = target,
        .optimize = optimize,
    });
    if (discoverLibpqIncludeDir(b)) |inc| {
        pg_translate.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    const libpq_mod = pg_translate.createModule();

    // Create executable
    const exe = b.addExecutable(.{
        .name = "zim",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("main.zig"),
        }),
    });

    // Import zmodu
    exe.root_module.addImport("zmodu", zmodu_dep.module("zmodu"));
    exe.root_module.addImport("libpq", libpq_mod);
    exe.root_module.addImport("zent", zent_dep.module("zent"));

    // Import core infrastructure module
    const core_module = b.createModule(.{
        .root_source_file = b.path("core.zig"),
    });
    core_module.addImport("zmodu", zmodu_dep.module("zmodu"));
    exe.root_module.addImport("core", core_module);

    // Import protobuf codec
    const proto_module = b.createModule(.{
        .root_source_file = b.path("proto/protobuf.zig"),
    });
    exe.root_module.addImport("protobuf", proto_module);

    const sdkws_module = b.createModule(.{
        .root_source_file = b.path("proto/sdkws.zig"),
    });
    exe.root_module.addImport("sdkws", sdkws_module);

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // b.args removed in Zig 0.17-dev; args are passed via the run step directly.
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step — protobuf codec
    const proto_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("proto/protobuf.zig"),
        }),
    });

    // Test step — core infrastructure + gateway HTTP contract (Testkit)
    const tests_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("tests.zig"),
    });
    tests_mod.addImport("zmodu", zmodu_dep.module("zmodu"));
    tests_mod.addImport("libpq", libpq_mod);
    tests_mod.addImport("core", core_module);
    tests_mod.addImport("protobuf", proto_module);
    tests_mod.addImport("sdkws", sdkws_module);
    tests_mod.addImport("zent", zent_dep.module("zent"));
    const tests_tests = b.addTest(.{ .root_module = tests_mod });

    const test_step = b.step("test", "Run unit tests");
    // Zig 0.15+ caches `Run` steps by default — tests must always execute,
    // otherwise CI gets a false "cached" pass without running them.
    const run_proto = b.addRunArtifact(proto_tests);
    run_proto.has_side_effects = true;
    const run_tests = b.addRunArtifact(tests_tests);
    run_tests.has_side_effects = true;
    test_step.dependOn(&run_proto.step);
    test_step.dependOn(&run_tests.step);

    // Bench executable — in-process load benchmark (needs PostgreSQL)
    const bench_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("bench.zig"),
    });
    bench_mod.addImport("zmodu", zmodu_dep.module("zmodu"));
    bench_mod.addImport("libpq", libpq_mod);
    bench_mod.addImport("core", core_module);
    bench_mod.addImport("protobuf", proto_module);
    bench_mod.addImport("sdkws", sdkws_module);
    const bench_exe = b.addExecutable(.{ .name = "zim-bench", .root_module = bench_mod });
    const bench_run = b.addRunArtifact(bench_exe);
    bench_run.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run in-process benchmark (needs PostgreSQL)");
    bench_step.dependOn(&bench_run.step);
}

// ── libpq include-dir discovery ─────────────────────────────────
// Same strategy as zent/build.zig: pg_config (Linux distros, Homebrew
// Postgres), then the Homebrew keg fallback. Returns null when nothing is
// found so configure still succeeds on exotic setups (compile fails later
// with a clear libpq-fe.h error instead).
fn discoverLibpqIncludeDir(b: *std.Build) ?[]const u8 {
    if (execOutput(b, &.{ "pg_config", "--includedir" })) |inc| {
        const header = std.fs.path.join(b.allocator, &.{ inc, "libpq-fe.h" }) catch return null;
        if (pathExists(b, header)) return inc;
    }
    // `libpq` is the keg-only brew formula; postgresql@N keeps the header
    // under a versioned prefix (plain or `<prefix>/postgresql/` subdir).
    const versions = [_][]const u8{ "postgresql@18", "postgresql@17", "postgresql@16", "postgresql@15", "postgresql@14", "postgresql", "libpq" };
    const homes = [_][]const u8{ "/opt/homebrew/opt", "/usr/local/opt" };
    for (homes) |home| {
        for (versions) |pkg| {
            const versioned = b.fmt("{s}/{s}/include/{s}/libpq-fe.h", .{ home, pkg, pkg });
            const plain = b.fmt("{s}/{s}/include/libpq-fe.h", .{ home, pkg });
            const header = if (pathExists(b, versioned)) versioned else if (pathExists(b, plain)) plain else continue;
            return std.fs.path.dirname(header).?;
        }
    }
    return null;
}

fn execOutput(b: *std.Build, argv: []const []const u8) ?[]const u8 {
    const result = std.process.run(b.allocator, b.graph.io, .{ .argv = argv }) catch return null;
    if (!result.term.success()) return null;
    return std.mem.trim(u8, result.stdout, " \n\r\t");
}

fn pathExists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(b.graph.io, path, .{}) catch return false;
    return true;
}
