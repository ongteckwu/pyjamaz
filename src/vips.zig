const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("types/image_buffer.zig").ImageBuffer;
const ImageMetadata = @import("types/image_metadata.zig").ImageMetadata;
const ImageFormat = @import("types/image_metadata.zig").ImageFormat;

/// libvips FFI bindings
///
/// This module provides safe Zig wrappers around libvips C API for image
/// decoding, transformation, and normalization.
///
/// Tiger Style: All functions have explicit error handling, bounded operations,
/// and RAII wrappers to prevent memory leaks.

// ============================================================================
// C FFI Declarations
// ============================================================================

/// Opaque vips image pointer
pub const VipsImage = opaque {};

/// Opaque GObject pointer (vips uses GObject)
pub const GObject = opaque {};

/// VipsBandFormat enum
pub const VipsBandFormat = enum(c_int) {
    notset = -1,
    uchar = 0,
    char = 1,
    ushort = 2,
    short = 3,
    uint = 4,
    int = 5,
    float = 6,
    complex = 7,
    double = 8,
    dpcomplex = 9,
};

/// VipsInterpretation enum (color space)
pub const VipsInterpretation = enum(c_int) {
    vips_error = -1,
    multiband = 0,
    b_w = 1,
    histogram = 10,
    xyz = 12,
    lab = 13,
    cmyk = 15,
    labq = 16,
    rgb = 17,
    cmc = 18,
    lch = 19,
    labs = 21,
    srgb = 22,
    yxy = 23,
    fourier = 24,
    rgb16 = 25,
    grey16 = 26,
    matrix = 27,
    scrgb = 28,
    hsv = 29,
};

/// VipsAngle enum (rotation)
pub const VipsAngle = enum(c_int) {
    d0 = 0,
    d90 = 1,
    d180 = 2,
    d270 = 3,
};

// External C functions from libvips
extern "c" fn vips_init(argv0: [*c]const u8) c_int;
extern "c" fn vips_shutdown() void;
extern "c" fn vips_error_buffer() [*c]const u8;
extern "c" fn vips_error_clear() void;

extern "c" fn vips_image_new_from_file(filename: [*c]const u8, ...) ?*VipsImage;
extern "c" fn vips_image_new_from_buffer(buf: [*c]const u8, len: usize, option_string: [*c]const u8, ...) ?*VipsImage;
extern "c" fn vips_image_write_to_memory(image: ?*VipsImage, size: *usize) [*c]u8;

extern "c" fn vips_image_get_width(image: ?*const VipsImage) c_int;
extern "c" fn vips_image_get_height(image: ?*const VipsImage) c_int;
extern "c" fn vips_image_get_bands(image: ?*const VipsImage) c_int;
extern "c" fn vips_image_get_format(image: ?*const VipsImage) VipsBandFormat;
extern "c" fn vips_image_get_interpretation(image: ?*const VipsImage) VipsInterpretation;

extern "c" fn vips_autorot(input: ?*VipsImage, output: *?*VipsImage, ...) c_int;
extern "c" fn vips_colourspace(input: ?*VipsImage, output: *?*VipsImage, space: VipsInterpretation, ...) c_int;
extern "c" fn vips_resize(input: ?*VipsImage, output: *?*VipsImage, scale: f64, ...) c_int;
extern "c" fn vips_thumbnail(filename: [*c]const u8, output: *?*VipsImage, width: c_int, ...) c_int;
extern "c" fn vips_sharpen(input: ?*VipsImage, output: *?*VipsImage, ...) c_int;
extern "c" fn vips_crop(input: ?*VipsImage, output: *?*VipsImage, left: c_int, top: c_int, width: c_int, height: c_int, ...) c_int;

extern "c" fn vips_image_new_from_memory(data: [*c]const u8, size: usize, width: c_int, height: c_int, bands: c_int, format: VipsBandFormat) ?*VipsImage;
extern "c" fn vips_jpegsave_buffer(input: ?*VipsImage, buffer: *[*c]u8, len: *usize, ...) c_int;
extern "c" fn vips_pngsave_buffer(input: ?*VipsImage, buffer: *[*c]u8, len: *usize, ...) c_int;

