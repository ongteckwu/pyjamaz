const std = @import("std");
const cli = @import("cli.zig");
const optimizer = @import("optimizer.zig");
const types = @import("types.zig");
const output = @import("output.zig");
const manifest = @import("manifest.zig");

/// Exit codes for Pyjamaz
///
/// Following UNIX convention: 0 = success, non-zero = failure
/// Using range 10-14 for domain-specific errors
pub const ExitCode = enum(u8) {
    success = 0, // All images optimized successfully
    cli_error = 1, // CLI parsing or validation error
    budget_unmet = 10, // At least one image exceeds max_bytes
    diff_ceiling_unmet = 11, // All candidates exceed max_diff
    decode_error = 12, // Input image invalid (decode/transform failed)
    encode_error = 13, // Encoder failure (codec crashed)
    metric_error = 14, // Perceptual metric computation failed

    /// Convert to u8 for std.process.exit()
    pub fn toU8(self: ExitCode) u8 {
        return @intFromEnum(self);
    }
};

/// Result of processing all images
pub const ProcessingResult = struct {
    total_processed: u32,
    total_succeeded: u32,
    total_failed: u32,
    total_warnings: u32,
    exit_code: ExitCode,
};

pub fn main() !void {
    // Use GPA for main allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line arguments
    var config = cli.parseArgs(allocator) catch |err| {
        switch (err) {
            error.NoInputs => {
                std.debug.print("Error: No input files specified. Use --help for usage.\n", .{});
                std.process.exit(ExitCode.cli_error.toU8());
            },
            error.UnknownOption => {
                std.debug.print("Error: Unknown option. Use --help for usage.\n", .{});
                std.process.exit(ExitCode.cli_error.toU8());
            },
            error.MissingValue => {
                std.debug.print("Error: Missing value for option. Use --help for usage.\n", .{});
                std.process.exit(ExitCode.cli_error.toU8());
            },
            else => {
                std.debug.print("Error parsing arguments: {}\n", .{err});
                std.process.exit(ExitCode.cli_error.toU8());
            },
        }
    };
    defer config.deinit();

    // Print configuration if verbose (level 2+)
    if (config.verbosity >= 2) {
        std.debug.print("Pyjamaz Image Optimizer\n", .{});
        std.debug.print("=======================\n", .{});
        std.debug.print("Inputs: {d} file(s)\n", .{config.inputs.items.len});
        std.debug.print("Output: {s}\n", .{config.output_dir});
        std.debug.print("Max bytes: {d}\n", .{config.max_bytes});
        std.debug.print("Max diff: {d:.2}\n", .{config.max_diff});
        std.debug.print("Metric: {s}\n", .{@tagName(config.metric_type)});
        std.debug.print("Formats: ", .{});
        for (config.formats.items, 0..) |format, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{format});
        }
        std.debug.print("\n\n", .{});
    }

    // Process all input files
    const result = try processImages(allocator, &config);

    // Print summary
    if (config.verbosity >= 1) {
        std.debug.print("\nSummary:\n", .{});
        std.debug.print("  Processed: {d}\n", .{result.total_processed});
        std.debug.print("  Succeeded: {d}\n", .{result.total_succeeded});
        std.debug.print("  Failed: {d}\n", .{result.total_failed});
        if (result.total_warnings > 0) {
            std.debug.print("  Warnings: {d}\n", .{result.total_warnings});
        }
    }

    // Exit with appropriate code
    std.process.exit(result.exit_code.toU8());
}

