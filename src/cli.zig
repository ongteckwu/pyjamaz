const std = @import("std");
const Allocator = std.mem.Allocator;
const MetricType = @import("metrics.zig").MetricType;
const SharpenStrength = @import("types/transform_params.zig").SharpenStrength;

/// CLI configuration parsed from command-line arguments
pub const CliConfig = struct {
    /// Input files or directories to process
    inputs: std.ArrayList([]const u8),

    /// Output directory (default: "./optimized")
    output_dir: []const u8,

    /// Maximum file size in bytes (0 = no limit)
    max_bytes: u32,

    /// Maximum perceptual difference (default: 1.0)
    max_diff: f64,

    /// Perceptual metric to use (default: dssim)
    metric_type: MetricType,

    /// Formats to try (comma-separated, e.g., "avif,webp,jpeg,png")
    formats: std.ArrayList([]const u8),

    /// Resize geometry (libvips format, e.g., "1920x1080")
    resize: ?[]const u8,

    /// Sharpening mode (none, auto, or 0.0-2.0)
    sharpen: SharpenStrength,

    /// Flatten color for JPEG with alpha (RGBA as u32, default: white 0xFFFFFFFF)
    flatten_color: u32,

    /// ICC profile handling: keep, srgb, discard
    icc_mode: IccMode,

    /// EXIF handling: keep, strip
    exif_mode: ExifMode,

    /// Concurrency level (0 = auto-detect)
    concurrency: u32,

    /// Output manifest JSON (null = no manifest)
    manifest_path: ?[]const u8,

    /// Verbosity level (0 = quiet, 1 = normal, 2 = verbose, 3 = debug)
    verbosity: u8,

    /// Random seed for deterministic encoding (null = non-deterministic)
    seed: ?u64,

    /// Dry run (don't write files)
    dry_run: bool,

    /// Enable JSON output format
    json_output: bool,

    /// Update golden snapshot baseline (regression testing)
    update_golden: bool,

    /// Golden manifest path (for regression testing)
    golden_manifest: ?[]const u8,

    /// Strict mode: exit 1 on any warning
    strict_mode: bool,

    allocator: Allocator,

    pub fn init(allocator: Allocator) CliConfig {
        return CliConfig{
            .inputs = std.ArrayList([]const u8){},
            .output_dir = "./optimized",
            .max_bytes = 0,
            .max_diff = 1.0,
            .metric_type = .dssim, // Default to DSSIM (v0.4.0)
            .formats = std.ArrayList([]const u8){},
            .resize = null,
            .sharpen = .none, // Default: no sharpening
            .flatten_color = 0xFFFFFFFF, // Default: white (RGBA)
            .icc_mode = .srgb,
            .exif_mode = .strip,
            .concurrency = 0,
            .manifest_path = null,
            .verbosity = 1, // Default: normal verbosity
            .seed = null, // Default: non-deterministic
            .dry_run = false,
            .json_output = false,
            .update_golden = false,
            .golden_manifest = null,
            .strict_mode = false, // Default: permissive mode
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CliConfig) void {
        self.inputs.deinit(self.allocator);
        self.formats.deinit(self.allocator);
    }
};

pub const IccMode = enum {
    keep, // Preserve original ICC profile
    srgb, // Convert to sRGB
    discard, // Remove ICC profile

    pub fn fromString(s: []const u8) ?IccMode {
        if (std.mem.eql(u8, s, "keep")) return .keep;
        if (std.mem.eql(u8, s, "srgb")) return .srgb;
        if (std.mem.eql(u8, s, "discard")) return .discard;
        return null;
    }
};

pub const ExifMode = enum {
    keep, // Preserve EXIF data
    strip, // Remove EXIF data

    pub fn fromString(s: []const u8) ?ExifMode {
        if (std.mem.eql(u8, s, "keep")) return .keep;
        if (std.mem.eql(u8, s, "strip")) return .strip;
        return null;
    }
};

/// Parse command-line arguments into CliConfig
///
/// Safety: Bounded argument parsing, explicit validation
pub fn parseArgs(allocator: Allocator) !CliConfig {
    var config = CliConfig.init(allocator);
    errdefer config.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    // Parse arguments
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--version")) {
            printVersion();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "-vv") or std.mem.eql(u8, arg, "-vvv")) {
            // Multi-level verbosity
            config.verbosity = @intCast(std.mem.count(u8, arg, "v"));
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            config.verbosity = 2; // --verbose = level 2
        } else if (std.mem.eql(u8, arg, "--out")) {
            const value = args.next() orelse return error.MissingValue;
            config.output_dir = value;
        } else if (std.mem.eql(u8, arg, "--max-kb")) {
            const value = args.next() orelse return error.MissingValue;
            const kb = try std.fmt.parseUnsigned(u32, value, 10);
            config.max_bytes = kb * 1024;
        } else if (std.mem.eql(u8, arg, "--max-bytes")) {
            const value = args.next() orelse return error.MissingValue;
            config.max_bytes = try std.fmt.parseUnsigned(u32, value, 10);
        } else if (std.mem.eql(u8, arg, "--max-diff")) {
            const value = args.next() orelse return error.MissingValue;
            config.max_diff = try std.fmt.parseFloat(f64, value);
            if (config.max_diff <= 0.0) return error.InvalidMaxDiff;
        } else if (std.mem.eql(u8, arg, "--metric")) {
            const value = args.next() orelse return error.MissingValue;
            config.metric_type = parseMetricType(value) orelse return error.InvalidMetric;
        } else if (std.mem.eql(u8, arg, "--sharpen")) {
            const value = args.next() orelse return error.MissingValue;
            config.sharpen = SharpenStrength.fromString(value) orelse return error.InvalidSharpen;
        } else if (std.mem.eql(u8, arg, "--flatten")) {
            const value = args.next() orelse return error.MissingValue;
            config.flatten_color = try parseHexColor(value);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            const value = args.next() orelse return error.MissingValue;
            config.seed = try std.fmt.parseUnsigned(u64, value, 10);
        } else if (std.mem.eql(u8, arg, "--formats")) {
            const value = args.next() orelse return error.MissingValue;
            try parseFormats(&config, value);
        } else if (std.mem.eql(u8, arg, "--resize")) {
            const value = args.next() orelse return error.MissingValue;
            config.resize = value;
        } else if (std.mem.eql(u8, arg, "--icc")) {
            const value = args.next() orelse return error.MissingValue;
            config.icc_mode = IccMode.fromString(value) orelse return error.InvalidIccMode;
        } else if (std.mem.eql(u8, arg, "--exif")) {
            const value = args.next() orelse return error.MissingValue;
            config.exif_mode = ExifMode.fromString(value) orelse return error.InvalidExifMode;
        } else if (std.mem.eql(u8, arg, "--concurrency")) {
            const value = args.next() orelse return error.MissingValue;
            config.concurrency = try std.fmt.parseUnsigned(u32, value, 10);
        } else if (std.mem.eql(u8, arg, "--manifest")) {
            const value = args.next() orelse return error.MissingValue;
            config.manifest_path = value;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            config.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            config.json_output = true;
        } else if (std.mem.eql(u8, arg, "--update-golden")) {
            config.update_golden = true;
        } else if (std.mem.eql(u8, arg, "--golden-manifest")) {
            const value = args.next() orelse return error.MissingValue;
            config.golden_manifest = value;
        } else if (std.mem.eql(u8, arg, "--strict")) {
            config.strict_mode = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("Unknown option: {s}\n", .{arg});
            return error.UnknownOption;
        } else {
            // Positional argument (input file/directory)
            try config.inputs.append(allocator, arg);
        }
    }

    // Validation
    if (config.inputs.items.len == 0) {
        std.debug.print("Error: No input files specified\n", .{});
        return error.NoInputs;
    }

    // Default formats if none specified
    if (config.formats.items.len == 0) {
        try config.formats.append(allocator, "webp");
        try config.formats.append(allocator, "jpeg");
        try config.formats.append(allocator, "png");
    }

    return config;
}