extern "c" fn g_object_unref(object: ?*anyopaque) void;
extern "c" fn g_free(mem: ?*anyopaque) void;

// ============================================================================
// Error Handling
// ============================================================================

pub const VipsError = error{
    InitFailed,
    LoadFailed,
    ConversionFailed,
    OperationFailed,
    OutOfMemory,
    InvalidImage,
};

/// Get the last vips error message
fn getVipsError() []const u8 {
    const err_buf = vips_error_buffer();
    if (err_buf) |buf| {
        return std.mem.span(buf);
    }
    return "Unknown vips error";
}

/// Clear vips error buffer
fn clearVipsError() void {
    vips_error_clear();
}

// ============================================================================
// VipsContext - Global vips initialization (RAII)
// ============================================================================

/// VipsContext manages global vips library initialization.
///
/// Tiger Style: RAII pattern ensures vips_shutdown() is always called.
/// Only one VipsContext should exist per process.
///
/// HIGH-014: Thread Safety
/// - vips_init() and vips_shutdown() are NOT thread-safe
/// - Must initialize VipsContext in main thread before spawning workers
/// - Once initialized, most vips operations are thread-safe
/// - VipsImageWrapper can be used safely across threads (libvips handles locking)
/// - Do NOT call deinit() while other threads are using vips operations
/// - Recommended: Initialize once in main(), deinit() at program exit
pub const VipsContext = struct {
    initialized: bool,

    /// Initialize libvips library
    ///
    /// Safety: Must be called before any vips operations.
    /// Only initialize once per process.
    /// Thread Safety: NOT thread-safe. Call from main thread only.
    pub fn init() !VipsContext {
        const result = vips_init("pyjamaz");
        if (result != 0) {
            const err = getVipsError();
            // HIGH-006: Use std.log.err for proper error reporting
            std.log.err("vips_init failed: {s}", .{err});
            clearVipsError();
            return VipsError.InitFailed;
        }

        return VipsContext{ .initialized = true };
    }

    /// Shutdown libvips library
    pub fn deinit(self: *VipsContext) void {
        if (self.initialized) {
            vips_shutdown();
            self.initialized = false;
        }
    }
};

// ============================================================================
// VipsImage - Safe wrapper around vips image (RAII)
// ============================================================================

