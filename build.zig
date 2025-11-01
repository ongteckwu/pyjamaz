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
    exe.linkLibC();

    // Native decoder/encoder libraries (Milestone 3 complete!)
    exe.linkSystemLibrary("jpeg"); // libjpeg-turbo (decode + encode)
    exe.linkSystemLibrary("png"); // libpng (decode + encode)
    exe.linkSystemLibrary("webp"); // libwebp (decode + encode)
    exe.linkSystemLibrary("avif"); // libavif (AVIF decode + encode, wraps aom/dav1d)

    // Perceptual metrics
    exe.linkSystemLibrary("dssim"); // TODO: Replace for MIT licensing

    b.installArtifact(exe);

    // Shared library for Python/Node.js bindings
    // TODO: Switch to static linkage after verifying all codecs work standalone
    const lib = b.addLibrary(.{
        .name = "pyjamaz",
        .linkage = .dynamic, // Will change to .static after Phase 1 verification
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/api.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });
    lib.root_module.addImport("fssimu2", fssimu2_module);

    // Phase 1: Static linking for native codecs
    // Approach: Link .a files directly for maximum portability

    // Static libraries (from Homebrew) - using absolute paths
    lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/jpeg-turbo/lib/libjpeg.a" });
    lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/libpng/lib/libpng16.a" });
    lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/webp/lib/libwebp.a" });
    lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/webp/lib/libsharpyuv.a" }); // Required by libwebp
    lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/lib/libdssim.a" });

    // libavif: Keep dynamic for now (building from source is complex)
    // TODO: Bundle libavif.dylib in wheel/package, or build static version
    lib.linkSystemLibrary("avif");

    // Dependencies of static libraries
    lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/zlib/lib/libz.a" }); // Required by libpng

    // System frameworks (for libdssim which uses Accelerate framework on macOS)
    lib.linkFramework("Accelerate");

    lib.linkLibC();
    b.installArtifact(lib);

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
    unit_tests.linkSystemLibrary("png");
    unit_tests.linkSystemLibrary("webp");
    unit_tests.linkSystemLibrary("avif");
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
    integration_tests.linkSystemLibrary("png");
    integration_tests.linkSystemLibrary("webp");
    integration_tests.linkSystemLibrary("avif");
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
    conformance_exe.linkSystemLibrary("png");
    conformance_exe.linkSystemLibrary("webp");
    conformance_exe.linkSystemLibrary("avif");
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
    benchmark_exe.linkSystemLibrary("png");
    benchmark_exe.linkSystemLibrary("webp");
    benchmark_exe.linkSystemLibrary("avif");
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

    // Codec baseline benchmark (libvips performance)
    const codec_baseline_exe = b.addExecutable(.{
        .name = "codec_baseline",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/codec_baseline_root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    codec_baseline_exe.root_module.addImport("fssimu2", fssimu2_module);

    // Link C libraries for codec baseline
    codec_baseline_exe.linkSystemLibrary("vips");
    codec_baseline_exe.linkSystemLibrary("jpeg");
    codec_baseline_exe.linkSystemLibrary("png");
    codec_baseline_exe.linkSystemLibrary("webp");
    codec_baseline_exe.linkSystemLibrary("avif");
    codec_baseline_exe.linkSystemLibrary("dssim");
    codec_baseline_exe.linkLibC();

    b.installArtifact(codec_baseline_exe);

    const run_codec_baseline = b.addRunArtifact(codec_baseline_exe);
    run_codec_baseline.step.dependOn(b.getInstallStep());

    // Set environment variables
    run_codec_baseline.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
    run_codec_baseline.setEnvironmentVariable("VIPS_NOVECTOR", "1");

    const codec_baseline_step = b.step("benchmark-codec-baseline", "Benchmark current libvips codec performance");
    codec_baseline_step.dependOn(&run_codec_baseline.step);

    // Memory tests (Zig)
    const memory_tests = b.addTest(.{
        .name = "memory-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/memory_test_root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    memory_tests.root_module.addImport("fssimu2", fssimu2_module);

    // Link C libraries for memory tests
    memory_tests.linkSystemLibrary("vips");
    memory_tests.linkSystemLibrary("jpeg");
    memory_tests.linkSystemLibrary("png");
    memory_tests.linkSystemLibrary("webp");
    memory_tests.linkSystemLibrary("avif");
    memory_tests.linkSystemLibrary("dssim");
    memory_tests.linkLibC();

    const run_memory_tests = b.addRunArtifact(memory_tests);

    // Set environment variables for vips
    run_memory_tests.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
    run_memory_tests.setEnvironmentVariable("VIPS_NOVECTOR", "1");

    // Memory test step for Zig only (quick)
    const memory_test_zig_step = b.step("memory-test-zig", "Run Zig memory tests (~1 min)");
    memory_test_zig_step.dependOn(&run_memory_tests.step);

    // Memory test step for all (Zig only by default, bindings are optional)
    const memory_test_all_step = b.step("memory-test", "Run Zig memory tests (~1 min)");
    memory_test_all_step.dependOn(&run_memory_tests.step);

    // Note: Node.js and Python memory tests are available in:
    // - bindings/nodejs/tests/memory/
    // - bindings/python/tests/memory/
    // Run them manually after setting up the respective environments.
    // See docs/MEMORY_TESTS.md for details.
}