/// Parse comma-separated format list
fn parseFormats(config: *CliConfig, formats_str: []const u8) !void {
    var iter = std.mem.splitScalar(u8, formats_str, ',');
    while (iter.next()) |format| {
        const trimmed = std.mem.trim(u8, format, " \t");
        if (trimmed.len > 0) {
            try config.formats.append(config.allocator, trimmed);
        }
    }
}

/// Parse metric type from string
fn parseMetricType(s: []const u8) ?MetricType {
    if (std.mem.eql(u8, s, "butteraugli")) return .butteraugli;
    if (std.mem.eql(u8, s, "dssim")) return .dssim;
    if (std.mem.eql(u8, s, "ssimulacra2")) return .ssimulacra2;
    if (std.mem.eql(u8, s, "none")) return .none;
    return null;
}

/// Parse hex color from string (supports #RGB, #RRGGBB, #RRGGBBAA)
/// Returns RGBA as u32 (0xRRGGBBAA)
fn parseHexColor(s: []const u8) !u32 {
    if (s.len == 0) return error.InvalidColor;

    // Skip leading '#' if present
    const hex_str = if (s[0] == '#') s[1..] else s;

    // Validate length and parse
    const rgba: u32 = switch (hex_str.len) {
        // #RGB -> #RRGGBBAA
        3 => blk: {
            const r = try std.fmt.parseInt(u8, hex_str[0..1], 16);
            const g = try std.fmt.parseInt(u8, hex_str[1..2], 16);
            const b = try std.fmt.parseInt(u8, hex_str[2..3], 16);
            break :blk (@as(u32, r) * 0x11 << 24) | (@as(u32, g) * 0x11 << 16) | (@as(u32, b) * 0x11 << 8) | 0xFF;
        },
        // #RRGGBB -> #RRGGBBAA
        6 => blk: {
            const rgb = try std.fmt.parseInt(u24, hex_str, 16);
            break :blk (@as(u32, rgb) << 8) | 0xFF; // Add full alpha
        },
        // #RRGGBBAA
        8 => try std.fmt.parseInt(u32, hex_str, 16),
        else => return error.InvalidColorFormat,
    };

    return rgba;
}