/// Safe wrapper around VipsImage pointer with automatic cleanup.
///
/// Tiger Style: RAII pattern prevents memory leaks via g_object_unref.
pub const VipsImageWrapper = struct {
    image: *VipsImage,

    /// Wrap a raw VipsImage pointer
    ///
    /// Safety: Takes ownership of the image pointer.
    pub fn wrap(image: *VipsImage) VipsImageWrapper {
        return VipsImageWrapper{ .image = image };
    }

    /// Release the vips image
    pub fn deinit(self: *VipsImageWrapper) void {
        g_object_unref(self.image);
        self.* = undefined;
    }

    /// Get image width
    pub fn width(self: *const VipsImageWrapper) u32 {
        const w = vips_image_get_width(self.image);
        std.debug.assert(w >= 0);
        return @intCast(w);
    }

    /// Get image height
    pub fn height(self: *const VipsImageWrapper) u32 {
        const h = vips_image_get_height(self.image);
        std.debug.assert(h >= 0);
        return @intCast(h);
    }

    /// Get number of bands (channels)
    pub fn bands(self: *const VipsImageWrapper) u32 {
        const b = vips_image_get_bands(self.image);
        std.debug.assert(b >= 0);
        return @intCast(b);
    }

    /// Get color space interpretation
    pub fn interpretation(self: *const VipsImageWrapper) VipsInterpretation {
        return vips_image_get_interpretation(self.image);
    }

    /// Check if image has alpha channel
    pub fn hasAlpha(self: *const VipsImageWrapper) bool {
        const b = self.bands();
        return b == 4; // RGBA or similar
    }

    /// Convert image to ImageBuffer
    ///
    /// Safety: Allocates memory, caller must call ImageBuffer.deinit()
    pub fn toImageBuffer(self: *const VipsImageWrapper, allocator: Allocator) !ImageBuffer {
        const w = self.width();
        const h = self.height();
        const b = self.bands();

        // Ensure we have RGB or RGBA
        std.debug.assert(b == 3 or b == 4);
        std.debug.assert(w > 0 and w <= 65535);
        std.debug.assert(h > 0 and h <= 65535);

        var size: usize = 0;
        const data_ptr = vips_image_write_to_memory(self.image, &size);
        if (data_ptr == null) {
            const err = getVipsError();
            std.debug.print("vips_image_write_to_memory failed: {s}\n", .{err});
            clearVipsError();
            return VipsError.ConversionFailed;
        }

        // Create ImageBuffer and copy data
        var buffer = try ImageBuffer.init(allocator, w, h, @intCast(b));
        errdefer buffer.deinit();

        const expected_size = @as(usize, buffer.stride) * @as(usize, h);
        if (size != expected_size) {
            std.debug.print("Size mismatch: expected {}, got {}\n", .{ expected_size, size });
            g_free(data_ptr);
            return VipsError.InvalidImage;
        }

        const src_slice = data_ptr[0..size];
        @memcpy(buffer.data, src_slice);
        g_free(data_ptr);

        return buffer;
    }

    /// Create VipsImage from ImageBuffer
    ///
    /// Safety: Creates a new vips image that shares the buffer's memory
    /// The returned image must be deinitialized, but does NOT own the pixel data
    pub fn fromImageBuffer(buffer: *const ImageBuffer) !VipsImageWrapper {
        std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
        std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
        std.debug.assert(buffer.channels == 3 or buffer.channels == 4);

        const image = vips_image_new_from_memory(
            buffer.data.ptr,
            buffer.data.len,
            @intCast(buffer.width),
            @intCast(buffer.height),
            @intCast(buffer.channels),
            .uchar,
        );

        if (image == null) {
            const err = getVipsError();
            std.debug.print("vips_image_new_from_memory failed: {s}\n", .{err});
            clearVipsError();
            return VipsError.ConversionFailed;
        }

        return VipsImageWrapper.wrap(image.?);
    }

    /// Save image as JPEG to memory buffer
    ///
    /// Quality: 0-100 (higher = better quality, larger file)
    /// Returns owned slice, caller must free
    /// Tiger Style: defer ensures g_free on all paths (prevents FFI leaks)
    pub fn saveAsJPEG(self: *const VipsImageWrapper, allocator: Allocator, quality: u8) ![]u8 {
        std.debug.assert(quality <= 100);

        var buffer_ptr: [*c]u8 = null;
        var buffer_len: usize = 0;

        // Note: vips varargs need null terminator
        const q_key = "Q";
        const result = vips_jpegsave_buffer(
            self.image,
            &buffer_ptr,
            &buffer_len,
            q_key.ptr,
            @as(c_int, quality),
            @as([*c]u8, null),
        );

        // Tiger Style: Always free buffer_ptr (prevents leak on error paths)
        defer if (buffer_ptr != null) g_free(buffer_ptr);

        if (result != 0) {
            const err = getVipsError();
            std.debug.print("vips_jpegsave_buffer failed: {s}\n", .{err});
            clearVipsError();
            return VipsError.OperationFailed;
        }

        if (buffer_ptr == null or buffer_len == 0) {
            std.debug.print("vips_jpegsave_buffer returned null/empty buffer\n", .{});
            return VipsError.OperationFailed;
        }

        // Copy to Zig-owned memory (buffer_ptr freed by defer above)
        const owned_buffer = try allocator.alloc(u8, buffer_len);
        errdefer allocator.free(owned_buffer);

        @memcpy(owned_buffer, buffer_ptr[0..buffer_len]);

        // Post-condition: Verify JPEG magic number (SOI marker)
        std.debug.assert(owned_buffer.len >= 2);
        std.debug.assert(owned_buffer[0] == 0xFF and owned_buffer[1] == 0xD8);

        return owned_buffer;
    }

    /// Save image as PNG to memory buffer
    ///
    /// Compression: 0-9 (higher = smaller file, slower)
    /// Returns owned slice, caller must free
    /// Tiger Style: defer ensures g_free on all paths (prevents FFI leaks)
    pub fn saveAsPNG(self: *const VipsImageWrapper, allocator: Allocator, compression: u8) ![]u8 {
        std.debug.assert(compression <= 9);

        var buffer_ptr: [*c]u8 = null;
        var buffer_len: usize = 0;

        const comp_key = "compression";
        const result = vips_pngsave_buffer(
            self.image,
            &buffer_ptr,
            &buffer_len,
            comp_key.ptr,
            @as(c_int, compression),
            @as([*c]u8, null),
        );

        // Tiger Style: Always free buffer_ptr (prevents leak on error paths)
        defer if (buffer_ptr != null) g_free(buffer_ptr);

        if (result != 0) {
            const err = getVipsError();
            std.debug.print("vips_pngsave_buffer failed: {s}\n", .{err});
            clearVipsError();
            return VipsError.OperationFailed;
        }

        if (buffer_ptr == null or buffer_len == 0) {
            std.debug.print("vips_pngsave_buffer returned null/empty buffer\n", .{});
            return VipsError.OperationFailed;
        }

        // Copy to Zig-owned memory (buffer_ptr freed by defer above)
        const owned_buffer = try allocator.alloc(u8, buffer_len);
        errdefer allocator.free(owned_buffer);

        @memcpy(owned_buffer, buffer_ptr[0..buffer_len]);

        // Post-condition: Verify PNG signature
        std.debug.assert(owned_buffer.len >= 8);
        std.debug.assert(owned_buffer[0] == 0x89); // PNG signature
        std.debug.assert(owned_buffer[1] == 0x50 and owned_buffer[2] == 0x4E and owned_buffer[3] == 0x47);

        return owned_buffer;
    }
};

