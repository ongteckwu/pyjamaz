const std = @import("std");

/// Options for input discovery
pub const DiscoveryOptions = struct {
    /// Whether to follow symlinks (default: false for security)
    allow_symlinks: bool = false,
    /// Maximum recursion depth (Tiger Style: explicit bound)
    max_depth: u32 = 100,
    /// Whether to include hidden files (starting with .)
    include_hidden: bool = false,
};

/// Supported image file extensions
const IMAGE_EXTENSIONS = [_][]const u8{
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".avif",
    ".JPG",
    ".JPEG",
    ".PNG",
    ".WEBP",
    ".AVIF",
};

/// Check if a file extension is a supported image format
fn isSupportedExtension(ext: []const u8) bool {
    for (IMAGE_EXTENSIONS) |supported| {
        if (std.mem.eql(u8, ext, supported)) {
            return true;
        }
    }
    return false;
}

/// Check if a filename should be excluded (hidden files, etc.)
fn shouldExcludeFile(name: []const u8, opts: DiscoveryOptions) bool {
    if (name.len == 0) return true;

    // Exclude hidden files unless explicitly allowed
    if (!opts.include_hidden and name[0] == '.') {
        return true;
    }

    return false;
}

/// Recursively discover image files in a directory
///
/// Tiger Style: Bounded recursion with explicit depth assertions
/// HIGH-005: Track visited inodes to detect symlink cycles
fn discoverInDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    results: *std.ArrayList([]u8),
    opts: DiscoveryOptions,
    current_depth: u32,
    visited_inodes: *std.AutoHashMap(u64, void),
) !void {
    // Tiger Style: Assert we haven't exceeded depth
    std.debug.assert(current_depth <= opts.max_depth);

    // Tiger Style: Bounded recursion
    if (current_depth >= opts.max_depth) {
        std.log.warn("Maximum recursion depth ({d}) reached at: {s}", .{ opts.max_depth, dir_path });
        return;
    }

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        std.log.warn("Failed to open directory {s}: {}", .{ dir_path, err });
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Skip excluded files
        if (shouldExcludeFile(entry.name, opts)) {
            continue;
        }

        // Construct full path
        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(full_path);

        switch (entry.kind) {
            .file => {
                // Check if it's an image file
                const ext = std.fs.path.extension(entry.name);
                if (isSupportedExtension(ext)) {
                    // Add to results (owned copy)
                    const owned_path = try allocator.dupe(u8, full_path);
                    try results.append(owned_path);
                }
            },
            .directory => {
                // Recurse into subdirectory
                const next_depth = current_depth + 1;
                std.debug.assert(next_depth <= opts.max_depth);
                try discoverInDirectory(allocator, full_path, results, opts, next_depth, visited_inodes);
            },
            .sym_link => {
                if (opts.allow_symlinks) {
                    // Resolve symlink and check if it's a file or directory
                    const stat = std.fs.cwd().statFile(full_path) catch {
                        std.log.warn("Failed to stat symlink: {s}", .{full_path});
                        continue;
                    };

                    // HIGH-005: Check for symlink cycles using inode tracking
                    if (stat.kind == .directory) {
                        const inode = stat.inode;
                        const gop = try visited_inodes.getOrPut(inode);

                        if (gop.found_existing) {
                            std.log.warn("Symlink cycle detected at: {s} (inode {d})", .{ full_path, inode });
                            continue;
                        }

                        const next_depth = current_depth + 1;
                        std.debug.assert(next_depth <= opts.max_depth);
                        try discoverInDirectory(allocator, full_path, results, opts, next_depth, visited_inodes);
                    } else if (stat.kind == .file) {
                        const ext = std.fs.path.extension(entry.name);
                        if (isSupportedExtension(ext)) {
                            const owned_path = try allocator.dupe(u8, full_path);
                            try results.append(owned_path);
                        }
                    }
                } else {
                    std.log.debug("Skipping symlink (not allowed): {s}", .{full_path});
                }
            },
            else => {
                // Ignore other file types (pipes, sockets, etc.)
            },
        }
    }

    // Tiger Style: Post-condition - verify we didn't somehow exceed depth
    std.debug.assert(current_depth <= opts.max_depth);
}

