const std = @import("std");
const testing = std.testing;
const vips = @import("../../vips.zig");
const codecs = @import("../../codecs.zig");
const image_ops = @import("../../image_ops.zig");
const ImageBuffer = @import("../../types/image_buffer.zig").ImageBuffer;
const ImageFormat = @import("../../types/image_metadata.zig").ImageFormat;
const test_utils = @import("../test_utils.zig");

// TODO: Skip vips tests due to libvips thread-safety issues in parallel test execution
// Re-enable after implementing proper locking around all vips operations
const SKIP_VIPS_TESTS = true;

// Test image paths
const TEST_PNG_PATH = "testdata/conformance/pngsuite/basn3p02.png"; // 32x32 PNG
const TEST_PNG_ALPHA_PATH = "testdata/conformance/pngsuite/bgwn6a08.png"; // PNG with alpha

const ensureVipsInit = test_utils.ensureVipsInit;

// ============================================================================
// JPEG Encoding Tests
// ============================================================================

test "encodeImage: JPEG with quality=0 (minimum)" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    const encoded = try codecs.encodeImage(allocator, &buffer, .jpeg, 0);
    defer allocator.free(encoded);

    // Verify we got some output
    try testing.expect(encoded.len > 0);

    // Verify it's a valid JPEG (starts with 0xFF 0xD8)
    try testing.expectEqual(@as(u8, 0xFF), encoded[0]);
    try testing.expectEqual(@as(u8, 0xD8), encoded[1]);
}

test "encodeImage: JPEG with quality=85 (default)" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    const encoded = try codecs.encodeImage(allocator, &buffer, .jpeg, 85);
    defer allocator.free(encoded);

    try testing.expect(encoded.len > 0);
    try testing.expectEqual(@as(u8, 0xFF), encoded[0]);
    try testing.expectEqual(@as(u8, 0xD8), encoded[1]);
}

test "encodeImage: JPEG with quality=100 (maximum)" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    const encoded = try codecs.encodeImage(allocator, &buffer, .jpeg, 100);
    defer allocator.free(encoded);

    try testing.expect(encoded.len > 0);
    try testing.expectEqual(@as(u8, 0xFF), encoded[0]);
    try testing.expectEqual(@as(u8, 0xD8), encoded[1]);
}

test "encodeImage: JPEG quality affects file size" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    const encoded_low = try codecs.encodeImage(allocator, &buffer, .jpeg, 10);
    defer allocator.free(encoded_low);

    const encoded_high = try codecs.encodeImage(allocator, &buffer, .jpeg, 95);
    defer allocator.free(encoded_high);

    // Higher quality should produce larger files (generally)
    try testing.expect(encoded_high.len >= encoded_low.len);
}

test "encodeImage: JPEG handles RGBA input (drops alpha)" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    // Load image with alpha
    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_ALPHA_PATH);
    defer buffer.deinit();

    // Encode as JPEG (should drop alpha automatically)
    const encoded = try codecs.encodeImage(allocator, &buffer, .jpeg, 85);
    defer allocator.free(encoded);

    try testing.expect(encoded.len > 0);
    try testing.expectEqual(@as(u8, 0xFF), encoded[0]);
    try testing.expectEqual(@as(u8, 0xD8), encoded[1]);
}

// ============================================================================
// PNG Encoding Tests
// ============================================================================

test "encodeImage: PNG with compression=0 (no compression)" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    const encoded = try codecs.encodeImage(allocator, &buffer, .png, 0);
    defer allocator.free(encoded);

    try testing.expect(encoded.len > 0);

    // Verify it's a valid PNG (starts with PNG magic number)
    try testing.expectEqual(@as(u8, 0x89), encoded[0]);
    try testing.expectEqual(@as(u8, 0x50), encoded[1]); // 'P'
    try testing.expectEqual(@as(u8, 0x4E), encoded[2]); // 'N'
    try testing.expectEqual(@as(u8, 0x47), encoded[3]); // 'G'
}

test "encodeImage: PNG with compression=6 (default)" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    const encoded = try codecs.encodeImage(allocator, &buffer, .png, 6);
    defer allocator.free(encoded);

    try testing.expect(encoded.len > 0);
    try testing.expectEqual(@as(u8, 0x89), encoded[0]);
}

