//! Integration tests for end-to-end image optimization workflow.
//!
//! These tests validate the complete pipeline from input discovery
//! through optimization to file output and manifest generation.
//!
//! Tiger Style compliance:
//! - Each test is self-contained and independent
//! - Tests use real image files from testdata/
//! - All allocations tracked with testing.allocator
//! - Bounded operations (no infinite loops)

const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const Allocator = std.mem.Allocator;

// Import modules under test directly
const optimizer = @import("../../optimizer.zig");
const output = @import("../../output.zig");
const manifest = @import("../../manifest.zig");
const vips = @import("../../vips.zig");
const types = @import("../../types.zig");
const ImageFormat = types.ImageFormat;

/// Helper: Find a test image from testdata/
fn getTestImagePath(allocator: Allocator, filename: []const u8) ![]const u8 {
    const paths = [_][]const u8{
        "testdata/conformance/testimages/",
        "testdata/conformance/pngsuite/",
    };

    // Try each path
    for (paths) |base_path| {
        const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_path, filename });
        errdefer allocator.free(full_path);

        // Check if file exists
        fs.cwd().access(full_path, .{}) catch {
            allocator.free(full_path);
            continue;
        };

        return full_path; // Found it!
    }

    return error.TestImageNotFound;
}

/// Helper: Clean up test output directory
fn cleanupTestDir(dir_path: []const u8) void {
    fs.cwd().deleteTree(dir_path) catch {};
}

/// Helper: Create test output directory
fn setupTestDir(dir_path: []const u8) !void {
    try fs.cwd().makePath(dir_path);
}

// ============================================================================
// Test 1: Single Image Optimization (No Constraints)
// ============================================================================

test "integration: single image optimization - basic workflow" {
    const allocator = testing.allocator;

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    // Setup test environment
    const test_dir = "zig-out/test_integration_basic";
    defer cleanupTestDir(test_dir);
    try setupTestDir(test_dir);

    // Find a test image
    const input_path = try getTestImagePath(allocator, "lena.png");
    defer allocator.free(input_path);

    const output_path = test_dir ++ "/lena_optimized.jpg";

    // Create optimization job
    var job = optimizer.OptimizationJob.init(input_path, output_path);
    job.formats = &[_]ImageFormat{ .jpeg, .png };

    // Run optimization
    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    // Verify result
    try testing.expect(result.success);
    try testing.expect(result.selected != null);

    const selected = result.selected.?;
    try testing.expect(selected.file_size > 0);
    try testing.expect(selected.encoded_bytes.len > 0);

    // Write output file
    try output.writeOptimizedImage(output_path, selected.encoded_bytes);

    // Verify file was created
    const file = try fs.cwd().openFile(output_path, .{});
    defer file.close();

    const stat = try file.stat();
    try testing.expectEqual(selected.file_size, @as(u32, @intCast(stat.size)));
}

// ============================================================================
// Test 2: Optimization with Size Constraint
// ============================================================================

test "integration: single image with max-kb constraint" {
    const allocator = testing.allocator;

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    // Setup test environment
    const test_dir = "zig-out/test_integration_constraint";
    defer cleanupTestDir(test_dir);
    try setupTestDir(test_dir);

    // Find a test image
    const input_path = try getTestImagePath(allocator, "peppers.png");
    defer allocator.free(input_path);

    const output_path = test_dir ++ "/peppers_constrained.jpg";

    // Create optimization job with size constraint
    var job = optimizer.OptimizationJob.init(input_path, output_path);
    job.formats = &[_]ImageFormat{ .jpeg, .png };
    job.max_bytes = 50_000; // 50KB limit

    // Run optimization
    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    // Verify result respects constraint
    if (result.selected) |selected| {
        // Selected candidate must be under budget
        try testing.expect(selected.file_size <= job.max_bytes.?);
        try testing.expect(selected.passed_constraints);

        // Write output
        try output.writeOptimizedImage(output_path, selected.encoded_bytes);

        // Verify written file size
        const file = try fs.cwd().openFile(output_path, .{});
        defer file.close();
        const stat = try file.stat();
        try testing.expect(stat.size <= job.max_bytes.?);
    } else {
        // If no candidate passed, all candidates should be over budget
        for (result.all_candidates) |candidate| {
            try testing.expect(candidate.file_size > job.max_bytes.?);
        }
    }
}

