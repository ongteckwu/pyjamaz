const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("../types/image_buffer.zig").ImageBuffer;

/// JPEG codec using libjpeg/mozjpeg
///
/// This module provides JPEG encoding and decoding using the libjpeg API.
/// Works with both libjpeg-turbo and mozjpeg (API-compatible).
///
/// Tiger Style: All operations bounded, explicit error handling, memory safety.

// ============================================================================
// C FFI Declarations (libjpeg)
// ============================================================================

/// JPEG error manager
const jpeg_error_mgr = extern struct {
    error_exit: ?*const fn (*jpeg_common_struct) callconv(.c) noreturn,
    emit_message: ?*const fn (*jpeg_common_struct, c_int) callconv(.c) void,
    output_message: ?*const fn (*jpeg_common_struct) callconv(.c) void,
    format_message: ?*const fn (*jpeg_common_struct, [*c]u8) callconv(.c) void,
    reset_error_mgr: ?*const fn (*jpeg_common_struct) callconv(.c) void,
    msg_code: c_int,
    msg_parm: extern union {
        i: [8]c_int,
        s: [80]u8,
    },
    trace_level: c_int,
    num_warnings: c_long,
    jpeg_message_table: [*c]const [*c]const u8,
    last_jpeg_message: c_int,
    addon_message_table: [*c]const [*c]const u8,
    first_addon_message: c_int,
    last_addon_message: c_int,
};

/// Common fields for compress and decompress
const jpeg_common_struct = extern struct {
    err: ?*jpeg_error_mgr,
    mem: ?*anyopaque,
    progress: ?*anyopaque,
    client_data: ?*anyopaque,
    is_decompressor: c_int,
    global_state: c_int,
};

/// JPEG compress structure
const jpeg_compress_struct = extern struct {
    err: ?*jpeg_error_mgr,
    mem: ?*anyopaque,
    progress: ?*anyopaque,
    client_data: ?*anyopaque,
    is_decompressor: c_int,
    global_state: c_int,

    dest: ?*anyopaque,
    image_width: c_uint,
    image_height: c_uint,
    input_components: c_int,
    in_color_space: J_COLOR_SPACE,
    input_gamma: f64,

    scale_num: c_uint,
    scale_denom: c_uint,
    jpeg_width: c_uint,
    jpeg_height: c_uint,

    data_precision: c_int,
    num_components: c_int,
    jpeg_color_space: J_COLOR_SPACE,

    comp_info: ?*anyopaque,
    quant_tbl_ptrs: [4]?*anyopaque,
    q_scale_factor: [4]c_int,

    dc_huff_tbl_ptrs: [4]?*anyopaque,
    ac_huff_tbl_ptrs: [4]?*anyopaque,

    arith_dc_L: [16]u8,
    arith_dc_U: [16]u8,
    arith_ac_K: [16]u8,

    num_scans: c_int,
    scan_info: ?*anyopaque,

    raw_data_in: c_int,
    arith_code: c_int,
    optimize_coding: c_int,
    CCIR601_sampling: c_int,
    do_fancy_downsampling: c_int,
    smoothing_factor: c_int,
    dct_method: J_DCT_METHOD,

    restart_interval: c_uint,
    restart_in_rows: c_int,

    write_JFIF_header: c_int,
    JFIF_major_version: u8,
    JFIF_minor_version: u8,
    density_unit: u8,
    X_density: u16,
    Y_density: u16,
    write_Adobe_marker: c_int,

    next_scanline: c_uint,
    progressive_mode: c_int,
    max_h_samp_factor: c_int,
    max_v_samp_factor: c_int,

    min_DCT_h_scaled_size: c_int,
    min_DCT_v_scaled_size: c_int,

    total_iMCU_rows: c_uint,
    comps_in_scan: c_int,
    cur_comp_info: [4]?*anyopaque,

    MCUs_per_row: c_uint,
    MCU_rows_in_scan: c_uint,
    blocks_in_MCU: c_int,
    MCU_membership: [10]c_int,

    Ss: c_int,
    Se: c_int,
    Ah: c_int,
    Al: c_int,
    block_size: c_int,
    natural_order: ?*const c_int,
    lim_Se: c_int,

    master: ?*anyopaque,
    main: ?*anyopaque,
    prep: ?*anyopaque,
    coef: ?*anyopaque,
    marker: ?*anyopaque,
    cconvert: ?*anyopaque,
    downsample: ?*anyopaque,
    fdct: ?*anyopaque,
    entropy: ?*anyopaque,
    script_space: ?*anyopaque,
    script_space_size: c_int,
};

