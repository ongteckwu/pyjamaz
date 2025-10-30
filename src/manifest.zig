const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// ManifestEntry represents a single optimization result for one input image.
/// Format matches RFC §10.2 for JSONL manifest output.
///
/// Tiger Style compliance:
/// - Explicit types (no implicit conversions)
/// - Bounded strings (paths, formats)
/// - Clear ownership (slices are borrowed, caller manages memory)
pub const ManifestEntry = struct {
    /// Input file path (relative or absolute)
    input: []const u8,

    /// Output file path
    output: []const u8,

    /// Output file size in bytes
    bytes: u32,

    /// Selected format (avif, webp, jpeg, png)
    format: []const u8,

    /// Perceptual diff metric used (butteraugli, dssim)
    diff_metric: []const u8,

    /// Perceptual diff value (0.0 = identical, higher = more different)
    /// For MVP: stubbed to 0.0 (will be computed in 0.2.0)
    diff_value: f64,

    /// Budget in bytes (from --max-kb or --max-bytes)
    budget_bytes: ?u32,

    /// Maximum allowed perceptual diff (from --max-diff)
    max_diff: ?f64,

    /// Whether this result passed all constraints
    passed: bool,

    /// Alternative candidates considered
    alternates: []const Alternate,

    /// Performance timings breakdown (milliseconds)
    timings_ms: Timings,

    /// Warnings encountered during optimization
    warnings: []const []const u8,

    pub const Alternate = struct {
        format: []const u8,
        bytes: u32,
        diff: f64,
        passed: bool,
        reason: ?[]const u8 = null,
    };

    pub const Timings = struct {
        decode: u32,
        transform: u32,
        encode_total: u32,
        metrics: u32,
    };
};

/// Writes a single manifest entry as a JSONL line.
/// Tiger Style: Explicit error handling, bounded writes.
/// Note: Uses manual JSON serialization for MVP (Zig 0.15 json API compatibility)
pub fn writeManifestLine(
    writer: anytype,
    entry: ManifestEntry,
) !void {
    // Tiger Style: Pre-condition assertions
    std.debug.assert(entry.input.len > 0);
    std.debug.assert(entry.output.len > 0);
    std.debug.assert(entry.format.len > 0);
    std.debug.assert(entry.bytes < 1_000_000_000); // Max 1GB (sanity check)

    // Manual JSON serialization (MVP - will use std.json in future)
    try writer.writeAll("{\"input\":\"");
    try writeJsonString(writer, entry.input);
    try writer.writeAll("\",\"output\":\"");
    try writeJsonString(writer, entry.output);
    try writer.print("\",\"bytes\":{d},\"format\":\"", .{entry.bytes});
    try writeJsonString(writer, entry.format);
    try writer.writeAll("\",\"diff_metric\":\"");
    try writeJsonString(writer, entry.diff_metric);
    try writer.print("\",\"diff_value\":{d:.2}", .{entry.diff_value});

    if (entry.budget_bytes) |budget| {
        try writer.print(",\"budget_bytes\":{d}", .{budget});
    } else {
        try writer.writeAll(",\"budget_bytes\":null");
    }

    if (entry.max_diff) |diff| {
        try writer.print(",\"max_diff\":{d:.2}", .{diff});
    } else {
        try writer.writeAll(",\"max_diff\":null");
    }

    try writer.print(",\"passed\":{}", .{entry.passed});

    // Alternates array
    try writer.writeAll(",\"alternates\":[");
    for (entry.alternates, 0..) |alt, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeAll("{\"format\":\"");
        try writeJsonString(writer, alt.format);
        try writer.print("\",\"bytes\":{d},\"diff\":{d:.2},\"passed\":{}", .{alt.bytes, alt.diff, alt.passed});
        if (alt.reason) |reason| {
            try writer.writeAll(",\"reason\":\"");
            try writeJsonString(writer, reason);
            try writer.writeByte('"');
        }
        try writer.writeByte('}');
    }
    try writer.writeByte(']');

    // Timings
    try writer.print(",\"timings_ms\":{{\"decode\":{d},\"transform\":{d},\"encode_total\":{d},\"metrics\":{d}}}", .{
        entry.timings_ms.decode, entry.timings_ms.transform, entry.timings_ms.encode_total, entry.timings_ms.metrics
    });

    // Warnings array
    try writer.writeAll(",\"warnings\":[");
    for (entry.warnings, 0..) |warning, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeByte('"');
        try writeJsonString(writer, warning);
        try writer.writeByte('"');
    }
    try writer.writeByte(']');

    try writer.writeByte('}');

    // JSONL format: one JSON object per line
    try writer.writeByte('\n');
}

