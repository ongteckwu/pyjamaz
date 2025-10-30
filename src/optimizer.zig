const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const types = @import("types.zig");
const ImageBuffer = types.ImageBuffer;
const ImageMetadata = types.ImageMetadata;
const ImageFormat = types.ImageFormat;
const TransformParams = @import("types/transform_params.zig").TransformParams;
const image_ops = @import("image_ops.zig");
const codecs = @import("codecs.zig");
const search = @import("search.zig");

/// Represents a single encoded candidate result
pub const EncodedCandidate = struct {
    format: ImageFormat,
    encoded_bytes: []u8, // Owned by this struct
    file_size: u32,
    quality: u8,
    diff_score: f64, // Stubbed to 0.0 for MVP, real metric in 0.2.0
    passed_constraints: bool,
    encoding_time_ns: u64,

    pub fn deinit(self: *EncodedCandidate, allocator: Allocator) void {
        allocator.free(self.encoded_bytes);
    }
};

/// Input parameters for image optimization
pub const OptimizationJob = struct {
    input_path: []const u8,
    output_path: []const u8,
    max_bytes: ?u32, // null = no size constraint
    max_diff: ?f64, // null = no quality constraint (stubbed for MVP)
    formats: []const ImageFormat, // Formats to try
    transform_params: TransformParams,
    concurrency: u8, // Max parallel encoding tasks

    /// Create a basic job with sensible defaults
    pub fn init(input_path: []const u8, output_path: []const u8) OptimizationJob {
        return .{
            .input_path = input_path,
            .output_path = output_path,
            .max_bytes = null,
            .max_diff = null,
            .formats = &[_]ImageFormat{ .jpeg, .png },
            .transform_params = TransformParams.init(),
            .concurrency = 4,
        };
    }
};

/// Timing breakdown for optimization pipeline
pub const OptimizationTimings = struct {
    decode_ns: u64,
    encode_ns: u64,
    total_ns: u64,
};

/// Result of image optimization
pub const OptimizationResult = struct {
    selected: ?EncodedCandidate, // null if no candidate passed constraints
    all_candidates: []EncodedCandidate, // All attempted candidates
    timings: OptimizationTimings,
    warnings: [][]const u8, // Owned warning strings
    success: bool,

    pub fn deinit(self: *OptimizationResult, allocator: Allocator) void {
        // Free selected candidate if present
        if (self.selected) |*selected| {
            selected.deinit(allocator);
        }

        // Free all candidates
        for (self.all_candidates) |*candidate| {
            candidate.deinit(allocator);
        }
        allocator.free(self.all_candidates);

        // Free warnings
        for (self.warnings) |warning| {
            allocator.free(warning);
        }
        allocator.free(self.warnings);
    }
};

/// Main optimization function - orchestrates the entire pipeline
///
/// Steps:
/// 1. Decode and normalize input image
/// 2. Generate candidates in parallel (one per format)
/// 3. Score candidates (stubbed for MVP)
/// 4. Select best passing candidate
/// 5. Return detailed result
///
/// Tiger Style:
/// - Bounded parallelism (job.concurrency)
/// - Explicit error handling
/// - Each step bounded to avoid infinite loops
pub fn optimizeImage(
    allocator: Allocator,
    job: OptimizationJob,
) !OptimizationResult {
    // Validate inputs
    std.debug.assert(job.formats.len > 0);
    std.debug.assert(job.concurrency > 0);
    std.debug.assert(job.input_path.len > 0);
    std.debug.assert(job.output_path.len > 0);

    const start_time = std.time.nanoTimestamp();
    var warnings = ArrayList([]u8){};
    errdefer {
        for (warnings.items) |warning| allocator.free(warning);
        warnings.deinit(allocator);
    }

    // Step 1: Decode and normalize
    const decode_start = std.time.nanoTimestamp();
    var buffer = try image_ops.decodeImage(allocator, job.input_path);
    errdefer buffer.deinit();
    const decode_time = @as(u64, @intCast(std.time.nanoTimestamp() - decode_start));

    // Step 2: Generate candidates in parallel
    const encode_start = std.time.nanoTimestamp();
    var candidates = try generateCandidates(
        allocator,
        &buffer,
        job.formats,
        job.max_bytes,
        job.concurrency,
        &warnings,
    );
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }
    const encode_time = @as(u64, @intCast(std.time.nanoTimestamp() - encode_start));

    buffer.deinit(); // No longer needed

    // Step 2.5: Add original file as baseline candidate
    // This ensures we never make files larger - original can be selected if smallest
    const original_bytes = blk: {
        const file = try std.fs.cwd().openFile(job.input_path, .{});
        defer file.close();
        const stat = try file.stat();
        break :blk try file.readToEndAlloc(allocator, stat.size);
    };
    errdefer allocator.free(original_bytes);

    const original_format = try image_ops.getImageMetadata(job.input_path);

    const original_candidate = EncodedCandidate{
        .format = original_format.format,
        .encoded_bytes = original_bytes,
        .file_size = @intCast(original_bytes.len),
        .quality = 100, // Original quality
        .diff_score = 0.0, // Perfect match to original
        .passed_constraints = if (job.max_bytes) |max| original_bytes.len <= max else true,
        .encoding_time_ns = 0, // No encoding needed
    };
    try candidates.append(allocator, original_candidate);
    // Note: original_bytes now owned by candidates list, errdefer above no longer applies

    // Step 3: Score candidates (stubbed - all get diff_score = 0.0)
    // In 0.2.0 this will compute Butteraugli/DSSIM

    // Step 4: Select best candidate
    const selected = try selectBestCandidate(
        allocator,
        candidates.items,
        job.max_bytes,
        job.max_diff,
    );

    const total_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

    return .{
        .selected = selected,
        .all_candidates = try candidates.toOwnedSlice(allocator),
        .timings = .{
            .decode_ns = decode_time,
            .encode_ns = encode_time,
            .total_ns = total_time,
        },
        .warnings = @ptrCast(try warnings.toOwnedSlice(allocator)),
        .success = selected != null,
    };
}

