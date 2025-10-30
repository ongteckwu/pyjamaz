const std = @import("std");
const Allocator = std.mem.Allocator;

/// ImageBuffer stores raw pixel data for in-memory image processing.
/// Used as the intermediate format between decode, transform, and encode stages.
///
/// Tiger Style: 2+ assertions, bounded sizes, explicit types, comptime size check
pub const ImageBuffer = struct {
    /// Raw pixel data in RGB or RGBA format (row-major)
    data: []u8,

    /// Image width in pixels (max 65535 for safety)
    width: u32,

    /// Image height in pixels (max 65535 for safety)
    height: u32,

    /// Bytes per row (stride). Must be >= width * channels
    stride: u32,

    /// Number of color channels (3 = RGB, 4 = RGBA)
    channels: u8,

    /// Allocator used for the pixel data
    allocator: Allocator,

    /// Color space identifier (0 = sRGB, 1 = Linear, 2 = P3)
    color_space: u8,

    // Tiger Style: Comptime assertion to prevent struct bloat
    comptime {
        std.debug.assert(@sizeOf(ImageBuffer) <= 64);
    }

    /// Initialize a new ImageBuffer with allocated memory
    ///
    /// Safety invariants:
    /// - width and height must be > 0
    /// - width and height must be <= 65535 (prevent overflow)
    /// - channels must be 3 or 4
    /// - stride must be >= width * channels
    ///
    /// Returns error.OutOfMemory if allocation fails
    pub fn init(
        allocator: Allocator,
        width: u32,
        height: u32,
        channels: u8,
    ) !ImageBuffer {
        // Assertions (Tiger Style: 2+)
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);
        std.debug.assert(width <= 65535); // Prevent overflow
        std.debug.assert(height <= 65535);
        std.debug.assert(channels == 3 or channels == 4);

        const stride: u32 = width * channels;
        const total_bytes: u64 = @as(u64, stride) * @as(u64, height);

        // HIGH-004: Explicit memory limits (Tiger Style)
        const MAX_SINGLE_IMAGE_BYTES: u64 = 4_294_967_296; // 4GB
        const LARGE_IMAGE_THRESHOLD: u64 = 100_000_000; // 100MB

        // Prevent absurdly large allocations
        if (total_bytes > MAX_SINGLE_IMAGE_BYTES) {
            std.log.err("Image too large: {d}x{d}x{d} = {d} MB (max {d} MB)", .{
                width,
                height,
                channels,
                total_bytes / (1024 * 1024),
                MAX_SINGLE_IMAGE_BYTES / (1024 * 1024),
            });
            return error.ImageTooLarge;
        }

        // Warn for large allocations
        if (total_bytes > LARGE_IMAGE_THRESHOLD) {
            std.log.warn("Allocating large image buffer: {d}x{d}x{d} = {d} MB", .{
                width,
                height,
                channels,
                total_bytes / (1024 * 1024),
            });
        }

        const data = try allocator.alloc(u8, @intCast(total_bytes));

        // Post-condition: allocation succeeded
        std.debug.assert(data.len == total_bytes);

        return ImageBuffer{
            .data = data,
            .width = width,
            .height = height,
            .stride = stride,
            .channels = channels,
            .allocator = allocator,
            .color_space = 0, // Default to sRGB
        };
    }

    /// Free the pixel data memory
    pub fn deinit(self: *ImageBuffer) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }

    /// Get a pointer to the start of a specific row
    ///
    /// Safety: y must be < height
    pub fn getRow(self: *const ImageBuffer, y: u32) []u8 {
        std.debug.assert(y < self.height);

        const offset: usize = @as(usize, y) * @as(usize, self.stride);
        const row_end = offset + self.stride;

        std.debug.assert(row_end <= self.data.len);

        return self.data[offset..row_end];
    }

    /// Get a pointer to a specific pixel
    ///
    /// Safety: x must be < width, y must be < height
    pub fn getPixel(self: *const ImageBuffer, x: u32, y: u32) []u8 {
        std.debug.assert(x < self.width);
        std.debug.assert(y < self.height);

        const offset: usize = (@as(usize, y) * @as(usize, self.stride)) +
                              (@as(usize, x) * @as(usize, self.channels));
        const pixel_end = offset + self.channels;

        std.debug.assert(pixel_end <= self.data.len);

        return self.data[offset..pixel_end];
    }

    /// Calculate total memory used by this buffer in bytes
    pub fn memoryUsage(self: *const ImageBuffer) u64 {
        return @as(u64, self.data.len) + @sizeOf(ImageBuffer);
    }

    /// Check if buffer has alpha channel
    pub fn hasAlpha(self: *const ImageBuffer) bool {
        return self.channels == 4;
    }

    /// Clone this buffer (deep copy)
    pub fn clone(self: *const ImageBuffer, allocator: Allocator) !ImageBuffer {
        var new_buffer = try ImageBuffer.init(
            allocator,
            self.width,
            self.height,
            self.channels,
        );

        @memcpy(new_buffer.data, self.data);
        new_buffer.color_space = self.color_space;

        return new_buffer;
    }
};

