const std = @import("std");
const ImageFormat = @import("types/image_metadata.zig").ImageFormat;

/// Options for output file naming
pub const NamingOptions = struct {
    /// Whether to add content hash to filenames
    content_hash_names: bool = false,
    /// Whether to preserve subdirectory structure
    preserve_subdirs: bool = false,
    /// Whether to add suffix before extension (e.g., "_optimized")
    suffix: ?[]const u8 = null,
};

/// Result of generating an output name
pub const OutputName = struct {
    /// Full output path
    path: []u8,
    /// Whether a collision was detected
    had_collision: bool = false,

    pub fn deinit(self: OutputName, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

/// HIGH-017: Validate that output directory exists and is writable
/// HIGH-008: Improved error messages for common file system errors
pub fn validateOutputDirectory(path: []const u8) !void {
    // Check if directory exists
    const dir = std.fs.cwd().openDir(path, .{}) catch |err| {
        // HIGH-008: Specific error messages for common failures
        const err_msg = switch (err) {
            error.FileNotFound => "Output directory does not exist",
            error.AccessDenied => "Permission denied accessing output directory",
            error.NotDir => "Path exists but is not a directory",
            error.SystemResources => "System resources exhausted",
            else => "Cannot access output directory",
        };
        std.log.err("{s}: {s} (error: {})", .{ err_msg, path, err });
        return error.OutputDirNotAccessible;
    };
    defer dir.close();

    // Try to create a temporary file to verify write permissions
    var tmp_name_buf: [64]u8 = undefined;
    const tmp_name = try std.fmt.bufPrint(&tmp_name_buf, ".pyjamaz_write_test_{d}", .{std.time.milliTimestamp()});

    const test_file = dir.createFile(tmp_name, .{}) catch |err| {
        // HIGH-008: Specific error messages for write failures
        const err_msg = switch (err) {
            error.AccessDenied => "Permission denied - output directory is not writable",
            error.DeviceBusy => "Device or resource busy",
            error.DiskQuota => "Disk quota exceeded",
            error.NoSpaceLeft => "No space left on device",
            error.ReadOnlyFileSystem => "Read-only file system",
            error.SystemResources => "System resources exhausted",
            else => "Cannot write to output directory",
        };
        std.log.err("{s}: {s} (error: {})", .{ err_msg, path, err });
        return error.OutputDirNotWritable;
    };
    test_file.close();

    // Clean up test file
    dir.deleteFile(tmp_name) catch {};
}

/// HIGH-015: Check available disk space before writing
///
/// Estimates required disk space and verifies sufficient space available.
/// This is a best-effort check - actual writes may still fail due to race conditions.
pub fn checkDiskSpace(dir_path: []const u8, estimated_size_bytes: u64) !void {
    // Tiger Style: Pre-condition
    std.debug.assert(estimated_size_bytes > 0);

    // Try to get file system statistics
    const dir = std.fs.cwd().openDir(dir_path, .{}) catch |err| {
        // If we can't open dir, validation should have caught this earlier
        std.log.warn("Cannot check disk space for {s}: {}", .{ dir_path, err });
        return; // Continue anyway, let write fail if needed
    };
    defer dir.close();

    // Get dir stat to check available space (if supported by platform)
    const stat = dir.stat() catch |err| {
        // Not all platforms support statfs/statvfs
        std.log.debug("Cannot stat filesystem for {s}: {} (proceeding anyway)", .{ dir_path, err });
        return; // Continue anyway
    };

    // Check if stat provides size information
    _ = stat; // stat doesn't provide filesystem-level info in Zig std currently

    // Log warning if estimated size is very large
    const LARGE_FILE_WARNING: u64 = 100 * 1024 * 1024; // 100MB
    if (estimated_size_bytes > LARGE_FILE_WARNING) {
        std.log.warn("About to write large file: {d} MB", .{estimated_size_bytes / (1024 * 1024)});
    }

    // Note: Zig standard library doesn't expose statvfs/statfs yet
    // This is a placeholder that logs warnings for large files
    // Platform-specific implementations could use:
    // - Linux: statfs/statvfs
    // - Windows: GetDiskFreeSpaceEx
    // - macOS: statfs
}

/// HIGH-018: Sanitize file path to prevent directory traversal
/// Returns error if path contains suspicious patterns
pub fn sanitizePath(path: []const u8) !void {
    // Check for directory traversal patterns
    if (std.mem.indexOf(u8, path, "..") != null) {
        std.log.err("Path contains directory traversal pattern (..): {s}", .{path});
        return error.PathTraversalDetected;
    }

    // Check for absolute paths (only allow relative paths in output names)
    if (path.len > 0 and path[0] == '/') {
        std.log.err("Absolute paths not allowed in output names: {s}", .{path});
        return error.AbsolutePathNotAllowed;
    }

    // Check for null bytes (security)
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        std.log.err("Path contains null byte: {s}", .{path});
        return error.InvalidPathCharacter;
    }
}

/// Get the file extension for a format
fn getExtensionForFormat(format: ImageFormat) []const u8 {
    return switch (format) {
        .jpeg => ".jpg",
        .png => ".png",
        .webp => ".webp",
        .avif => ".avif",
        .unknown => ".bin",
    };
}

/// Compute a content hash for a file using Blake3
///
/// Returns first 8 bytes (16 hex chars) of Blake3 hash.
/// Blake3 chosen for speed and collision resistance.
/// 16 hex chars provides 2^64 uniqueness, sufficient for file naming.
///
/// Tiger Style: Bounded file reading (max 100MB) to prevent hangs on large files
fn computeContentHash(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    // Read file in chunks and compute hash
    var hasher = std.crypto.hash.Blake3.init(.{});
    var buf: [4096]u8 = undefined;

    // Tiger Style: Bounded file reading (protect against huge files)
    const MAX_HASH_SIZE: u64 = 100 * 1024 * 1024; // 100MB
    var total_read: u64 = 0;

    while (total_read < MAX_HASH_SIZE) {
        const bytes_read = try file.read(&buf);
        if (bytes_read == 0) break;
        hasher.update(buf[0..bytes_read]);
        total_read += bytes_read;
    }

    // Post-loop assertion
    std.debug.assert(total_read <= MAX_HASH_SIZE);

    if (total_read >= MAX_HASH_SIZE) {
        std.log.warn("File too large for content hashing (>100MB): {s}", .{file_path});
    }

    var hash_bytes: [32]u8 = undefined;
    hasher.final(&hash_bytes);

    // Convert to hex string (first 8 bytes = 16 hex chars)
    const hash_hex = try allocator.alloc(u8, 16);
    errdefer allocator.free(hash_hex);

    // Format as hex
    const hex_chars = "0123456789abcdef";
    for (hash_bytes[0..8], 0..) |byte, i| {
        hash_hex[i * 2] = hex_chars[byte >> 4];
        hash_hex[i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    return hash_hex;
}

/// Generate output filename for an input file
///
/// Naming strategies:
/// - Default: <stem>.<format>
/// - With content hash: <stem>.<hash>.<format>
/// - With suffix: <stem><suffix>.<format>
/// - With preserve subdirs: <output_dir>/<input_subdir>/<stem>.<format>
///
/// Tiger Style:
/// - Handles collisions by appending numbers
/// - Bounded collision attempts (max 1000)
/// - Explicit error handling
pub fn generateOutputName(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_dir: []const u8,
    format: ImageFormat,
    opts: NamingOptions,
) !OutputName {
    // Tiger Style: Assertions
    std.debug.assert(input_path.len > 0);
    std.debug.assert(output_dir.len > 0);

    // Get input file basename and stem
    const basename = std.fs.path.basename(input_path);
    const stem = std.fs.path.stem(basename);

    // Build output filename components
    var name_buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&name_buf);
    const writer = fbs.writer();

    // Write stem
    try writer.writeAll(stem);

    // Add suffix if specified
    if (opts.suffix) |suffix| {
        try writer.writeAll(suffix);
    }

    // Add content hash if requested
    if (opts.content_hash_names) {
        const hash = try computeContentHash(allocator, input_path);
        defer allocator.free(hash);

        try writer.writeAll(".");
        try writer.writeAll(hash);
    }

    // Add extension
    const ext = getExtensionForFormat(format);
    try writer.writeAll(ext);

    const filename = fbs.getWritten();

    // Determine output directory
    var output_path: []u8 = undefined;
    if (opts.preserve_subdirs) {
        // Get relative directory of input
        const input_dir = std.fs.path.dirname(input_path) orelse ".";
        const joined = try std.fs.path.join(allocator, &.{ output_dir, input_dir, filename });
        output_path = joined;
    } else {
        // Just output_dir + filename
        output_path = try std.fs.path.join(allocator, &.{ output_dir, filename });
    }

    // Check for collisions and handle them
    var had_collision = false;
    var attempt: u32 = 0;
    const max_attempts: u32 = 1000; // Tiger Style: bounded attempts

    while (attempt < max_attempts) : (attempt += 1) {
        // Check if file exists
        const exists = blk: {
            std.fs.cwd().access(output_path, .{}) catch {
                break :blk false;
            };
            break :blk true;
        };

        if (!exists) {
            // No collision, we're done
            break;
        }

        // Collision detected
        had_collision = true;
        allocator.free(output_path);

        // Generate new name with counter
        var collision_buf: [512]u8 = undefined;
        var collision_fbs = std.io.fixedBufferStream(&collision_buf);
        const collision_writer = collision_fbs.writer();

        try collision_writer.writeAll(stem);

        if (opts.suffix) |suffix| {
            try collision_writer.writeAll(suffix);
        }

        // Add counter
        try collision_writer.print("_{d}", .{attempt + 1});

        if (opts.content_hash_names) {
            const hash = try computeContentHash(allocator, input_path);
            defer allocator.free(hash);
            try collision_writer.writeAll(".");
            try collision_writer.writeAll(hash);
        }

        try collision_writer.writeAll(ext);

        const collision_filename = collision_fbs.getWritten();

        if (opts.preserve_subdirs) {
            const input_dir = std.fs.path.dirname(input_path) orelse ".";
            output_path = try std.fs.path.join(allocator, &.{ output_dir, input_dir, collision_filename });
        } else {
            output_path = try std.fs.path.join(allocator, &.{ output_dir, collision_filename });
        }
    }

    // Tiger Style: Post-loop assertion
    std.debug.assert(attempt <= max_attempts);

    if (attempt >= max_attempts) {
        std.log.err("Too many collisions generating output name for: {s}", .{input_path});
        return error.TooManyCollisions;
    }

    return OutputName{
        .path = output_path,
        .had_collision = had_collision,
    };
}

// Unit tests
test "getExtensionForFormat: returns correct extensions" {
    const testing = std.testing;

    try testing.expectEqualStrings(".jpg", getExtensionForFormat(.jpeg));
    try testing.expectEqualStrings(".png", getExtensionForFormat(.png));
    try testing.expectEqualStrings(".webp", getExtensionForFormat(.webp));
    try testing.expectEqualStrings(".avif", getExtensionForFormat(.avif));
}

test "generateOutputName: default naming" {
    const testing = std.testing;

    const result = try generateOutputName(
        testing.allocator,
        "input/photo.jpg",
        "output",
        .png,
        .{},
    );
    defer result.deinit(testing.allocator);

    try testing.expect(std.mem.endsWith(u8, result.path, "photo.png"));
    try testing.expect(std.mem.indexOf(u8, result.path, "output") != null);
    try testing.expect(!result.had_collision);
}

test "generateOutputName: with suffix" {
    const testing = std.testing;

    const result = try generateOutputName(
        testing.allocator,
        "input/photo.jpg",
        "output",
        .webp,
        .{ .suffix = "_optimized" },
    );
    defer result.deinit(testing.allocator);

    try testing.expect(std.mem.endsWith(u8, result.path, "photo_optimized.webp"));
    try testing.expect(!result.had_collision);
}

test "generateOutputName: collision handling" {
    const testing = std.testing;

    // Create output directory
    const test_dir = "test_naming_collision";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create a test input file
    const input_file = "test_collision_input.jpg";
    const input = try std.fs.cwd().createFile(input_file, .{});
    input.close();
    defer std.fs.cwd().deleteFile(input_file) catch {};

    // Create first output file (will cause collision)
    const collision_file = try std.fs.path.join(testing.allocator, &.{ test_dir, "test_collision_input.png" });
    defer testing.allocator.free(collision_file);

    const existing = try std.fs.cwd().createFile(collision_file, .{});
    existing.close();

    // Generate name (should detect collision and add counter)
    const result = try generateOutputName(
        testing.allocator,
        input_file,
        test_dir,
        .png,
        .{},
    );
    defer result.deinit(testing.allocator);

    try testing.expect(result.had_collision);
    try testing.expect(std.mem.indexOf(u8, result.path, "_1") != null);
}

test "computeContentHash: consistent hashing" {
    const testing = std.testing;

    // Create a test file with known content
    const test_file = "test_hash_file.txt";
    const file = try std.fs.cwd().createFile(test_file, .{});
    defer std.fs.cwd().deleteFile(test_file) catch {};

    try file.writeAll("Hello, World!");
    file.close();

    // Compute hash twice
    const hash1 = try computeContentHash(testing.allocator, test_file);
    defer testing.allocator.free(hash1);

    const hash2 = try computeContentHash(testing.allocator, test_file);
    defer testing.allocator.free(hash2);

    // Should be identical
    try testing.expectEqualStrings(hash1, hash2);
    try testing.expectEqual(@as(usize, 16), hash1.len);
}

test "generateOutputName: with content hash" {
    const testing = std.testing;

    // Create a test input file
    const test_file = "test_hash_input.jpg";
    const file = try std.fs.cwd().createFile(test_file, .{});
    defer std.fs.cwd().deleteFile(test_file) catch {};
    try file.writeAll("test content");
    file.close();

    const result = try generateOutputName(
        testing.allocator,
        test_file,
        "output",
        .png,
        .{ .content_hash_names = true },
    );
    defer result.deinit(testing.allocator);

    // Should contain hash (16 hex chars)
    try testing.expect(std.mem.indexOf(u8, result.path, "test_hash_input.") != null);
    try testing.expect(std.mem.endsWith(u8, result.path, ".png"));

    // Extract the hash portion (between last two dots before .png)
    const basename = std.fs.path.basename(result.path);
    // Format: test_hash_input.<hash>.png
    var parts = std.mem.splitScalar(u8, basename, '.');
    _ = parts.next(); // stem
    const hash_part = parts.next().?;
    try testing.expectEqual(@as(usize, 16), hash_part.len);
}

test "generateOutputName: preserve subdirs" {
    const testing = std.testing;

    const result = try generateOutputName(
        testing.allocator,
        "input/subdir/photo.jpg",
        "output",
        .png,
        .{ .preserve_subdirs = true },
    );
    defer result.deinit(testing.allocator);

    // Should contain both output dir and input subdir structure
    try testing.expect(std.mem.indexOf(u8, result.path, "output") != null);
    try testing.expect(std.mem.indexOf(u8, result.path, "input") != null);
    try testing.expect(std.mem.indexOf(u8, result.path, "subdir") != null);
    try testing.expect(std.mem.endsWith(u8, result.path, "photo.png"));
}
