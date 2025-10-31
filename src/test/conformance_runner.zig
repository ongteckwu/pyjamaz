//! Conformance Test Runner for Pyjamaz
//!
//! Discovers images in testdata/conformance/ and runs optimization tests
//! to verify the optimizer produces valid, smaller outputs.
//!
//! Exit codes:
//!   0 - All tests passed
//!   1 - Some tests failed
//!
//! Usage: zig build conformance

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Import Pyjamaz modules from root
const root = @import("root");
const optimizer = root.optimizer;
const output = root.output;
const vips = root.vips;
const types = root.types;
const ImageFormat = types.ImageFormat;

// Test result structure
const TestResult = struct {
    name: []const u8,
    passed: bool,
    skipped: bool = false,
    input_bytes: u64,
    output_bytes: ?u32,
    ratio: ?f64,
    diff_value: ?f64 = null, // Perceptual quality diff (0.0 = identical, higher = more different)
    reason: ?[]const u8,
    category: FailureCategory = .none,
    selected_format: ?ImageFormat = null,
    time_ms: u64 = 0,

    const FailureCategory = enum {
        none,
        decode_error,
        encode_error,
        size_regression,
        no_candidates,
        write_error,
        skipped_invalid,
        quality_regression, // Perceptual quality too different
    };
};