fn printHelp() void {
    const help_text =
        \\Pyjamaz - Zig-powered image optimizer with perceptual quality guardrails
        \\
        \\USAGE:
        \\    pyjamaz [OPTIONS] <INPUT>...
        \\
        \\ARGS:
        \\    <INPUT>...    Input files or directories
        \\
        \\OPTIONS:
        \\    -h, --help              Print help information
        \\    --version               Print version information
        \\    --out <DIR>             Output directory (default: ./optimized)
        \\    --max-kb <KB>           Maximum file size in kilobytes
        \\    --max-bytes <BYTES>     Maximum file size in bytes
        \\    --max-diff <FLOAT>      Maximum perceptual difference (default: 1.0, must be > 0)
        \\    --metric <TYPE>         Perceptual metric: dssim, ssimulacra2, butteraugli, none (default: dssim)
        \\    --formats <LIST>        Comma-separated formats to try (default: webp,jpeg,png)
        \\    --resize <GEOMETRY>     Resize geometry (e.g., 1920x1080, 1024, x480)
        \\    --sharpen <MODE>        Sharpening: none, auto, or 0.0-2.0 (default: none)
        \\    --flatten <COLOR>       Background color for JPEG with alpha (hex: #RGB, #RRGGBB, #RRGGBBAA, default: #FFF)
        \\    --icc <MODE>            ICC profile handling: keep, srgb, discard (default: srgb)
        \\    --exif <MODE>           EXIF handling: keep, strip (default: strip)
        \\    --concurrency <N>       Concurrency level (default: auto)
        \\    --manifest <FILE>       Output manifest JSON file
        \\    -v, -vv, -vvv           Verbosity level (1=normal, 2=verbose, 3=debug)
        \\    --verbose               Same as -vv
        \\    --seed <N>              Random seed for deterministic encoding (0-18446744073709551615)
        \\    --dry-run               Don't write output files
        \\    --json                  Output results as JSON
        \\    --strict                Exit with error (code 1) on any warning
        \\
        \\REGRESSION TESTING:
        \\    --update-golden         Update golden snapshot baseline (creates/updates manifest)
        \\    --golden-manifest <FILE> Golden manifest path (default: testdata/golden/v0.4.0/manifest.tsv)
        \\
        \\EXAMPLES:
        \\    pyjamaz image.jpg
        \\    pyjamaz --max-kb 100 --formats avif,webp *.jpg
        \\    pyjamaz --out ./optimized --resize 1920x1080 --sharpen auto images/
        \\    pyjamaz --metric ssimulacra2 --max-diff 0.002 --seed 42 *.png
        \\    pyjamaz --flatten #000000 --formats jpeg image-with-alpha.png
        \\
        \\PERCEPTUAL METRICS:
        \\    dssim        DSSIM metric (default), threshold: 0.01 = small difference
        \\    ssimulacra2  SSIMULACRA2 metric (recommended), threshold: 0.002 = acceptable quality
        \\    butteraugli  Butteraugli metric (not implemented, will error)
        \\    none         Disable perceptual checking (size-only optimization)
        \\
        \\EXIT CODES:
        \\    0   Success: all images optimized successfully
        \\    1   CLI error: invalid arguments or options
        \\    10  Budget unmet: at least one image exceeds max_bytes constraint
        \\    11  Diff ceiling unmet: all candidates exceed max_diff quality threshold
        \\    12  Decode error: input image invalid or corrupted
        \\    13  Encode error: codec failure during encoding
        \\    14  Metric error: perceptual metric computation failed
        \\
        \\REGRESSION TESTING WORKFLOW:
        \\    # 1. Generate golden snapshot baseline
        \\    pyjamaz --update-golden --golden-manifest golden.tsv testdata/
        \\
        \\    # 2. Run tests and compare against baseline
        \\    pyjamaz --golden-manifest golden.tsv testdata/
        \\
        \\    # 3. Update baseline after verifying changes
        \\    pyjamaz --update-golden --golden-manifest golden.tsv testdata/
        \\
    ;
    std.debug.print("{s}", .{help_text});
}

fn printVersion() void {
    std.debug.print("pyjamaz 0.1.0\n", .{});
}

// Unit tests
test "CliConfig.init creates default config" {
    const testing = std.testing;

    var config = CliConfig.init(testing.allocator);
    defer config.deinit();

    try testing.expectEqual(@as(usize, 0), config.inputs.items.len);
    try testing.expectEqual(@as(u32, 0), config.max_bytes);
    try testing.expectEqual(@as(f64, 1.0), config.max_diff);
    try testing.expectEqual(MetricType.dssim, config.metric_type);
    try testing.expect(config.sharpen == .none);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.flatten_color);
    try testing.expectEqual(@as(u8, 1), config.verbosity);
    try testing.expect(config.seed == null);
    try testing.expect(!config.dry_run);
}