/// Process all input images and return aggregated result
///
/// Tiger Style:
/// - Bounded loop (MAX_INPUT_FILES)
/// - Comprehensive error tracking
/// - Clear exit code determination
fn processImages(
    allocator: std.mem.Allocator,
    config: *const cli.CliConfig,
) !ProcessingResult {
    // Pre-conditions
    std.debug.assert(config.inputs.items.len > 0);

    // Tiger Style: Bound input file count
    const MAX_INPUT_FILES: u32 = 10000;
    if (config.inputs.items.len > MAX_INPUT_FILES) {
        std.log.err("Too many input files: {d} (max: {d})", .{ config.inputs.items.len, MAX_INPUT_FILES });
        return error.TooManyInputs;
    }

    var total_succeeded: u32 = 0;
    var total_failed: u32 = 0;
    var total_warnings: u32 = 0;

    // Track worst exit code encountered
    var worst_exit_code: ExitCode = .success;

    // Convert format strings to ImageFormat enums
    var formats = std.ArrayList(types.ImageFormat){};
    defer formats.deinit(allocator);
    for (config.formats.items) |format_str| {
        const format = types.ImageFormat.fromString(format_str) orelse {
            std.log.err("Invalid format: {s}", .{format_str});
            return error.InvalidFormat;
        };
        try formats.append(allocator, format);
    }

    // Process each input file (bounded by assertion)
    var processed_count: u32 = 0;
    for (config.inputs.items) |input_path| {
        std.debug.assert(processed_count < MAX_INPUT_FILES); // Loop invariant

        if (config.verbosity >= 1) {
            std.debug.print("Processing: {s}\n", .{input_path});
        }

        // Process single file
        const result = processSingleImage(
            allocator,
            input_path,
            config,
            formats.items,
        ) catch |err| {
            total_failed += 1;
            const exit_code = classifyError(err);
            if (@intFromEnum(exit_code) > @intFromEnum(worst_exit_code)) {
                worst_exit_code = exit_code;
            }

            if (config.verbosity >= 1) {
                std.log.err("Failed to process {s}: {} (exit code: {})", .{ input_path, err, exit_code.toU8() });
            }

            // In strict mode, fail immediately on first error
            if (config.strict_mode) {
                return ProcessingResult{
                    .total_processed = processed_count + 1,
                    .total_succeeded = total_succeeded,
                    .total_failed = total_failed,
                    .total_warnings = total_warnings,
                    .exit_code = exit_code,
                };
            }

            processed_count += 1;
            continue;
        };

        total_warnings += @intCast(result.warnings.len);

        // Check if optimization succeeded
        if (result.selected != null) {
            total_succeeded += 1;
        } else {
            total_failed += 1;
            // No candidate passed constraints
            if (config.max_bytes > 0 and config.max_diff > 0.0) {
                worst_exit_code = .diff_ceiling_unmet; // Assume diff was the issue
            } else if (config.max_bytes > 0) {
                worst_exit_code = .budget_unmet;
            } else {
                worst_exit_code = .diff_ceiling_unmet;
            }
        }

        // In strict mode, fail on warnings
        if (config.strict_mode and result.warnings.len > 0) {
            if (config.verbosity >= 1) {
                std.log.err("Strict mode: failing due to {d} warnings", .{result.warnings.len});
            }
            return ProcessingResult{
                .total_processed = processed_count + 1,
                .total_succeeded = total_succeeded,
                .total_failed = total_failed,
                .total_warnings = total_warnings,
                .exit_code = .cli_error, // Warnings treated as errors in strict mode
            };
        }

        processed_count += 1;
    }

    // Post-loop assertions
    std.debug.assert(processed_count == config.inputs.items.len);
    std.debug.assert(processed_count <= MAX_INPUT_FILES);
    std.debug.assert(total_succeeded + total_failed == processed_count);

    // Determine final exit code
    const final_exit_code: ExitCode = if (total_failed == 0)
        .success
    else if (worst_exit_code != .success)
        worst_exit_code
    else
        .cli_error; // Shouldn't happen, but safe fallback

    return ProcessingResult{
        .total_processed = processed_count,
        .total_succeeded = total_succeeded,
        .total_failed = total_failed,
        .total_warnings = total_warnings,
        .exit_code = final_exit_code,
    };
}

/// Process a single image file
///
/// Tiger Style: Clear error propagation, comprehensive logging
fn processSingleImage(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    config: *const cli.CliConfig,
    formats: []const types.ImageFormat,
) !optimizer.OptimizationResult {
    // Pre-conditions
    std.debug.assert(input_path.len > 0);
    std.debug.assert(formats.len > 0);

    // TODO: Implement output path generation
    // For now, use simple basename + format extension
    const basename = std.fs.path.basename(input_path);
    const output_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ config.output_dir, basename });
    defer allocator.free(output_path);

    // Create optimization job
    const max_bytes: ?u32 = if (config.max_bytes > 0) config.max_bytes else null;
    const max_diff: ?f64 = if (config.max_diff > 0.0) config.max_diff else null;

    var job = optimizer.OptimizationJob.init(input_path, output_path);
    job.max_bytes = max_bytes;
    job.max_diff = max_diff;
    job.metric_type = config.metric_type;
    job.formats = formats;
    job.concurrency = @intCast(if (config.concurrency > 0) config.concurrency else 4);

    // Run optimization
    const result = try optimizer.optimizeImage(allocator, job);

    // Post-condition: Result is valid
    std.debug.assert(result.all_candidates.len > 0);

    return result;
}