/// Discover image files from one or more input paths
///
/// Input paths can be:
/// - Individual image files
/// - Directories (recursively scanned)
///
/// Returns an ArrayList of owned paths. Caller must free each path and the ArrayList.
///
/// Tiger Style:
/// - Bounded recursion depth
/// - Explicit error handling
/// - No infinite loops (directory iteration is bounded)
pub fn discoverInputs(
    allocator: std.mem.Allocator,
    paths: []const []const u8,
    opts: DiscoveryOptions,
) !std.ArrayList([]u8) {
    // Tiger Style: Assertions
    std.debug.assert(paths.len > 0);

    var results = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (results.items) |path| {
            allocator.free(path);
        }
        results.deinit();
    }

    // HIGH-005: Track visited inodes to detect symlink cycles
    var visited_inodes = std.AutoHashMap(u64, void).init(allocator);
    defer visited_inodes.deinit();

    for (paths) |path| {
        const stat = std.fs.cwd().statFile(path) catch |err| {
            std.log.warn("Failed to stat path {s}: {}", .{ path, err });
            continue;
        };

        switch (stat.kind) {
            .file => {
                // Check if it's an image file
                const ext = std.fs.path.extension(path);
                if (isSupportedExtension(ext)) {
                    const owned_path = try allocator.dupe(u8, path);
                    try results.append(owned_path);
                } else {
                    std.log.warn("Skipping non-image file: {s}", .{path});
                }
            },
            .directory => {
                // Recursively discover in directory
                try discoverInDirectory(allocator, path, &results, opts, 0, &visited_inodes);
            },
            else => {
                std.log.warn("Skipping non-file/non-directory: {s}", .{path});
            },
        }
    }

    // Tiger Style: Post-condition
    std.debug.assert(results.items.len >= 0);

    return results;
}

/// Deduplicate paths by comparing absolute paths
///
/// Tiger Style: Explicit error handling, bounded operations
pub fn deduplicatePaths(allocator: std.mem.Allocator, paths: *std.ArrayList([]u8)) !void {
    if (paths.items.len <= 1) return;

    // Use a hash map to track seen paths
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var write_idx: usize = 0;
    for (paths.items, 0..) |path, read_idx| {
        // Normalize path (resolve relative paths)
        // Tiger Style: Explicit error handling with fallback
        const abs_path = std.fs.cwd().realpathAlloc(allocator, path) catch |err| {
            std.log.warn("Failed to resolve path '{s}': {} - using as-is", .{ path, err });
            path // Fallback to original path
        };
        const is_different_path = abs_path.ptr != path.ptr;
        defer if (is_different_path) allocator.free(abs_path);

        const gop = try seen.getOrPut(abs_path);
        if (!gop.found_existing) {
            // Keep this path
            if (write_idx != read_idx) {
                paths.items[write_idx] = paths.items[read_idx];
            }
            write_idx += 1;

            // Invariant: write_idx <= read_idx + 1
            std.debug.assert(write_idx <= read_idx + 1);
        } else {
            // Duplicate, free it
            allocator.free(path);
        }
    }

    // Truncate to deduplicated size
    paths.shrinkRetainingCapacity(write_idx);

    // Tiger Style: Post-condition
    std.debug.assert(write_idx <= paths.capacity);
}

// Unit tests
test "isSupportedExtension: recognizes image extensions" {
    const testing = std.testing;

    try testing.expect(isSupportedExtension(".jpg"));
    try testing.expect(isSupportedExtension(".jpeg"));
    try testing.expect(isSupportedExtension(".png"));
    try testing.expect(isSupportedExtension(".webp"));
    try testing.expect(isSupportedExtension(".avif"));
    try testing.expect(isSupportedExtension(".JPG"));
    try testing.expect(isSupportedExtension(".JPEG"));

    try testing.expect(!isSupportedExtension(".txt"));
    try testing.expect(!isSupportedExtension(".gif"));
    try testing.expect(!isSupportedExtension(""));
}

