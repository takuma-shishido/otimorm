const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const otimorm_module = b.addModule("otimorm", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/otimorm.zig"),
    });

    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    otimorm_module.addImport("pg", pg.module("pg"));

    const debug_log = b.option(bool, "debug_log", "") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "debug_log", debug_log);

    otimorm_module.addOptions("build_options", build_options);

    const lib_test = b.addTest(.{
        .root_source_file = b.path("src/otimorm.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_test.root_module.addImport("pg", pg.module("pg"));

    const run_test = b.addRunArtifact(lib_test);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_test.step);
}
