# Source Code Implementation Guide

**Purpose**: Implementation patterns, code organization, and Zig-specific guidelines for your project's source code.

---

## Table of Contents

1. [Source Organization](#source-organization)
2. [Tiger Style Enforcement](#tiger-style-enforcement)
3. [Zig Implementation Patterns](#zig-implementation-patterns)
4. [Common Code Patterns](#common-code-patterns)
5. [Error Handling](#error-handling)
6. [Memory Management](#memory-management)
7. [Testing Patterns](#testing-patterns)
8. [Performance Considerations](#performance-considerations)
9. [WebAssembly Considerations](#webassembly-considerations) (if applicable)

---

## Source Organization

### Directory Structure

```
src/
├── main.zig              # Entry point
├── CLAUDE.md             # This file
├── [module1]/            # Feature modules
│   ├── core.zig         # Core functionality
│   ├── types.zig        # Type definitions
│   └── utils.zig        # Utilities
├── [module2]/            # Another module
│   └── ...
└── test/                 # All tests
    ├── unit/            # Unit tests (mirrors src/)
    │   ├── [module1]/
    │   └── [module2]/
    ├── integration/     # Integration tests
    └── benchmark/       # Performance benchmarks
```

### File Organization Principles

1. **One module per directory**: Group related functionality
2. **Mirror test structure**: `src/foo/bar.zig` → `src/test/unit/foo/bar_test.zig`
3. **Keep files focused**: Each file has a single, clear purpose
4. **Public API first**: Export functions/types at top of file

### Module Template

```zig
//! Brief module description.
//!
//! Detailed explanation of what this module does,
//! how it fits into the system, and any important notes.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import other modules
const OtherModule = @import("../other_module/core.zig");

// Public types
pub const MyType = struct {
    field1: u32,
    field2: []const u8,

    /// Creates a new instance.
    /// Caller owns returned memory and must call `deinit()`.
    pub fn init(allocator: Allocator, value: u32) !MyType {
        // Implementation
    }

    pub fn deinit(self: *MyType, allocator: Allocator) void {
        // Cleanup
    }
};

// Public functions
pub fn myFunction(input: []const u8) !Result {
    // Implementation
}

// Internal/private functions (not exported)
fn helperFunction(data: []const u8) u32 {
    // Implementation
}

// Tests (inline with source)
test "MyType.init creates valid instance" {
    const testing = std.testing;
    // Test implementation
}
```

---

## Tiger Style Enforcement

### The Four Pillars

1. **Safety First** (2+ assertions per function)
2. **Predictable Performance** (bounded loops, known complexity)
3. **Developer Experience** (≤70 lines, clear naming)
4. **Zero Dependencies** (only Zig stdlib)

### Safety First: Assertions

**Every function needs 2+ assertions**:

```zig
pub fn processData(allocator: Allocator, data: []const u8, count: u32) !Result {
    // Pre-conditions (what must be true on entry)
    std.debug.assert(data.len > 0); // #1: Non-empty input
    std.debug.assert(count <= data.len); // #2: Count within bounds

    // ... implementation ...

    // Post-conditions (what must be true before return)
    std.debug.assert(result.isValid()); // #3: Result is well-formed
    return result;
}
```

**Types of Assertions**:

1. **Pre-conditions**: Validate inputs
   ```zig
   std.debug.assert(ptr != null);
   std.debug.assert(size > 0);
   std.debug.assert(index < array.len);
   ```

2. **Post-conditions**: Validate outputs
   ```zig
   std.debug.assert(result != null);
   std.debug.assert(bytes_written == expected);
   std.debug.assert(list.items.len > 0);
   ```

3. **Invariants**: Validate state
   ```zig
   std.debug.assert(self.count <= self.capacity);
   std.debug.assert(self.state == .Valid);
   std.debug.assert(self.lock_count >= 0);
   ```

4. **Post-loop**: Verify loop termination
   ```zig
   var i: u32 = 0;
   while (i < max_items) : (i += 1) {
       // Process item
   }
   std.debug.assert(i == max_items); // Always verify!
   ```

### Predictable Performance: Bounded Loops

**❌ NEVER write unbounded loops**:
```zig
// ❌ BAD: What if condition never becomes false?
while (condition) {
    // Could run forever
}
```

**✅ ALWAYS bound loops explicitly**:
```zig
// ✅ GOOD: Explicit upper bound
var i: usize = 0;
const MAX_ITERATIONS: usize = 1000;
while (i < items.len and i < MAX_ITERATIONS) : (i += 1) {
    // Process item
}
std.debug.assert(i <= MAX_ITERATIONS); // Post-condition
```

**Common Patterns**:

1. **Array iteration** (naturally bounded)
   ```zig
   for (items) |item| {
       // Process item - bounded by array length
   }
   ```

2. **Conditional iteration** (with explicit limit)
   ```zig
   var i: usize = 0;
   while (i < items.len and !found) : (i += 1) {
       if (matches(items[i])) found = true;
   }
   std.debug.assert(i <= items.len);
   ```

3. **Search iteration** (with timeout)
   ```zig
   var attempts: u32 = 0;
   const MAX_ATTEMPTS: u32 = 10;
   while (attempts < MAX_ATTEMPTS and !success) : (attempts += 1) {
       success = tryOperation();
   }
   std.debug.assert(attempts <= MAX_ATTEMPTS);
   ```

### Developer Experience: Function Size

**Keep functions ≤70 lines**:

```zig
// ❌ BAD: 150-line function doing many things
pub fn processEverything(data: []const u8) !void {
    // 150 lines of mixed concerns
}

// ✅ GOOD: Break into focused functions
pub fn processEverything(data: []const u8) !void {
    const validated = try validateInput(data);
    const parsed = try parseData(validated);
    const transformed = try transformData(parsed);
    try writeOutput(transformed);
}

fn validateInput(data: []const u8) !ValidatedData {
    // 20 lines - focused on validation
}

fn parseData(validated: ValidatedData) !ParsedData {
    // 30 lines - focused on parsing
}

fn transformData(parsed: ParsedData) !TransformedData {
    // 40 lines - focused on transformation
}

fn writeOutput(transformed: TransformedData) !void {
    // 15 lines - focused on output
}
```

### Zero Dependencies

**Only use Zig standard library**:

```zig
// ✅ GOOD: Standard library only
const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;

// ❌ BAD: External dependency (unless absolutely justified)
// const external = @import("some_package");
```

**If you must add a dependency**:
1. Document WHY in README.md
2. List in build.zig with version pinning
3. Evaluate alternatives first
4. Consider implementing yourself if simple

---

## Zig Implementation Patterns

### Type Conventions

**Use explicit types, avoid `usize`**:

```zig
// ✅ GOOD: Explicit, platform-independent
const count: u32 = 100;
const index: u32 = 0;
const size_bytes: u64 = 1024 * 1024; // 1MB

// ❌ AVOID: Architecture-dependent (32-bit vs 64-bit)
const count: usize = 100; // Changes between platforms
```

**When to use `usize`**:
- Memory addresses: `@intFromPtr()`, `@ptrFromInt()`
- Array/slice lengths: `array.len` returns `usize`
- Allocator APIs: `allocator.alloc()` takes `usize`

**Pattern**: Use `u32` for business logic, cast to `usize` only when calling stdlib:

```zig
const item_count: u32 = 1000; // Business logic

// Cast to usize only at API boundary
const items = try allocator.alloc(Item, @intCast(item_count));
```

### Memory Ownership Patterns

#### Pattern 1: Caller-Allocated (Preferred)

**Pros**: No allocations, no cleanup, fast
**Cons**: Caller must provide buffer

```zig
/// Formats data into provided buffer.
/// Returns number of bytes written.
pub fn format(data: Data, buffer: []u8) !usize {
    std.debug.assert(buffer.len > 0);
    std.debug.assert(buffer.len >= estimateSize(data));

    // Write into buffer
    const written = // ... format data ...

    std.debug.assert(written <= buffer.len);
    return written;
}

// Usage
var buffer: [1024]u8 = undefined;
const written = try format(data, &buffer);
const result = buffer[0..written];
```

#### Pattern 2: Function-Allocated (Common)

**Pros**: Convenient for caller
**Cons**: Caller must free, risk of leaks

```zig
/// Allocates and returns formatted data.
/// Caller owns returned slice and must free it.
pub fn allocAndFormat(allocator: Allocator, data: Data) ![]u8 {
    std.debug.assert(@intFromPtr(allocator.vtable) != 0); // Valid allocator

    const size = estimateSize(data);
    const buffer = try allocator.alloc(u8, size);

    const written = try format(data, buffer);
    std.debug.assert(written <= buffer.len);

    return buffer[0..written];
}

// Usage
const result = try allocAndFormat(allocator, data);
defer allocator.free(result); // Caller must free!
```

#### Pattern 3: Arena-Allocated (Best for Batches)

**Pros**: Batch cleanup, no individual frees
**Cons**: Memory held until arena deinit

```zig
pub fn processBatch(allocator: Allocator, items: []Item) !Result {
    // Create arena for all temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit(); // All allocations freed at once
    const arena_alloc = arena.allocator();

    // All these allocations freed on scope exit
    const temp1 = try arena_alloc.alloc(u8, 100);
    const temp2 = try processItem(arena_alloc, items[0]);
    // ... more processing ...

    // Return value uses original allocator (lives beyond function)
    return Result.init(allocator, final_data);
}
```

### Struct Patterns

#### Pattern 1: Simple Value Type

```zig
/// Simple data holder, no cleanup needed.
pub const Point = struct {
    x: f64,
    y: f64,

    pub fn init(x: f64, y: f64) Point {
        return .{ .x = x, .y = y };
    }

    pub fn distance(self: Point, other: Point) f64 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }
};
```

#### Pattern 2: Resource-Owning Type

```zig
/// Owns allocated resources, requires cleanup.
pub const Buffer = struct {
    data: []u8,
    allocator: Allocator,

    /// Creates buffer with given size.
    /// Caller must call `deinit()` when done.
    pub fn init(allocator: Allocator, size: usize) !Buffer {
        std.debug.assert(size > 0);

        const data = try allocator.alloc(u8, size);
        std.debug.assert(data.len == size);

        return Buffer{
            .data = data,
            .allocator = allocator,
        };
    }

    /// Frees all resources.
    pub fn deinit(self: *Buffer) void {
        std.debug.assert(self.data.len > 0);
        self.allocator.free(self.data);
        self.* = undefined; // Poison pointer
    }
};
```

#### Pattern 3: Iterator Type

```zig
/// Iterator over items, no allocations.
pub const ItemIterator = struct {
    items: []const Item,
    index: usize,

    pub fn init(items: []const Item) ItemIterator {
        return .{ .items = items, .index = 0 };
    }

    pub fn next(self: *ItemIterator) ?Item {
        if (self.index >= self.items.len) return null;

        const item = self.items[self.index];
        self.index += 1;

        std.debug.assert(self.index <= self.items.len);
        return item;
    }
};
```

---

## Common Code Patterns

### Pattern: Allocation with Cleanup

```zig
pub fn processFile(allocator: Allocator, path: []const u8) !Result {
    std.debug.assert(path.len > 0);

    // Allocate
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close(); // Cleanup on all paths

    const contents = try file.readToEndAlloc(allocator, 1_000_000);
    defer allocator.free(contents); // Cleanup on all paths

    // Process
    const result = try parse(allocator, contents);

    std.debug.assert(result.isValid());
    return result;
}
```

### Pattern: Error Context

```zig
pub fn parseData(data: []const u8) !ParsedData {
    std.debug.assert(data.len > 0);

    var parser = Parser.init(data);
    return parser.parse() catch |err| {
        // Add context before propagating
        std.log.err("Parse failed at offset {}: {}", .{
            parser.current_offset,
            err,
        });
        return err;
    };
}
```

### Pattern: Result with Validation

```zig
pub fn createThing(allocator: Allocator, config: Config) !Thing {
    std.debug.assert(config.isValid());

    const thing = Thing{
        .field1 = try allocate(allocator, config.size),
        .field2 = config.value,
    };

    // Validate result before returning
    std.debug.assert(thing.field1.len == config.size);
    std.debug.assert(thing.field2 == config.value);

    return thing;
}
```

### Pattern: Optional with Assertion

```zig
pub fn findItem(items: []const Item, id: u32) ?Item {
    std.debug.assert(items.len > 0); // Pre-condition

    for (items) |item| {
        if (item.id == id) {
            std.debug.assert(item.isValid()); // Found item is valid
            return item;
        }
    }

    return null; // Not found
}
```

---

## Error Handling

### Error Set Definition

```zig
pub const Error = error{
    OutOfMemory,
    InvalidInput,
    NotFound,
    OperationFailed,
};
```

### Error Handling Patterns

#### Pattern 1: Propagate (Default)

```zig
pub fn outer() !Result {
    const inner_result = try inner(); // Propagate on error
    return process(inner_result);
}
```

#### Pattern 2: Handle Specific Errors

```zig
pub fn outer() !Result {
    const inner_result = inner() catch |err| switch (err) {
        error.NotFound => return Result.empty(),
        error.InvalidInput => {
            std.log.warn("Invalid input, using default", .{});
            return Result.default();
        },
        else => return err, // Propagate others
    };

    return process(inner_result);
}
```

#### Pattern 3: Convert Errors

```zig
pub fn outer() !Result {
    const inner_result = inner() catch |err| {
        std.log.err("Inner failed: {}", .{err});
        return error.OperationFailed; // Convert to domain error
    };

    return process(inner_result);
}
```

#### Pattern 4: Critical Section (Use Sparingly)

```zig
pub fn initGlobal() void {
    // Only use `unreachable` when you can PROVE it won't fail
    global = allocate() catch unreachable; // Must succeed or program is broken
}
```

---

## Memory Management

### The Golden Rules

1. **Explicit allocators**: Every allocation takes an `Allocator` parameter
2. **Clear ownership**: Document who owns memory in function comments
3. **Defer cleanup**: Use `defer` for cleanup immediately after allocation
4. **Arena for batches**: Use `ArenaAllocator` for many small allocations

### Allocator Patterns

#### Pattern 1: General Purpose Allocator (GPA)

**Use when**: Long-lived allocations, variable sizes, need to free individually

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

const items = try allocator.alloc(Item, 100);
defer allocator.free(items);
```

#### Pattern 2: Arena Allocator

**Use when**: Many small allocations, batch cleanup

```zig
var arena = std.heap.ArenaAllocator.init(parent_allocator);
defer arena.deinit(); // Frees everything at once
const allocator = arena.allocator();

// No need for individual `defer free()` calls
const temp1 = try allocator.alloc(u8, 100);
const temp2 = try allocator.alloc(u8, 200);
const temp3 = try allocator.alloc(u8, 300);
// All freed on arena.deinit()
```

#### Pattern 3: Fixed Buffer Allocator

**Use when**: Stack-based allocation, known max size

```zig
var buffer: [4096]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();

// Allocations come from stack buffer
const items = try allocator.alloc(Item, 10);
// No free needed - buffer is stack-allocated
```

### Memory Leak Detection

**Use testing.allocator in tests**:

```zig
test "no memory leaks" {
    const allocator = std.testing.allocator;

    // Run operation 1000 times
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const thing = try createThing(allocator);
        defer thing.deinit(allocator);
        // Use thing...
    }

    // testing.allocator will fail if there are leaks
}
```

---

## Testing Patterns

### Test Organization

- **Unit Tests**: `src/test/unit/[module]/[file]_test.zig` - Mirror source structure
- **Integration Tests**: `src/test/integration/` - End-to-end workflows
- **Benchmarks**: `src/test/benchmark/` - Performance testing
- **Conformance Tests**: `src/test/conformance_runner.zig` - Template for external test suites
- **Inline tests**: Simple tests can go in source files

### Conformance Testing

For projects that need to validate against external specifications or test suites:

1. **Setup**: Place test files in `testdata/` directory
2. **Customize**: Edit `src/test/conformance_runner.zig` for your test format
3. **Build**: Uncomment conformance section in `build.zig`
4. **Run**: Execute with `zig build conformance`

See `src/test/conformance_runner.zig` for a template example.

### Test Template

```zig
const std = @import("std");
const testing = std.testing;
const MyModule = @import("../../../[module]/[file].zig");

test "MyModule: basic functionality" {
    const allocator = testing.allocator;

    // Setup
    const input = // ...

    // Execute
    const result = try MyModule.doSomething(allocator, input);
    defer result.deinit(allocator);

    // Assert
    try testing.expectEqual(expected, result.value);
    try testing.expect(result.isValid());
}

test "MyModule: error conditions" {
    const allocator = testing.allocator;

    // Test error case
    const result = MyModule.doSomething(allocator, invalid_input);
    try testing.expectError(error.InvalidInput, result);
}

test "MyModule: no memory leaks" {
    const allocator = testing.allocator;

    // Run many times to detect leaks
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const thing = try MyModule.create(allocator);
        defer thing.deinit(allocator);
    }
}
```

### Common Test Patterns

#### Pattern 1: Setup/Teardown

```zig
test "operation with cleanup" {
    const allocator = testing.allocator;

    // Setup
    const thing = try createThing(allocator);
    defer thing.deinit(allocator); // Always cleanup

    // Test
    try testing.expect(thing.isValid());
}
```

#### Pattern 2: Multiple Assertions

```zig
test "comprehensive validation" {
    const result = doSomething();

    try testing.expectEqual(@as(u32, 42), result.count);
    try testing.expectEqualStrings("expected", result.name);
    try testing.expect(result.flag);
    try testing.expectApproxEqAbs(@as(f64, 3.14), result.value, 0.001);
}
```

#### Pattern 3: Error Testing

```zig
test "handles invalid input" {
    const result = parseData(&[_]u8{});
    try testing.expectError(error.InvalidInput, result);
}
```

---

## Performance Considerations

### General Guidelines

1. **Profile first**: Don't guess bottlenecks
2. **Algorithmic wins**: O(n²) → O(n log n) beats micro-optimizations
3. **Memory layout**: Contiguous data is cache-friendly
4. **Avoid allocations**: Reuse buffers, use stack when possible

### Performance Patterns

#### Pattern 1: Batch Processing

```zig
// ✅ GOOD: Process in batches
pub fn processBatch(items: []Item) !void {
    const BATCH_SIZE = 1000;
    var offset: usize = 0;

    while (offset < items.len) : (offset += BATCH_SIZE) {
        const end = @min(offset + BATCH_SIZE, items.len);
        const batch = items[offset..end];
        try processSingleBatch(batch);
    }
}
```

#### Pattern 2: Reuse Buffers

```zig
// ✅ GOOD: Reuse buffer across iterations
pub fn processMany(allocator: Allocator, inputs: []Input) !void {
    var buffer = try ArrayList(u8).initCapacity(allocator, 4096);
    defer buffer.deinit();

    for (inputs) |input| {
        buffer.clearRetainingCapacity(); // Reuse allocation
        try processIntoBuffer(input, &buffer);
    }
}
```

#### Pattern 3: Avoid Allocations in Hot Path

```zig
// ❌ BAD: Allocates on every call
pub fn processHot(allocator: Allocator, data: []const u8) !Result {
    const temp = try allocator.alloc(u8, 100); // Hot path allocation!
    defer allocator.free(temp);
    // ...
}

// ✅ GOOD: Caller-allocated buffer
pub fn processHot(data: []const u8, buffer: []u8) !Result {
    std.debug.assert(buffer.len >= 100);
    // Use provided buffer - no allocation
    // ...
}
```

---

## WebAssembly Considerations

*Only relevant if building for WebAssembly target*

### Critical Rules for Wasm

1. **No large stack allocations**: Wasm stack is limited (~1MB)
   ```zig
   // ❌ BAD: Stack overflow in browser
   var big_buffer: [10 * 1024 * 1024]u8 = undefined;

   // ✅ GOOD: Heap allocation
   const big_buffer = try allocator.alloc(u8, 10 * 1024 * 1024);
   defer allocator.free(big_buffer);
   ```

2. **Use u32 for pointers**: Wasm32 uses 32-bit addresses
   ```zig
   // ❌ BAD: usize changes between wasm32/wasm64
   export fn getPointer() usize { /* ... */ }

   // ✅ GOOD: Explicit u32 for wasm32
   export fn getPointer() u32 { /* ... */ }
   ```

3. **Export allocation functions**: Let JS allocate safely
   ```zig
   export fn myAlloc(size: u32) u32 {
       const mem = allocator.alloc(u8, size) catch return 0;
       return @intCast(@intFromPtr(mem.ptr));
   }

   export fn myFree(ptr: u32, size: u32) void {
       const mem = @as([*]u8, @ptrFromInt(ptr))[0..size];
       allocator.free(mem);
   }
   ```

---

## Quick Reference

### Checklist for Every Function

- [ ] Function ≤70 lines (break up if longer)
- [ ] 2+ assertions (pre-conditions, post-conditions, invariants)
- [ ] All loops bounded (explicit upper limit)
- [ ] Post-loop assertions (verify termination)
- [ ] Clear ownership (document who frees memory)
- [ ] Explicit types (u32, not usize, unless required)
- [ ] Error handling (try/catch, not silent failure)
- [ ] Tests written (in src/test/unit/)

### Checklist for Every Struct

- [ ] Clear ownership (fields owned by struct?)
- [ ] init() function (if needs allocation)
- [ ] deinit() function (if owns resources)
- [ ] Documentation (what it is, how to use)
- [ ] Tests (creation, usage, cleanup)

### Checklist Before Commit

- [ ] `zig fmt src/` (format code)
- [ ] `zig build test` (all tests pass)
- [ ] No compiler warnings
- [ ] Documentation updated (if API changed)
- [ ] TODO.md updated (if task completed)

---

## Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Tiger Style Guide](../docs/TIGER_STYLE_GUIDE.md)
- [Project Architecture](../docs/ARCHITECTURE.md)

---

## Critical Learnings from Code Review (2025-10-30)

### Image Processing Safety

**LESSON 1: Always Bound File I/O Loops**

When hashing file contents, ALWAYS bound the loop to prevent hangs:

```zig
// ❌ BAD: Unbounded file read
while (true) {
    const bytes_read = try file.read(&buf);
    if (bytes_read == 0) break;
    hasher.update(buf[0..bytes_read]);
}

// ✅ GOOD: Bounded with max size
const MAX_HASH_SIZE: u64 = 100 * 1024 * 1024; // 100MB
var total_read: u64 = 0;

while (total_read < MAX_HASH_SIZE) {
    const bytes_read = try file.read(&buf);
    if (bytes_read == 0) break;
    hasher.update(buf[0..bytes_read]);
    total_read += bytes_read;
}

std.debug.assert(total_read <= MAX_HASH_SIZE);
```

**LESSON 2: Validate Image Dimensions at Load Time**

Protect against decompression bombs:

```zig
// ✅ Validate immediately after load
const MAX_DIMENSION: u32 = 65535;
const MAX_PIXELS: u64 = 178_000_000; // ~500 megapixels

const w = wrapper.width();
const h = wrapper.height();

if (w == 0 or h == 0 or w > MAX_DIMENSION or h > MAX_DIMENSION) {
    return VipsError.InvalidImage;
}

const total_pixels: u64 = @as(u64, w) * @as(u64, h);
if (total_pixels > MAX_PIXELS) {
    std.log.err("Image too large: {d}x{d} = {d} pixels", .{w, h, total_pixels});
    return VipsError.InvalidImage;
}
```

**LESSON 3: Always Use `defer` for C FFI Cleanup**

libvips memory leaks on error paths are common:

```zig
// ❌ BAD: Leaks if allocator.alloc fails
var buffer_ptr: [*c]u8 = null;
const result = vips_save_buffer(..., &buffer_ptr, ...);

if (result != 0) return error.Failed; // LEAK if buffer_ptr != null

const owned = try allocator.alloc(u8, len); // LEAK if this fails
g_free(buffer_ptr);

// ✅ GOOD: defer ensures cleanup on all paths
var buffer_ptr: [*c]u8 = null;
const result = vips_save_buffer(..., &buffer_ptr, ...);

defer if (buffer_ptr != null) g_free(buffer_ptr);

if (result != 0) return error.Failed; // No leak

const owned = try allocator.alloc(u8, len); // No leak if this fails
```

**LESSON 4: Validate Encoded Image Magic Numbers**

Always verify codec output:

```zig
// ✅ Verify JPEG magic number
pub fn saveAsJPEG(...) ![]u8 {
    const encoded = try vips_img.saveAsJPEG(allocator, quality);

    // Post-condition: Verify JPEG SOI marker
    std.debug.assert(encoded.len >= 2);
    std.debug.assert(encoded[0] == 0xFF and encoded[1] == 0xD8);

    return encoded;
}

// ✅ Verify PNG signature
pub fn saveAsPNG(...) ![]u8 {
    const encoded = try vips_img.saveAsPNG(allocator, compression);

    // Post-condition: Verify PNG signature
    std.debug.assert(encoded.len >= 8);
    std.debug.assert(encoded[0] == 0x89); // PNG signature
    std.debug.assert(encoded[1] == 0x50 and encoded[2] == 0x4E and encoded[3] == 0x47);

    return encoded;
}
```

**LESSON 5: Add Loop Invariants to Binary Search**

Binary search needs invariants inside the loop:

```zig
while (iteration < opts.max_iterations and q_min <= q_max) : (iteration += 1) {
    // Loop invariants
    std.debug.assert(q_min <= q_max);
    std.debug.assert(q_min >= opts.quality_min);
    std.debug.assert(q_max <= opts.quality_max);

    const q_mid = q_min + (q_max - q_min) / 2;
    std.debug.assert(q_mid >= q_min and q_mid <= q_max);

    const encoded = try encodeImage(..., q_mid);

    // Invariant: Encoded data is non-empty
    std.debug.assert(encoded.len > 0);

    // ... search logic ...
}

// Post-loop assertions
std.debug.assert(iteration <= opts.max_iterations);
std.debug.assert(best_quality >= opts.quality_min and best_quality <= opts.quality_max);
```

**LESSON 6: Warn When Discarding Alpha Channel**

Image optimizers must warn users about lossy transformations:

```zig
pub fn encodeImage(buffer: *const ImageBuffer, format: ImageFormat, quality: u8) ![]u8 {
    // Warn if encoding RGBA to format that doesn't support alpha
    if (buffer.channels == 4 and !formatSupportsAlpha(format)) {
        std.log.warn("Encoding RGBA image to {s} will drop alpha channel",
                     .{format.toString()});
    }

    // ... rest of encoding ...
}
```

**LESSON 7: Add Encoding Timeouts**

Protect against malformed images that cause slow encoding:

```zig
pub const SearchOptions = struct {
    max_iterations: u8 = 7,
    max_encode_time_ms: u64 = 5000, // 5 second timeout
    // ...
};

while (iteration < opts.max_iterations and q_min <= q_max) : (iteration += 1) {
    const start_time = std.time.milliTimestamp();

    const encoded = try codecs.encodeImage(...);

    const encode_time = std.time.milliTimestamp() - start_time;
    if (encode_time > opts.max_encode_time_ms) {
        std.log.warn("Encoding took {d}ms (>{}ms timeout)",
                     .{encode_time, opts.max_encode_time_ms});
    }
}
```

### Tiger Style Patterns

**LESSON 8: Minimum 2 Assertions = Pre + Post**

Every function needs at least:
1. Pre-condition(s) - validate inputs
2. Post-condition(s) - validate outputs

```zig
pub fn decodeImage(allocator: Allocator, path: []const u8) !ImageBuffer {
    // Pre-conditions (2)
    std.debug.assert(path.len > 0);
    std.debug.assert(path.len < std.fs.max_path_bytes);

    // ... operations ...

    const buffer = try srgb.toImageBuffer(allocator);

    // Post-conditions (2)
    std.debug.assert(buffer.width > 0 and buffer.height > 0);
    std.debug.assert(buffer.data.len == @as(usize, buffer.stride) * @as(usize, buffer.height));

    return buffer;
}
```

**LESSON 9: Add Invariants for Multi-Step Operations**

For functions with multiple steps, add invariants between steps:

```zig
pub fn decodeImage(allocator: Allocator, path: []const u8) !ImageBuffer {
    std.debug.assert(path.len > 0);

    var img = try vips.loadImage(path);
    defer img.deinit();

    // Invariant: Loaded image has valid dimensions
    std.debug.assert(img.width() > 0 and img.width() <= 65535);
    std.debug.assert(img.height() > 0 and img.height() <= 65535);

    var rotated = try vips.autorot(&img);
    defer rotated.deinit();

    // Invariant: Rotation preserves validity
    std.debug.assert(rotated.width() > 0 and rotated.height() > 0);

    var srgb = try vips.toSRGB(&rotated);
    defer srgb.deinit();

    // Invariant: Color space conversion succeeded
    std.debug.assert(srgb.interpretation() == .srgb);

    const buffer = try srgb.toImageBuffer(allocator);

    // Post-conditions
    std.debug.assert(buffer.width > 0 and buffer.height > 0);
    std.debug.assert(buffer.data.len > 0);

    return buffer;
}
```

**LESSON 10: Use Comptime Assertions for Struct Sizes**

Prevent struct bloat with comptime checks:

```zig
pub const ImageBuffer = struct {
    data: []u8,
    width: u32,
    height: u32,
    stride: u32,
    channels: u8,
    allocator: Allocator,
    color_space: u8,

    comptime {
        // Tiger Style: Ensure struct size is reasonable
        std.debug.assert(@sizeOf(ImageBuffer) <= 64);
    }
};
```

### Common Pitfalls

**PITFALL 1: Silent Alpha Channel Loss**

When encoding RGBA to JPEG, alpha is silently dropped. Always warn:

```zig
if (buffer.channels == 4 and format == .jpeg) {
    std.log.warn("Encoding RGBA to JPEG will discard alpha channel", .{});
}
```

**PITFALL 2: Forgetting to Free C-Allocated Memory**

libvips uses `g_free()`, not Zig allocator:

```zig
var buffer_ptr: [*c]u8 = null;
// ...
defer if (buffer_ptr != null) g_free(buffer_ptr); // ✅ Must use g_free
```

**PITFALL 3: Not Checking Empty Encoded Buffers**

Codec failures might return zero-byte buffers:

```zig
const encoded = try encodeImage(...);
std.debug.assert(encoded.len > 0); // ✅ Always check
```

**PITFALL 4: Missing Post-Loop Assertions**

Always verify loop termination:

```zig
while (iteration < MAX_ITERATIONS) : (iteration += 1) {
    // ... loop body ...
}
std.debug.assert(iteration <= MAX_ITERATIONS); // ✅ Verify bounded
```

---

**Last Updated**: 2025-10-30

This is a living document - update as you discover better patterns!
