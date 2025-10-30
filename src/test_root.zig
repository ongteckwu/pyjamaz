//! Test root file - exposes all modules for testing
//! This allows test files to import modules using @import("test_root").ModuleName

const std = @import("std");

// Re-export all modules for tests
pub const optimizer = @import("optimizer.zig");
pub const output = @import("output.zig");
pub const manifest = @import("manifest.zig");
pub const vips = @import("vips.zig");
pub const types = @import("types.zig");
pub const codecs = @import("codecs.zig");
pub const image_ops = @import("image_ops.zig");
pub const search = @import("search.zig");
pub const cli = @import("cli.zig");
pub const discovery = @import("discovery.zig");
pub const naming = @import("naming.zig");

// Import integration tests
test "integration tests" {
    _ = @import("test/integration/basic_optimization.zig");
}