// ============================================================================
// High-level Image Operations
// ============================================================================

/// Load image from file path
///
/// Safety: Returns wrapped image, caller must call deinit()
/// Tiger Style: Validates dimensions to prevent decompression bombs
pub fn loadImage(path: []const u8) !VipsImageWrapper {
    // Convert Zig string to null-terminated C string
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path.len >= path_buf.len) return VipsError.LoadFailed;

    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    // Assert null terminator
    std.debug.assert(path_buf[path.len] == 0);

    const image = vips_image_new_from_file(&path_buf, @as([*c]u8, null));
    if (image == null) {
        const err = getVipsError();
        std.debug.print("Failed to load image '{s}': {s}\n", .{ path, err });
        clearVipsError();
        return VipsError.LoadFailed;
    }

    var wrapper = VipsImageWrapper.wrap(image.?);

    // Tiger Style: Validate dimensions immediately after load (prevents decompression bombs)
    const w = wrapper.width();
    const h = wrapper.height();
    const b = wrapper.bands();

    // Enforce realistic limits for image optimizer
    const MAX_DIMENSION: u32 = 65535;
    const MAX_PIXELS: u64 = 178_000_000; // ~500 megapixels (e.g., 13000x13000)

    if (w == 0 or h == 0 or w > MAX_DIMENSION or h > MAX_DIMENSION) {
        std.log.err("Image dimensions out of bounds: {d}x{d} (path: {s})", .{ w, h, path });
        wrapper.deinit();
        return VipsError.InvalidImage;
    }

    const total_pixels: u64 = @as(u64, w) * @as(u64, h);
    if (total_pixels > MAX_PIXELS) {
        std.log.err("Image too large: {d}x{d} = {d} pixels (max {d}, path: {s})", .{ w, h, total_pixels, MAX_PIXELS, path });
        wrapper.deinit();
        return VipsError.InvalidImage;
    }

    // Validate bands
    std.debug.assert(b > 0 and b <= 4);

    return wrapper;
}

