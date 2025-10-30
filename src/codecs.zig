const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("types/image_buffer.zig").ImageBuffer;
const ImageFormat = @import("types/image_metadata.zig").ImageFormat;
const vips = @import("vips.zig");

/// Unified codec interface for Pyjamaz
///
/// This module provides a consistent API for encoding images to different formats
/// (JPEG, PNG, WebP, AVIF) using libvips as the backend.
///
/// Tiger Style: Bounded quality parameters, explicit error handling, memory safety.

pub const CodecError = error{
    UnsupportedFormat,
    EncodeFailed,
    InvalidQuality,
    InvalidImage,
};

/// Encode ImageBuffer to specified format
///
/// Format: Target image format (JPEG, PNG, WebP, AVIF)
/// Quality: 0-100 for JPEG/WebP/AVIF, 0-9 for PNG compression
///
/// Safety: Returns owned slice, caller must free with allocator
/// Tiger Style: Quality bounded, format validated, magic numbers verified
pub fn encodeImage(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    format: ImageFormat,
    quality: u8,
) ![]u8 {
    // Pre-conditions
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);

    // Validate quality based on format
    switch (format) {
        .jpeg, .webp, .avif => std.debug.assert(quality <= 100),
        .png => std.debug.assert(quality <= 9),
        .unknown => return CodecError.UnsupportedFormat,
    }

    // Warn if encoding RGBA to format that doesn't support alpha
    if (buffer.channels == 4 and !formatSupportsAlpha(format)) {
        std.log.warn("Encoding RGBA image to {s} will discard alpha channel", .{@tagName(format)});
    }

    // Create vips image from buffer
    var vips_img = try vips.VipsImageWrapper.fromImageBuffer(buffer);
    defer vips_img.deinit();

    // Encode to target format
    const encoded = try switch (format) {
        .jpeg => vips_img.saveAsJPEG(allocator, quality),
        .png => vips_img.saveAsPNG(allocator, @min(quality, 9)),
        .webp => {
            // TODO: Add WebP encoding when vips_webpsave_buffer is bound
            std.debug.print("WebP encoding not yet implemented\n", .{});
            return CodecError.UnsupportedFormat;
        },
        .avif => {
            // TODO: Add AVIF encoding when vips_avifsave_buffer is bound
            std.debug.print("AVIF encoding not yet implemented\n", .{});
            return CodecError.UnsupportedFormat;
        },
        .unknown => CodecError.UnsupportedFormat,
    };

    // Post-conditions: Validate encoded data (Tiger Style)
    std.debug.assert(encoded.len > 0);
    std.debug.assert(encoded.len < 100 * 1024 * 1024); // Sanity check: <100MB

    // HIGH-009: Runtime check for zero-byte encoded files (codec corruption)
    if (encoded.len == 0) {
        std.log.err("Codec produced zero-byte output for format {s}", .{@tagName(format)});
        return CodecError.EncodeFailed;
    }

    // Verify magic numbers (already done in vips.zig saveAsJPEG/saveAsPNG)
    // But we add extra verification here for defense in depth
    switch (format) {
        .jpeg => {
            std.debug.assert(encoded.len >= 2);
            std.debug.assert(encoded[0] == 0xFF and encoded[1] == 0xD8); // JPEG SOI
        },
        .png => {
            std.debug.assert(encoded.len >= 8);
            std.debug.assert(encoded[0] == 0x89); // PNG signature
            std.debug.assert(encoded[1] == 0x50 and encoded[2] == 0x4E and encoded[3] == 0x47);
        },
        else => {},
    }

    return encoded;
}

/// Get recommended quality for format (middle-ground default)
pub fn getDefaultQuality(format: ImageFormat) u8 {
    return switch (format) {
        .jpeg => 85, // Good balance
        .webp => 80, // Slightly lower (WebP more efficient)
        .avif => 75, // Even lower (AVIF very efficient)
        .png => 6, // Middle compression
        .unknown => 85,
    };
}

/// Get quality range for format
pub fn getQualityRange(format: ImageFormat) struct { min: u8, max: u8 } {
    return switch (format) {
        .jpeg => .{ .min = 1, .max = 100 }, // libvips doesn't support quality=0 for JPEG
        .webp, .avif => .{ .min = 0, .max = 100 },
        .png => .{ .min = 0, .max = 9 },
        .unknown => .{ .min = 1, .max = 100 },
    };
}

/// Check if format supports alpha channel
pub fn formatSupportsAlpha(format: ImageFormat) bool {
    return switch (format) {
        .png, .webp, .avif => true,
        .jpeg => false,
        .unknown => false,
    };
}

// ============================================================================
// Unit Tests
// ============================================================================

test "getDefaultQuality returns sensible values" {
    const testing = std.testing;

    try testing.expectEqual(@as(u8, 85), getDefaultQuality(.jpeg));
    try testing.expectEqual(@as(u8, 80), getDefaultQuality(.webp));
    try testing.expectEqual(@as(u8, 75), getDefaultQuality(.avif));
    try testing.expectEqual(@as(u8, 6), getDefaultQuality(.png));
}

test "getQualityRange returns correct ranges" {
    const testing = std.testing;

    const jpeg_range = getQualityRange(.jpeg);
    try testing.expectEqual(@as(u8, 1), jpeg_range.min); // JPEG min is 1 (libvips limitation)
    try testing.expectEqual(@as(u8, 100), jpeg_range.max);

    const png_range = getQualityRange(.png);
    try testing.expectEqual(@as(u8, 0), png_range.min);
    try testing.expectEqual(@as(u8, 9), png_range.max);
}

test "formatSupportsAlpha checks correctly" {
    const testing = std.testing;

    try testing.expect(!formatSupportsAlpha(.jpeg));
    try testing.expect(formatSupportsAlpha(.png));
    try testing.expect(formatSupportsAlpha(.webp));
    try testing.expect(formatSupportsAlpha(.avif));
}

// Note: Full encoding tests require vips context to be initialized
// These will be in integration tests
