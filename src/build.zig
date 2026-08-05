const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add zigmodu dependency
    const zigmodu_dep = b.dependency("zigmodu", .{
        .target = target,
        .optimize = optimize,
    });

    // Translate libpq C header -> Zig module (Zig 0.17 removed the @cImport builtin)
    const pg_translate = b.addTranslateC(.{
        .root_source_file = b.path("modules/db_postgres/libpq_include.h"),
        .target = target,
        .optimize = optimize,
    });
    pg_translate.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/libpq/include" });
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

    // Import zigmodu
    exe.root_module.addImport("zigmodu", zigmodu_dep.module("zigmodu"));
    exe.root_module.addImport("libpq", libpq_mod);

    // Import core infrastructure module
    const core_module = b.createModule(.{
        .root_source_file = b.path("core.zig"),
    });
    core_module.addImport("zigmodu", zigmodu_dep.module("zigmodu"));
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
    tests_mod.addImport("zigmodu", zigmodu_dep.module("zigmodu"));
    tests_mod.addImport("libpq", libpq_mod);
    tests_mod.addImport("core", core_module);
    tests_mod.addImport("protobuf", proto_module);
    tests_mod.addImport("sdkws", sdkws_module);
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
    bench_mod.addImport("zigmodu", zigmodu_dep.module("zigmodu"));
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
