const std = @import("std");
const Allocator = std.mem.Allocator;

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

    /// Formats to try (comma-separated, e.g., "avif,webp,jpeg,png")
    formats: std.ArrayList([]const u8),

    /// Resize geometry (libvips format, e.g., "1920x1080")
    resize: ?[]const u8,

    /// ICC profile handling: keep, srgb, discard
    icc_mode: IccMode,

    /// EXIF handling: keep, strip
    exif_mode: ExifMode,

    /// Concurrency level (0 = auto-detect)
    concurrency: u32,

    /// Output manifest JSON (null = no manifest)
    manifest_path: ?[]const u8,

    /// Enable verbose logging
    verbose: bool,

    /// Dry run (don't write files)
    dry_run: bool,

    /// Enable JSON output format
    json_output: bool,

    allocator: Allocator,

    pub fn init(allocator: Allocator) CliConfig {
        return CliConfig{
            .inputs = std.ArrayList([]const u8){},
            .output_dir = "./optimized",
            .max_bytes = 0,
            .max_diff = 1.0,
            .formats = std.ArrayList([]const u8){},
            .resize = null,
            .icc_mode = .srgb,
            .exif_mode = .strip,
            .concurrency = 0,
            .manifest_path = null,
            .verbose = false,
            .dry_run = false,
            .json_output = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CliConfig) void {
        self.inputs.deinit(self.allocator);
        self.formats.deinit(self.allocator);
    }
};

pub const IccMode = enum {
    keep,    // Preserve original ICC profile
    srgb,    // Convert to sRGB
    discard, // Remove ICC profile

    pub fn fromString(s: []const u8) ?IccMode {
        if (std.mem.eql(u8, s, "keep")) return .keep;
        if (std.mem.eql(u8, s, "srgb")) return .srgb;
        if (std.mem.eql(u8, s, "discard")) return .discard;
        return null;
    }
};

pub const ExifMode = enum {
    keep,  // Preserve EXIF data
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
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            std.process.exit(0);
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
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            config.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            config.json_output = true;
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
        \\    -v, --version           Print version information
        \\    --out <DIR>             Output directory (default: ./optimized)
        \\    --max-kb <KB>           Maximum file size in kilobytes
        \\    --max-bytes <BYTES>     Maximum file size in bytes
        \\    --max-diff <FLOAT>      Maximum perceptual difference (default: 1.0)
        \\    --formats <LIST>        Comma-separated formats to try (default: webp,jpeg,png)
        \\    --resize <GEOMETRY>     Resize geometry (e.g., 1920x1080)
        \\    --icc <MODE>            ICC profile handling: keep, srgb, discard (default: srgb)
        \\    --exif <MODE>           EXIF handling: keep, strip (default: strip)
        \\    --concurrency <N>       Concurrency level (default: auto)
        \\    --manifest <FILE>       Output manifest JSON file
        \\    --verbose               Enable verbose logging
        \\    --dry-run               Don't write output files
        \\    --json                  Output results as JSON
        \\
        \\EXAMPLES:
        \\    pyjamaz image.jpg
        \\    pyjamaz --max-kb 100 --formats avif,webp *.jpg
        \\    pyjamaz --out ./optimized --resize 1920x1080 images/
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
    try testing.expect(!config.verbose);
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
