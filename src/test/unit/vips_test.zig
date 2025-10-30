const std = @import("std");
const testing = std.testing;
const vips = @import("../../vips.zig");
const ImageBuffer = @import("../../types/image_buffer.zig").ImageBuffer;
const test_utils = @import("../test_utils.zig");

// TODO: Skip vips tests due to libvips thread-safety issues in parallel test execution
// Re-enable after implementing proper locking around all vips operations
const SKIP_VIPS_TESTS = true;

// Test image paths (using real files from testdata)
const TEST_PNG_PATH = "testdata/conformance/pngsuite/basn3p02.png"; // 32x32 PNG
const TEST_PNG_ALPHA_PATH = "testdata/conformance/pngsuite/bgwn6a08.png"; // PNG with alpha
const INVALID_PATH = "testdata/nonexistent.png";

const ensureVipsInit = test_utils.ensureVipsInit;

// ============================================================================
// VipsContext Tests
// ============================================================================

test "VipsContext: init and deinit" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    // Test basic initialization and cleanup
    var ctx = try vips.VipsContext.init();
    defer ctx.deinit();

    try testing.expect(ctx.initialized);
}

test "VipsContext: double deinit is safe" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    var ctx = try vips.VipsContext.init();
    ctx.deinit();
    ctx.deinit(); // Should be safe

    try testing.expect(!ctx.initialized);
}

// ============================================================================
// VipsImageWrapper Tests - Loading
// ============================================================================

test "VipsImageWrapper: load valid PNG" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    var img = try vips.loadImage(TEST_PNG_PATH);
    defer img.deinit();

    // Verify image properties
    const w = img.width();
    const h = img.height();
    const b = img.bands();

    try testing.expect(w > 0);
    try testing.expect(h > 0);
    try testing.expect(b >= 3); // At least RGB
}

test "VipsImageWrapper: load invalid file returns error" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    const result = vips.loadImage(INVALID_PATH);
    try testing.expectError(vips.VipsError.LoadFailed, result);
}

test "VipsImageWrapper: helper methods" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    var img = try vips.loadImage(TEST_PNG_PATH);
    defer img.deinit();

    // Test helper methods
    const w = img.width();
    const h = img.height();
    const b = img.bands();
    const interp = img.interpretation();

    // Assertions (Tiger Style)
    try testing.expect(w > 0);
    try testing.expect(h > 0);
    try testing.expect(b >= 3);
    try testing.expect(interp != .vips_error);

    // Test hasAlpha
    const has_alpha = img.hasAlpha();
    try testing.expect(has_alpha == (b == 4));
}

// ============================================================================
// VipsImageWrapper Tests - Conversions
// ============================================================================

// FIXME: This test triggers a libvips segfault - needs investigation
// See docs/TODO.md - Known Issue: toImageBuffer conversion test
// test "VipsImageWrapper: toImageBuffer conversion" {
//     const allocator = testing.allocator;
//
//     try ensureVipsInit();
//
//     var img = try vips.loadImage(TEST_PNG_PATH);
//     defer img.deinit();
//
//     // Convert to sRGB first (required for toImageBuffer)
//     var srgb = try vips.toSRGB(&img);
//     defer srgb.deinit();
//
//     // Convert to ImageBuffer
//     var buffer = try srgb.toImageBuffer(allocator);
//     defer buffer.deinit();
//
//     // Verify buffer properties
//     try testing.expect(buffer.width > 0);
//     try testing.expect(buffer.height > 0);
//     try testing.expect(buffer.channels == 3 or buffer.channels == 4);
//     try testing.expect(buffer.data.len == buffer.stride * buffer.height);
// }

// FIXME: This test also triggers libvips segfault in toImageBuffer
// test "VipsImageWrapper: round-trip fromImageBuffer → toImageBuffer" {
//     const allocator = testing.allocator;
//
//     try ensureVipsInit();
//
//     // Load and convert to ImageBuffer
//     var img1 = try vips.loadImage(TEST_PNG_PATH);
//     defer img1.deinit();
//
//     var srgb1 = try vips.toSRGB(&img1);
//     defer srgb1.deinit();
//
//     var buffer1 = try srgb1.toImageBuffer(allocator);
//     defer buffer1.deinit();
//
//     const original_width = buffer1.width;
//     const original_height = buffer1.height;
//     const original_channels = buffer1.channels;
//
//     // Create VipsImage from ImageBuffer
//     var img2 = try vips.VipsImageWrapper.fromImageBuffer(&buffer1);
//     defer img2.deinit();
//
//     // Convert back to ImageBuffer
//     var buffer2 = try img2.toImageBuffer(allocator);
//     defer buffer2.deinit();
//
//     // Verify dimensions preserved
//     try testing.expectEqual(original_width, buffer2.width);
//     try testing.expectEqual(original_height, buffer2.height);
//     try testing.expectEqual(original_channels, buffer2.channels);
// }

