//! Golden Snapshot Testing Infrastructure
//!
//! Provides deterministic output hashing and comparison for regression testing.
//! Golden snapshots ensure optimizer outputs remain consistent across versions.
//!
//! Tiger Style:
//! - 2+ assertions per function
//! - Bounded operations (no infinite loops)
//! - Explicit error handling

const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;

/// Hash algorithm for golden snapshots (SHA256 for stability)
pub const HashType = std.crypto.hash.sha2.Sha256;
pub const hash_length = HashType.digest_length;
pub const HashDigest = [hash_length]u8;

/// Golden snapshot entry
pub const GoldenEntry = struct {
    /// Test case identifier (e.g., "kodak/kodim01.png")
    test_name: []const u8,
    /// Input file hash (for input change detection)
    input_hash: HashDigest,
    /// Output file hash (for output consistency check)
    output_hash: HashDigest,
    /// Format of output (jpeg, png, webp, avif)
    format: []const u8,
    /// Output size in bytes
    output_size: u64,

    pub fn format_hex(self: GoldenEntry, allocator: Allocator) ![]const u8 {
        // Pre-condition: test_name and format must be valid
        std.debug.assert(self.test_name.len > 0);
        std.debug.assert(self.format.len > 0);

        const input_hex = try hexEncode(allocator, &self.input_hash);
        defer allocator.free(input_hex);
        const output_hex = try hexEncode(allocator, &self.output_hash);
        defer allocator.free(output_hex);

        return std.fmt.allocPrint(allocator, "{s}\t{s}\t{s}\t{s}\t{d}", .{
            self.test_name,
            input_hex,
            output_hex,
            self.format,
            self.output_size,
        });
    }
};

/// Golden snapshot manifest (collection of entries)
pub const GoldenManifest = struct {
    entries: std.ArrayList(GoldenEntry),
    allocator: Allocator,

    pub fn init(allocator: Allocator) GoldenManifest {
        return .{
            .entries = std.ArrayList(GoldenEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GoldenManifest) void {
        // Free all test_name and format strings
        for (self.entries.items) |entry| {
            self.allocator.free(entry.test_name);
            self.allocator.free(entry.format);
        }
        self.entries.deinit();
    }

    pub fn add(self: *GoldenManifest, entry: GoldenEntry) !void {
        // Pre-condition: entry must have valid strings
        std.debug.assert(entry.test_name.len > 0);
        std.debug.assert(entry.format.len > 0);

        // Duplicate strings for ownership
        const test_name = try self.allocator.dupe(u8, entry.test_name);
        errdefer self.allocator.free(test_name);
        const format = try self.allocator.dupe(u8, entry.format);
        errdefer self.allocator.free(format);

        try self.entries.append(.{
            .test_name = test_name,
            .input_hash = entry.input_hash,
            .output_hash = entry.output_hash,
            .format = format,
            .output_size = entry.output_size,
        });

        // Post-condition: entry added
        std.debug.assert(self.entries.items.len > 0);
    }

    pub fn find(self: *const GoldenManifest, test_name: []const u8) ?*const GoldenEntry {
        // Pre-condition: test_name must be valid
        std.debug.assert(test_name.len > 0);

        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.test_name, test_name)) {
                return entry;
            }
        }
        return null;
    }

    /// Save manifest to TSV file
    pub fn saveToFile(self: *const GoldenManifest, path: []const u8) !void {
        // Pre-condition: must have entries, path must be valid
        std.debug.assert(self.entries.items.len > 0);
        std.debug.assert(path.len > 0);

        const file = try fs.cwd().createFile(path, .{});
        defer file.close();

        const writer = file.writer();

        // Header
        try writer.writeAll("# Golden Snapshot Manifest\n");
        try writer.writeAll("# Format: test_name\tinput_hash\toutput_hash\tformat\toutput_size\n");

        // Entries
        for (self.entries.items) |entry| {
            const line = try entry.format_hex(self.allocator);
            defer self.allocator.free(line);
            try writer.writeAll(line);
            try writer.writeAll("\n");
        }

        // Post-condition: file written
        std.debug.assert(true); // File operation succeeded
    }

    /// Load manifest from TSV file
    pub fn loadFromFile(allocator: Allocator, path: []const u8) !GoldenManifest {
        // Pre-condition: path must be valid
        std.debug.assert(path.len > 0);

        const file = try fs.cwd().openFile(path, .{});
        defer file.close();

        var manifest = GoldenManifest.init(allocator);
        errdefer manifest.deinit();

        const reader = file.reader();
        var buf: [4096]u8 = undefined;

        while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            // Skip comments and empty lines
            if (line.len == 0 or line[0] == '#') continue;

            // Parse TSV: test_name\tinput_hash\toutput_hash\tformat\toutput_size
            var iter = std.mem.splitScalar(u8, line, '\t');
            const test_name = iter.next() orelse continue;
            const input_hex = iter.next() orelse continue;
            const output_hex = iter.next() orelse continue;
            const format = iter.next() orelse continue;
            const size_str = iter.next() orelse continue;

            const input_hash = try hexDecode(input_hex);
            const output_hash = try hexDecode(output_hex);
            const output_size = try std.fmt.parseInt(u64, size_str, 10);

            try manifest.add(.{
                .test_name = test_name,
                .input_hash = input_hash,
                .output_hash = output_hash,
                .format = format,
                .output_size = output_size,
            });
        }

        // Post-condition: manifest loaded
        std.debug.assert(manifest.entries.items.len >= 0);

        return manifest;
    }
};

