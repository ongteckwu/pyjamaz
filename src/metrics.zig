//! Perceptual quality metrics for image optimization
//!
//! This module provides perceptual diff scoring to ensure optimized images
//! maintain visual quality. Supported metrics:
//! - Butteraugli (psychovisual distance) - STUB, not implemented
//! - DSSIM (structural similarity) - v0.4.0
//! - SSIMULACRA2 (perceptual similarity) - v0.5.0
//!
//! Tiger Style: Bounded operations, explicit error handling

const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("types/image_buffer.zig").ImageBuffer;
const dssim = @import("metrics/dssim.zig");
const ssimulacra2 = @import("metrics/ssimulacra2.zig");

pub const MetricError = error{
    UnsupportedMetric,
    ComputeFailed,
    DimensionMismatch,
    InvalidImage,
    OutOfMemory,
};

/// Supported perceptual metrics
pub const MetricType = enum {
    butteraugli, // STUB - not implemented (use ssimulacra2 instead)
    dssim, // v0.4.0 - Structural dissimilarity
    ssimulacra2, // v0.5.0 - Perceptual similarity (recommended)
    none, // For MVP - no perceptual checking
};

/// Compute perceptual difference between two images
///
/// Returns a score where:
/// - 0.0 = identical images
/// - Higher values = more perceptual difference
/// - Butteraugli: values > 1.5 are usually noticeable
/// - DSSIM: values > 0.01 are usually noticeable
///
/// Tiger Style:
/// - Pre-condition: Images must have same dimensions
/// - Bounded: Returns error for images > 500MP
/// - Memory-safe: All allocations tracked
pub fn computePerceptualDiff(
    allocator: Allocator,
    baseline: *const ImageBuffer,
    candidate: *const ImageBuffer,
    metric: MetricType,
) MetricError!f64 {
    // Pre-conditions: Validate inputs
    std.debug.assert(baseline.width > 0 and baseline.height > 0);
    std.debug.assert(candidate.width > 0 and candidate.height > 0);
    std.debug.assert(baseline.channels >= 3 and candidate.channels >= 3);

    // Dimensions must match
    if (baseline.width != candidate.width or baseline.height != candidate.height) {
        return MetricError.DimensionMismatch;
    }

    // Prevent OOM on huge images (Tiger Style: bounded operations)
    const MAX_PIXELS: u64 = 500_000_000; // 500 megapixels
    const total_pixels: u64 = @as(u64, baseline.width) * @as(u64, baseline.height);
    if (total_pixels > MAX_PIXELS) {
        std.log.err("Image too large for perceptual diff: {d} pixels (max: {d})", .{ total_pixels, MAX_PIXELS });
        return MetricError.InvalidImage;
    }

    const result = switch (metric) {
        .butteraugli => try computeButteraugli(allocator, baseline, candidate),
        .dssim => try computeDSSIM(allocator, baseline, candidate),
        .ssimulacra2 => try computeSSIMULACRA2(allocator, baseline, candidate),
        .none => 0.0, // MVP: no perceptual checking
    };

    // Post-conditions: Validate result (Tiger Style)
    std.debug.assert(result >= 0.0); // Non-negative
    std.debug.assert(!std.math.isNan(result)); // Not NaN
    std.debug.assert(!std.math.isInf(result)); // Not infinite

    return result;
}

/// Compute Butteraugli psychovisual distance
///
/// Returns distance where:
/// - 0.0 = identical
/// - 0.0-1.0 = barely noticeable
/// - 1.0-1.5 = small differences
/// - 1.5+ = noticeable differences
/// - 3.0+ = very noticeable
///
/// Tiger Style: Bounded iteration, explicit memory management
///
/// NOTE: This is a STUB implementation for v0.3.0 MVP.
/// Butteraugli FFI is not yet implemented. Use metric_type=.none to bypass.
fn computeButteraugli(
    allocator: Allocator,
    baseline: *const ImageBuffer,
    candidate: *const ImageBuffer,
) MetricError!f64 {
    _ = allocator;

    // Tiger Style: Fail loudly for unimplemented features
    // Returning 0.0 would falsely indicate "perfect match" and bypass quality constraints
    std.log.err("Butteraugli not implemented. Set metric_type=.none to bypass quality checks.", .{});
    std.log.err("Baseline: {d}x{d}, Candidate: {d}x{d}", .{
        baseline.width,
        baseline.height,
        candidate.width,
        candidate.height,
    });

    return MetricError.UnsupportedMetric;
}

/// Compute DSSIM (structural dissimilarity)
///
/// Returns dissimilarity where:
/// - 0.0 = identical
/// - 0.0-0.01 = barely noticeable
/// - 0.01-0.05 = small differences
/// - 0.05+ = noticeable differences
///
/// Tiger Style: Bounded iteration, memory-safe
fn computeDSSIM(
    allocator: Allocator,
    baseline: *const ImageBuffer,
    candidate: *const ImageBuffer,
) MetricError!f64 {
    return dssim.compute(allocator, baseline, candidate) catch |err| {
        std.log.err("DSSIM computation failed: {}", .{err});
        return MetricError.ComputeFailed;
    };
}

