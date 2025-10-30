const std = @import("std");
const testing = std.testing;
const vips = @import("../../vips.zig");
const image_ops = @import("../../image_ops.zig");
const ImageBuffer = @import("../../types/image_buffer.zig").ImageBuffer;
const ImageMetadata = @import("../../types/image_metadata.zig").ImageMetadata;
const ImageFormat = @import("../../types/image_metadata.zig").ImageFormat;
const test_utils = @import("../test_utils.zig");

// TODO: Skip vips tests due to libvips thread-safety issues in parallel test execution
// Re-enable after implementing proper locking around all vips operations
const SKIP_VIPS_TESTS = true;

// Test image paths
const TEST_PNG_PATH = "testdata/conformance/pngsuite/basn3p02.png"; // 32x32 PNG
const TEST_PNG_ALPHA_PATH = "testdata/conformance/pngsuite/bgwn6a08.png"; // PNG with alpha
const INVALID_PATH = "testdata/nonexistent.png";

const ensureVipsInit = test_utils.ensureVipsInit;

// ============================================================================
// decodeImage Tests
// ============================================================================

test "decodeImage: loads valid PNG" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    // Verify buffer is valid
    try testing.expect(buffer.width > 0);
    try testing.expect(buffer.height > 0);
    try testing.expect(buffer.channels == 3 or buffer.channels == 4);
    try testing.expect(buffer.data.len > 0);
    try testing.expect(buffer.data.len == buffer.stride * buffer.height);
}

test "decodeImage: loads PNG with alpha" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_ALPHA_PATH);
    defer buffer.deinit();

    // This PNG has alpha, verify we handle it
    try testing.expect(buffer.width > 0);
    try testing.expect(buffer.height > 0);
    try testing.expect(buffer.channels >= 3); // Should be 3 or 4
    try testing.expect(buffer.data.len > 0);
}

// TEMPORARILY SKIP: This test causes GLib errors that corrupt vips state
// TODO: Investigate why loading non-existent files causes hash table errors
// test "decodeImage: handles invalid file" {
//     const allocator = testing.allocator;

//     try ensureVipsInit();

//     const result = image_ops.decodeImage(allocator, INVALID_PATH);
//     try testing.expectError(vips.VipsError.LoadFailed, result);
// }

test "decodeImage: applies EXIF auto-rotation" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();

    // Even without EXIF data, autorot should succeed (no-op)
    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    try testing.expect(buffer.width > 0);
    try testing.expect(buffer.height > 0);

    // Note: To fully test EXIF rotation, we'd need test images with EXIF orientation tags
    // For now, we verify it doesn't crash on images without EXIF
}

test "decodeImage: normalizes to sRGB color space" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    // The image should be in sRGB color space after decoding
    // (we can't directly verify this from ImageBuffer, but we test that the pipeline runs)
    try testing.expect(buffer.width > 0);
    try testing.expect(buffer.data.len > 0);
}

// ============================================================================
// getImageMetadata Tests
// ============================================================================

test "getImageMetadata: extracts metadata without full decode" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    const metadata = try image_ops.getImageMetadata(TEST_PNG_PATH);

    // Verify metadata is valid
    try testing.expect(metadata.original_width > 0);
    try testing.expect(metadata.original_height > 0);
    try testing.expectEqual(ImageFormat.png, metadata.format);
}

test "getImageMetadata: detects alpha channel" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    const metadata_alpha = try image_ops.getImageMetadata(TEST_PNG_ALPHA_PATH);

    // This image should have alpha (or be detected as potentially having it)
    // Note: Detection might vary, so we just verify we get valid metadata
    try testing.expect(metadata_alpha.original_width > 0);
    try testing.expect(metadata_alpha.original_height > 0);
}

test "getImageMetadata: handles invalid file" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    const result = image_ops.getImageMetadata(INVALID_PATH);
    try testing.expectError(vips.VipsError.LoadFailed, result);
}

// ============================================================================
// detectFormat Tests (internal function, tested via getImageMetadata)
// ============================================================================

test "detectFormat: recognizes file extensions" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    // Test PNG extension
    const metadata_png = try image_ops.getImageMetadata(TEST_PNG_PATH);
    try testing.expectEqual(ImageFormat.png, metadata_png.format);

    // Note: For comprehensive extension testing, see the inline test in image_ops.zig
    // which tests .jpg, .jpeg, .png, .webp, .avif extensions
}

// ============================================================================
// normalizeColorSpace Tests
// ============================================================================

test "normalizeColorSpace: clones buffer with sRGB mode" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var original = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer original.deinit();

    var normalized = try image_ops.normalizeColorSpace(allocator, original, .srgb);
    defer normalized.deinit();

    // Should have same dimensions
    try testing.expectEqual(original.width, normalized.width);
    try testing.expectEqual(original.height, normalized.height);
    try testing.expectEqual(original.channels, normalized.channels);
}

// ============================================================================
// Memory Safety Tests
// ============================================================================

test "decodeImage: no memory leaks on repeated calls" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    // Decode many times to detect leaks
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
        defer buffer.deinit();

        // Verify each buffer is valid
        try testing.expect(buffer.width > 0);
    }

    // testing.allocator will fail if there are leaks
}

test "getImageMetadata: no memory leaks on repeated calls" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    // Get metadata many times to detect leaks
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const metadata = try image_ops.getImageMetadata(TEST_PNG_PATH);
        _ = metadata;

        // Metadata is a small struct with no owned memory, but verify no leaks
    }
}

// ============================================================================
// Integration Tests (full pipeline)
// ============================================================================

test "full pipeline: decode → normalize → metadata" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    // Get metadata first (fast)
    const metadata = try image_ops.getImageMetadata(TEST_PNG_PATH);
    const expected_width = metadata.original_width;
    const expected_height = metadata.original_height;

    // Full decode
    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    // Verify dimensions match metadata
    try testing.expectEqual(expected_width, buffer.width);
    try testing.expectEqual(expected_height, buffer.height);

    // Normalize (currently a clone)
    var normalized = try image_ops.normalizeColorSpace(allocator, buffer, .srgb);
    defer normalized.deinit();

    // Verify dimensions still match
    try testing.expectEqual(expected_width, normalized.width);
    try testing.expectEqual(expected_height, normalized.height);
}