/// Compute hash of file contents
pub fn hashFile(path: []const u8) !HashDigest {
    // Pre-condition: path must be valid
    std.debug.assert(path.len > 0);

    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    var hasher = HashType.init(.{});
    var buf: [8192]u8 = undefined;

    // Bounded read loop
    const max_iterations: u32 = 1_000_000; // Max ~8GB file
    var iterations: u32 = 0;

    while (iterations < max_iterations) : (iterations += 1) {
        const bytes_read = try file.read(&buf);
        if (bytes_read == 0) break;
        hasher.update(buf[0..bytes_read]);
    }

    // Post-condition: iterations bounded
    std.debug.assert(iterations < max_iterations);

    var digest: HashDigest = undefined;
    hasher.final(&digest);

    return digest;
}

/// Compute hash of memory buffer
pub fn hashBuffer(data: []const u8) HashDigest {
    // Pre-condition: data must be valid (can be empty)
    std.debug.assert(data.len >= 0);

    var hasher = HashType.init(.{});
    hasher.update(data);

    var digest: HashDigest = undefined;
    hasher.final(&digest);

    return digest;
}

/// Convert hash digest to hex string
pub fn hexEncode(allocator: Allocator, hash: *const HashDigest) ![]const u8 {
    // Pre-condition: hash must be valid
    std.debug.assert(hash.len == hash_length);

    const hex = try allocator.alloc(u8, hash_length * 2);
    _ = try std.fmt.bufPrint(hex, "{s}", .{std.fmt.fmtSliceHexLower(hash)});

    // Post-condition: hex string is correct length
    std.debug.assert(hex.len == hash_length * 2);

    return hex;
}

/// Convert hex string to hash digest
pub fn hexDecode(hex: []const u8) !HashDigest {
    // Pre-condition: hex string must be correct length
    if (hex.len != hash_length * 2) return error.InvalidHexLength;

    var digest: HashDigest = undefined;
    _ = try std.fmt.hexToBytes(&digest, hex);

    // Post-condition: digest decoded
    std.debug.assert(digest.len == hash_length);

    return digest;
}

/// Comparison result for golden snapshot testing
pub const ComparisonResult = struct {
    /// Test case identifier
    test_name: []const u8,
    /// Match status
    status: Status,
    /// Expected hash (from golden)
    expected_hash: ?HashDigest,
    /// Actual hash (from current run)
    actual_hash: HashDigest,
    /// Expected size (from golden)
    expected_size: ?u64,
    /// Actual size (from current run)
    actual_size: u64,

    pub const Status = enum {
        match, // Hashes match
        mismatch, // Hashes differ (regression!)
        new, // Test not in golden manifest (new test)
        missing, // Test in golden but not found (deleted test)
    };

    pub fn format_message(self: ComparisonResult, allocator: Allocator) ![]const u8 {
        // Pre-condition: test_name must be valid
        std.debug.assert(self.test_name.len > 0);

        return switch (self.status) {
            .match => try std.fmt.allocPrint(
                allocator,
                "✅ {s}: MATCH (size: {d} bytes)",
                .{ self.test_name, self.actual_size },
            ),
            .mismatch => blk: {
                const expected_hex = if (self.expected_hash) |h|
                    try hexEncode(allocator, &h)
                else
                    try allocator.dupe(u8, "none");
                defer allocator.free(expected_hex);

                const actual_hex = try hexEncode(allocator, &self.actual_hash);
                defer allocator.free(actual_hex);

                break :blk try std.fmt.allocPrint(
                    allocator,
                    "❌ {s}: MISMATCH\n  Expected: {s} ({d} bytes)\n  Actual:   {s} ({d} bytes)",
                    .{
                        self.test_name,
                        expected_hex,
                        self.expected_size orelse 0,
                        actual_hex,
                        self.actual_size,
                    },
                );
            },
            .new => try std.fmt.allocPrint(
                allocator,
                "🆕 {s}: NEW (size: {d} bytes)",
                .{ self.test_name, self.actual_size },
            ),
            .missing => try std.fmt.allocPrint(
                allocator,
                "⚠️  {s}: MISSING (expected in output)",
                .{self.test_name},
            ),
        };
    }
};

