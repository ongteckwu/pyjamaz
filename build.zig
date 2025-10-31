const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // v0.5.0: SSIMULACRA2 dependency
    const fssimu2_dep = b.dependency("fssimu2", .{
        .target = target,
        .optimize = optimize,
    });
    const fssimu2_module = fssimu2_dep.module("fssimu2");

    // Main executable
    const exe = b.addExecutable(.{
        .name = "pyjamaz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("fssimu2", fssimu2_module);

    // C library dependencies
    // libvips is now required for Phase 3
    exe.linkSystemLibrary("vips");
    exe.linkLibC();

    // Phase 4: Codecs
    exe.linkSystemLibrary("jpeg"); // libjpeg-turbo or mozjpeg
    // exe.linkSystemLibrary("png");
    // exe.linkSystemLibrary("webp");

    // v0.4.0: Perceptual metrics
    exe.linkSystemLibrary("dssim");

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
    unit_tests.root_module.addImport("fssimu2", fssimu2_module);

    // Link C libraries for tests too
    unit_tests.linkSystemLibrary("vips");
    unit_tests.linkSystemLibrary("jpeg");
    unit_tests.linkSystemLibrary("dssim");
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Set environment variables for vips
    run_unit_tests.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0"); // Disable disc caching
    run_unit_tests.setEnvironmentVariable("VIPS_NOVECTOR", "1"); // Disable vectorization

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests (from src/test/integration/)
    const integration_tests = b.addTest(.{
        .name = "integration-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    integration_tests.root_module.addImport("fssimu2", fssimu2_module);

    // Link C libraries for integration tests
    integration_tests.linkSystemLibrary("vips");
    integration_tests.linkSystemLibrary("jpeg");
    integration_tests.linkSystemLibrary("dssim");
    integration_tests.linkLibC();

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Set environment variables for vips
    run_integration_tests.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
    run_integration_tests.setEnvironmentVariable("VIPS_NOVECTOR", "1");

    const test_integration_step = b.step("test-integration", "Run integration tests");
    test_integration_step.dependOn(&run_integration_tests.step);

    // Conformance testing
    const conformance_exe = b.addExecutable(.{
        .name = "conformance",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/conformance_root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    conformance_exe.root_module.addImport("fssimu2", fssimu2_module);

    // Link C libraries for conformance tests
    conformance_exe.linkSystemLibrary("vips");
    conformance_exe.linkSystemLibrary("jpeg");
    conformance_exe.linkSystemLibrary("dssim");
    conformance_exe.linkLibC();

    b.installArtifact(conformance_exe);

    const run_conformance = b.addRunArtifact(conformance_exe);
    run_conformance.step.dependOn(b.getInstallStep());

    // Set environment variables
    run_conformance.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
    run_conformance.setEnvironmentVariable("VIPS_NOVECTOR", "1");

    const conformance_step = b.step("conformance", "Run conformance tests on testdata/");
    conformance_step.dependOn(&run_conformance.step);

    // Benchmark executable (v0.2.0: Parallel optimization)
    const benchmark_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark_root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    benchmark_exe.root_module.addImport("fssimu2", fssimu2_module);

    // Link C libraries for benchmarks
    benchmark_exe.linkSystemLibrary("vips");
    benchmark_exe.linkSystemLibrary("jpeg");
    benchmark_exe.linkSystemLibrary("dssim");
    benchmark_exe.linkLibC();

    b.installArtifact(benchmark_exe);

    const run_benchmark = b.addRunArtifact(benchmark_exe);
    run_benchmark.step.dependOn(b.getInstallStep());

    // Set environment variables
    run_benchmark.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
    run_benchmark.setEnvironmentVariable("VIPS_NOVECTOR", "1");

    const benchmark_step = b.step("benchmark", "Run parallel encoding performance benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);
}
