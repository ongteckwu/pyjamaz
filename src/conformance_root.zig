//! Conformance test root - provides main() for conformance runner

// Re-export modules for conformance tests
pub const optimizer = @import("optimizer.zig");
pub const output = @import("output.zig");
pub const vips = @import("vips.zig");
pub const types = @import("types.zig");
pub const codecs = @import("codecs.zig");
pub const image_ops = @import("image_ops.zig");

// Import and run conformance main
pub const main = @import("test/conformance_runner.zig").main;