/// Helper to write a JSON-escaped string
fn writeJsonString(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
}

/// Writes multiple manifest entries to a file.
/// Tiger Style: Bounded operations, explicit error handling.
pub fn writeManifest(
    allocator: Allocator,
    path: []const u8,
    entries: []const ManifestEntry,
) !void {
    std.debug.assert(path.len > 0);
    std.debug.assert(entries.len < 100_000); // Bounded: max 100k entries

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    // Write each entry as a JSONL line
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    for (entries) |entry| {
        buffer.clearRetainingCapacity();
        try writeManifestLine(buffer.writer(allocator), entry);
        try file.writeAll(buffer.items);
    }
}

/// Helper to create a manifest entry with default values for MVP.
/// Perceptual diff stubbed to 0.0 (will be computed in 0.2.0).
pub fn createEntry(
    _: Allocator,
    input: []const u8,
    output: []const u8,
    bytes: u32,
    format: []const u8,
    budget_bytes: ?u32,
    max_diff: ?f64,
    alternates: []const ManifestEntry.Alternate,
    timings_ms: ManifestEntry.Timings,
) !ManifestEntry {
    // allocator parameter reserved for future use

    // Tiger Style: Pre-condition assertions
    std.debug.assert(input.len > 0);
    std.debug.assert(output.len > 0);
    std.debug.assert(format.len > 0);

    // Determine if passed (for MVP, just check budget)
    const passed = if (budget_bytes) |budget|
        bytes <= budget
    else
        true;

    return ManifestEntry{
        .input = input,
        .output = output,
        .bytes = bytes,
        .format = format,
        .diff_metric = "butteraugli", // Default for MVP
        .diff_value = 0.0, // MVP stub: will be computed in 0.2.0
        .budget_bytes = budget_bytes,
        .max_diff = max_diff,
        .passed = passed,
        .alternates = alternates,
        .timings_ms = timings_ms,
        .warnings = &[_][]const u8{}, // Empty for MVP
    };
}

// ============================================================================
// Unit Tests
// ============================================================================

test "ManifestEntry serializes to valid JSON" {
    const allocator = std.testing.allocator;

    const entry = ManifestEntry{
        .input = "images/hero.png",
        .output = "out/hero.avif",
        .bytes = 142381,
        .format = "avif",
        .diff_metric = "butteraugli",
        .diff_value = 0.93,
        .budget_bytes = 153600,
        .max_diff = 1.2,
        .passed = true,
        .alternates = &[_]ManifestEntry.Alternate{
            .{ .format = "webp", .bytes = 151202, .diff = 1.01, .passed = true },
            .{ .format = "jpeg", .bytes = 154900, .diff = 0.85, .passed = false, .reason = "over_budget" },
        },
        .timings_ms = .{
            .decode = 8,
            .transform = 4,
            .encode_total = 31,
            .metrics = 6,
        },
        .warnings = &[_][]const u8{},
    };

    // Serialize to buffer
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    try writeManifestLine(buffer.writer(allocator), entry);

    const json_str = buffer.items;

    // Verify it's valid JSON by parsing it back
    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    // Verify key fields
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("images/hero.png", obj.get("input").?.string);
    try std.testing.expectEqualStrings("out/hero.avif", obj.get("output").?.string);
    try std.testing.expectEqual(@as(i64, 142381), obj.get("bytes").?.integer);
    try std.testing.expectEqualStrings("avif", obj.get("format").?.string);
    try std.testing.expectEqual(true, obj.get("passed").?.bool);

    // Verify it ends with newline (JSONL format)
    try std.testing.expect(json_str[json_str.len - 1] == '\n');
}

test "writeManifestLine produces JSONL format" {
    const allocator = std.testing.allocator;

    const entry = ManifestEntry{
        .input = "test.png",
        .output = "test.webp",
        .bytes = 1000,
        .format = "webp",
        .diff_metric = "butteraugli",
        .diff_value = 0.5,
        .budget_bytes = null,
        .max_diff = null,
        .passed = true,
        .alternates = &[_]ManifestEntry.Alternate{},
        .timings_ms = .{ .decode = 1, .transform = 2, .encode_total = 3, .metrics = 4 },
        .warnings = &[_][]const u8{},
    };

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    try writeManifestLine(buffer.writer(allocator), entry);

    const json_str = buffer.items;

    // Should be valid JSON
    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    // Should end with exactly one newline
    try std.testing.expect(json_str[json_str.len - 1] == '\n');
    try std.testing.expect(json_str[json_str.len - 2] != '\n');
}