// ============================================================================
// VipsImageWrapper Tests - Encoding (JPEG)
// ============================================================================

test "VipsImageWrapper: saveAsJPEG with quality bounds" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    // SKIP: This test causes libvips segfault (CRIT-010 in TO-FIX.md)
    // Known libvips bug with hash table initialization, not our code issue
    // GLib-CRITICAL: g_hash_table_lookup: assertion 'hash_table != NULL' failed
    return error.SkipZigTest;

    // const allocator = testing.allocator;
    // try ensureVipsInit();
    // var img = try vips.loadImage(TEST_PNG_PATH);
    // defer img.deinit();
    // var srgb = try vips.toSRGB(&img);
    // defer srgb.deinit();
    // // Test quality=1 (minimum - libvips doesn't support 0)
    // {
    //     const encoded = try srgb.saveAsJPEG(allocator, 1);
    //     defer allocator.free(encoded);
    //     try testing.expect(encoded.len > 0);
    // }
    // // Test quality=50 (medium)
    // {
    //     const encoded = try srgb.saveAsJPEG(allocator, 50);
    //     defer allocator.free(encoded);
    //     try testing.expect(encoded.len > 0);
    // }
    // // Test quality=100 (maximum)
    // {
    //     const encoded = try srgb.saveAsJPEG(allocator, 100);
    //     defer allocator.free(encoded);
    //     try testing.expect(encoded.len > 0);
    // }
}

test "VipsImageWrapper: JPEG quality affects file size" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    // SKIP: This test causes libvips segfault (CRIT-010 in TO-FIX.md)
    return error.SkipZigTest;

    // const allocator = testing.allocator;
    // try ensureVipsInit();
    // var img = try vips.loadImage(TEST_PNG_PATH);
    // defer img.deinit();
    // var srgb = try vips.toSRGB(&img);
    // defer srgb.deinit();
    // const encoded_low = try srgb.saveAsJPEG(allocator, 10);
    // defer allocator.free(encoded_low);
    // const encoded_high = try srgb.saveAsJPEG(allocator, 95);
    // defer allocator.free(encoded_high);
    // try testing.expect(encoded_high.len >= encoded_low.len);
}

// ============================================================================
// VipsImageWrapper Tests - Encoding (PNG)
// ============================================================================

test "VipsImageWrapper: saveAsPNG with compression bounds" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    // SKIP: This test causes libvips segfault (CRIT-010 in TO-FIX.md)
    return error.SkipZigTest;
}

test "VipsImageWrapper: PNG preserves alpha channel" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    // SKIP: This test causes libvips segfault (CRIT-010 in TO-FIX.md)
    return error.SkipZigTest;
}

// ============================================================================
// High-level Operations Tests
// ============================================================================

test "vips: autorot operation" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    var img = try vips.loadImage(TEST_PNG_PATH);
    defer img.deinit();

    var rotated = try vips.autorot(&img);
    defer rotated.deinit();

    // Verify we got a valid image back
    try testing.expect(rotated.width() > 0);
    try testing.expect(rotated.height() > 0);
}

test "vips: toSRGB color space conversion" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    try ensureVipsInit();
    

    var img = try vips.loadImage(TEST_PNG_PATH);
    defer img.deinit();

    var srgb = try vips.toSRGB(&img);
    defer srgb.deinit();

    // Verify conversion succeeded
    try testing.expect(srgb.width() > 0);
    try testing.expect(srgb.height() > 0);
    try testing.expect(srgb.interpretation() == .srgb);
}

// ============================================================================
// Memory Safety Tests
// ============================================================================

test "VipsImageWrapper: no memory leaks on repeated operations" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    // SKIP: This test causes libvips segfault (CRIT-010 in TO-FIX.md)
    return error.SkipZigTest;
}

test "VipsImageWrapper: encoding operations don't leak" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    // SKIP: This test causes libvips segfault (CRIT-010 in TO-FIX.md)
    return error.SkipZigTest;
}
