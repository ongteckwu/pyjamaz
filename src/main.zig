const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    // Use GPA for main allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line arguments
    var config = cli.parseArgs(allocator) catch |err| {
        switch (err) {
            error.NoInputs => {
                std.debug.print("Error: No input files specified. Use --help for usage.\n", .{});
                std.process.exit(1);
            },
            error.UnknownOption => {
                std.debug.print("Error: Unknown option. Use --help for usage.\n", .{});
                std.process.exit(1);
            },
            error.MissingValue => {
                std.debug.print("Error: Missing value for option. Use --help for usage.\n", .{});
                std.process.exit(1);
            },
            else => {
                std.debug.print("Error parsing arguments: {}\n", .{err});
                std.process.exit(1);
            },
        }
    };
    defer config.deinit();

    // Print configuration if verbose
    if (config.verbose) {
        std.debug.print("Pyjamaz Image Optimizer\n", .{});
        std.debug.print("=======================\n", .{});
        std.debug.print("Inputs: {d} file(s)\n", .{config.inputs.items.len});
        std.debug.print("Output: {s}\n", .{config.output_dir});
        std.debug.print("Max bytes: {d}\n", .{config.max_bytes});
        std.debug.print("Max diff: {d:.2}\n", .{config.max_diff});
        std.debug.print("Formats: ", .{});
        for (config.formats.items, 0..) |format, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{format});
        }
        std.debug.print("\n\n", .{});
    }

    // TODO: Implement image optimization pipeline
    std.debug.print("Pyjamaz MVP - Coming soon!\n", .{});
    std.debug.print("Configuration parsed successfully.\n", .{});
    std.debug.print("Input files: {d}\n", .{config.inputs.items.len});

    for (config.inputs.items) |input| {
        std.debug.print("  - {s}\n", .{input});
    }
}

// Import tests from other modules
test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("cli.zig");
    _ = @import("types/image_buffer.zig");
    _ = @import("types/image_metadata.zig");
    _ = @import("vips.zig");
    _ = @import("image_ops.zig");
    _ = @import("codecs.zig");

    // Standalone test files
    _ = @import("test/unit/vips_test.zig");
    _ = @import("test/unit/image_ops_test.zig");
    _ = @import("test/unit/codecs_encoding_test.zig");
}
