const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "pyjamaz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // C library dependencies
    // libvips is now required for Phase 3
    exe.linkSystemLibrary("vips");
    exe.linkLibC();

    // Phase 4: Codecs
    exe.linkSystemLibrary("jpeg"); // libjpeg-turbo or mozjpeg
    // exe.linkSystemLibrary("png");
    // exe.linkSystemLibrary("webp");

    b.installArtifact(exe);

    // Run step (for `zig build run`)
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Unit tests (inline tests in source files)
    const unit_tests = b.addTest(.{
        .name = "unit-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link C libraries for tests too
    unit_tests.linkSystemLibrary("vips");
    unit_tests.linkSystemLibrary("jpeg");
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