/// Apply EXIF auto-rotation to image
///
/// Safety: Returns new image, caller must deinit both input and output
pub fn autorot(input: *const VipsImageWrapper) !VipsImageWrapper {
    var output: ?*VipsImage = null;
    const result = vips_autorot(input.image, &output, @as([*c]u8, null));

    if (result != 0 or output == null) {
        const err = getVipsError();
        std.debug.print("vips_autorot failed: {s}\n", .{err});
        clearVipsError();
        return VipsError.OperationFailed;
    }

    return VipsImageWrapper.wrap(output.?);
}

/// Convert image to sRGB color space
///
/// Safety: Returns new image, caller must deinit both input and output
pub fn toSRGB(input: *const VipsImageWrapper) !VipsImageWrapper {
    var output: ?*VipsImage = null;
    const result = vips_colourspace(input.image, &output, .srgb, @as([*c]u8, null));

    if (result != 0 or output == null) {
        const err = getVipsError();
        std.debug.print("vips_colourspace failed: {s}\n", .{err});
        clearVipsError();
        return VipsError.OperationFailed;
    }

    return VipsImageWrapper.wrap(output.?);
}

/// Resize image by scale factor
///
/// HIGH-007: Comprehensive scale bounds validation to prevent integer overflow
/// and unreasonable memory allocation.
///
/// Safety: Returns new image, caller must deinit both input and output
pub fn resize(input: *const VipsImageWrapper, scale: f64) !VipsImageWrapper {
    // Tiger Style: Pre-conditions with detailed bounds checking
    std.debug.assert(scale > 0.0 and scale <= 10.0);
    std.debug.assert(!std.math.isNan(scale));
    std.debug.assert(!std.math.isInf(scale));

    // HIGH-007: Validate scale would not cause dimension overflow
    const current_w = input.width();
    const current_h = input.height();

    // Pre-condition: Current dimensions are valid
    std.debug.assert(current_w > 0 and current_h > 0);
    std.debug.assert(current_w <= 65535 and current_h <= 65535);

    // Calculate new dimensions (as floats first to check for overflow)
    const new_w_f64 = @as(f64, @floatFromInt(current_w)) * scale;
    const new_h_f64 = @as(f64, @floatFromInt(current_h)) * scale;

    // Check for dimension overflow before casting
    const MAX_DIMENSION_F64: f64 = 65535.0;
    if (new_w_f64 > MAX_DIMENSION_F64 or new_h_f64 > MAX_DIMENSION_F64) {
        std.log.err("Resize scale {d} would exceed max dimension: {d}x{d} -> {d:.0}x{d:.0}",
                    .{ scale, current_w, current_h, new_w_f64, new_h_f64 });
        return VipsError.InvalidImage;
    }

    // Check for minimum dimension (at least 1 pixel)
    if (new_w_f64 < 1.0 or new_h_f64 < 1.0) {
        std.log.err("Resize scale {d} would result in zero dimension: {d}x{d} -> {d:.0}x{d:.0}",
                    .{ scale, current_w, current_h, new_w_f64, new_h_f64 });
        return VipsError.InvalidImage;
    }

    var output: ?*VipsImage = null;
    const result = vips_resize(input.image, &output, scale, @as([*c]u8, null));

    if (result != 0 or output == null) {
        const err = getVipsError();
        std.log.err("vips_resize failed (scale={d}): {s}", .{ scale, err });
        clearVipsError();
        return VipsError.OperationFailed;
    }

    const wrapper = VipsImageWrapper.wrap(output.?);

    // Post-condition: Verify dimensions are reasonable
    const actual_w = wrapper.width();
    const actual_h = wrapper.height();
    std.debug.assert(actual_w > 0 and actual_h > 0);
    std.debug.assert(actual_w <= 65535 and actual_h <= 65535);

    return wrapper;
}

// ============================================================================
// Unit Tests (require libvips installed)
// ============================================================================

test "VipsContext init and deinit" {
    var ctx = try VipsContext.init();
    defer ctx.deinit();

    const testing = std.testing;
    try testing.expect(ctx.initialized);
}

// Note: File-based tests require actual image files
// These will be implemented in integration tests with test data