test "createEntry generates valid manifest entry with defaults" {
    const allocator = std.testing.allocator;

    const entry = try createEntry(
        allocator,
        "input.jpg",
        "output.avif",
        50000,
        "avif",
        100000, // budget
        1.0, // max_diff
        &[_]ManifestEntry.Alternate{},
        .{ .decode = 10, .transform = 5, .encode_total = 20, .metrics = 3 },
    );

    // Verify defaults
    try std.testing.expectEqualStrings("input.jpg", entry.input);
    try std.testing.expectEqualStrings("output.avif", entry.output);
    try std.testing.expectEqual(@as(u32, 50000), entry.bytes);
    try std.testing.expectEqualStrings("avif", entry.format);
    try std.testing.expectEqual(@as(f64, 0.0), entry.diff_value); // MVP stub
    try std.testing.expectEqual(true, entry.passed); // Under budget
}

test "createEntry marks as failed when over budget" {
    const allocator = std.testing.allocator;

    const entry = try createEntry(
        allocator,
        "input.jpg",
        "output.webp",
        150000, // Over budget
        "webp",
        100000, // budget
        1.0,
        &[_]ManifestEntry.Alternate{},
        .{ .decode = 10, .transform = 5, .encode_total = 20, .metrics = 3 },
    );

    // Should be marked as failed
    try std.testing.expectEqual(false, entry.passed);
}

test "writeManifest writes multiple entries to file" {
    const allocator = std.testing.allocator;

    const test_dir = "zig-out/test_manifest";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const manifest_path = test_dir ++ "/manifest.jsonl";

    const entries = [_]ManifestEntry{
        .{
            .input = "img1.png",
            .output = "img1.avif",
            .bytes = 1000,
            .format = "avif",
            .diff_metric = "butteraugli",
            .diff_value = 0.5,
            .budget_bytes = null,
            .max_diff = null,
            .passed = true,
            .alternates = &[_]ManifestEntry.Alternate{},
            .timings_ms = .{ .decode = 1, .transform = 2, .encode_total = 3, .metrics = 4 },
            .warnings = &[_][]const u8{},
        },
        .{
            .input = "img2.jpg",
            .output = "img2.webp",
            .bytes = 2000,
            .format = "webp",
            .diff_metric = "butteraugli",
            .diff_value = 0.8,
            .budget_bytes = null,
            .max_diff = null,
            .passed = true,
            .alternates = &[_]ManifestEntry.Alternate{},
            .timings_ms = .{ .decode = 5, .transform = 3, .encode_total = 10, .metrics = 2 },
            .warnings = &[_][]const u8{},
        },
    };

    try writeManifest(allocator, manifest_path, &entries);

    // Verify file exists and has 2 lines
    const file = try std.fs.cwd().openFile(manifest_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10_000);
    defer allocator.free(content);

    // Count newlines
    var line_count: u32 = 0;
    for (content) |c| {
        if (c == '\n') line_count += 1;
    }

    try std.testing.expectEqual(@as(u32, 2), line_count);
}

test "ManifestEntry with alternates serializes correctly" {
    const allocator = std.testing.allocator;

    const entry = ManifestEntry{
        .input = "test.png",
        .output = "test.avif",
        .bytes = 50000,
        .format = "avif",
        .diff_metric = "butteraugli",
        .diff_value = 0.9,
        .budget_bytes = 100000,
        .max_diff = 1.0,
        .passed = true,
        .alternates = &[_]ManifestEntry.Alternate{
            .{ .format = "webp", .bytes = 60000, .diff = 0.95, .passed = true },
            .{ .format = "jpeg", .bytes = 120000, .diff = 0.7, .passed = false, .reason = "over_budget" },
        },
        .timings_ms = .{ .decode = 10, .transform = 5, .encode_total = 20, .metrics = 3 },
        .warnings = &[_][]const u8{ "alpha channel present", "high memory usage" },
    };

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    try writeManifestLine(buffer.writer(allocator), entry);

    const json_str = buffer.items;

    // Parse and verify
    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    // Verify alternates array
    const alternates = obj.get("alternates").?.array;
    try std.testing.expectEqual(@as(usize, 2), alternates.items.len);

    // Verify first alternate
    const alt1 = alternates.items[0].object;
    try std.testing.expectEqualStrings("webp", alt1.get("format").?.string);
    try std.testing.expectEqual(@as(i64, 60000), alt1.get("bytes").?.integer);

    // Verify warnings array
    const warnings = obj.get("warnings").?.array;
    try std.testing.expectEqual(@as(usize, 2), warnings.items.len);
}
