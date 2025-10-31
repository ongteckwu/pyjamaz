//! SSIMULACRA2 perceptual metric
//!
//! Pure Zig implementation via fssimu2 library.
//! SSIMULACRA2 is based on MS-SSIM in a perceptually relevant color space (XYB),
//! adding asymmetric error maps for blockiness/ringing and smoothing/blur.
//!
//! Higher scores = more similar images (opposite of DSSIM!)
//! Score range: -inf to 100
//! Typical thresholds:
//! - 95+: Visually identical
//! - 90-95: Barely noticeable
//! - 80-90: Noticeable but acceptable
//! - <80: Clearly different
//!
//! References:
//! - https://github.com/cloudinary/ssimulacra2
//! - https://github.com/gianni-rosato/fssimu2
//!
//! v0.5.0: SSIMULACRA2 integration

const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("../types/image_buffer.zig").ImageBuffer;
const fssimu2 = @import("fssimu2");

/// Compute SSIMULACRA2 score between two images
///
/// Higher score = more similar images (0-100 range, 100 = identical)
/// Returns error if images have mismatched dimensions or invalid data
///
/// Tiger Style:
/// - Pre-condition: Images must have same width/height
/// - Pre-condition: Images must have RGB or RGBA data
/// - Bounded operation: O(width * height * channels)
/// - Post-condition: Score is valid (not NaN, in reasonable range)
pub fn compute(
    allocator: Allocator,
    baseline: *const ImageBuffer,
    candidate: *const ImageBuffer,
) !f64 {
    // Pre-conditions
    std.debug.assert(baseline.width > 0 and baseline.height > 0);
    std.debug.assert(candidate.width > 0 and candidate.height > 0);
    std.debug.assert(baseline.width == candidate.width);
    std.debug.assert(baseline.height == candidate.height);
    std.debug.assert(baseline.channels >= 3 and baseline.channels <= 4);
    std.debug.assert(candidate.channels >= 3 and candidate.channels <= 4);
    std.debug.assert(baseline.data.len > 0);
    std.debug.assert(candidate.data.len > 0);

    // fssimu2 expects interleaved RGB/RGBA data
    // Our ImageBuffer already has this format from libvips
    const score = try fssimu2.computeSsimu2(
        allocator,
        baseline.data,
        candidate.data,
        baseline.width,
        baseline.height,
        baseline.channels,
        null, // No error map needed for now
    );

    // Post-condition: Valid SSIMULACRA2 score
    std.debug.assert(!std.math.isNan(score));
    std.debug.assert(!std.math.isInf(score)); // Sanity check
    // Note: Score can be negative for very different images, so no lower bound

    return score;
}

