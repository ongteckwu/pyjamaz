const std = @import("std");
const testing = std.testing;
const optimizer = @import("../../optimizer.zig");
const types = @import("../../types.zig");
const ImageBuffer = types.ImageBuffer;
const ImageFormat = types.ImageFormat;

const EncodedCandidate = optimizer.EncodedCandidate;
const OptimizationJob = optimizer.OptimizationJob;
const OptimizationResult = optimizer.OptimizationResult;

// Test PNG path (from other tests)
const TEST_PNG_PATH = "testdata/basic/100x100_rgb.png";

// ============================================================================
// Unit Tests for Optimizer Types
// ============================================================================

test "EncodedCandidate: deinit frees memory" {
    var candidate = EncodedCandidate{
        .format = .jpeg,
        .encoded_bytes = try testing.allocator.alloc(u8, 100),
        .file_size = 100,
        .quality = 85,
        .diff_score = 0.0,
        .passed_constraints = true,
        .encoding_time_ns = 1000,
    };

    candidate.deinit(testing.allocator);
    // No leak if this test passes
}

test "EncodedCandidate: multiple candidates cleanup" {
    var candidates = [_]EncodedCandidate{
        .{
            .format = .jpeg,
            .encoded_bytes = try testing.allocator.alloc(u8, 100),
            .file_size = 100,
            .quality = 85,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1000,
        },
        .{
            .format = .png,
            .encoded_bytes = try testing.allocator.alloc(u8, 200),
            .file_size = 200,
            .quality = 6,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1200,
        },
    };

    for (&candidates) |*candidate| {
        candidate.deinit(testing.allocator);
    }
}

test "OptimizationJob: init with defaults" {
    const job = OptimizationJob.init("input.jpg", "output.jpg");

    try testing.expectEqualStrings("input.jpg", job.input_path);
    try testing.expectEqualStrings("output.jpg", job.output_path);
    try testing.expectEqual(@as(?u32, null), job.max_bytes);
    try testing.expectEqual(@as(?f64, null), job.max_diff);
    try testing.expectEqual(@as(u8, 4), job.concurrency);
    try testing.expect(job.formats.len >= 2);
    try testing.expectEqual(ImageFormat.jpeg, job.formats[0]);
    try testing.expectEqual(ImageFormat.png, job.formats[1]);
}

test "OptimizationJob: custom configuration" {
    const formats = [_]ImageFormat{ .png, .webp };
    const job = OptimizationJob{
        .input_path = "test.png",
        .output_path = "out.png",
        .max_bytes = 50_000,
        .max_diff = 1.0,
        .formats = &formats,
        .transform_params = .{},
        .concurrency = 8,
    };

    try testing.expectEqualStrings("test.png", job.input_path);
    try testing.expectEqual(@as(u32, 50_000), job.max_bytes.?);
    try testing.expectEqual(@as(f64, 1.0), job.max_diff.?);
    try testing.expectEqual(@as(u8, 8), job.concurrency);
    try testing.expectEqual(@as(usize, 2), job.formats.len);
}

test "OptimizationResult: cleanup all resources" {
    var candidates = std.ArrayList(EncodedCandidate){};
    try candidates.append(testing.allocator, .{
        .format = .jpeg,
        .encoded_bytes = try testing.allocator.alloc(u8, 100),
        .file_size = 100,
        .quality = 85,
        .diff_score = 0.0,
        .passed_constraints = true,
        .encoding_time_ns = 1000,
    });

    var warnings = std.ArrayList([]u8){};
    try warnings.append(testing.allocator, try testing.allocator.dupe(u8, "Test warning"));

    var result = OptimizationResult{
        .selected = .{
            .format = .jpeg,
            .encoded_bytes = try testing.allocator.alloc(u8, 50),
            .file_size = 50,
            .quality = 85,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 500,
        },
        .all_candidates = try candidates.toOwnedSlice(),
        .timings = .{
            .decode_ns = 1000,
            .encode_ns = 2000,
            .total_ns = 3000,
        },
        .warnings = try warnings.toOwnedSlice(),
        .success = true,
    };

    result.deinit(testing.allocator);
    // No leaks if this passes
}

// ============================================================================
// Integration Tests for Full Optimization Pipeline
// ============================================================================

test "optimizeImage: basic optimization without constraints" {
    const allocator = testing.allocator;

    // Skip if test file doesn't exist
    std.fs.cwd().access(TEST_PNG_PATH, .{}) catch {
        std.debug.print("Skipping test: {} not found\n", .{TEST_PNG_PATH});
        return error.SkipZigTest;
    };

    const job = OptimizationJob.init(TEST_PNG_PATH, "output_test.jpg");

    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    // Verify result structure
    try testing.expect(result.success);
    try testing.expect(result.selected != null);
    try testing.expect(result.all_candidates.len >= 1);
    try testing.expect(result.timings.total_ns > 0);
    try testing.expect(result.timings.decode_ns > 0);
    try testing.expect(result.timings.encode_ns > 0);

    // Verify selected candidate
    const selected = result.selected.?;
    try testing.expect(selected.file_size > 0);
    try testing.expect(selected.encoded_bytes.len > 0);
    try testing.expect(selected.quality > 0);
    try testing.expect(selected.encoding_time_ns > 0);
}