/// Generate encoding candidates for all requested formats
///
/// Tiger Style:
/// - Bounded loop (iterates exactly formats.len times)
/// - Bounded parallelism (respects max_workers)
/// - Handles encoder errors gracefully (logs, continues)
fn generateCandidates(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    max_workers: u8,
    warnings: *ArrayList([]u8),
) !ArrayList(EncodedCandidate) {
    std.debug.assert(formats.len > 0);
    std.debug.assert(max_workers > 0);

    var candidates = ArrayList(EncodedCandidate){};
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    // For MVP: Sequential encoding (parallel encoding in future iteration)
    // Tiger Style: Bounded loop (exactly formats.len iterations)
    for (formats) |format| {
        const candidate = encodeCandidateForFormat(
            allocator,
            buffer,
            format,
            max_bytes,
        ) catch |err| {
            // Log error and continue with other formats
            const warning = try std.fmt.allocPrint(
                allocator,
                "Failed to encode {s}: {}",
                .{ @tagName(format), err },
            );
            try warnings.append(allocator, warning);
            continue;
        };
        try candidates.append(allocator, candidate);
    }

    return candidates;
}

/// Encode a single candidate for a specific format
///
/// Uses binary search to hit size target if max_bytes is specified,
/// otherwise uses default quality.
fn encodeCandidateForFormat(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    format: ImageFormat,
    max_bytes: ?u32,
) !EncodedCandidate {
    const encode_start = std.time.nanoTimestamp();

    var encoded_bytes: []u8 = undefined;
    var quality: u8 = undefined;

    if (max_bytes) |target_bytes| {
        // Use binary search to hit target size
        const search_result = try search.binarySearchQuality(
            allocator,
            buffer.*,
            format,
            target_bytes,
            .{}, // Default search options
        );
        encoded_bytes = search_result.encoded;
        quality = search_result.quality;
    } else {
        // No size constraint - use default quality
        quality = codecs.getDefaultQuality(format);
        encoded_bytes = try codecs.encodeImage(allocator, buffer, format, quality);
    }

    const encode_time = @as(u64, @intCast(std.time.nanoTimestamp() - encode_start));
    const file_size: u32 = @intCast(encoded_bytes.len);

    // Check if constraints are met
    const passed = blk: {
        if (max_bytes) |limit| {
            if (file_size > limit) break :blk false;
        }
        // In 0.2.0: Also check max_diff constraint here
        break :blk true;
    };

    return .{
        .format = format,
        .encoded_bytes = encoded_bytes,
        .file_size = file_size,
        .quality = quality,
        .diff_score = 0.0, // Stubbed for MVP
        .passed_constraints = passed,
        .encoding_time_ns = encode_time,
    };
}