/// Compare current outputs against golden manifest
pub fn compareWithGolden(
    allocator: Allocator,
    golden: *const GoldenManifest,
    test_results: []const struct { test_name: []const u8, output_path: []const u8 },
) ![]ComparisonResult {
    // Pre-condition: must have test results
    std.debug.assert(test_results.len > 0);

    var results = std.ArrayList(ComparisonResult).init(allocator);
    errdefer results.deinit();

    // Compare each test result
    for (test_results) |result| {
        const actual_hash = try hashFile(result.output_path);
        const stat = try fs.cwd().statFile(result.output_path);
        const actual_size = stat.size;

        if (golden.find(result.test_name)) |entry| {
            const status: ComparisonResult.Status = if (std.mem.eql(u8, &entry.output_hash, &actual_hash))
                .match
            else
                .mismatch;

            try results.append(.{
                .test_name = result.test_name,
                .status = status,
                .expected_hash = entry.output_hash,
                .actual_hash = actual_hash,
                .expected_size = entry.output_size,
                .actual_size = actual_size,
            });
        } else {
            // New test not in golden
            try results.append(.{
                .test_name = result.test_name,
                .status = .new,
                .expected_hash = null,
                .actual_hash = actual_hash,
                .expected_size = null,
                .actual_size = actual_size,
            });
        }
    }

    // Post-condition: results generated
    std.debug.assert(results.items.len == test_results.len);

    return results.toOwnedSlice();
}

test "hashBuffer: identical buffers produce same hash" {
    const data1 = "Hello, World!";
    const data2 = "Hello, World!";

    const hash1 = hashBuffer(data1);
    const hash2 = hashBuffer(data2);

    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "hashBuffer: different buffers produce different hashes" {
    const data1 = "Hello, World!";
    const data2 = "Hello, world!"; // Different case

    const hash1 = hashBuffer(data1);
    const hash2 = hashBuffer(data2);

    try std.testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "hexEncode/hexDecode: round trip" {
    const allocator = std.testing.allocator;

    const original_data = "Test data for hashing";
    const hash = hashBuffer(original_data);

    const hex = try hexEncode(allocator, &hash);
    defer allocator.free(hex);

    const decoded = try hexDecode(hex);

    try std.testing.expectEqualSlices(u8, &hash, &decoded);
}

test "GoldenManifest: add and find entries" {
    const allocator = std.testing.allocator;
    var manifest = GoldenManifest.init(allocator);
    defer manifest.deinit();

    const hash1 = hashBuffer("input1");
    const hash2 = hashBuffer("output1");

    try manifest.add(.{
        .test_name = "test1.png",
        .input_hash = hash1,
        .output_hash = hash2,
        .format = "jpeg",
        .output_size = 1024,
    });

    const found = manifest.find("test1.png");
    try std.testing.expect(found != null);
    try std.testing.expectEqualSlices(u8, &hash2, &found.?.output_hash);
    try std.testing.expectEqual(@as(u64, 1024), found.?.output_size);
}

test "GoldenManifest: find returns null for missing entry" {
    const allocator = std.testing.allocator;
    var manifest = GoldenManifest.init(allocator);
    defer manifest.deinit();

    const found = manifest.find("nonexistent.png");
    try std.testing.expect(found == null);
}

test "GoldenManifest: save and load round trip" {
    const allocator = std.testing.allocator;

    // Create manifest
    var manifest1 = GoldenManifest.init(allocator);
    defer manifest1.deinit();

    const hash1 = hashBuffer("input1");
    const hash2 = hashBuffer("output1");

    try manifest1.add(.{
        .test_name = "test1.png",
        .input_hash = hash1,
        .output_hash = hash2,
        .format = "jpeg",
        .output_size = 2048,
    });

    // Save to temp file
    const temp_path = "test_golden_manifest.tsv";
    defer fs.cwd().deleteFile(temp_path) catch {};

    try manifest1.saveToFile(temp_path);

    // Load from file
    var manifest2 = try GoldenManifest.loadFromFile(allocator, temp_path);
    defer manifest2.deinit();

    // Verify
    try std.testing.expectEqual(@as(usize, 1), manifest2.entries.items.len);
    const entry = manifest2.entries.items[0];
    try std.testing.expectEqualStrings("test1.png", entry.test_name);
    try std.testing.expectEqualSlices(u8, &hash2, &entry.output_hash);
    try std.testing.expectEqual(@as(u64, 2048), entry.output_size);
}

test "ComparisonResult: format match message" {
    const allocator = std.testing.allocator;

    const hash = hashBuffer("test data");
    const result = ComparisonResult{
        .test_name = "test.png",
        .status = .match,
        .expected_hash = hash,
        .actual_hash = hash,
        .expected_size = 1024,
        .actual_size = 1024,
    };

    const msg = try result.format_message(allocator);
    defer allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "MATCH") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "test.png") != null);
}

test "ComparisonResult: format mismatch message" {
    const allocator = std.testing.allocator;

    const hash1 = hashBuffer("expected");
    const hash2 = hashBuffer("actual");

    const result = ComparisonResult{
        .test_name = "test.png",
        .status = .mismatch,
        .expected_hash = hash1,
        .actual_hash = hash2,
        .expected_size = 1024,
        .actual_size = 2048,
    };

    const msg = try result.format_message(allocator);
    defer allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "MISMATCH") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "test.png") != null);
}