const J_COLOR_SPACE = enum(c_int) {
    JCS_UNKNOWN = 0,
    JCS_GRAYSCALE = 1,
    JCS_RGB = 2,
    JCS_YCbCr = 3,
    JCS_CMYK = 4,
    JCS_YCCK = 5,
    JCS_EXT_RGB = 6,
    JCS_EXT_RGBX = 7,
    JCS_EXT_BGR = 8,
    JCS_EXT_BGRX = 9,
    JCS_EXT_XBGR = 10,
    JCS_EXT_XRGB = 11,
    JCS_EXT_RGBA = 12,
    JCS_EXT_BGRA = 13,
    JCS_EXT_ABGR = 14,
    JCS_EXT_ARGB = 15,
};

const J_DCT_METHOD = enum(c_int) {
    JDCT_ISLOW = 0,
    JDCT_IFAST = 1,
    JDCT_FLOAT = 2,
};

// External C functions from libjpeg
extern "c" fn jpeg_std_error(err: *jpeg_error_mgr) *jpeg_error_mgr;
extern "c" fn jpeg_CreateCompress(cinfo: *jpeg_compress_struct, version: c_int, structsize: usize) void;
extern "c" fn jpeg_destroy_compress(cinfo: *jpeg_compress_struct) void;
extern "c" fn jpeg_mem_dest(cinfo: *jpeg_compress_struct, outbuffer: *[*c]u8, outsize: *c_ulong) void;
extern "c" fn jpeg_set_defaults(cinfo: *jpeg_compress_struct) void;
extern "c" fn jpeg_set_quality(cinfo: *jpeg_compress_struct, quality: c_int, force_baseline: c_int) void;
extern "c" fn jpeg_start_compress(cinfo: *jpeg_compress_struct, write_all_tables: c_int) void;
extern "c" fn jpeg_write_scanlines(cinfo: *jpeg_compress_struct, scanlines: [*c][*c]u8, num_lines: c_uint) c_uint;
extern "c" fn jpeg_finish_compress(cinfo: *jpeg_compress_struct) void;

// ============================================================================
// Error Handling
// ============================================================================

pub const JpegError = error{
    InitFailed,
    EncodeFailed,
    DecodeFailed,
    OutOfMemory,
    InvalidQuality,
    InvalidImage,
};

// ============================================================================
// JPEG Encoding
// ============================================================================