/// Convert SSIMULACRA2 score (0-100, higher=better) to DSSIM-like distance (0+, lower=better)
///
/// This allows using SSIMULACRA2 with the same threshold logic as DSSIM.
/// Rough mapping:
/// - Score 100 → distance 0.0000 (identical)
/// - Score 95  → distance 0.0005 (barely noticeable)
/// - Score 90  → distance 0.0020 (noticeable)
/// - Score 80  → distance 0.0100 (clearly different)
/// - Score 70  → distance 0.0200
/// - Score <70 → distance 0.0300+
///
/// Tiger Style:
/// - Pre-condition: score is valid (not NaN/Inf)
/// - Post-condition: distance >= 0.0
pub fn scoreToDistance(score: f64) f64 {
    std.debug.assert(!std.math.isNan(score));
    std.debug.assert(!std.math.isInf(score));

    // Exponential mapping: distance = e^((100 - score) / 20) * 0.0001
    // This gives a reasonable scale compared to DSSIM
    const normalized = (100.0 - score) / 20.0;
    const distance = @exp(normalized) * 0.0001;

    // Post-condition
    std.debug.assert(distance >= 0.0);
    std.debug.assert(!std.math.isNan(distance));

    return distance;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "SSIMULACRA2: identical RGB images return high score" {
    const allocator = testing.allocator;

    // Create identical 32x32 RGB images
    const width: u32 = 32;
    const height: u32 = 32;
    const channels: u8 = 3;
    const size = @as(usize, width) * height * channels;

    const data = try allocator.alloc(u8, size);
    defer allocator.free(data);

    // Fill with mid-gray
    @memset(data, 128);

    const img1 = ImageBuffer{
        .data = data,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 1, // sRGB
    };

    const score = try compute(allocator, &img1, &img1);

    // Identical images should score very high (close to 100)
    try testing.expect(score >= 99.0);
    try testing.expect(score <= 100.0);
}

test "SSIMULACRA2: identical RGBA images return high score" {
    const allocator = testing.allocator;

    const width: u32 = 32;
    const height: u32 = 32;
    const channels: u8 = 4;
    const size = @as(usize, width) * height * channels;

    const data = try allocator.alloc(u8, size);
    defer allocator.free(data);

    // Fill with mid-gray + full alpha
    var i: usize = 0;
    while (i < size) : (i += 4) {
        data[i] = 128; // R
        data[i + 1] = 128; // G
        data[i + 2] = 128; // B
        data[i + 3] = 255; // A
    }

    const img1 = ImageBuffer{
        .data = data,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 1,
    };

    const score = try compute(allocator, &img1, &img1);

    try testing.expect(score >= 99.0);
    try testing.expect(score <= 100.0);
}

test "SSIMULACRA2: very different images return low score" {
    const allocator = testing.allocator;

    const width: u32 = 32;
    const height: u32 = 32;
    const channels: u8 = 3;
    const size = @as(usize, width) * height * channels;

    // Black image
    const black = try allocator.alloc(u8, size);
    defer allocator.free(black);
    @memset(black, 0);

    // White image
    const white = try allocator.alloc(u8, size);
    defer allocator.free(white);
    @memset(white, 255);

    const img_black = ImageBuffer{
        .data = black,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 1,
    };

    const img_white = ImageBuffer{
        .data = white,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 1,
    };

    const score = try compute(allocator, &img_black, &img_white);

    // Black vs white should score very low (well below 80)
    try testing.expect(score < 50.0);
}

test "SSIMULACRA2: slightly different images return moderate score" {
    const allocator = testing.allocator;

    const width: u32 = 32;
    const height: u32 = 32;
    const channels: u8 = 3;
    const size = @as(usize, width) * height * channels;

    // Image 1: gray (128)
    const gray1 = try allocator.alloc(u8, size);
    defer allocator.free(gray1);
    @memset(gray1, 128);

    // Image 2: slightly darker gray (120)
    const gray2 = try allocator.alloc(u8, size);
    defer allocator.free(gray2);
    @memset(gray2, 120);

    const img1 = ImageBuffer{
        .data = gray1,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 1,
    };

    const img2 = ImageBuffer{
        .data = gray2,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 1,
    };

    const score = try compute(allocator, &img1, &img2);

    // Slightly different images should score in moderate range (80-95)
    try testing.expect(score >= 75.0);
    try testing.expect(score <= 98.0);
}

test "SSIMULACRA2: scoreToDistance conversion" {
    // Test score-to-distance mapping
    const dist_100 = scoreToDistance(100.0);
    const dist_95 = scoreToDistance(95.0);
    const dist_90 = scoreToDistance(90.0);
    const dist_80 = scoreToDistance(80.0);

    // Higher scores → lower distances
    try testing.expect(dist_100 < dist_95);
    try testing.expect(dist_95 < dist_90);
    try testing.expect(dist_90 < dist_80);

    // Score 100 should give very small distance
    try testing.expect(dist_100 < 0.0002);

    // All distances should be positive
    try testing.expect(dist_100 >= 0.0);
    try testing.expect(dist_95 >= 0.0);
    try testing.expect(dist_90 >= 0.0);
    try testing.expect(dist_80 >= 0.0);
}

test "SSIMULACRA2: mixed RGB and RGBA comparison" {
    const allocator = testing.allocator;

    const width: u32 = 32;
    const height: u32 = 32;

    // RGB image
    const rgb_size = @as(usize, width) * height * 3;
    const rgb_data = try allocator.alloc(u8, rgb_size);
    defer allocator.free(rgb_data);
    @memset(rgb_data, 128);

    // RGBA image (same content, with alpha)
    const rgba_size = @as(usize, width) * height * 4;
    const rgba_data = try allocator.alloc(u8, rgba_size);
    defer allocator.free(rgba_data);

    var i: usize = 0;
    var j: usize = 0;
    while (i < rgba_size) : (i += 4) {
        rgba_data[i] = 128;
        rgba_data[i + 1] = 128;
        rgba_data[i + 2] = 128;
        rgba_data[i + 3] = 255;
        j += 3;
    }

    const img_rgb = ImageBuffer{
        .data = rgb_data,
        .width = width,
        .height = height,
        .stride = width * 3,
        .channels = 3,
        .allocator = allocator,
        .color_space = 1,
    };

    const img_rgba = ImageBuffer{
        .data = rgba_data,
        .width = width,
        .height = height,
        .stride = width * 4,
        .channels = 4,
        .allocator = allocator,
        .color_space = 1,
    };

    // fssimu2 handles both RGB and RGBA
    const score = try compute(allocator, &img_rgb, &img_rgba);

    // Should still score high (content is the same)
    try testing.expect(score >= 85.0);
}