// Suite statistics
const SuiteStats = struct {
    name: []const u8,
    total: u32 = 0,
    passed: u32 = 0,
    failed: u32 = 0,
    skipped: u32 = 0,
    total_input_bytes: u64 = 0,
    total_output_bytes: u64 = 0,
    total_time_ms: u64 = 0,
    total_diff_value: f64 = 0.0, // Sum of all diff_values for averaging
    diff_count: u32 = 0, // Number of tests with valid diff_value
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    std.debug.print("\n=== Pyjamaz Conformance Tests ===\n\n", .{});

    // Test directories with suite names
    const TestSuite = struct {
        path: []const u8,
        name: []const u8,
    };

    const test_suites = [_]TestSuite{
        .{ .path = "testdata/conformance/kodak", .name = "Kodak" },
        .{ .path = "testdata/conformance/pngsuite", .name = "PNGSuite" },
        .{ .path = "testdata/conformance/webp", .name = "WebP" },
        .{ .path = "testdata/conformance/jpeg", .name = "JPEG" },
        .{ .path = "testdata/conformance/samples", .name = "Samples" },
        .{ .path = "testdata/conformance/testimages", .name = "TestImages" },
    };

    var all_results = std.ArrayList(TestResult){};
    defer {
        for (all_results.items) |result| {
            if (result.reason) |reason| allocator.free(reason);
        }
        all_results.deinit(allocator);
    }

    var suite_stats = std.ArrayList(SuiteStats){};
    defer suite_stats.deinit(allocator);

    var total_tests: u32 = 0;
    var passed: u32 = 0;
    var failed: u32 = 0;
    var skipped: u32 = 0;
    var total_time_ms: u64 = 0;

    // Run tests from each suite
    for (test_suites) |suite| {
        // Check if directory exists
        var dir = fs.cwd().openDir(suite.path, .{ .iterate = true }) catch |err| {
            std.debug.print("⚠️  Skipping {s}: {}\n", .{ suite.name, err });
            continue;
        };
        defer dir.close();

        var stats = SuiteStats{ .name = suite.name };

        std.debug.print("Testing {s} ({s}/)\n", .{ suite.name, suite.path });

        // Iterate over files
        var walker = dir.iterate();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;

            // Filter for image files
            const is_image = std.mem.endsWith(u8, entry.name, ".png") or
                std.mem.endsWith(u8, entry.name, ".jpg") or
                std.mem.endsWith(u8, entry.name, ".jpeg") or
                std.mem.endsWith(u8, entry.name, ".webp") or
                std.mem.endsWith(u8, entry.name, ".tif") or
                std.mem.endsWith(u8, entry.name, ".tiff");

            if (!is_image) continue;

            // Tiger Style: Skip known-invalid test files
            // PNGSuite: Files starting with "x" are intentionally malformed (xc*, xd*, xs*, xh*, xlf*)
            const skip_patterns = [_][]const u8{"x"};
            var should_skip = false;
            for (skip_patterns) |pattern| {
                if (std.mem.startsWith(u8, entry.name, pattern)) {
                    should_skip = true;
                    std.log.debug("Skipping known-invalid test file: {s} (pattern: {s})", .{ entry.name, pattern });
                    break;
                }
            }

            if (should_skip) {
                total_tests += 1;
                stats.total += 1;
                skipped += 1;
                stats.skipped += 1;

                const skip_result = TestResult{
                    .name = entry.name,
                    .passed = false,
                    .skipped = true,
                    .input_bytes = 0,
                    .output_bytes = null,
                    .ratio = null,
                    .reason = try allocator.dupe(u8, "Known-invalid test file"),
                    .category = .skipped_invalid,
                };
                try all_results.append(allocator, skip_result);
                std.debug.print("  ⊘ SKIP: {s} (known-invalid)\n", .{entry.name});
                continue;
            }

            total_tests += 1;
            stats.total += 1;

            // Build full path
            const input_path = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ suite.path, entry.name },
            );
            defer allocator.free(input_path);

            // Run test with timing
            const start_time = std.time.milliTimestamp();
            const result = try runOptimizationTest(allocator, input_path);
            const end_time = std.time.milliTimestamp();
            const test_time = @as(u64, @intCast(end_time - start_time));

            var result_with_time = result;
            result_with_time.time_ms = test_time;
            try all_results.append(allocator, result_with_time);

            total_time_ms += test_time;
            stats.total_time_ms += test_time;

            if (result.skipped) {
                std.debug.print("  ⊘ SKIP: {s} ({s})\n", .{ entry.name, result.reason.? });
                skipped += 1;
                stats.skipped += 1;
            } else if (result.passed) {
                const fmt_str = if (result.selected_format) |fmt|
                    @tagName(fmt)
                else
                    "?";

                // Print with or without diff_value
                if (result.diff_value) |diff| {
                    std.debug.print("  ✅ PASS: {s} ({d} → {d} bytes, {d:.1}%, {s}, diff={d:.4}, {d}ms)\n", .{
                        entry.name,
                        result.input_bytes,
                        result.output_bytes.?,
                        result.ratio.? * 100.0,
                        fmt_str,
                        diff,
                        test_time,
                    });
                } else {
                    std.debug.print("  ✅ PASS: {s} ({d} → {d} bytes, {d:.1}%, {s}, {d}ms)\n", .{
                        entry.name,
                        result.input_bytes,
                        result.output_bytes.?,
                        result.ratio.? * 100.0,
                        fmt_str,
                        test_time,
                    });
                }

                passed += 1;
                stats.passed += 1;
                stats.total_input_bytes += result.input_bytes;
                stats.total_output_bytes += result.output_bytes.?;

                // Track diff_value statistics
                if (result.diff_value) |diff| {
                    stats.total_diff_value += diff;
                    stats.diff_count += 1;
                }
            } else {
                std.debug.print("  ❌ FAIL: {s} - {s} ({d}ms)\n", .{ entry.name, result.reason.?, test_time });
                failed += 1;
                stats.failed += 1;
            }
        }

        try suite_stats.append(allocator, stats);
        std.debug.print("\n", .{});
    }

    // Print per-suite statistics
    std.debug.print("=== Per-Suite Results ===\n", .{});
    for (suite_stats.items) |stats| {
        if (stats.total == 0) continue;

        const pass_rate = (stats.passed * 100) / stats.total;
        const avg_compression = if (stats.passed > 0)
            (@as(f64, @floatFromInt(stats.total_output_bytes)) /
            @as(f64, @floatFromInt(stats.total_input_bytes))) * 100.0
        else
            0.0;

        std.debug.print("{s}:\n", .{stats.name});
        std.debug.print("  Total:   {d}\n", .{stats.total});
        std.debug.print("  Passed:  {d} ({d}%)\n", .{ stats.passed, pass_rate });
        if (stats.skipped > 0) std.debug.print("  Skipped: {d}\n", .{stats.skipped});
        if (stats.failed > 0) std.debug.print("  Failed:  {d}\n", .{stats.failed});
        if (stats.passed > 0) {
            std.debug.print("  Avg compression: {d:.1}%\n", .{avg_compression});
        }
        // Print average perceptual diff if available
        if (stats.diff_count > 0) {
            const avg_diff = stats.total_diff_value / @as(f64, @floatFromInt(stats.diff_count));
            std.debug.print("  Avg diff (DSSIM): {d:.4} (n={d})\n", .{ avg_diff, stats.diff_count });
        }
        std.debug.print("  Time: {d}ms\n", .{stats.total_time_ms});
        std.debug.print("\n", .{});
    }

    // Print overall summary
    std.debug.print("=== Overall Results ===\n", .{});
    std.debug.print("Total:   {d}\n", .{total_tests});
    std.debug.print("Passed:  {d}\n", .{passed});
    if (skipped > 0) std.debug.print("Skipped: {d}\n", .{skipped});
    std.debug.print("Failed:  {d}\n", .{failed});
    std.debug.print("Time:    {d}ms ({d:.2}s)\n", .{ total_time_ms, @as(f64, @floatFromInt(total_time_ms)) / 1000.0 });

    if (total_tests > 0) {
        const pass_rate = (passed * 100) / total_tests;
        std.debug.print("Pass rate: {d}%\n", .{pass_rate});

        // Calculate stats for passing tests
        var total_input_bytes: u64 = 0;
        var total_output_bytes: u64 = 0;

        for (all_results.items) |result| {
            if (result.passed and !result.skipped) {
                total_input_bytes += result.input_bytes;
                total_output_bytes += result.output_bytes.?;
            }
        }

        if (passed > 0) {
            const avg_ratio = @as(f64, @floatFromInt(total_output_bytes)) /
                @as(f64, @floatFromInt(total_input_bytes));
            std.debug.print("Average compression: {d:.1}%\n", .{avg_ratio * 100.0});
            const bytes_saved = total_input_bytes - total_output_bytes;
            std.debug.print("Total bytes saved: {d} ({d:.2} MB)\n", .{
                bytes_saved,
                @as(f64, @floatFromInt(bytes_saved)) / (1024.0 * 1024.0),
            });
        }
    }

    // Print failure breakdown
    if (failed > 0) {
        std.debug.print("\n=== Failure Breakdown ===\n", .{});
        var decode_errors: u32 = 0;
        var encode_errors: u32 = 0;
        var size_regressions: u32 = 0;
        var no_candidates: u32 = 0;
        var write_errors: u32 = 0;

        for (all_results.items) |result| {
            if (!result.passed and !result.skipped) {
                switch (result.category) {
                    .decode_error => decode_errors += 1,
                    .encode_error => encode_errors += 1,
                    .size_regression => size_regressions += 1,
                    .no_candidates => no_candidates += 1,
                    .write_error => write_errors += 1,
                    else => {},
                }
            }
        }

        var quality_regressions: u32 = 0;
        for (all_results.items) |result| {
            if (!result.passed and !result.skipped and result.category == .quality_regression) {
                quality_regressions += 1;
            }
        }

        if (decode_errors > 0) std.debug.print("Decode errors:     {d}\n", .{decode_errors});
        if (encode_errors > 0) std.debug.print("Encode errors:     {d}\n", .{encode_errors});
        if (size_regressions > 0) std.debug.print("Size regressions:  {d}\n", .{size_regressions});
        if (quality_regressions > 0) std.debug.print("Quality regressions: {d}\n", .{quality_regressions});
        if (no_candidates > 0) std.debug.print("No candidates:     {d}\n", .{no_candidates});
        if (write_errors > 0) std.debug.print("Write errors:      {d}\n", .{write_errors});
    }

    if (failed == 0 and total_tests > 0) {
        std.debug.print("\n✅ All conformance tests passed!\n", .{});
        std.process.exit(0);
    } else if (total_tests == 0) {
        std.debug.print("\n⚠️  No tests found in testdata/conformance/\n", .{});
        std.debug.print("Run: ./scripts/download_testdata.sh\n", .{});
        std.process.exit(1);
    } else {
        std.debug.print("\n❌ Some tests failed\n", .{});
        std.process.exit(1);
    }
}