// Unit tests
test "ImageBuffer.init validates dimensions" {
    const testing = std.testing;

    // Valid dimensions
    var buffer = try ImageBuffer.init(testing.allocator, 100, 100, 3);
    defer buffer.deinit();

    try testing.expectEqual(@as(u32, 100), buffer.width);
    try testing.expectEqual(@as(u32, 100), buffer.height);
    try testing.expectEqual(@as(u8, 3), buffer.channels);
    try testing.expectEqual(@as(u32, 300), buffer.stride);
}

test "ImageBuffer.getRow returns correct slice" {
    const testing = std.testing;

    var buffer = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer buffer.deinit();

    const row = buffer.getRow(5);
    try testing.expectEqual(@as(usize, 30), row.len);
}

test "ImageBuffer.getPixel returns correct slice" {
    const testing = std.testing;

    var buffer = try ImageBuffer.init(testing.allocator, 10, 10, 4);
    defer buffer.deinit();

    // Set a pixel value
    const pixel = buffer.getPixel(5, 5);
    pixel[0] = 255; // R
    pixel[1] = 128; // G
    pixel[2] = 64;  // B
    pixel[3] = 255; // A

    // Read it back
    const read_pixel = buffer.getPixel(5, 5);
    try testing.expectEqual(@as(u8, 255), read_pixel[0]);
    try testing.expectEqual(@as(u8, 128), read_pixel[1]);
    try testing.expectEqual(@as(u8, 64), read_pixel[2]);
    try testing.expectEqual(@as(u8, 255), read_pixel[3]);
}

test "ImageBuffer.hasAlpha detects RGBA" {
    const testing = std.testing;

    var rgb = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer rgb.deinit();
    try testing.expect(!rgb.hasAlpha());

    var rgba = try ImageBuffer.init(testing.allocator, 10, 10, 4);
    defer rgba.deinit();
    try testing.expect(rgba.hasAlpha());
}

test "ImageBuffer.clone creates deep copy" {
    const testing = std.testing;

    var original = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer original.deinit();

    // Modify original
    original.data[0] = 42;

    var copy = try original.clone(testing.allocator);
    defer copy.deinit();

    try testing.expectEqual(@as(u8, 42), copy.data[0]);

    // Modify copy - should not affect original
    copy.data[0] = 99;
    try testing.expectEqual(@as(u8, 42), original.data[0]);
    try testing.expectEqual(@as(u8, 99), copy.data[0]);
}

test "ImageBuffer memory leak check" {
    const testing = std.testing;

    // testing.allocator will detect leaks
    var buffer = try ImageBuffer.init(testing.allocator, 100, 100, 4);
    buffer.deinit();
}