// ============================================================================
// Test 3: Manifest Generation
// ============================================================================

test "integration: manifest generation for single optimization" {
    const allocator = testing.allocator;

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    // Setup test environment
    const test_dir = "zig-out/test_integration_manifest";
    defer cleanupTestDir(test_dir);
    try setupTestDir(test_dir);

    // Find a test image
    const input_path = try getTestImagePath(allocator, "baboon.png");
    defer allocator.free(input_path);

    const output_path = test_dir ++ "/baboon_optimized.png";
    const manifest_path = test_dir ++ "/manifest.jsonl";

    // Create optimization job
    var job = optimizer.OptimizationJob.init(input_path, output_path);
    job.formats = &[_]ImageFormat{ .jpeg, .png };
    job.max_bytes = 100_000;

    // Run optimization
    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    try testing.expect(result.success);
    const selected = result.selected.?;

    // Write output file
    try output.writeOptimizedImage(output_path, selected.encoded_bytes);

    // Generate alternates list for manifest
    var alternates = std.ArrayList(manifest.ManifestEntry.Alternate){};
    defer alternates.deinit(allocator);

    for (result.all_candidates) |candidate| {
        try alternates.append(allocator, .{
            .format = @tagName(candidate.format),
            .bytes = candidate.file_size,
            .diff = candidate.diff_score,
            .passed = candidate.passed_constraints,
            .reason = if (!candidate.passed_constraints) @as(?[]const u8, "over_budget") else null,
        });
    }

    // Create manifest entry
    const entry = try manifest.createEntry(
        allocator,
        input_path,
        output_path,
        selected.file_size,
        @tagName(selected.format),
        job.max_bytes,
        job.max_diff,
        alternates.items,
        .{
            .decode = @intCast(result.timings.decode_ns / 1_000_000),
            .transform = 0,
            .encode_total = @intCast(result.timings.encode_ns / 1_000_000),
            .metrics = 0,
        },
    );

    // Write manifest
    const manifest_file = try fs.cwd().createFile(manifest_path, .{ .truncate = true });
    defer manifest_file.close();

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    try manifest.writeManifestLine(buffer.writer(allocator), entry);
    try manifest_file.writeAll(buffer.items);

    // Verify manifest file exists and is valid JSON
    const read_file = try fs.cwd().openFile(manifest_path, .{});
    defer read_file.close();

    const content = try read_file.readToEndAlloc(allocator, 10_000);
    defer allocator.free(content);

    // Verify it's valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try testing.expectEqualStrings(input_path, obj.get("input").?.string);
    try testing.expectEqualStrings(output_path, obj.get("output").?.string);
    try testing.expectEqual(@as(i64, @intCast(selected.file_size)), obj.get("bytes").?.integer);
}

// ============================================================================
// Test 4: Batch Optimization Workflow
// ============================================================================

test "integration: batch optimization of multiple images" {
    const allocator = testing.allocator;

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    // Setup test environment
    const test_dir = "zig-out/test_integration_batch";
    defer cleanupTestDir(test_dir);
    try setupTestDir(test_dir);

    // Test with multiple images
    const test_images = [_][]const u8{ "lena.png", "peppers.png", "baboon.png" };

    var successful_optimizations: u32 = 0;

    // Process each image
    for (test_images) |filename| {
        // Find input path
        const input_path = getTestImagePath(allocator, filename) catch continue;
        defer allocator.free(input_path);

        // Generate output path
        const output_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}_optimized.jpg",
            .{ test_dir, filename },
        );
        defer allocator.free(output_path);

        // Create job
        var job = optimizer.OptimizationJob.init(input_path, output_path);
        job.formats = &[_]ImageFormat{ .jpeg, .png };

        // Optimize
        var result = optimizer.optimizeImage(allocator, job) catch continue;
        defer result.deinit(allocator);

        if (result.selected) |selected| {
            // Write output
            output.writeOptimizedImage(output_path, selected.encoded_bytes) catch continue;
            successful_optimizations += 1;
        }
    }

    // Verify we successfully optimized at least 2 images
    try testing.expect(successful_optimizations >= 2);
}

// ============================================================================
// Test 5: Format Selection (JPEG vs PNG)
// ============================================================================

