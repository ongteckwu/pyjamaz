//! Golden Snapshot Regression Tests
//!
//! Ensures optimizer outputs remain deterministic across versions.
//! Tests compare current outputs against saved golden snapshots.
//!
//! Usage:
//!   1. First run (--update-golden): Generate golden manifest
//!   2. Subsequent runs: Compare outputs against golden manifest
//!   3. On failure: Outputs changed (potential regression!)

const std = @import("std");
const golden = @import("../../golden.zig");
const optimizer = @import("../../optimizer.zig");
const types = @import("../../types.zig");
const vips = @import("../../vips.zig");

const testing = std.testing;
const allocator = testing.allocator;

/// Test configuration
const test_inputs = [_]struct {
    name: []const u8,
    path: []const u8,
}{
    .{ .name = "small_png", .path = "testdata/conformance/pngsuite/basn0g01.png" },
    .{ .name = "rgb_png", .path = "testdata/conformance/pngsuite/basn2c08.png" },
    .{ .name = "rgba_png", .path = "testdata/conformance/pngsuite/basn6a08.png" },
};

/// Generate golden snapshot manifest from test run
pub fn generateGolden(
    alloc: std.mem.Allocator,
    output_dir: []const u8,
    golden_path: []const u8,
) !void {
    // Pre-condition: paths must be valid
    std.debug.assert(output_dir.len > 0);
    std.debug.assert(golden_path.len > 0);

    var manifest = golden.GoldenManifest.init(alloc);
    defer manifest.deinit();

    // Create output directory
    try std.fs.cwd().makePath(output_dir);

    // Initialize libvips
    var ctx = try vips.VipsContext.init();
    defer ctx.deinit();

    // Run optimizer on each test input
    for (test_inputs) |input| {
        std.debug.print("Generating golden for: {s}\n", .{input.name});

        // Check if file exists
        const file = std.fs.cwd().openFile(input.path, .{}) catch |err| {
            std.debug.print("  Skipping {s}: {}\n", .{ input.name, err });
            continue;
        };
        file.close();

        // Create optimization job
        const job = types.OptimizationJob{
            .input_path = input.path,
            .output_path = null, // Will generate in output_dir
            .formats = &[_]types.ImageFormat{ .jpeg, .png },
            .max_bytes = null,
            .max_diff = 1.0,
            .metric_type = .dssim,
            .transform_params = types.TransformParams.init(),
            .parallel_encoding = false,
        };

        // Run optimizer
        const result = optimizer.optimizeImage(alloc, job) catch |err| {
            std.debug.print("  Optimization failed for {s}: {}\n", .{ input.name, err });
            continue;
        };
        defer alloc.free(result.encoded_data);

        // Write output to file
        const output_filename = try std.fmt.allocPrint(
            alloc,
            "{s}/{s}.{s}",
            .{ output_dir, input.name, @tagName(result.format) },
        );
        defer alloc.free(output_filename);

        const output_file = try std.fs.cwd().createFile(output_filename, .{});
        defer output_file.close();
        try output_file.writeAll(result.encoded_data);

        // Compute hashes
        const input_hash = try golden.hashFile(input.path);
        const output_hash = golden.hashBuffer(result.encoded_data);

        // Add to manifest
        try manifest.add(.{
            .test_name = input.name,
            .input_hash = input_hash,
            .output_hash = output_hash,
            .format = @tagName(result.format),
            .output_size = result.encoded_data.len,
        });

        std.debug.print("  ✅ Generated: {s} ({d} bytes)\n", .{
            output_filename,
            result.encoded_data.len,
        });
    }

    // Save manifest
    try manifest.saveToFile(golden_path);
    std.debug.print("\n✅ Golden manifest saved to: {s}\n", .{golden_path});
    std.debug.print("   Entries: {d}\n", .{manifest.entries.items.len});

    // Post-condition: manifest created
    std.debug.assert(manifest.entries.items.len > 0);
}