/// Encode ImageBuffer to JPEG with given quality
///
/// Quality: 0-100 (0 = worst, 100 = best)
/// Progressive: Enable progressive JPEG encoding
///
/// Safety: Returns owned slice, caller must free with allocator
/// Tiger Style: Quality bounded 0-100, explicit error handling
pub fn encodeJPEG(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    quality: u8,
    progressive: bool,
) ![]u8 {
    // Assertions (Tiger Style: 2+)
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);
    std.debug.assert(quality <= 100);

    // JPEG doesn't support alpha, must be RGB
    if (buffer.channels == 4) {
        std.debug.print("Warning: JPEG doesn't support alpha, will be discarded\n", .{});
    }

    var jerr: jpeg_error_mgr = undefined;
    var cinfo: jpeg_compress_struct = undefined;

    // Initialize error manager
    _ = jpeg_std_error(&jerr);
    cinfo.err = &jerr;

    // Create compressor
    jpeg_CreateCompress(&cinfo, 62, @sizeOf(jpeg_compress_struct)); // 62 = JPEG_LIB_VERSION
    defer jpeg_destroy_compress(&cinfo);

    // Set up memory destination
    var outbuffer: [*c]u8 = null;
    var outsize: c_ulong = 0;
    jpeg_mem_dest(&cinfo, &outbuffer, &outsize);

    // Set image parameters
    cinfo.image_width = buffer.width;
    cinfo.image_height = buffer.height;
    cinfo.input_components = 3; // Always RGB for JPEG
    cinfo.in_color_space = .JCS_RGB;

    // Set defaults
    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, @intCast(quality), 1); // force_baseline = 1

    // Enable progressive if requested
    if (progressive) {
        // TODO: Call jpeg_simple_progression() if available
        // This requires checking for mozjpeg vs libjpeg-turbo
    }

    // Enable optimized coding (slower but smaller)
    cinfo.optimize_coding = 1;

    // Start compression
    jpeg_start_compress(&cinfo, 1);

    // Write scanlines
    var row: c_uint = 0;
    while (row < buffer.height) : (row += 1) {
        // Get row data
        const row_data = buffer.getRow(row);

        // If RGBA, need to strip alpha channel
        var rgb_row: [65535 * 3]u8 = undefined; // Max width * 3 channels
        if (buffer.channels == 4) {
            // Convert RGBA to RGB
            var x: u32 = 0;
            while (x < buffer.width) : (x += 1) {
                const src_offset = x * 4;
                const dst_offset = x * 3;
                rgb_row[dst_offset + 0] = row_data[src_offset + 0]; // R
                rgb_row[dst_offset + 1] = row_data[src_offset + 1]; // G
                rgb_row[dst_offset + 2] = row_data[src_offset + 2]; // B
                // Skip alpha
            }
            var row_ptr: [*c]u8 = &rgb_row;
            _ = jpeg_write_scanlines(&cinfo, @ptrCast(&row_ptr), 1);
        } else {
            // Already RGB
            var row_ptr: [*c]u8 = @constCast(row_data.ptr);
            _ = jpeg_write_scanlines(&cinfo, @ptrCast(&row_ptr), 1);
        }
    }

    std.debug.assert(row == buffer.height); // Post-loop assertion

    // Finish compression
    jpeg_finish_compress(&cinfo);

    // Copy output buffer to Zig-owned memory
    if (outbuffer == null or outsize == 0) {
        return JpegError.EncodeFailed;
    }

    const result = try allocator.alloc(u8, @intCast(outsize));
    @memcpy(result, outbuffer[0..@intCast(outsize)]);

    // Free libjpeg's buffer (it uses malloc)
    const c = @cImport({
        @cInclude("stdlib.h");
    });
    c.free(outbuffer);

    std.debug.assert(result.len == outsize); // Post-condition
    return result;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "JPEG encoding with valid quality" {
    const testing = std.testing;

    // Create small test image (10x10 RGB)
    var buffer = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer buffer.deinit();

    // Fill with red color
    for (buffer.data) |*pixel| {
        pixel.* = 255;
    }

    // Encode at various quality levels
    const qualities = [_]u8{ 10, 50, 90, 100 };
    for (qualities) |quality| {
        const jpeg_data = try encodeJPEG(testing.allocator, &buffer, quality, false);
        defer testing.allocator.free(jpeg_data);

        // Verify JPEG magic bytes (FF D8 FF)
        try testing.expect(jpeg_data.len > 3);
        try testing.expectEqual(@as(u8, 0xFF), jpeg_data[0]);
        try testing.expectEqual(@as(u8, 0xD8), jpeg_data[1]);
        try testing.expectEqual(@as(u8, 0xFF), jpeg_data[2]);
    }
}

test "JPEG encoding handles RGBA by stripping alpha" {
    const testing = std.testing;

    // Create small RGBA image
    var buffer = try ImageBuffer.init(testing.allocator, 10, 10, 4);
    defer buffer.deinit();

    // Fill with semi-transparent red
    var i: usize = 0;
    while (i < buffer.data.len) : (i += 4) {
        buffer.data[i + 0] = 255; // R
        buffer.data[i + 1] = 0; // G
        buffer.data[i + 2] = 0; // B
        buffer.data[i + 3] = 128; // A (will be stripped)
    }

    const jpeg_data = try encodeJPEG(testing.allocator, &buffer, 90, false);
    defer testing.allocator.free(jpeg_data);

    try testing.expect(jpeg_data.len > 0);
}