test "shouldExcludeFile: excludes hidden files by default" {
    const testing = std.testing;

    const opts_default = DiscoveryOptions{};
    const opts_include_hidden = DiscoveryOptions{ .include_hidden = true };

    try testing.expect(shouldExcludeFile(".hidden", opts_default));
    try testing.expect(!shouldExcludeFile(".hidden", opts_include_hidden));
    try testing.expect(!shouldExcludeFile("visible.jpg", opts_default));
}

test "discoverInputs: single file" {
    const testing = std.testing;

    // Create a temporary test file
    const test_dir = "test_discovery_single";
    std.fs.cwd().makePath(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const test_file = try std.fs.path.join(testing.allocator, &.{ test_dir, "test.jpg" });
    defer testing.allocator.free(test_file);

    // Create the file
    const file = try std.fs.cwd().createFile(test_file, .{});
    file.close();

    // Discover it
    const paths = [_][]const u8{test_file};
    var results = try discoverInputs(testing.allocator, &paths, .{});
    defer {
        for (results.items) |path| {
            testing.allocator.free(path);
        }
        results.deinit();
    }

    try testing.expectEqual(@as(usize, 1), results.items.len);
    try testing.expect(std.mem.endsWith(u8, results.items[0], "test.jpg"));
}

test "discoverInputs: directory" {
    const testing = std.testing;

    // Create a temporary test directory with files
    const test_dir = "test_discovery_dir";
    std.fs.cwd().makePath(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test files
    const files = [_][]const u8{ "test1.jpg", "test2.png", "test3.txt" };
    for (files) |filename| {
        const path = try std.fs.path.join(testing.allocator, &.{ test_dir, filename });
        defer testing.allocator.free(path);

        const file = try std.fs.cwd().createFile(path, .{});
        file.close();
    }

    // Discover images in directory
    const paths = [_][]const u8{test_dir};
    var results = try discoverInputs(testing.allocator, &paths, .{});
    defer {
        for (results.items) |path| {
            testing.allocator.free(path);
        }
        results.deinit();
    }

    // Should find 2 images (jpg and png, but not txt)
    try testing.expectEqual(@as(usize, 2), results.items.len);
}

test "discoverInputs: nested directories" {
    const testing = std.testing;

    // Create nested directory structure
    const test_dir = "test_discovery_nested";
    const sub_dir = try std.fs.path.join(testing.allocator, &.{ test_dir, "subdir" });
    defer testing.allocator.free(sub_dir);

    std.fs.cwd().makePath(sub_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create files at both levels
    const root_file = try std.fs.path.join(testing.allocator, &.{ test_dir, "root.jpg" });
    defer testing.allocator.free(root_file);
    const file1 = try std.fs.cwd().createFile(root_file, .{});
    file1.close();

    const sub_file = try std.fs.path.join(testing.allocator, &.{ sub_dir, "nested.png" });
    defer testing.allocator.free(sub_file);
    const file2 = try std.fs.cwd().createFile(sub_file, .{});
    file2.close();

    // Discover
    const paths = [_][]const u8{test_dir};
    var results = try discoverInputs(testing.allocator, &paths, .{});
    defer {
        for (results.items) |path| {
            testing.allocator.free(path);
        }
        results.deinit();
    }

    // Should find both images
    try testing.expectEqual(@as(usize, 2), results.items.len);
}

test "deduplicatePaths: removes duplicates" {
    const testing = std.testing;

    var paths = std.ArrayList([]u8).init(testing.allocator);
    defer {
        for (paths.items) |path| {
            testing.allocator.free(path);
        }
        paths.deinit();
    }

    // Add some paths (some duplicates)
    try paths.append(try testing.allocator.dupe(u8, "image1.jpg"));
    try paths.append(try testing.allocator.dupe(u8, "image2.png"));
    try paths.append(try testing.allocator.dupe(u8, "image1.jpg")); // duplicate
    try paths.append(try testing.allocator.dupe(u8, "image3.webp"));

    try deduplicatePaths(testing.allocator, &paths);

    // Should have 3 unique paths
    try testing.expectEqual(@as(usize, 3), paths.items.len);
}
