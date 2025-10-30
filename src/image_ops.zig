const std = @import("std");
const Allocator = std.mem.Allocator;
const vips = @import("vips.zig");
const ImageBuffer = @import("types/image_buffer.zig").ImageBuffer;
const ImageMetadata = @import("types/image_metadata.zig").ImageMetadata;
const ImageFormat = @import("types/image_metadata.zig").ImageFormat;

/// High-level image operations using libvips
///
/// This module provides the main image processing functions for Pyjamaz:
/// - decodeImage: Load and normalize image from file
/// - resizeImage: Resize with various modes
/// - normalizeColorSpace: Convert to sRGB
///
/// Tiger Style: All functions have bounded operations, explicit error handling,
/// and return owned memory that must be freed by caller.

/// Decode image from file path
///
/// Steps:
/// 1. Load image from file
/// 2. Apply EXIF auto-rotation
/// 3. Convert to sRGB color space
/// 4. Return normalized ImageBuffer
///
/// Safety: Returns ImageBuffer, caller must call deinit()
/// Requires: VipsContext must be initialized
/// Tiger Style: 10 assertions (pre-conditions, invariants, post-conditions)
pub fn decodeImage(allocator: Allocator, path: []const u8) !ImageBuffer {
    // Pre-conditions (Tiger Style: 2)
    std.debug.assert(path.len > 0);
    std.debug.assert(path.len < std.fs.max_path_bytes);

    // Load image
    var img = try vips.loadImage(path);
    defer img.deinit();

    // Invariant: Loaded image has valid dimensions
    std.debug.assert(img.width() > 0 and img.width() <= 65535);
    std.debug.assert(img.height() > 0 and img.height() <= 65535);

    // Apply EXIF auto-rotation
    var rotated = try vips.autorot(&img);
    defer rotated.deinit();

    // Invariant: Rotation preserves validity
    std.debug.assert(rotated.width() > 0 and rotated.height() > 0);

    // Convert to sRGB (normalized color space)
    var srgb = try vips.toSRGB(&rotated);
    defer srgb.deinit();

    // Invariant: Color space conversion succeeded
    std.debug.assert(srgb.interpretation() == .srgb);

    // Convert to ImageBuffer
    const buffer = try srgb.toImageBuffer(allocator);

    // Post-conditions (Tiger Style: 2)
    std.debug.assert(buffer.width > 0 and buffer.height > 0);
    std.debug.assert(buffer.data.len == @as(usize, buffer.stride) * @as(usize, buffer.height));

    return buffer;
}

/// Resize mode for image transformations
pub const ResizeMode = enum {
    /// Resize to exact dimensions (may distort aspect ratio)
    exact,

    /// Resize to fit within dimensions (preserve aspect ratio)
    contain,

    /// Resize to cover dimensions (preserve aspect ratio, crop if needed)
    cover,

    /// Only shrink, never upscale
    only_shrink,
};

/// Resize parameters
pub const ResizeParams = struct {
    /// Target width (0 = keep original)
    target_width: u32,

    /// Target height (0 = keep original)
    target_height: u32,

    /// Resize mode
    mode: ResizeMode,

    /// Apply sharpening after resize
    sharpen: bool,
};

/// Resize image according to parameters
///
/// Safety: Modifies buffer in place or returns error
/// Tiger Style: Bounded scale factors (0.01 to 10.0)
pub fn resizeImage(buffer: ImageBuffer, params: ResizeParams) !ImageBuffer {
    _ = buffer;
    _ = params;

    // TODO: Implement resize logic
    // This requires converting ImageBuffer back to VipsImage,
    // which needs vips_image_new_from_memory
    return error.NotImplemented;
}

/// ICC profile handling mode
pub const IccMode = enum {
    /// Keep original ICC profile
    keep,

    /// Convert to sRGB
    srgb,

    /// Discard ICC profile
    discard,
};

/// Normalize color space according to ICC mode
///
/// Safety: Returns new ImageBuffer, caller must deinit
pub fn normalizeColorSpace(
    allocator: Allocator,
    buffer: ImageBuffer,
    mode: IccMode,
) !ImageBuffer {
    _ = mode;

    // For now, we already convert to sRGB in decodeImage
    // TODO: Implement full ICC profile handling
    return buffer.clone(allocator);
}

/// Get image metadata from file without decoding pixels
///
/// This is faster than full decode when you only need dimensions/format
pub fn getImageMetadata(path: []const u8) !ImageMetadata {
    // Load image to get metadata
    var img = try vips.loadImage(path);
    defer img.deinit();

    const width = img.width();
    const height = img.height();
    const has_alpha = img.hasAlpha();

    // Detect format from file extension (simple heuristic)
    const format = detectFormat(path);

    return ImageMetadata.init(format, width, height, has_alpha);
}

/// Detect image format from file extension
fn detectFormat(path: []const u8) ImageFormat {
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) {
        return .jpeg;
    } else if (std.mem.endsWith(u8, path, ".png")) {
        return .png;
    } else if (std.mem.endsWith(u8, path, ".webp")) {
        return .webp;
    } else if (std.mem.endsWith(u8, path, ".avif")) {
        return .avif;
    } else {
        return .unknown;
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

test "detectFormat recognizes extensions" {
    const testing = std.testing;

    try testing.expectEqual(ImageFormat.jpeg, detectFormat("test.jpg"));
    try testing.expectEqual(ImageFormat.jpeg, detectFormat("test.jpeg"));
    try testing.expectEqual(ImageFormat.png, detectFormat("test.png"));
    try testing.expectEqual(ImageFormat.webp, detectFormat("test.webp"));
    try testing.expectEqual(ImageFormat.avif, detectFormat("test.avif"));
    try testing.expectEqual(ImageFormat.unknown, detectFormat("test.bmp"));
}

// Note: Full integration tests require actual image files
// These will be in src/test/integration/
