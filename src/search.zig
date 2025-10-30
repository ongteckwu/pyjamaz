const std = @import("std");
const ImageBuffer = @import("types/image_buffer.zig").ImageBuffer;
const ImageFormat = @import("types/image_metadata.zig").ImageFormat;
const codecs = @import("codecs.zig");

/// Options for binary search quality optimization
pub const SearchOptions = struct {
    /// Maximum number of iterations (Tiger Style: explicit bound)
    max_iterations: u8 = 7,
    /// Tolerance percentage (e.g., 0.01 for 1%)
    tolerance: f32 = 0.01,
    /// Minimum quality to try
    quality_min: u8 = 0,
    /// Maximum quality to try
    quality_max: u8 = 100,
    /// Maximum encode time in milliseconds (warning threshold)
    max_encode_time_ms: u64 = 5000,
    /// If true, return error if no candidate meets budget
    /// If false, return closest candidate with warning
    strict_budget: bool = false,
};

/// Result of a binary search
pub const SearchResult = struct {
    /// The encoded bytes that best match the target
    encoded: []u8,
    /// Quality value used for this encoding
    quality: u8,
    /// Actual size of the encoded bytes
    size: u32,
    /// Number of iterations taken
    iterations: u8,
};

/// Performs binary search to find the quality setting that produces
/// an encoded image closest to (but not exceeding) the target size.
///
/// Tiger Style:
/// - Bounded iterations (max_iterations)
/// - Explicit quality bounds
/// - Proper memory management for intermediate results
///
/// Returns the best candidate within tolerance, or the smallest one found if
/// no candidate is within tolerance.
pub fn binarySearchQuality(
    allocator: std.mem.Allocator,
    buffer: ImageBuffer,
    format: ImageFormat,
    target_bytes: u32,
    opts: SearchOptions,
) !SearchResult {
    // Tiger Style: Assertions for pre-conditions
    std.debug.assert(opts.quality_min <= opts.quality_max);
    std.debug.assert(opts.max_iterations > 0);
    std.debug.assert(target_bytes > 0);
    std.debug.assert(opts.tolerance > 0.0 and opts.tolerance < 1.0);

    var q_min: u8 = opts.quality_min;
    var q_max: u8 = opts.quality_max;
    var iteration: u8 = 0;

    // Track best candidate so far
    var best_quality: u8 = opts.quality_min;
    var best_encoded: ?[]u8 = null;
    var best_size: u32 = std.math.maxInt(u32);
    var best_distance: u32 = std.math.maxInt(u32);

    defer {
        // Only free if we didn't return it
        if (best_encoded) |encoded| {
            if (best_quality != q_min or iteration == 0) {
                allocator.free(encoded);
            }
        }
    }

    // Tiger Style: Bounded loop with invariants
    while (iteration < opts.max_iterations and q_min <= q_max) : (iteration += 1) {
        // Loop invariants (Tiger Style)
        std.debug.assert(q_min <= q_max);
        std.debug.assert(q_min >= opts.quality_min);
        std.debug.assert(q_max <= opts.quality_max);

        const q_mid = q_min + (q_max - q_min) / 2;
        std.debug.assert(q_mid >= q_min and q_mid <= q_max);

        // Encode at this quality (track time for performance monitoring)
        const start_time = std.time.milliTimestamp();
        const encoded = try codecs.encodeImage(allocator, &buffer, format, q_mid);
        const encode_time = std.time.milliTimestamp() - start_time;

        // Warn if encoding is taking too long (potential malformed image)
        if (encode_time > @as(i64, @intCast(opts.max_encode_time_ms))) {
            std.log.warn("Encoding took {d}ms (>{d}ms threshold) at quality {d}", .{ encode_time, opts.max_encode_time_ms, q_mid });
        }

        const size: u32 = @intCast(encoded.len);

        // Invariant: Encoded data is non-empty
        std.debug.assert(size > 0);
        std.debug.assert(encoded.len > 0);

        // Calculate distance from target
        const distance = if (size > target_bytes)
            size - target_bytes
        else
            target_bytes - size;

        // Check if this is within tolerance
        const tolerance_bytes: u32 = @intFromFloat(@as(f32, @floatFromInt(target_bytes)) * opts.tolerance);
        const within_tolerance = distance <= tolerance_bytes;

        // Update best candidate if this is better
        const is_better = if (size <= target_bytes)
            // Prefer candidates under budget, bigger is better
            size > best_size and best_size <= target_bytes
        else if (best_size > target_bytes)
            // Both over budget, prefer smaller
            size < best_size
        else
            // This is over budget but best is under, keep best
            false;

        if (is_better or best_encoded == null) {
            // Free old best
            if (best_encoded) |old| {
                allocator.free(old);
            }
            best_encoded = encoded;
            best_quality = q_mid;
            best_size = size;
            best_distance = distance;
        } else {
            // This isn't better, free it
            allocator.free(encoded);
        }

        // If within tolerance and under budget, we're done
        if (within_tolerance and size <= target_bytes) {
            break;
        }

        // Adjust search bounds
        if (size > target_bytes) {
            // Too big, reduce quality
            if (q_mid == 0) break;
            q_max = q_mid - 1;
        } else {
            // Too small, increase quality
            if (q_mid == 100) break;
            q_min = q_mid + 1;
        }

        // Post-iteration invariant
        std.debug.assert(q_min <= opts.quality_max + 1);
        std.debug.assert(q_max >= opts.quality_min - 1);
    }

    // Tiger Style: Post-loop assertions
    std.debug.assert(iteration <= opts.max_iterations);
    std.debug.assert(best_encoded != null);
    std.debug.assert(best_size > 0 and best_size < std.math.maxInt(u32));
    std.debug.assert(best_quality >= opts.quality_min and best_quality <= opts.quality_max);
    std.debug.assert(best_distance < std.math.maxInt(u32));

    // HIGH-003: Check if we met budget (strict mode)
    if (best_size > target_bytes) {
        if (opts.strict_budget) {
            std.log.err("No candidate met budget of {d} bytes (best: {d} bytes at quality {d})", .{ target_bytes, best_size, best_quality });
            allocator.free(best_encoded.?);
            return error.BudgetNotMet;
        } else {
            std.log.warn("Best candidate ({d} bytes) exceeds budget ({d} bytes) by {d} bytes", .{ best_size, target_bytes, best_size - target_bytes });
        }
    }

    return SearchResult{
        .encoded = best_encoded.?,
        .quality = best_quality,
        .size = best_size,
        .iterations = iteration,
    };
}