/// Select the best candidate that passes all constraints
///
/// Selection criteria:
/// 1. Must pass size constraint (bytes <= max_bytes)
/// 2. Must pass quality constraint (diff <= max_diff) [stubbed for MVP]
/// 3. Prefer smallest file size
/// 4. Tiebreak by format preference (AVIF > WebP > JPEG > PNG)
///
/// Returns null if no candidate passes constraints.
fn selectBestCandidate(
    allocator: Allocator,
    candidates: []const EncodedCandidate,
    max_bytes: ?u32,
    max_diff: ?f64,
) !?EncodedCandidate {
    _ = max_diff; // Stubbed for MVP
    std.debug.assert(candidates.len > 0);

    var best: ?*const EncodedCandidate = null;

    // Tiger Style: Bounded loop (exactly candidates.len iterations)
    for (candidates) |*candidate| {
        // Filter: Check size constraint
        if (max_bytes) |limit| {
            if (candidate.file_size > limit) continue;
        }

        // Filter: Check diff constraint (stubbed for MVP)
        // In 0.2.0: if (max_diff) |limit| if (candidate.diff_score > limit) continue;

        // Select if first passing candidate or smaller than current best
        if (best == null or candidate.file_size < best.?.file_size) {
            best = candidate;
        } else if (candidate.file_size == best.?.file_size) {
            // Tiebreak by format preference
            if (formatPreference(candidate.format) > formatPreference(best.?.format)) {
                best = candidate;
            }
        }
    }

    if (best) |b| {
        // Clone the best candidate for return
        const cloned_bytes = try allocator.dupe(u8, b.encoded_bytes);
        return .{
            .format = b.format,
            .encoded_bytes = cloned_bytes,
            .file_size = b.file_size,
            .quality = b.quality,
            .diff_score = b.diff_score,
            .passed_constraints = b.passed_constraints,
            .encoding_time_ns = b.encoding_time_ns,
        };
    }

    return null;
}

/// Format preference for tiebreaking (higher = better)
fn formatPreference(format: ImageFormat) u8 {
    return switch (format) {
        .avif => 4, // Best compression, modern
        .webp => 3, // Good compression, wide support
        .jpeg => 2, // Universal support
        .png => 1, // Lossless but often larger
        .unknown => 0,
    };
}

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

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

test "OptimizationJob: init with defaults" {
    const job = OptimizationJob.init("input.jpg", "output.jpg");
    try testing.expectEqualStrings("input.jpg", job.input_path);
    try testing.expectEqualStrings("output.jpg", job.output_path);
    try testing.expectEqual(@as(?u32, null), job.max_bytes);
    try testing.expectEqual(@as(u8, 4), job.concurrency);
    try testing.expect(job.formats.len >= 2);
}

test "formatPreference: correct ordering" {
    try testing.expect(formatPreference(.avif) > formatPreference(.webp));
    try testing.expect(formatPreference(.webp) > formatPreference(.jpeg));
    try testing.expect(formatPreference(.jpeg) > formatPreference(.png));
    try testing.expect(formatPreference(.png) > formatPreference(.unknown));
}

test "selectBestCandidate: picks smallest passing candidate" {
    const candidates = [_]EncodedCandidate{
        .{
            .format = .jpeg,
            .encoded_bytes = try testing.allocator.alloc(u8, 1000),
            .file_size = 1000,
            .quality = 85,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1000,
        },
        .{
            .format = .png,
            .encoded_bytes = try testing.allocator.alloc(u8, 800),
            .file_size = 800,
            .quality = 6,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1200,
        },
    };
    defer {
        testing.allocator.free(candidates[0].encoded_bytes);
        testing.allocator.free(candidates[1].encoded_bytes);
    }

    const best = try selectBestCandidate(
        testing.allocator,
        &candidates,
        null,
        null,
    );

    try testing.expect(best != null);
    try testing.expectEqual(@as(u32, 800), best.?.file_size);
    try testing.expectEqual(ImageFormat.png, best.?.format);
}

test "selectBestCandidate: respects size constraint" {
    const candidates = [_]EncodedCandidate{
        .{
            .format = .jpeg,
            .encoded_bytes = try testing.allocator.alloc(u8, 1000),
            .file_size = 1000,
            .quality = 85,
            .diff_score = 0.0,
            .passed_constraints = false,
            .encoding_time_ns = 1000,
        },
        .{
            .format = .png,
            .encoded_bytes = try testing.allocator.alloc(u8, 1500),
            .file_size = 1500,
            .quality = 6,
            .diff_score = 0.0,
            .passed_constraints = false,
            .encoding_time_ns = 1200,
        },
    };
    defer {
        testing.allocator.free(candidates[0].encoded_bytes);
        testing.allocator.free(candidates[1].encoded_bytes);
    }

    // Max 900 bytes - both candidates too large
    const best = try selectBestCandidate(
        testing.allocator,
        &candidates,
        900,
        null,
    );

    try testing.expect(best == null);
}

test "selectBestCandidate: format tiebreak" {
    const candidates = [_]EncodedCandidate{
        .{
            .format = .png,
            .encoded_bytes = try testing.allocator.alloc(u8, 800),
            .file_size = 800,
            .quality = 6,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1200,
        },
        .{
            .format = .webp,
            .encoded_bytes = try testing.allocator.alloc(u8, 800),
            .file_size = 800,
            .quality = 75,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1000,
        },
    };
    defer {
        testing.allocator.free(candidates[0].encoded_bytes);
        testing.allocator.free(candidates[1].encoded_bytes);
    }

    const best = try selectBestCandidate(
        testing.allocator,
        &candidates,
        null,
        null,
    );

    try testing.expect(best != null);
    // WebP preferred over PNG at same size
    try testing.expectEqual(ImageFormat.webp, best.?.format);
}
