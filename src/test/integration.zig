//! Integration test entry point
//! This file imports and runs all integration tests

// Import the actual integration tests
pub const basic_optimization = @import("integration/basic_optimization.zig");

// Run all integration tests
test {
    @import("std").testing.refAllDecls(@This());
}