test "integration: format selection prefers smaller output" {
    const allocator = testing.allocator;

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    // Setup test environment
    const test_dir = "zig-out/test_integration_format";
    defer cleanupTestDir(test_dir);
    try setupTestDir(test_dir);

    // Find a test image
    const input_path = try getTestImagePath(allocator, "lena.png");
    defer allocator.free(input_path);

    const output_path = test_dir ++ "/lena_best_format";

    // Create job that tries both JPEG and PNG
    var job = optimizer.OptimizationJob.init(input_path, output_path);
    job.formats = &[_]ImageFormat{ .jpeg, .png };

    // Run optimization
    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    try testing.expect(result.success);
    try testing.expect(result.all_candidates.len >= 2);

    // Verify selected candidate is smallest
    const selected = result.selected.?;
    for (result.all_candidates) |candidate| {
        // Selected should be <= all others
        try testing.expect(selected.file_size <= candidate.file_size);
    }
}

// ============================================================================
// Test 6: Memory Safety (No Leaks)
// ============================================================================

test "integration: no memory leaks in optimization pipeline" {
    const allocator = testing.allocator;

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    // Setup test environment
    const test_dir = "zig-out/test_integration_memory";
    defer cleanupTestDir(test_dir);
    try setupTestDir(test_dir);

    // Find a test image
    const input_path = try getTestImagePath(allocator, "peppers.png");
    defer allocator.free(input_path);

    // Run optimization 10 times to detect leaks
    var iteration: u32 = 0;
    const MAX_ITERATIONS: u32 = 10;

    while (iteration < MAX_ITERATIONS) : (iteration += 1) {
        const output_path = try std.fmt.allocPrint(
            allocator,
            "{s}/peppers_{d}.jpg",
            .{ test_dir, iteration },
        );
        defer allocator.free(output_path);

        var job = optimizer.OptimizationJob.init(input_path, output_path);
        job.formats = &[_]ImageFormat{ .jpeg, .png };

        var result = try optimizer.optimizeImage(allocator, job);
        defer result.deinit(allocator);

        if (result.selected) |selected| {
            try output.writeOptimizedImage(output_path, selected.encoded_bytes);
        }
    }

    // Post-loop assertion
    std.debug.assert(iteration == MAX_ITERATIONS);

    // If we reach here without leaks detected by testing.allocator, test passes
}

// ============================================================================
// Test 7: Error Handling (Invalid Input)
// ============================================================================

test "integration: handles invalid input file gracefully" {
    const allocator = testing.allocator;

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    // Setup test environment
    const test_dir = "zig-out/test_integration_error";
    defer cleanupTestDir(test_dir);
    try setupTestDir(test_dir);

    // Create an invalid "image" file
    const invalid_input = test_dir ++ "/not_an_image.png";
    const invalid_file = try fs.cwd().createFile(invalid_input, .{});
    defer invalid_file.close();
    try invalid_file.writeAll("This is not an image file");

    const output_path = test_dir ++ "/should_not_exist.jpg";

    // Create job with invalid input
    var job = optimizer.OptimizationJob.init(invalid_input, output_path);
    job.formats = &[_]ImageFormat{ .jpeg, .png };

    // Should return error
    const result = optimizer.optimizeImage(allocator, job);

    // Expect an error
    try testing.expectError(error.VipsLoadFailed, result);
}

// ============================================================================
// Test 8: Output Directory Creation
// ============================================================================

test "integration: creates nested output directories" {
    const allocator = testing.allocator;

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    // Setup test environment
    const test_dir = "zig-out/test_integration_nested";
    defer cleanupTestDir(test_dir);
    // Don't create test_dir - let the code create it

    // Find a test image
    const input_path = try getTestImagePath(allocator, "lena.png");
    defer allocator.free(input_path);

    // Output path with nested directories that don't exist
    const output_path = test_dir ++ "/level1/level2/level3/lena_optimized.jpg";

    // Create job
    var job = optimizer.OptimizationJob.init(input_path, output_path);
    job.formats = &[_]ImageFormat{.jpeg};

    // Run optimization
    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    try testing.expect(result.success);

    // Write output - should create all directories
    try output.writeOptimizedImage(output_path, result.selected.?.encoded_bytes);

    // Verify file was created
    const file = try fs.cwd().openFile(output_path, .{});
    defer file.close();
}
