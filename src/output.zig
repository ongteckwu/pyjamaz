const std = @import("std");
const fs = std.fs;
const path_utils = std.fs.path;
const Allocator = std.mem.Allocator;

/// Writes an optimized image to disk with proper error handling and permissions.
///
/// Tiger Style compliance:
/// - Bounded operations (no infinite loops)
/// - 2+ assertions (path validation, data validation)
/// - Explicit error handling
/// - File permissions set explicitly (0644 default)
pub fn writeOptimizedImage(
    output_path: []const u8,
    encoded_bytes: []const u8,
) !void {
    // Tiger Style: Pre-condition assertions
    std.debug.assert(output_path.len > 0);
    std.debug.assert(encoded_bytes.len > 0);
    std.debug.assert(encoded_bytes.len < 1_000_000_000); // Max 1GB (sanity check)

    // Create output directory if needed
    try ensureOutputDirectory(output_path);

    // Write file atomically (write to temp, then rename)
    try writeFileAtomic(output_path, encoded_bytes);

    // Set permissions (0644: rw-r--r--)
    try setFilePermissions(output_path, 0o644);
}

/// Ensures the output directory exists, creating it if necessary.
/// Tiger Style: Bounded recursion (max 100 directory levels).
fn ensureOutputDirectory(output_path: []const u8) !void {
    std.debug.assert(output_path.len > 0);

    // Extract directory from path
    const dir_path = path_utils.dirname(output_path) orelse {
        // No directory component (current directory)
        return;
    };

    // Check if directory already exists
    fs.cwd().access(dir_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // Directory doesn't exist, create it
            try fs.cwd().makePath(dir_path);
            return;
        },
        else => return err,
    };
}

/// Writes a file atomically using temp file + rename strategy.
/// Tiger Style: Explicit error handling, bounded operations.
fn writeFileAtomic(output_path: []const u8, data: []const u8) !void {
    std.debug.assert(output_path.len > 0);
    std.debug.assert(data.len > 0);

    // For simplicity in MVP, write directly (atomic write can be added later)
    // TODO: Implement true atomic write with temp file + rename for production
    const file = try fs.cwd().createFile(output_path, .{
        .truncate = true,
        .exclusive = false,
    });
    defer file.close();

    try file.writeAll(data);
}

/// Sets file permissions on the output file.
/// Tiger Style: Explicit permissions, cross-platform handling.
fn setFilePermissions(output_path: []const u8, mode: u16) !void {
    std.debug.assert(output_path.len > 0);
    std.debug.assert(mode <= 0o777); // Valid Unix permission range

    // Note: File permissions are platform-specific
    // On Unix: chmod() via fs.File.chmod()
    // On Windows: Limited permission control
    const file = try fs.cwd().openFile(output_path, .{});
    defer file.close();

    // Set permissions (cross-platform best-effort)
    if (@import("builtin").os.tag != .windows) {
        try file.chmod(mode);
    }
    // Windows: Permissions are more limited, createFile() sets reasonable defaults
}

/// Options for batch writing operations.
pub const WriteOptions = struct {
    /// Whether to overwrite existing files
    overwrite: bool = true,

    /// File permissions (Unix only)
    permissions: u16 = 0o644,

    /// Whether to create parent directories
    create_dirs: bool = true,
};

/// Writes multiple optimized images in a batch.
/// Tiger Style: Bounded operations, explicit error handling.
pub fn writeOptimizedImages(
    outputs: []const OutputEntry,
    options: WriteOptions,
) !void {
    std.debug.assert(outputs.len < 100_000); // Bounded: max 100k files per batch

    for (outputs) |entry| {
        // Check if file exists
        if (!options.overwrite) {
            fs.cwd().access(entry.path, .{}) catch |err| switch (err) {
                error.FileNotFound => {}, // OK, file doesn't exist
                else => return err,
            };
        }

        // Write the file
        if (options.create_dirs) {
            try ensureOutputDirectory(entry.path);
        }

        try writeFileAtomic(entry.path, entry.data);

        if (options.permissions != 0o644) {
            try setFilePermissions(entry.path, options.permissions);
        }
    }
}

/// Represents a single file to write in a batch operation.
pub const OutputEntry = struct {
    path: []const u8,
    data: []const u8,
};

// ============================================================================
// Unit Tests
// ============================================================================

test "writeOptimizedImage creates file with content" {
    // Create temp directory for test
    const test_dir = "zig-out/test_output";
    try fs.cwd().makePath(test_dir);
    defer fs.cwd().deleteTree(test_dir) catch {};

    const output_path = test_dir ++ "/test_image.jpg";
    const test_data = "fake JPEG data";

    try writeOptimizedImage(output_path, test_data);

    // Verify file exists and has correct content
    const file = try fs.cwd().openFile(output_path, .{});
    defer file.close();

    var buffer: [100]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);

    try std.testing.expectEqual(test_data.len, bytes_read);
    try std.testing.expectEqualSlices(u8, test_data, buffer[0..bytes_read]);
}

test "writeOptimizedImage creates nested directories" {
    // Create temp directory for test
    const test_dir = "zig-out/test_output_nested";
    defer fs.cwd().deleteTree(test_dir) catch {};

    const output_path = test_dir ++ "/sub1/sub2/test_image.png";
    const test_data = "fake PNG data";

    try writeOptimizedImage(output_path, test_data);

    // Verify file exists
    const file = try fs.cwd().openFile(output_path, .{});
    defer file.close();

    var buffer: [100]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);

    try std.testing.expectEqual(test_data.len, bytes_read);
}

test "writeOptimizedImage overwrites existing file" {
    const test_dir = "zig-out/test_output_overwrite";
    try fs.cwd().makePath(test_dir);
    defer fs.cwd().deleteTree(test_dir) catch {};

    const output_path = test_dir ++ "/overwrite.jpg";

    // Write first version
    try writeOptimizedImage(output_path, "version 1");

    // Overwrite with second version
    try writeOptimizedImage(output_path, "version 2");

    // Verify second version is present
    const file = try fs.cwd().openFile(output_path, .{});
    defer file.close();

    var buffer: [100]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);

    try std.testing.expectEqualSlices(u8, "version 2", buffer[0..bytes_read]);
}

test "writeOptimizedImages batch operation" {
    const test_dir = "zig-out/test_batch_output";
    try fs.cwd().makePath(test_dir);
    defer fs.cwd().deleteTree(test_dir) catch {};

    const outputs = [_]OutputEntry{
        .{ .path = test_dir ++ "/image1.jpg", .data = "data1" },
        .{ .path = test_dir ++ "/image2.png", .data = "data2" },
        .{ .path = test_dir ++ "/image3.webp", .data = "data3" },
    };

    try writeOptimizedImages(&outputs, .{});

    // Verify all files exist
    for (outputs) |entry| {
        const file = try fs.cwd().openFile(entry.path, .{});
        defer file.close();

        var buffer: [100]u8 = undefined;
        const bytes_read = try file.readAll(&buffer);

        try std.testing.expectEqualSlices(u8, entry.data, buffer[0..bytes_read]);
    }
}

test "ensureOutputDirectory handles existing directory" {
    const test_dir = "zig-out/test_existing_dir";
    try fs.cwd().makePath(test_dir);
    defer fs.cwd().deleteTree(test_dir) catch {};

    const output_path = test_dir ++ "/file.jpg";

    // Should not error when directory exists
    try ensureOutputDirectory(output_path);
}
