const std = @import("std");
const Allocator = std.mem.Allocator;

/// Supported image formats
pub const ImageFormat = enum(u8) {
    jpeg = 0,
    png = 1,
    webp = 2,
    avif = 3,
    unknown = 255,

    pub fn toString(self: ImageFormat) []const u8 {
        return switch (self) {
            .jpeg => "JPEG",
            .png => "PNG",
            .webp => "WebP",
            .avif => "AVIF",
            .unknown => "Unknown",
        };
    }

    pub fn fileExtension(self: ImageFormat) []const u8 {
        return switch (self) {
            .jpeg => ".jpg",
            .png => ".png",
            .webp => ".webp",
            .avif => ".avif",
            .unknown => "",
        };
    }
};

/// EXIF orientation values (standard)
pub const ExifOrientation = enum(u8) {
    normal = 1,           // No transformation
    flip_horizontal = 2,  // Flip horizontally
    rotate_180 = 3,       // Rotate 180°
    flip_vertical = 4,    // Flip vertically
    transpose = 5,        // Flip horizontally and rotate 270° CW
    rotate_90 = 6,        // Rotate 90° CW
    transverse = 7,       // Flip horizontally and rotate 90° CW
    rotate_270 = 8,       // Rotate 270° CW (90° CCW)
};

/// ImageMetadata stores format-specific information about an image
///
/// Tiger Style: explicit types, optional fields for ICC/EXIF
pub const ImageMetadata = struct {
    /// Image format (JPEG, PNG, WebP, AVIF)
    format: ImageFormat,

    /// Original width before any transformations (max 65535)
    original_width: u32,

    /// Original height before any transformations (max 65535)
    original_height: u32,

    /// Does the image have an alpha channel?
    has_alpha: bool,

    /// EXIF orientation (1-8, or 1 if not present)
    exif_orientation: ExifOrientation,

    /// ICC color profile data (owned by this struct)
    /// null if no profile or profile was discarded
    icc_profile: ?[]u8,

    /// Allocator for ICC profile data
    allocator: ?Allocator,

    /// Initialize ImageMetadata with required fields
    ///
    /// Safety invariants:
    /// - width and height must be > 0
    /// - width and height must be <= 65535
    pub fn init(
        format: ImageFormat,
        width: u32,
        height: u32,
        has_alpha: bool,
    ) ImageMetadata {
        // Assertions (Tiger Style: 2+)
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);
        std.debug.assert(width <= 65535);
        std.debug.assert(height <= 65535);

        return ImageMetadata{
            .format = format,
            .original_width = width,
            .original_height = height,
            .has_alpha = has_alpha,
            .exif_orientation = .normal,
            .icc_profile = null,
            .allocator = null,
        };
    }

    /// Set ICC profile data (takes ownership)
    ///
    /// HIGH-013: Validates ICC profile size to prevent maliciously large profiles
    /// that could cause OOM or excessive memory usage.
    ///
    /// If an ICC profile already exists, it will be freed first.
    pub fn setIccProfile(self: *ImageMetadata, allocator: Allocator, profile_data: []const u8) !void {
        // Tiger Style: Pre-conditions
        std.debug.assert(profile_data.len > 0);

        // HIGH-013: Validate ICC profile size
        // Typical ICC profiles are 500B - 5MB. Anything > 10MB is suspicious.
        const MAX_ICC_PROFILE_SIZE: usize = 10 * 1024 * 1024; // 10MB
        const LARGE_ICC_WARNING_SIZE: usize = 1 * 1024 * 1024; // 1MB

        if (profile_data.len > MAX_ICC_PROFILE_SIZE) {
            std.log.err("ICC profile too large: {d} bytes (max {d} bytes)",
                       .{ profile_data.len, MAX_ICC_PROFILE_SIZE });
            return error.IccProfileTooLarge;
        }

        if (profile_data.len > LARGE_ICC_WARNING_SIZE) {
            std.log.warn("Unusually large ICC profile: {d} KB (typical < 1MB)",
                        .{ profile_data.len / 1024 });
        }

        // Free existing profile if present
        if (self.icc_profile) |old_profile| {
            if (self.allocator) |alloc| {
                alloc.free(old_profile);
            }
        }

        // Allocate and copy new profile
        const new_profile = try allocator.alloc(u8, profile_data.len);
        errdefer allocator.free(new_profile);

        @memcpy(new_profile, profile_data);

        self.icc_profile = new_profile;
        self.allocator = allocator;

        // Post-condition
        std.debug.assert(self.icc_profile != null);
        std.debug.assert(self.icc_profile.?.len == profile_data.len);
    }

    /// Free ICC profile data if allocated
    pub fn deinit(self: *ImageMetadata) void {
        if (self.icc_profile) |profile| {
            if (self.allocator) |allocator| {
                allocator.free(profile);
            }
        }
        self.* = undefined;
    }

    /// Check if orientation transformation is needed
    pub fn needsOrientationFix(self: *const ImageMetadata) bool {
        return self.exif_orientation != .normal;
    }

    /// Get dimensions after applying EXIF orientation
    pub fn orientedDimensions(self: *const ImageMetadata) struct { width: u32, height: u32 } {
        return switch (self.exif_orientation) {
            .rotate_90, .rotate_270, .transpose, .transverse => .{
                .width = self.original_height,
                .height = self.original_width,
            },
            else => .{
                .width = self.original_width,
                .height = self.original_height,
            },
        };
    }

    /// Calculate memory usage of this metadata struct
    pub fn memoryUsage(self: *const ImageMetadata) u64 {
        var total: u64 = @sizeOf(ImageMetadata);
        if (self.icc_profile) |profile| {
            total += profile.len;
        }
        return total;
    }

    /// Check if format supports alpha channel
    pub fn formatSupportsAlpha(format: ImageFormat) bool {
        return switch (format) {
            .png, .webp, .avif => true,
            .jpeg => false,
            .unknown => false,
        };
    }
};

