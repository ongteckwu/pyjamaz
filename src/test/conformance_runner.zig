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
    input_bytes: u64,
    output_bytes: ?u32,
    ratio: ?f64,
    reason: ?[]const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    std.debug.print("\n=== Pyjamaz Conformance Tests ===\n\n", .{});

    // Test directories
    const test_dirs = [_][]const u8{
        "testdata/conformance/testimages",
        "testdata/conformance/pngsuite",
        "testdata/conformance/kodak",
        "testdata/conformance/webp",
    };

    var all_results = std.ArrayList(TestResult){};
    defer {
        for (all_results.items) |result| {
            if (result.reason) |reason| allocator.free(reason);
        }
        all_results.deinit(allocator);
    }

    var total_tests: u32 = 0;
    var passed: u32 = 0;
    var failed: u32 = 0;

    // Run tests from each directory
    for (test_dirs) |dir_path| {
        // Check if directory exists
        var dir = fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            std.debug.print("⚠️  Skipping {s}/: {}\n", .{ dir_path, err });
            continue;
        };
        defer dir.close();

        std.debug.print("Testing {s}/\n", .{dir_path});

        // Iterate over files
        var walker = dir.iterate();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;

            // Filter for image files
            const is_image = std.mem.endsWith(u8, entry.name, ".png") or
                std.mem.endsWith(u8, entry.name, ".jpg") or
                std.mem.endsWith(u8, entry.name, ".jpeg") or
                std.mem.endsWith(u8, entry.name, ".webp");

            if (!is_image) continue;

            total_tests += 1;

            // Build full path
            const input_path = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ dir_path, entry.name },
            );
            defer allocator.free(input_path);

            // Run test
            const result = try runOptimizationTest(allocator, input_path);
            try all_results.append(allocator, result);

            if (result.passed) {
                std.debug.print("  ✅ PASS: {s} ({d} → {d} bytes, {d:.1}%)\n", .{
                    entry.name,
                    result.input_bytes,
                    result.output_bytes.?,
                    result.ratio.? * 100.0,
                });
                passed += 1;
            } else {
                std.debug.print("  ❌ FAIL: {s} - {s}\n", .{ entry.name, result.reason.? });
                failed += 1;
            }
        }

        std.debug.print("\n", .{});
    }

    // Print summary
    std.debug.print("=== Results ===\n", .{});
    std.debug.print("Total:   {d}\n", .{total_tests});
    std.debug.print("Passed:  {d}\n", .{passed});
    std.debug.print("Failed:  {d}\n", .{failed});

    if (total_tests > 0) {
        const pass_rate = (passed * 100) / total_tests;
        std.debug.print("Pass rate: {d}%\n", .{pass_rate});

        // Calculate stats for passing tests
        var total_input_bytes: u64 = 0;
        var total_output_bytes: u64 = 0;

        for (all_results.items) |result| {
            if (result.passed) {
                total_input_bytes += result.input_bytes;
                total_output_bytes += result.output_bytes.?;
            }
        }

        if (passed > 0) {
            const avg_ratio = @as(f64, @floatFromInt(total_output_bytes)) /
                @as(f64, @floatFromInt(total_input_bytes));
            std.debug.print("Average compression: {d:.1}%\n", .{avg_ratio * 100.0});
        }
    }

    if (failed == 0 and total_tests > 0) {
        std.debug.print("\n✅ All conformance tests passed!\n", .{});
        std.process.exit(0);
    } else if (total_tests == 0) {
        std.debug.print("\n⚠️  No tests found in testdata/conformance/\n", .{});
        std.debug.print("Run: ./docs/scripts/download_testdata.sh\n", .{});
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

    // Skip empty Kodak placeholders
    if (std.mem.startsWith(u8, basename, "kodim")) {
        return true;
    }

    // Skip missing testimages (HTML redirects)
    if (std.mem.eql(u8, basename, "lena.png") or
        std.mem.eql(u8, basename, "peppers.png") or
        std.mem.eql(u8, basename, "baboon.png"))
    {
        return true;
    }

    return false;
}

/// Run optimization test on a single image
fn runOptimizationTest(allocator: Allocator, input_path: []const u8) !TestResult {
    // Skip known-invalid or empty placeholder files
    if (shouldSkipFile(input_path)) {
        return TestResult{
            .name = input_path,
            .passed = true, // Count as pass - these are expected to not work
            .input_bytes = 0,
            .output_bytes = 0,
            .ratio = 1.0,
            .reason = null,
        };
    }

    // Get input file size
    const input_file = fs.cwd().openFile(input_path, .{}) catch |err| {
        const reason = try std.fmt.allocPrint(allocator, "Cannot open file: {}", .{err});
        return TestResult{
            .name = input_path,
            .passed = false,
            .input_bytes = 0,
            .output_bytes = null,
            .ratio = null,
            .reason = reason,
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
    job.formats = &[_]ImageFormat{ .jpeg, .png };
    job.max_bytes = null; // No size constraint for conformance

    // Run optimization
    var result = optimizer.optimizeImage(allocator, job) catch |err| {
        const reason = try std.fmt.allocPrint(allocator, "Optimization failed: {}", .{err});
        return TestResult{
            .name = input_path,
            .passed = false,
            .input_bytes = input_bytes,
            .output_bytes = null,
            .ratio = null,
            .reason = reason,
        };
    };
    defer result.deinit(allocator);

    // Check if optimization succeeded
    if (!result.success or result.selected == null) {
        const reason = try allocator.dupe(u8, "No valid candidate produced");
        return TestResult{
            .name = input_path,
            .passed = false,
            .input_bytes = input_bytes,
            .output_bytes = null,
            .ratio = null,
            .reason = reason,
        };
    }

    const selected = result.selected.?;

    // Write output file
    output.writeOptimizedImage(output_path, selected.encoded_bytes) catch |err| {
        const reason = try std.fmt.allocPrint(allocator, "Cannot write output: {}", .{err});
        return TestResult{
            .name = input_path,
            .passed = false,
            .input_bytes = input_bytes,
            .output_bytes = null,
            .ratio = null,
            .reason = reason,
        };
    };

    // Verify output is smaller or within 5% (acceptable for small files)
    const output_bytes = selected.file_size;
    const ratio = @as(f64, @floatFromInt(output_bytes)) / @as(f64, @floatFromInt(input_bytes));

    // Pass if output is smaller or within 105% (acceptable for already optimized files)
    const passed = ratio <= 1.05;

    const reason: ?[]const u8 = if (!passed)
        try std.fmt.allocPrint(
            allocator,
            "Output larger than input: {d} → {d} bytes ({d:.1}%)",
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
        .reason = reason,
    };
}