// Unit tests
test "binarySearchQuality: converges to target size" {
    const testing = std.testing;

    // Create a simple test image (10x10 red square)
    var buffer = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer buffer.deinit();

    // Fill with red
    var i: u32 = 0;
    while (i < buffer.height) : (i += 1) {
        const row = buffer.getRow(i);
        var j: u32 = 0;
        while (j < buffer.width) : (j += 1) {
            row[j * 3 + 0] = 255; // R
            row[j * 3 + 1] = 0;   // G
            row[j * 3 + 2] = 0;   // B
        }
    }

    // Search for a target size (this is approximate, actual size varies by codec)
    const target_bytes: u32 = 500;
    const result = try binarySearchQuality(
        testing.allocator,
        buffer,
        .jpeg,
        target_bytes,
        .{},
    );
    defer testing.allocator.free(result.encoded);

    // Verify we got a result
    try testing.expect(result.size > 0);
    try testing.expect(result.quality >= 0 and result.quality <= 100);
    try testing.expect(result.iterations > 0 and result.iterations <= 7);

    // The result should be reasonably close to target (within 50% for this test)
    const max_distance = target_bytes / 2;
    const distance = if (result.size > target_bytes)
        result.size - target_bytes
    else
        target_bytes - result.size;
    try testing.expect(distance <= max_distance);
}

test "binarySearchQuality: respects max iterations" {
    const testing = std.testing;

    var buffer = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer buffer.deinit();

    const result = try binarySearchQuality(
        testing.allocator,
        buffer,
        .jpeg,
        1000,
        .{ .max_iterations = 3 },
    );
    defer testing.allocator.free(result.encoded);

    try testing.expect(result.iterations <= 3);
}

test "binarySearchQuality: handles quality bounds" {
    const testing = std.testing;

    var buffer = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer buffer.deinit();

    // Search with limited quality range
    const result = try binarySearchQuality(
        testing.allocator,
        buffer,
        .jpeg,
        1000,
        .{ .quality_min = 50, .quality_max = 70 },
    );
    defer testing.allocator.free(result.encoded);

    try testing.expect(result.quality >= 50 and result.quality <= 70);
}

test "binarySearchQuality: no memory leaks" {
    const testing = std.testing;

    var buffer = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer buffer.deinit();

    // Run multiple searches to verify no leaks
    var count: u32 = 0;
    while (count < 5) : (count += 1) {
        const result = try binarySearchQuality(
            testing.allocator,
            buffer,
            .jpeg,
            500 + count * 100,
            .{},
        );
        testing.allocator.free(result.encoded);
    }

    // If we get here without leaks detected, test passes
    try testing.expect(true);
}