// Unit tests
test "ImageMetadata.init creates valid metadata" {
    const testing = std.testing;

    const metadata = ImageMetadata.init(.jpeg, 1920, 1080, false);

    try testing.expectEqual(ImageFormat.jpeg, metadata.format);
    try testing.expectEqual(@as(u32, 1920), metadata.original_width);
    try testing.expectEqual(@as(u32, 1080), metadata.original_height);
    try testing.expect(!metadata.has_alpha);
    try testing.expectEqual(ExifOrientation.normal, metadata.exif_orientation);
    try testing.expect(metadata.icc_profile == null);
}

test "ImageMetadata.setIccProfile stores profile" {
    const testing = std.testing;

    var metadata = ImageMetadata.init(.png, 800, 600, true);
    defer metadata.deinit();

    const fake_profile = [_]u8{ 1, 2, 3, 4, 5 };
    try metadata.setIccProfile(testing.allocator, &fake_profile);

    try testing.expect(metadata.icc_profile != null);
    try testing.expectEqual(@as(usize, 5), metadata.icc_profile.?.len);
    try testing.expectEqual(@as(u8, 1), metadata.icc_profile.?[0]);
}

test "ImageMetadata.needsOrientationFix detects rotation" {
    const testing = std.testing;

    var metadata = ImageMetadata.init(.jpeg, 1920, 1080, false);
    try testing.expect(!metadata.needsOrientationFix());

    metadata.exif_orientation = .rotate_90;
    try testing.expect(metadata.needsOrientationFix());
}

test "ImageMetadata.orientedDimensions handles rotation" {
    const testing = std.testing;

    var metadata = ImageMetadata.init(.jpeg, 1920, 1080, false);

    // Normal orientation
    var dims = metadata.orientedDimensions();
    try testing.expectEqual(@as(u32, 1920), dims.width);
    try testing.expectEqual(@as(u32, 1080), dims.height);

    // 90° rotation swaps dimensions
    metadata.exif_orientation = .rotate_90;
    dims = metadata.orientedDimensions();
    try testing.expectEqual(@as(u32, 1080), dims.width);
    try testing.expectEqual(@as(u32, 1920), dims.height);
}

test "ImageMetadata.formatSupportsAlpha checks correctly" {
    const testing = std.testing;

    try testing.expect(ImageMetadata.formatSupportsAlpha(.png));
    try testing.expect(ImageMetadata.formatSupportsAlpha(.webp));
    try testing.expect(ImageMetadata.formatSupportsAlpha(.avif));
    try testing.expect(!ImageMetadata.formatSupportsAlpha(.jpeg));
}

test "ImageFormat.toString returns readable names" {
    const testing = std.testing;

    try testing.expectEqualStrings("JPEG", ImageFormat.jpeg.toString());
    try testing.expectEqualStrings("PNG", ImageFormat.png.toString());
    try testing.expectEqualStrings("WebP", ImageFormat.webp.toString());
    try testing.expectEqualStrings("AVIF", ImageFormat.avif.toString());
}

test "ImageFormat.fileExtension returns correct extensions" {
    const testing = std.testing;

    try testing.expectEqualStrings(".jpg", ImageFormat.jpeg.fileExtension());
    try testing.expectEqualStrings(".png", ImageFormat.png.fileExtension());
    try testing.expectEqualStrings(".webp", ImageFormat.webp.fileExtension());
    try testing.expectEqualStrings(".avif", ImageFormat.avif.fileExtension());
}

test "ImageMetadata memory leak check" {
    const testing = std.testing;

    var metadata = ImageMetadata.init(.png, 100, 100, true);
    const fake_profile = [_]u8{ 1, 2, 3 };
    try metadata.setIccProfile(testing.allocator, &fake_profile);
    metadata.deinit(); // Should free ICC profile
}
