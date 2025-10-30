const std = @import("std");
const vips = @import("../vips.zig");

/// Global vips context - initialized once for all tests across all files
var vips_init_once = std.once(initVipsOnce);
var vips_ctx: vips.VipsContext = undefined;
var vips_init_error: ?anyerror = null;

/// Mutex to serialize vips operations across parallel tests
/// libvips is not thread-safe, so we must ensure only one test uses it at a time
var vips_mutex: std.Thread.Mutex = .{};

fn initVipsOnce() void {
    vips_ctx = vips.VipsContext.init() catch |err| {
        vips_init_error = err;
        return;
    };
}

/// Ensure vips is initialized before running tests
/// Thread-safe - can be called from any test, will only initialize once
pub fn ensureVipsInit() !void {
    vips_init_once.call();
    if (vips_init_error) |err| {
        return err;
    }
}

/// Lock vips for exclusive use
/// Call this before any vips operation in tests
/// Must be paired with unlockVips()
pub fn lockVips() void {
    vips_mutex.lock();
}

/// Unlock vips after use
/// Must be called after lockVips() to allow other tests to proceed
pub fn unlockVips() void {
    vips_mutex.unlock();
}
