const std = @import("std");

/// Resize mode for image transformation
pub const ResizeMode = enum {
    /// Resize to cover the target dimensions (may crop)
    cover,
    /// Resize to contain within target dimensions (may letterbox)
    contain,
    /// Resize to exact dimensions (may distort aspect ratio)
    exact,
    /// Only shrink, never upscale
    only_shrink,

    pub fn toString(self: ResizeMode) []const u8 {
        return switch (self) {
            .cover => "cover",
            .contain => "contain",
            .exact => "exact",
            .only_shrink => "only-shrink",
        };
    }

    pub fn fromString(s: []const u8) ?ResizeMode {
        if (std.mem.eql(u8, s, "cover")) return .cover;
        if (std.mem.eql(u8, s, "contain")) return .contain;
        if (std.mem.eql(u8, s, "exact")) return .exact;
        if (std.mem.eql(u8, s, "only-shrink")) return .only_shrink;
        return null;
    }
};

/// Sharpening strength
pub const SharpenStrength = union(enum) {
    /// No sharpening
    none,
    /// Automatic sharpening based on resize amount
    auto,
    /// Custom sharpening amount (0.0 = none, 1.0 = default, 2.0 = strong)
    custom: f32,

    pub fn toString(self: SharpenStrength, buf: []u8) ![]const u8 {
        return switch (self) {
            .none => "none",
            .auto => "auto",
            .custom => |value| try std.fmt.bufPrint(buf, "{d:.2}", .{value}),
        };
    }

    pub fn fromString(s: []const u8) ?SharpenStrength {
        if (std.mem.eql(u8, s, "none")) return .none;
        if (std.mem.eql(u8, s, "auto")) return .auto;
        const value = std.fmt.parseFloat(f32, s) catch return null;
        if (value < 0.0 or value > 10.0) return null;
        return .{ .custom = value };
    }
};

/// ICC profile handling mode
pub const IccMode = enum {
    /// Keep original ICC profile
    keep,
    /// Convert to sRGB
    srgb,
    /// Discard ICC profile
    discard,

    pub fn toString(self: IccMode) []const u8 {
        return switch (self) {
            .keep => "keep",
            .srgb => "srgb",
            .discard => "discard",
        };
    }

    pub fn fromString(s: []const u8) ?IccMode {
        if (std.mem.eql(u8, s, "keep")) return .keep;
        if (std.mem.eql(u8, s, "srgb")) return .srgb;
        if (std.mem.eql(u8, s, "discard")) return .discard;
        return null;
    }
};

/// EXIF metadata handling mode
pub const ExifMode = enum {
    /// Strip all EXIF metadata
    strip,
    /// Keep EXIF metadata
    keep,

    pub fn toString(self: ExifMode) []const u8 {
        return switch (self) {
            .strip => "strip",
            .keep => "keep",
        };
    }

    pub fn fromString(s: []const u8) ?ExifMode {
        if (std.mem.eql(u8, s, "strip")) return .strip;
        if (std.mem.eql(u8, s, "keep")) return .keep;
        return null;
    }
};

/// Target dimensions for resize
pub const TargetDimensions = struct {
    width: u32,
    height: u32,

    /// Tiger Style: Assertions for valid dimensions
    pub fn init(width: u32, height: u32) TargetDimensions {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);
        std.debug.assert(width <= 65535);
        std.debug.assert(height <= 65535);

        return .{ .width = width, .height = height };
    }

    /// Parse from libvips-style geometry string
    /// Formats: "WxH", "W", or "xH"
    pub fn fromString(s: []const u8) ?TargetDimensions {
        if (s.len == 0) return null;

        var width: ?u32 = null;
        var height: ?u32 = null;

        if (std.mem.indexOf(u8, s, "x")) |pos| {
            // Format: WxH or xH or Wx
            if (pos > 0) {
                width = std.fmt.parseInt(u32, s[0..pos], 10) catch return null;
            }
            if (pos + 1 < s.len) {
                height = std.fmt.parseInt(u32, s[pos + 1 ..], 10) catch return null;
            }
        } else {
            // Format: W (square)
            width = std.fmt.parseInt(u32, s, 10) catch return null;
            height = width;
        }

        if (width == null and height == null) return null;
        const w = width orelse height.?;
        const h = height orelse width.?;

        if (w == 0 or h == 0 or w > 65535 or h > 65535) return null;

        return init(w, h);
    }
};

/// Parameters for image transformation
pub const TransformParams = struct {
    /// Target dimensions (null = no resize)
    target_dimensions: ?TargetDimensions = null,
    /// Resize mode
    resize_mode: ResizeMode = .only_shrink,
    /// Sharpening strength
    sharpen: SharpenStrength = .none,
    /// ICC profile handling
    icc_mode: IccMode = .srgb,
    /// EXIF handling
    exif_mode: ExifMode = .strip,

    /// Tiger Style: Default constructor with safe defaults
    pub fn init() TransformParams {
        return .{};
    }

    /// Create params with custom dimensions
    pub fn withDimensions(width: u32, height: u32) TransformParams {
        return .{
            .target_dimensions = TargetDimensions.init(width, height),
        };
    }

    /// Check if any transformation is needed
    pub fn needsTransform(self: TransformParams) bool {
        return self.target_dimensions != null or
            self.sharpen != .none or
            self.icc_mode != .keep or
            self.exif_mode == .strip;
    }
};