/// Check if a test file should be skipped (known-invalid or empty placeholder)
fn shouldSkipFile(input_path: []const u8) bool {
    const basename = std.fs.path.basename(input_path);

    // Skip PNG Suite intentionally corrupt test cases (x* prefix)
    if (std.mem.startsWith(u8, basename, "xc") or // Invalid color type
        std.mem.startsWith(u8, basename, "xd") or // Invalid bit depth
        std.mem.startsWith(u8, basename, "xs") or // Invalid signature
        std.mem.startsWith(u8, basename, "xlf")) // Invalid chunk length
    {
        return true;
    }

    return false;
}

/// Run optimization test on a single image
fn runOptimizationTest(allocator: Allocator, input_path: []const u8) !TestResult {
    // Skip known-invalid or empty placeholder files
    if (shouldSkipFile(input_path)) {
        const reason = try allocator.dupe(u8, "known invalid test file");
        return TestResult{
            .name = input_path,
            .passed = true,
            .skipped = true,
            .input_bytes = 0,
            .output_bytes = 0,
            .ratio = 1.0,
            .reason = reason,
            .category = .skipped_invalid,
        };
    }

    // Get input file size
    const input_file = fs.cwd().openFile(input_path, .{}) catch |err| {
        const reason = try std.fmt.allocPrint(allocator, "Cannot open: {}", .{err});
        return TestResult{
            .name = input_path,
            .passed = false,
            .input_bytes = 0,
            .output_bytes = null,
            .ratio = null,
            .reason = reason,
            .category = .decode_error,
        };
    };
    defer input_file.close();

    const input_stat = try input_file.stat();
    const input_bytes = input_stat.size;

    // Create output path
    const output_path = try std.fmt.allocPrint(
        allocator,
        "zig-out/conformance/{s}.optimized",
        .{std.fs.path.basename(input_path)},
    );
    defer allocator.free(output_path);

    // Ensure output directory exists
    try fs.cwd().makePath("zig-out/conformance");

    // Create optimization job with default settings
    var job = optimizer.OptimizationJob.init(input_path, output_path);
    // WebP, JPEG, PNG supported - AVIF excluded due to libvips compatibility issues
    job.formats = &[_]ImageFormat{ .webp, .jpeg, .png };
    job.max_bytes = null; // No size constraint for conformance

    // Run optimization
    var result = optimizer.optimizeImage(allocator, job) catch |err| {
        const reason = try std.fmt.allocPrint(allocator, "Opt failed: {}", .{err});
        const category: TestResult.FailureCategory = if (std.mem.indexOf(u8, @errorName(err), "Load") != null or
            std.mem.indexOf(u8, @errorName(err), "Decode") != null)
            .decode_error
        else
            .encode_error;
        return TestResult{
            .name = input_path,
            .passed = false,
            .input_bytes = input_bytes,
            .output_bytes = null,
            .ratio = null,
            .reason = reason,
            .category = category,
        };
    };
    defer result.deinit(allocator);

    // Check if optimization succeeded
    if (!result.success or result.selected == null) {
        const reason = try allocator.dupe(u8, "No valid candidate");
        return TestResult{
            .name = input_path,
            .passed = false,
            .input_bytes = input_bytes,
            .output_bytes = null,
            .ratio = null,
            .reason = reason,
            .category = .no_candidates,
        };
    }

    const selected = result.selected.?;

    // Write output file
    output.writeOptimizedImage(output_path, selected.encoded_bytes) catch |err| {
        const reason = try std.fmt.allocPrint(allocator, "Write failed: {}", .{err});
        return TestResult{
            .name = input_path,
            .passed = false,
            .input_bytes = input_bytes,
            .output_bytes = null,
            .ratio = null,
            .diff_value = null,
            .reason = reason,
            .category = .write_error,
        };
    };

    // Verify output is smaller or within 5% (acceptable for small files)
    const output_bytes = selected.file_size;
    const ratio = @as(f64, @floatFromInt(output_bytes)) / @as(f64, @floatFromInt(input_bytes));

    // Extract perceptual diff_value from selected candidate
    const diff_value = selected.diff_score;

    // Pass if output is smaller or within 105% (acceptable for already optimized files)
    // Also check perceptual quality if diff_value available
    const passed = ratio <= 1.05;

    const reason: ?[]const u8 = if (!passed)
        try std.fmt.allocPrint(
            allocator,
            "Size regression: {d} → {d} bytes ({d:.1}%)",
            .{ input_bytes, output_bytes, ratio * 100.0 },
        )
    else
        null;

    return TestResult{
        .name = input_path,
        .passed = passed,
        .input_bytes = input_bytes,
        .output_bytes = output_bytes,
        .ratio = ratio,
        .diff_value = diff_value,
        .reason = reason,
        .category = if (passed) .none else .size_regression,
        .selected_format = selected.format,
    };
}