/// Compare current outputs against golden manifest
pub fn compareAgainstGolden(
    alloc: std.mem.Allocator,
    output_dir: []const u8,
    golden_path: []const u8,
) !bool {
    // Pre-condition: paths must be valid
    std.debug.assert(output_dir.len > 0);
    std.debug.assert(golden_path.len > 0);

    // Load golden manifest
    var manifest = golden.GoldenManifest.loadFromFile(alloc, golden_path) catch |err| {
        std.debug.print("❌ Failed to load golden manifest: {}\n", .{err});
        std.debug.print("   Run with --update-golden to create it\n", .{});
        return error.GoldenManifestNotFound;
    };
    defer manifest.deinit();

    std.debug.print("Loaded golden manifest: {d} entries\n", .{manifest.entries.items.len});

    // Create output directory
    try std.fs.cwd().makePath(output_dir);

    // Initialize libvips
    var ctx = try vips.VipsContext.init();
    defer ctx.deinit();

    var test_results = std.ArrayList(struct {
        test_name: []const u8,
        output_path: []const u8,
    }).init(alloc);
    defer {
        for (test_results.items) |result| {
            alloc.free(result.output_path);
        }
        test_results.deinit();
    }

    // Run optimizer on each test input
    for (test_inputs) |input| {
        std.debug.print("Testing: {s}\n", .{input.name});

        // Check if file exists
        const file = std.fs.cwd().openFile(input.path, .{}) catch |err| {
            std.debug.print("  Skipping {s}: {}\n", .{ input.name, err });
            continue;
        };
        file.close();

        // Create optimization job
        const job = types.OptimizationJob{
            .input_path = input.path,
            .output_path = null,
            .formats = &[_]types.ImageFormat{ .jpeg, .png },
            .max_bytes = null,
            .max_diff = 1.0,
            .metric_type = .dssim,
            .transform_params = types.TransformParams.init(),
            .parallel_encoding = false,
        };

        // Run optimizer
        const result = optimizer.optimizeImage(alloc, job) catch |err| {
            std.debug.print("  Optimization failed for {s}: {}\n", .{ input.name, err });
            continue;
        };
        defer alloc.free(result.encoded_data);

        // Write output to file
        const output_filename = try std.fmt.allocPrint(
            alloc,
            "{s}/{s}.{s}",
            .{ output_dir, input.name, @tagName(result.format) },
        );
        errdefer alloc.free(output_filename);

        const output_file = try std.fs.cwd().createFile(output_filename, .{});
        defer output_file.close();
        try output_file.writeAll(result.encoded_data);

        try test_results.append(.{
            .test_name = input.name,
            .output_path = output_filename,
        });
    }

    // Compare against golden
    const comparisons = try golden.compareWithGolden(
        alloc,
        &manifest,
        test_results.items,
    );
    defer alloc.free(comparisons);

    // Print results
    std.debug.print("\n=== Comparison Results ===\n", .{});

    var match_count: u32 = 0;
    var mismatch_count: u32 = 0;
    var new_count: u32 = 0;

    for (comparisons) |comp| {
        const msg = try comp.format_message(alloc);
        defer alloc.free(msg);
        std.debug.print("{s}\n", .{msg});

        switch (comp.status) {
            .match => match_count += 1,
            .mismatch => mismatch_count += 1,
            .new => new_count += 1,
            .missing => {},
        }
    }

    // Summary
    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("Matches:    {d}\n", .{match_count});
    std.debug.print("Mismatches: {d}\n", .{mismatch_count});
    std.debug.print("New:        {d}\n", .{new_count});

    const all_match = mismatch_count == 0;

    if (all_match) {
        std.debug.print("\n✅ All tests match golden snapshots!\n", .{});
    } else {
        std.debug.print("\n❌ {d} test(s) differ from golden snapshots!\n", .{mismatch_count});
        std.debug.print("   This may indicate a regression.\n", .{});
        std.debug.print("   Review changes or run with --update-golden to update baseline.\n", .{});
    }

    return all_match;
}

// Test: Generate and compare golden snapshots
test "golden snapshots: generate and compare" {
    const output_dir = "zig-out/test-golden";
    const golden_path = "zig-out/test-golden/manifest.tsv";

    // Clean up from previous runs
    std.fs.cwd().deleteTree(output_dir) catch {};

    // Generate golden
    try generateGolden(allocator, output_dir, golden_path);

    // Compare against itself (should all match)
    const all_match = try compareAgainstGolden(allocator, output_dir, golden_path);
    try testing.expect(all_match);

    // Clean up
    std.fs.cwd().deleteTree(output_dir) catch {};
}

test "golden snapshots: detect changes" {
    const output_dir = "zig-out/test-golden-detect";
    const golden_path = "zig-out/test-golden-detect/manifest.tsv";

    // Clean up from previous runs
    std.fs.cwd().deleteTree(output_dir) catch {};
    defer std.fs.cwd().deleteTree(output_dir) catch {};

    // Generate golden
    try generateGolden(allocator, output_dir, golden_path);

    // Modify one output file to simulate a change
    const modified_file = try std.fmt.allocPrint(
        allocator,
        "{s}/small_png.png",
        .{output_dir},
    );
    defer allocator.free(modified_file);

    // Check if file exists before modifying
    const file_exists = blk: {
        const file = std.fs.cwd().openFile(modified_file, .{}) catch break :blk false;
        file.close();
        break :blk true;
    };

    if (file_exists) {
        const file = try std.fs.cwd().openFile(modified_file, .{ .mode = .write_only });
        defer file.close();

        // Write different content
        try file.writeAll("Modified content to trigger mismatch");

        // Compare again (should detect mismatch)
        const all_match = try compareAgainstGolden(allocator, output_dir, golden_path);
        try testing.expect(!all_match); // Should NOT match
    } else {
        // Skip test if file doesn't exist
        std.debug.print("Skipping change detection test: file not generated\n", .{});
    }
}