test "optimizeImage: respects size constraint" {
    const allocator = testing.allocator;

    // Skip if test file doesn't exist
    std.fs.cwd().access(TEST_PNG_PATH, .{}) catch {
        std.debug.print("Skipping test: {} not found\n", .{TEST_PNG_PATH});
        return error.SkipZigTest;
    };

    const formats = [_]ImageFormat{ .jpeg, .png };
    const job = OptimizationJob{
        .input_path = TEST_PNG_PATH,
        .output_path = "output_constrained.jpg",
        .max_bytes = 5000, // 5KB constraint
        .max_diff = null,
        .formats = &formats,
        .transform_params = .{},
        .concurrency = 4,
    };

    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    // Verify constraint was respected
    if (result.selected) |selected| {
        try testing.expect(selected.file_size <= 5000);
        try testing.expect(selected.passed_constraints);
    }

    // All candidates should be within constraint or marked as failed
    for (result.all_candidates) |candidate| {
        if (candidate.file_size <= 5000) {
            try testing.expect(candidate.passed_constraints);
        } else {
            try testing.expect(!candidate.passed_constraints);
        }
    }
}

test "optimizeImage: tries multiple formats" {
    const allocator = testing.allocator;

    // Skip if test file doesn't exist
    std.fs.cwd().access(TEST_PNG_PATH, .{}) catch {
        std.debug.print("Skipping test: {} not found\n", .{TEST_PNG_PATH});
        return error.SkipZigTest;
    };

    const formats = [_]ImageFormat{ .jpeg, .png };
    const job = OptimizationJob{
        .input_path = TEST_PNG_PATH,
        .output_path = "output_multi.jpg",
        .max_bytes = null,
        .max_diff = null,
        .formats = &formats,
        .transform_params = .{},
        .concurrency = 4,
    };

    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    // Should have tried both formats
    try testing.expect(result.all_candidates.len >= 2);

    // Check that we have both formats
    var has_jpeg = false;
    var has_png = false;

    for (result.all_candidates) |candidate| {
        if (candidate.format == .jpeg) has_jpeg = true;
        if (candidate.format == .png) has_png = true;
    }

    try testing.expect(has_jpeg);
    try testing.expect(has_png);
}

test "optimizeImage: selects smallest passing candidate" {
    const allocator = testing.allocator;

    // Skip if test file doesn't exist
    std.fs.cwd().access(TEST_PNG_PATH, .{}) catch {
        std.debug.print("Skipping test: {} not found\n", .{TEST_PNG_PATH});
        return error.SkipZigTest;
    };

    const formats = [_]ImageFormat{ .jpeg, .png };
    const job = OptimizationJob{
        .input_path = TEST_PNG_PATH,
        .output_path = "output_smallest.jpg",
        .max_bytes = null,
        .max_diff = null,
        .formats = &formats,
        .transform_params = .{},
        .concurrency = 4,
    };

    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    // Find the smallest candidate
    var min_size: u32 = std.math.maxInt(u32);
    for (result.all_candidates) |candidate| {
        if (candidate.file_size < min_size) {
            min_size = candidate.file_size;
        }
    }

    // Selected candidate should be the smallest
    try testing.expectEqual(min_size, result.selected.?.file_size);
}

test "optimizeImage: handles tight constraint gracefully" {
    const allocator = testing.allocator;

    // Skip if test file doesn't exist
    std.fs.cwd().access(TEST_PNG_PATH, .{}) catch {
        std.debug.print("Skipping test: {} not found\n", .{TEST_PNG_PATH});
        return error.SkipZigTest;
    };

    const formats = [_]ImageFormat{ .jpeg, .png };
    const job = OptimizationJob{
        .input_path = TEST_PNG_PATH,
        .output_path = "output_tight.jpg",
        .max_bytes = 100, // Unrealistically small
        .max_diff = null,
        .formats = &formats,
        .transform_params = .{},
        .concurrency = 4,
    };

    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    // May not find a passing candidate with such tight constraint
    // But should not crash and should provide candidates
    try testing.expect(result.all_candidates.len > 0);

    // Check if any candidate passed
    if (result.selected == null) {
        // No candidate passed - this is OK for tight constraint
        // Verify all candidates failed the constraint
        for (result.all_candidates) |candidate| {
            try testing.expect(candidate.file_size > 100);
        }
    } else {
        // If one passed, it must be <= 100 bytes (unlikely)
        try testing.expect(result.selected.?.file_size <= 100);
    }
}

test "optimizeImage: timings are reasonable" {
    const allocator = testing.allocator;

    // Skip if test file doesn't exist
    std.fs.cwd().access(TEST_PNG_PATH, .{}) catch {
        std.debug.print("Skipping test: {} not found\n", .{TEST_PNG_PATH});
        return error.SkipZigTest;
    };

    const job = OptimizationJob.init(TEST_PNG_PATH, "output_timing.jpg");

    var result = try optimizer.optimizeImage(allocator, job);
    defer result.deinit(allocator);

    // Verify timing breakdown
    try testing.expect(result.timings.decode_ns > 0);
    try testing.expect(result.timings.encode_ns > 0);
    try testing.expect(result.timings.total_ns > 0);

    // Total time should be sum of parts (approximately)
    try testing.expect(result.timings.total_ns >= result.timings.decode_ns);
    try testing.expect(result.timings.total_ns >= result.timings.encode_ns);
}

test "optimizeImage: no memory leaks with repeated calls" {
    const allocator = testing.allocator;

    // Skip if test file doesn't exist
    std.fs.cwd().access(TEST_PNG_PATH, .{}) catch {
        std.debug.print("Skipping test: {} not found\n", .{TEST_PNG_PATH});
        return error.SkipZigTest;
    };

    const job = OptimizationJob.init(TEST_PNG_PATH, "output_leak_test.jpg");

    // Run optimization 10 times to detect leaks
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var result = try optimizer.optimizeImage(allocator, job);
        defer result.deinit(allocator);

        try testing.expect(result.success);
    }

    // testing.allocator will fail if there are leaks
}