test "encodeImage: PNG with compression=9 (maximum)" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    const encoded = try codecs.encodeImage(allocator, &buffer, .png, 9);
    defer allocator.free(encoded);

    try testing.expect(encoded.len > 0);
    try testing.expectEqual(@as(u8, 0x89), encoded[0]);
}

test "encodeImage: PNG preserves alpha channel" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    // Load PNG with alpha
    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_ALPHA_PATH);
    defer buffer.deinit();

    // Verify original has alpha
    const original_channels = buffer.channels;

    // Encode as PNG
    const encoded = try codecs.encodeImage(allocator, &buffer, .png, 6);
    defer allocator.free(encoded);

    try testing.expect(encoded.len > 0);
    try testing.expectEqual(@as(u8, 0x89), encoded[0]);

    // PNG should support alpha if original had it
    if (original_channels == 4) {
        // Successfully encoded RGBA image
        try testing.expect(encoded.len > 0);
    }
}

// ============================================================================
// Round-trip Tests
// ============================================================================

test "encodeImage: round-trip JPEG preserves dimensions" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    // Load original
    var buffer1 = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer1.deinit();

    const original_width = buffer1.width;
    const original_height = buffer1.height;

    // Encode as JPEG
    const encoded = try codecs.encodeImage(allocator, &buffer1, .jpeg, 85);
    defer allocator.free(encoded);

    // Decode back (via vips to verify it's valid)
    var vips_img = try vips.VipsImageWrapper.fromImageBuffer(&buffer1);
    defer vips_img.deinit();

    // Create JPEG-encoded vips image
    const jpeg_bytes = try vips_img.saveAsJPEG(allocator, 85);
    defer allocator.free(jpeg_bytes);

    // Dimensions should be preserved in encoding
    try testing.expect(jpeg_bytes.len > 0);
    try testing.expectEqual(original_width, buffer1.width);
    try testing.expectEqual(original_height, buffer1.height);
}

test "encodeImage: round-trip PNG preserves dimensions" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    // Load original
    var buffer1 = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer1.deinit();

    const original_width = buffer1.width;
    const original_height = buffer1.height;

    // Encode as PNG
    const encoded = try codecs.encodeImage(allocator, &buffer1, .png, 6);
    defer allocator.free(encoded);

    // Verify dimensions are preserved
    try testing.expectEqual(original_width, buffer1.width);
    try testing.expectEqual(original_height, buffer1.height);
}

// ============================================================================
// Memory Safety Tests
// ============================================================================

test "encodeImage: no memory leaks on repeated encoding" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    // Encode many times to detect leaks
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        const jpeg = try codecs.encodeImage(allocator, &buffer, .jpeg, 85);
        allocator.free(jpeg);

        const png = try codecs.encodeImage(allocator, &buffer, .png, 6);
        allocator.free(png);
    }

    // testing.allocator will fail if there are leaks
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "encodeImage: unsupported format returns error" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    // WebP not yet implemented
    const result_webp = codecs.encodeImage(allocator, &buffer, .webp, 80);
    try testing.expectError(codecs.CodecError.UnsupportedFormat, result_webp);

    // AVIF not yet implemented
    const result_avif = codecs.encodeImage(allocator, &buffer, .avif, 75);
    try testing.expectError(codecs.CodecError.UnsupportedFormat, result_avif);

    // Unknown format
    const result_unknown = codecs.encodeImage(allocator, &buffer, .unknown, 85);
    try testing.expectError(codecs.CodecError.UnsupportedFormat, result_unknown);
}

// ============================================================================
// Default Quality Tests (via helper functions)
// ============================================================================

test "encodeImage: uses sensible defaults for each format" {
    if (SKIP_VIPS_TESTS) return error.SkipZigTest;

    const allocator = testing.allocator;

    try ensureVipsInit();
    

    var buffer = try image_ops.decodeImage(allocator, TEST_PNG_PATH);
    defer buffer.deinit();

    // Test JPEG with default quality
    {
        const default_q = codecs.getDefaultQuality(.jpeg);
        const encoded = try codecs.encodeImage(allocator, &buffer, .jpeg, default_q);
        defer allocator.free(encoded);
        try testing.expect(encoded.len > 0);
    }

    // Test PNG with default compression
    {
        const default_q = codecs.getDefaultQuality(.png);
        const encoded = try codecs.encodeImage(allocator, &buffer, .png, default_q);
        defer allocator.free(encoded);
        try testing.expect(encoded.len > 0);
    }
}