/// Compute SSIMULACRA2 (perceptual similarity)
///
/// SSIMULACRA2 returns a similarity score (higher = more similar).
/// This function converts it to a distance metric (lower = more similar)
/// to maintain API consistency with other metrics.
///
/// Returns distance where:
/// - 0.0 = identical (score 100)
/// - 0.0-0.001 = barely noticeable (score 95-100)
/// - 0.001-0.002 = small differences (score 90-95)
/// - 0.002+ = noticeable differences (score <90)
///
/// Tiger Style: Bounded iteration, memory-safe
/// v0.5.0: SSIMULACRA2 integration
fn computeSSIMULACRA2(
    allocator: Allocator,
    baseline: *const ImageBuffer,
    candidate: *const ImageBuffer,
) MetricError!f64 {
    const score = ssimulacra2.compute(allocator, baseline, candidate) catch |err| {
        std.log.err("SSIMULACRA2 computation failed: {}", .{err});
        return MetricError.ComputeFailed;
    };

    // Convert similarity score (0-100, higher=better) to distance (0+, lower=better)
    const distance = ssimulacra2.scoreToDistance(score);

    return distance;
}

/// Get recommended threshold for a metric
/// These are conservative values - most users want higher quality
pub fn getRecommendedThreshold(metric: MetricType) f64 {
    return switch (metric) {
        .butteraugli => 1.5, // Noticeable difference threshold
        .dssim => 0.01, // Small difference threshold
        .ssimulacra2 => 0.002, // Converted from score ~90 (acceptable quality)
        .none => std.math.floatMax(f64), // Effectively disabled
    };
}

// ============================================================================
// Unit Tests
// ============================================================================

test "getRecommendedThreshold returns sensible values" {
    const testing = std.testing;

    try testing.expectApproxEqAbs(1.5, getRecommendedThreshold(.butteraugli), 0.01);
    try testing.expectApproxEqAbs(0.01, getRecommendedThreshold(.dssim), 0.001);
    try testing.expectApproxEqAbs(0.002, getRecommendedThreshold(.ssimulacra2), 0.0001);
    try testing.expect(getRecommendedThreshold(.none) > 1000.0);
}

test "computePerceptualDiff rejects mismatched dimensions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var baseline = ImageBuffer{
        .data = &[_]u8{},
        .width = 100,
        .height = 100,
        .stride = 300,
        .channels = 3,
        .allocator = allocator,
        .color_space = 0,
    };

    var candidate = ImageBuffer{
        .data = &[_]u8{},
        .width = 200,
        .height = 100,
        .stride = 600,
        .channels = 3,
        .allocator = allocator,
        .color_space = 0,
    };

    const result = computePerceptualDiff(allocator, &baseline, &candidate, .none);
    try testing.expectError(MetricError.DimensionMismatch, result);
}

test "computePerceptualDiff with none metric returns 0.0" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var baseline = ImageBuffer{
        .data = &[_]u8{},
        .width = 100,
        .height = 100,
        .stride = 300,
        .channels = 3,
        .allocator = allocator,
        .color_space = 0,
    };

    var candidate = ImageBuffer{
        .data = &[_]u8{},
        .width = 100,
        .height = 100,
        .stride = 300,
        .channels = 3,
        .allocator = allocator,
        .color_space = 0,
    };

    const diff = try computePerceptualDiff(allocator, &baseline, &candidate, .none);
    try testing.expectEqual(@as(f64, 0.0), diff);
}

test "computePerceptualDiff with butteraugli stub returns UnsupportedMetric" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var baseline = ImageBuffer{
        .data = &[_]u8{},
        .width = 100,
        .height = 100,
        .stride = 300,
        .channels = 3,
        .allocator = allocator,
        .color_space = 0,
    };

    var candidate = ImageBuffer{
        .data = &[_]u8{},
        .width = 100,
        .height = 100,
        .stride = 300,
        .channels = 3,
        .allocator = allocator,
        .color_space = 0,
    };

    const result = computePerceptualDiff(allocator, &baseline, &candidate, .butteraugli);
    try testing.expectError(MetricError.UnsupportedMetric, result);
}

test "computePerceptualDiff validates image size limits" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create image that exceeds MAX_PIXELS (500 megapixels)
    var baseline = ImageBuffer{
        .data = &[_]u8{},
        .width = 50000, // 50k x 50k = 2.5 gigapixels > 500 megapixels
        .height = 50000,
        .stride = 150000,
        .channels = 3,
        .allocator = allocator,
        .color_space = 0,
    };

    var candidate = ImageBuffer{
        .data = &[_]u8{},
        .width = 50000,
        .height = 50000,
        .stride = 150000,
        .channels = 3,
        .allocator = allocator,
        .color_space = 0,
    };

    const result = computePerceptualDiff(allocator, &baseline, &candidate, .none);
    try testing.expectError(MetricError.InvalidImage, result);
}
