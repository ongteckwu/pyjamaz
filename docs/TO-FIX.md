# Tiger Style Code Review - TO-FIX

Last Updated: 2025-10-30

## Critical Issues (Must Fix)

### CRIT-001: Integration Tests - Missing vips Module Reference
**File**: `src/test/integration/basic_optimization.zig:22`
**Severity**: CRITICAL (Build Failure)
**Issue**: Test file references `root.vips` but test runner has no access to vips module
```zig
// ❌ FAIL: Compilation error
const vips = root.vips;
// Error: root source file struct 'test_runner' has no member named 'vips'
```
**Root Cause**: Test uses default test_runner which doesn't expose project modules
**Fix Required**:
1. Create custom test runner that exposes all modules
2. Or restructure integration tests to use executable pattern (conformance runner model)
3. Update build.zig to use custom test runner

**Status**: ⚪ Not Fixed
**Priority**: P0 (Blocks `zig build test-integration`)

---

### CRIT-002: Conformance Tests - PNG Load Failures
**File**: `src/test/conformance_runner.zig`
**Severity**: CRITICAL (79% Test Failures)
**Issue**: 164/208 conformance tests failing with two failure modes:
1. **Load failures**: "VipsForeignLoad: not a known file format" (Kodak images, some PNGSuite)
2. **Size regression**: Output larger than input (many small PNGSuite images)

**Examples**:
```
Failed to load image 'testdata/conformance/kodak/kodim01.png':
  VipsForeignLoad: "testdata/conformance/kodak/kodim01.png" is not a known file format

❌ FAIL: s39i3p04.png - Output larger than input: 420 → 482 bytes (114.8%)
❌ FAIL: basi0g08.png - Output larger than input: 254 → 967 bytes (380.7%)
```

**Root Causes**:
1. PNG files may be corrupt/invalid test cases (intentionally malformed for PNGSuite)
2. Optimizer forcing re-encoding on already-optimal tiny images adds overhead
3. Missing PNG codec optimization for small files

**Fix Required**:
1. Add image validation before attempting optimization
2. Skip known-invalid test files (xc*, xd*, xs* from PNGSuite)
3. Implement "keep original if smaller" logic in candidate selection
4. Verify PNG encoding settings (compression level, filters)

**Status**: ⚪ Not Fixed
**Priority**: P0 (Blocks 0.1.0 MVP - need 90%+ conformance)

---

## High Priority Issues

### HIGH-001: ArrayList API Migration Incomplete
**Files**: Multiple files using old ArrayList API
**Severity**: HIGH (Potential Runtime Errors)
**Issue**: Some files still use old managed ArrayList API, not new Zig 0.15.1 unmanaged API

**Files Affected**:
- `src/discovery.zig` - ✅ FIXED in diff
- `src/optimizer.zig` - ❓ Need to verify
- `src/test/conformance_runner.zig` - ❓ Need to verify
- `src/manifest.zig` - ❓ Need to verify

**Old API (WRONG)**:
```zig
var list = ArrayList(T).init(allocator);
list.append(item);
list.deinit();
```

**New API (CORRECT)**:
```zig
var list = ArrayList(T){};
list.append(allocator, item);
list.deinit(allocator);
```

**Fix Required**: Audit all ArrayList usage and migrate to unmanaged API

**Status**: 🟡 Partially Fixed (discovery.zig done)
**Priority**: P1 (Prevents future bugs)

---

### HIGH-002: Thread Safety in libvips Tests
**File**: `src/test/unit/vips_test.zig`, `src/test/unit/image_ops_test.zig`, etc.
**Severity**: HIGH (Flaky Tests)
**Issue**: 6 tests skipped due to SKIP_VIPS_TESTS flag because libvips has thread-safety issues in parallel test execution

**Impact**:
- Reduced test coverage (6 tests skipped)
- Cannot verify libvips integration in CI
- Risk of regressions going undetected

**Root Cause**: libvips uses global state, not safe for parallel test runner

**Fix Options**:
1. Run libvips tests sequentially (build.zig: single-threaded test runner)
2. Create separate build step for libvips tests
3. Wrap libvips calls in mutex (performance cost)
4. Document as known limitation

**Status**: ⚪ Not Fixed (workaround: SKIP_VIPS_TESTS)
**Priority**: P1 (Affects CI reliability)

---

### HIGH-003: Missing Assertions in optimizer.zig
**File**: `src/optimizer.zig`
**Severity**: HIGH (Tiger Style Violation)
**Issue**: Need to verify functions have minimum 2 assertions per function

**Tiger Style Requirement**:
- Pre-condition: Assert input validity
- Post-condition: Assert output validity
- Invariants: Assert critical state

**Fix Required**: Audit `src/optimizer.zig` functions for assertion count

**Status**: ⚪ Not Verified
**Priority**: P1 (Tiger Style compliance)

---

## Medium Priority Issues

### MED-001: Conformance Test Coverage Gaps
**File**: `testdata/conformance/`
**Severity**: MEDIUM (Incomplete Test Suite)
**Issue**: Missing test coverage for:
- AVIF format (no test images)
- Large images (>10MB)
- CMYK JPEG (color space conversion)
- Animated formats (GIF, APNG)
- ICC profile handling

**Fix Required**: Add diverse test images to conformance suite

**Status**: ⚪ Not Fixed
**Priority**: P2 (Improves confidence, not blocking)

---