test "IccMode.fromString parses correctly" {
    const testing = std.testing;

    try testing.expectEqual(IccMode.keep, IccMode.fromString("keep").?);
    try testing.expectEqual(IccMode.srgb, IccMode.fromString("srgb").?);
    try testing.expectEqual(IccMode.discard, IccMode.fromString("discard").?);
    try testing.expect(IccMode.fromString("invalid") == null);
}

test "ExifMode.fromString parses correctly" {
    const testing = std.testing;

    try testing.expectEqual(ExifMode.keep, ExifMode.fromString("keep").?);
    try testing.expectEqual(ExifMode.strip, ExifMode.fromString("strip").?);
    try testing.expect(ExifMode.fromString("invalid") == null);
}

test "parseMetricType parses all metric types" {
    const testing = std.testing;

    try testing.expectEqual(MetricType.butteraugli, parseMetricType("butteraugli").?);
    try testing.expectEqual(MetricType.dssim, parseMetricType("dssim").?);
    try testing.expectEqual(MetricType.ssimulacra2, parseMetricType("ssimulacra2").?);
    try testing.expectEqual(MetricType.none, parseMetricType("none").?);
    try testing.expect(parseMetricType("invalid") == null);
    try testing.expect(parseMetricType("") == null);
}

test "parseHexColor handles #RGB format" {
    const testing = std.testing;

    // #RGB -> #RRGGBBAA
    const white = try parseHexColor("#FFF");
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), white);

    const red = try parseHexColor("#F00");
    try testing.expectEqual(@as(u32, 0xFF0000FF), red);

    const green = try parseHexColor("#0F0");
    try testing.expectEqual(@as(u32, 0x00FF00FF), green);

    const blue = try parseHexColor("#00F");
    try testing.expectEqual(@as(u32, 0x0000FFFF), blue);
}

test "parseHexColor handles #RRGGBB format" {
    const testing = std.testing;

    // #RRGGBB -> #RRGGBBAA (adds full alpha)
    const white = try parseHexColor("#FFFFFF");
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), white);

    const red = try parseHexColor("#FF0000");
    try testing.expectEqual(@as(u32, 0xFF0000FF), red);

    const green = try parseHexColor("#00FF00");
    try testing.expectEqual(@as(u32, 0x00FF00FF), green);

    const blue = try parseHexColor("#0000FF");
    try testing.expectEqual(@as(u32, 0x0000FFFF), blue);

    // Without # prefix
    const black = try parseHexColor("000000");
    try testing.expectEqual(@as(u32, 0x000000FF), black);
}

test "parseHexColor handles #RRGGBBAA format" {
    const testing = std.testing;

    const white_full = try parseHexColor("#FFFFFFFF");
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), white_full);

    const white_half = try parseHexColor("#FFFFFF80");
    try testing.expectEqual(@as(u32, 0xFFFFFF80), white_half);

    const transparent = try parseHexColor("#00000000");
    try testing.expectEqual(@as(u32, 0x00000000), transparent);

    // Without # prefix
    const red_half = try parseHexColor("FF000080");
    try testing.expectEqual(@as(u32, 0xFF000080), red_half);
}

test "parseHexColor rejects invalid formats" {
    const testing = std.testing;

    try testing.expectError(error.InvalidColor, parseHexColor(""));
    try testing.expectError(error.InvalidColorFormat, parseHexColor("#"));
    try testing.expectError(error.InvalidColorFormat, parseHexColor("#FF"));
    try testing.expectError(error.InvalidColorFormat, parseHexColor("#FFFF"));
    try testing.expectError(error.InvalidColorFormat, parseHexColor("#FFFFFFF"));
    try testing.expectError(error.InvalidCharacter, parseHexColor("#GGGGGG"));
}