/// Classify error into appropriate exit code
///
/// Tiger Style: Explicit error mapping with exhaustive switch
fn classifyError(err: anyerror) ExitCode {
    return switch (err) {
        // Decode/transform errors (input image invalid)
        error.InvalidImage,
        error.UnsupportedFormat,
        error.FileNotFound,
        error.AccessDenied,
        error.IsDir,
        error.FileTooLarge,
        error.NotOpenForReading,
        => .decode_error,

        // Encode errors (codec failure)
        error.EncodeFailed,
        error.SaveFailed,
        => .encode_error,

        // Metric errors (perceptual metric computation failed)
        error.MetricFailed,
        error.DSSIMError,
        error.ButteraugliError,
        => .metric_error,

        // Memory/resource errors
        error.OutOfMemory => .cli_error,

        // Catch-all for unexpected errors
        else => .cli_error,
    };
}

// Unit tests
const testing = std.testing;

test "ExitCode.toU8 returns correct values" {
    try testing.expectEqual(@as(u8, 0), ExitCode.success.toU8());
    try testing.expectEqual(@as(u8, 1), ExitCode.cli_error.toU8());
    try testing.expectEqual(@as(u8, 10), ExitCode.budget_unmet.toU8());
    try testing.expectEqual(@as(u8, 11), ExitCode.diff_ceiling_unmet.toU8());
    try testing.expectEqual(@as(u8, 12), ExitCode.decode_error.toU8());
    try testing.expectEqual(@as(u8, 13), ExitCode.encode_error.toU8());
    try testing.expectEqual(@as(u8, 14), ExitCode.metric_error.toU8());
}

test "classifyError maps decode errors correctly" {
    try testing.expectEqual(ExitCode.decode_error, classifyError(error.InvalidImage));
    try testing.expectEqual(ExitCode.decode_error, classifyError(error.UnsupportedFormat));
    try testing.expectEqual(ExitCode.decode_error, classifyError(error.FileNotFound));
    try testing.expectEqual(ExitCode.decode_error, classifyError(error.FileTooLarge));
}

test "classifyError maps encode errors correctly" {
    try testing.expectEqual(ExitCode.encode_error, classifyError(error.EncodeFailed));
    try testing.expectEqual(ExitCode.encode_error, classifyError(error.SaveFailed));
}

test "classifyError maps metric errors correctly" {
    try testing.expectEqual(ExitCode.metric_error, classifyError(error.MetricFailed));
    try testing.expectEqual(ExitCode.metric_error, classifyError(error.DSSIMError));
    try testing.expectEqual(ExitCode.metric_error, classifyError(error.ButteraugliError));
}

test "classifyError maps unknown errors to cli_error" {
    try testing.expectEqual(ExitCode.cli_error, classifyError(error.OutOfMemory));
    try testing.expectEqual(ExitCode.cli_error, classifyError(error.Unexpected));
}

test "ProcessingResult tracks counts correctly" {
    const result = ProcessingResult{
        .total_processed = 10,
        .total_succeeded = 8,
        .total_failed = 2,
        .total_warnings = 5,
        .exit_code = .success,
    };

    try testing.expectEqual(@as(u32, 10), result.total_processed);
    try testing.expectEqual(@as(u32, 8), result.total_succeeded);
    try testing.expectEqual(@as(u32, 2), result.total_failed);
    try testing.expectEqual(@as(u32, 5), result.total_warnings);
    try testing.expectEqual(ExitCode.success, result.exit_code);
}

// Import tests from other modules
test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("cli.zig");
    _ = @import("types/image_buffer.zig");
    _ = @import("types/image_metadata.zig");
    _ = @import("vips.zig");
    _ = @import("image_ops.zig");
    _ = @import("codecs.zig");
    _ = @import("output.zig");
    _ = @import("manifest.zig");

    // Standalone test files
    _ = @import("test/unit/vips_test.zig");
    _ = @import("test/unit/image_ops_test.zig");
    _ = @import("test/unit/codecs_encoding_test.zig");

    // Integration tests (uncomment when ready)
    // Note: Integration tests are currently in conformance runner
    // Run with: zig build conformance
}