### MED-002: Error Message Quality
**File**: `src/test/conformance_runner.zig`
**Severity**: MEDIUM (Developer Experience)
**Issue**: Generic error messages don't help debug failures

**Example**:
```
❌ FAIL: kodim01.png - Optimization failed: error.LoadFailed
```

**Better Error**:
```
❌ FAIL: kodim01.png - Optimization failed: error.LoadFailed
  Cause: libvips cannot identify file format
  Hint: Check if file is valid PNG/JPEG/WebP
  Path: testdata/conformance/kodak/kodim01.png
```

**Fix Required**: Enhance error messages with actionable hints

**Status**: ⚪ Not Fixed
**Priority**: P2 (DX improvement)

---

### MED-003: Build.zig Environment Variable Duplication
**File**: `build.zig`
**Severity**: MEDIUM (Code Smell)
**Issue**: Environment variables duplicated across 3 test targets

**Current Code**:
```zig
run_unit_tests.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
run_unit_tests.setEnvironmentVariable("VIPS_NOVECTOR", "1");

run_integration_tests.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
run_integration_tests.setEnvironmentVariable("VIPS_NOVECTOR", "1");

run_conformance.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
run_conformance.setEnvironmentVariable("VIPS_NOVECTOR", "1");
```

**Better Approach**:
```zig
fn setVipsEnv(step: *std.Build.Step.Run) void {
    step.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
    step.setEnvironmentVariable("VIPS_NOVECTOR", "1");
}
```

**Fix Required**: Extract helper function

**Status**: ⚪ Not Fixed
**Priority**: P2 (Maintainability)

---

## Low Priority Issues

### LOW-001: TODO.md Progress Percentage Mismatch
**File**: `docs/TODO.md`
**Severity**: LOW (Documentation)
**Issue**: Progress shows "98% complete" but summary table shows "95% done"

**Fix Required**: Reconcile percentages or clarify what each measures

**Status**: ⚪ Not Fixed
**Priority**: P3 (Documentation polish)

---

### LOW-002: Conformance Runner Output Formatting
**File**: `src/test/conformance_runner.zig`
**Severity**: LOW (UX)
**Issue**: Output format inconsistent (some use `{d}`, some use `{}`)

**Fix Required**: Standardize format specifiers

**Status**: ⚪ Not Fixed
**Priority**: P3 (Polish)

---

## Learnings for src/CLAUDE.md

### 1. Zig 0.15.1 ArrayList API Migration
**Pattern**: Always use unmanaged ArrayList
```zig
// ✅ CORRECT: Unmanaged API
var list = ArrayList(T){};
defer list.deinit(allocator);
try list.append(allocator, item);

// ❌ WRONG: Old managed API
var list = ArrayList(T).init(allocator);
defer list.deinit();
try list.append(item);
```

**Rationale**: Zig 0.15+ uses unmanaged collections by default for explicit allocator control

---

### 2. Integration Test Structure
**Pattern**: Use executable pattern for integration tests, not test runner
```zig
// ✅ CORRECT: Executable with main()
pub fn main() !void {
    // Full access to project modules
    const vips = @import("vips.zig");
}

// ❌ PROBLEMATIC: Using test runner for integration tests
test "integration" {
    const vips = root.vips; // root doesn't expose modules
}
```

**Rationale**: Test runner has limited module exposure, executables have full control

---

### 3. Conformance Test Design
**Pattern**: Always include original as baseline candidate
```zig
// ✅ CORRECT: Original file is a candidate
candidates.append(EncodedCandidate{
    .data = original_data,
    .format = original_format,
    .quality = 100,
    .diff_score = 0.0, // No degradation
});

// Then add re-encoded candidates
for (formats) |fmt| {
    candidates.append(encodeAt(fmt, quality));
}

// Select smallest that meets constraints
```

**Rationale**: Re-encoding tiny already-optimal images wastes bytes. Original may be best.

---

### 4. Error Message Design
**Pattern**: Include context and hints
```zig
// ✅ CORRECT: Actionable error
std.log.err(
    \\Failed to load image: {s}
    \\Cause: {}
    \\Hint: Verify file is valid {s}
    \\Path: {s}
, .{filename, err, expected_format, full_path});

// ❌ WRONG: Generic error
std.log.err("Load failed: {}", .{err});
```

---

### 5. Build System Environment Variables
**Pattern**: Extract helper for repeated env vars
```zig
fn configureVipsEnv(run_step: *std.Build.Step.Run) void {
    run_step.setEnvironmentVariable("VIPS_DISC_THRESHOLD", "0");
    run_step.setEnvironmentVariable("VIPS_NOVECTOR", "1");
}

// Usage:
configureVipsEnv(run_unit_tests);
configureVipsEnv(run_integration_tests);
```

---

## Summary

**Critical Issues**: 2 (CRIT-001, CRIT-002)
**High Priority**: 3 (HIGH-001 partially fixed, HIGH-002, HIGH-003)
**Medium Priority**: 3
**Low Priority**: 2

**Blockers for 0.1.0 MVP**:
1. ✅ CRIT-001: Integration test compilation (can defer - use conformance runner instead)
2. ❌ CRIT-002: Conformance test pass rate (21% → need 90%+)

**Next Steps**:
1. Fix CRIT-002: Conformance test failures (P0)
2. Verify HIGH-003: Assertion count in optimizer.zig (P1)
3. Complete HIGH-001: ArrayList API migration audit (P1)
4. Address HIGH-002: libvips thread safety (P1)