// Unit tests
test "ResizeMode: string conversion" {
    const testing = std.testing;

    try testing.expectEqual(ResizeMode.cover, ResizeMode.fromString("cover").?);
    try testing.expectEqual(ResizeMode.contain, ResizeMode.fromString("contain").?);
    try testing.expectEqual(ResizeMode.exact, ResizeMode.fromString("exact").?);
    try testing.expectEqual(ResizeMode.only_shrink, ResizeMode.fromString("only-shrink").?);

    try testing.expect(ResizeMode.fromString("invalid") == null);

    try testing.expectEqualStrings("cover", ResizeMode.cover.toString());
    try testing.expectEqualStrings("only-shrink", ResizeMode.only_shrink.toString());
}

test "SharpenStrength: parsing" {
    const testing = std.testing;

    const none = SharpenStrength.fromString("none").?;
    try testing.expect(none == .none);

    const auto = SharpenStrength.fromString("auto").?;
    try testing.expect(auto == .auto);

    const custom = SharpenStrength.fromString("1.5").?;
    try testing.expect(custom == .custom);
    try testing.expectApproxEqAbs(@as(f32, 1.5), custom.custom, 0.01);

    try testing.expect(SharpenStrength.fromString("invalid") == null);
    try testing.expect(SharpenStrength.fromString("-1.0") == null);
    try testing.expect(SharpenStrength.fromString("11.0") == null);
}

test "IccMode: string conversion" {
    const testing = std.testing;

    try testing.expectEqual(IccMode.keep, IccMode.fromString("keep").?);
    try testing.expectEqual(IccMode.srgb, IccMode.fromString("srgb").?);
    try testing.expectEqual(IccMode.discard, IccMode.fromString("discard").?);

    try testing.expect(IccMode.fromString("invalid") == null);
}

test "ExifMode: string conversion" {
    const testing = std.testing;

    try testing.expectEqual(ExifMode.strip, ExifMode.fromString("strip").?);
    try testing.expectEqual(ExifMode.keep, ExifMode.fromString("keep").?);

    try testing.expect(ExifMode.fromString("invalid") == null);
}

test "TargetDimensions: parsing geometry strings" {
    const testing = std.testing;

    // WxH format
    const d1 = TargetDimensions.fromString("800x600").?;
    try testing.expectEqual(@as(u32, 800), d1.width);
    try testing.expectEqual(@as(u32, 600), d1.height);

    // W format (square)
    const d2 = TargetDimensions.fromString("1024").?;
    try testing.expectEqual(@as(u32, 1024), d2.width);
    try testing.expectEqual(@as(u32, 1024), d2.height);

    // xH format
    const d3 = TargetDimensions.fromString("x480").?;
    try testing.expectEqual(@as(u32, 480), d3.width);
    try testing.expectEqual(@as(u32, 480), d3.height);

    // Wx format
    const d4 = TargetDimensions.fromString("640x").?;
    try testing.expectEqual(@as(u32, 640), d4.width);
    try testing.expectEqual(@as(u32, 640), d4.height);

    // Invalid formats
    try testing.expect(TargetDimensions.fromString("") == null);
    try testing.expect(TargetDimensions.fromString("x") == null);
    try testing.expect(TargetDimensions.fromString("abc") == null);
    try testing.expect(TargetDimensions.fromString("0x0") == null);
    try testing.expect(TargetDimensions.fromString("99999x99999") == null);
}

test "TransformParams: default initialization" {
    const testing = std.testing;

    const params = TransformParams.init();
    try testing.expect(params.target_dimensions == null);
    try testing.expectEqual(ResizeMode.only_shrink, params.resize_mode);
    try testing.expect(params.sharpen == .none);
    try testing.expectEqual(IccMode.srgb, params.icc_mode);
    try testing.expectEqual(ExifMode.strip, params.exif_mode);
}

test "TransformParams: withDimensions" {
    const testing = std.testing;

    const params = TransformParams.withDimensions(1920, 1080);
    try testing.expect(params.target_dimensions != null);
    try testing.expectEqual(@as(u32, 1920), params.target_dimensions.?.width);
    try testing.expectEqual(@as(u32, 1080), params.target_dimensions.?.height);
}

test "TransformParams: needsTransform detection" {
    const testing = std.testing;

    // Default params with sRGB conversion and EXIF stripping needs transform
    var params = TransformParams.init();
    try testing.expect(params.needsTransform());

    // With ICC keep and EXIF keep, no transform needed
    params.icc_mode = .keep;
    params.exif_mode = .keep;
    try testing.expect(!params.needsTransform());

    // With dimensions, needs transform
    params.target_dimensions = TargetDimensions.init(800, 600);
    try testing.expect(params.needsTransform());

    // With sharpening, needs transform
    params.target_dimensions = null;
    params.sharpen = .auto;
    try testing.expect(params.needsTransform());
}
