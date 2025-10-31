# Golden Snapshot Regression Testing

**Last Updated**: 2025-10-30

Golden snapshot testing ensures that optimizer outputs remain deterministic and consistent across versions. This prevents unintended regressions in output quality, size, or format selection.

---

## Overview

### What Are Golden Snapshots?

Golden snapshots are saved outputs from a known-good version of the optimizer. New code changes are tested by comparing their outputs against these "golden" baselines.

### Why Use Golden Snapshots?

1. **Regression Detection**: Catch unexpected changes in optimizer behavior
2. **Determinism Verification**: Ensure optimizer produces consistent outputs
3. **Quality Assurance**: Validate that output quality remains stable
4. **Format Selection Tracking**: Monitor format choice changes over time

---

## Architecture

### Components

1. **Golden Module** (`src/golden.zig`)
   - Hash computation (SHA256 for stability)
   - Manifest serialization (TSV format)
   - Comparison logic

2. **Integration Tests** (`src/test/integration/golden_snapshot.zig`)
   - Golden generation workflow
   - Comparison workflow
   - Test cases

3. **CLI Flags** (`src/cli.zig`)
   - `--update-golden`: Generate/update golden baseline
   - `--golden-manifest <FILE>`: Specify manifest path

### Data Format

**Manifest Format** (TSV):
```
# Golden Snapshot Manifest
# Format: test_name	input_hash	output_hash	format	output_size
small_png	abc123...	def456...	jpeg	1024
rgb_png	789ghi...	012jkl...	png	2048
rgba_png	345mno...	678pqr...	webp	1536
```

**Fields**:
- `test_name`: Test case identifier (e.g., "kodak/kodim01")
- `input_hash`: SHA256 of input file (detects input changes)
- `output_hash`: SHA256 of output file (detects output changes)
- `format`: Output format chosen (jpeg, png, webp, avif)
- `output_size`: Output file size in bytes

---

## Workflow

### 1. Initial Golden Generation

**First-time setup** or **after major optimizer changes**:

```bash
# 1. Run optimizer in golden update mode
pyjamaz --update-golden \
        --golden-manifest testdata/golden/v0.4.0/manifest.tsv \
        --out testdata/golden/v0.4.0/outputs \
        testdata/conformance/

# This creates:
# - testdata/golden/v0.4.0/manifest.tsv (hashes and metadata)
# - testdata/golden/v0.4.0/outputs/* (optimized images)
```

**What happens**:
1. Optimizer processes all test inputs
2. Computes SHA256 hash of each input file
3. Computes SHA256 hash of each output file
4. Records: test name, input hash, output hash, format, size
5. Saves manifest to specified path

### 2. Regression Testing

**On every code change** or **in CI pipeline**:

```bash
# Run optimizer and compare against golden baseline
pyjamaz --golden-manifest testdata/golden/v0.4.0/manifest.tsv \
        --out zig-out/test-outputs \
        testdata/conformance/

# Exit code:
# 0 = All outputs match golden snapshots (no regression)
# 1 = One or more outputs differ (potential regression!)
```

**What happens**:
1. Optimizer processes all test inputs
2. Computes SHA256 hash of each output
3. Compares against golden manifest
4. Reports:
   - ✅ **MATCH**: Hash matches golden (no change)
   - ❌ **MISMATCH**: Hash differs (regression detected!)
   - 🆕 **NEW**: Test not in golden (new test added)
   - ⚠️  **MISSING**: Test in golden but not found (test removed)

### 3. Updating Golden Baseline

**After verifying changes are intentional**:

```bash
# Update golden baseline with new outputs
pyjamaz --update-golden \
        --golden-manifest testdata/golden/v0.4.0/manifest.tsv \
        --out testdata/golden/v0.4.0/outputs \
        testdata/conformance/
```

**When to update**:
- ✅ After performance improvements (same quality, smaller size)
- ✅ After format support additions (AVIF, etc.)
- ✅ After intentional algorithm changes (documented)
- ❌ NOT after accidental regressions!

---

## Integration with Testing

### Running Golden Snapshot Tests

```bash
# Run integration tests (includes golden snapshot tests)
zig build test-integration

# Output:
# Testing: small_png
#   ✅ Generated: zig-out/test-golden/small_png.png (420 bytes)
# Testing: rgb_png
#   ✅ Generated: zig-out/test-golden/rgb_png.jpeg (1024 bytes)
#
# === Comparison Results ===
# ✅ small_png: MATCH (size: 420 bytes)
# ✅ rgb_png: MATCH (size: 1024 bytes)
#
# === Summary ===
# Matches:    2
# Mismatches: 0
# New:        0
#
# ✅ All tests match golden snapshots!
```

### Test Cases

**Predefined Test Inputs** (`src/test/integration/golden_snapshot.zig`):
```zig
const test_inputs = [_]struct {
    name: []const u8,
    path: []const u8,
}{
    .{ .name = "small_png", .path = "testdata/conformance/pngsuite/basn0g01.png" },
    .{ .name = "rgb_png", .path = "testdata/conformance/pngsuite/basn2c08.png" },
    .{ .name = "rgba_png", .path = "testdata/conformance/pngsuite/basn6a08.png" },
};
```

**To add more tests**: Add entries to `test_inputs` array.

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Golden Snapshot Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libvips-dev

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.1

      - name: Build
        run: zig build

      - name: Run Golden Snapshot Tests
        run: |
          # Generate outputs and compare against golden baseline
          zig build test-integration

      - name: Check for Regressions
        run: |
          # Compare outputs against golden manifest
          ./zig-out/bin/pyjamaz \
            --golden-manifest testdata/golden/v0.4.0/manifest.tsv \
            --out zig-out/ci-outputs \
            testdata/conformance/

          # Exit code 1 if any mismatches found
```

---

## Troubleshooting

### Mismatch Detected: What to Do?

**1. Understand the Change**

```bash
# Run comparison to see which tests failed
pyjamaz --golden-manifest testdata/golden/v0.4.0/manifest.tsv \
        --out zig-out/test-outputs \
        testdata/conformance/

# Output shows:
# ❌ small_png: MISMATCH
#   Expected: abc123... (420 bytes)
#   Actual:   def456... (482 bytes)
```

**2. Investigate the Difference**

```bash
# Compare visually
compare testdata/golden/v0.4.0/outputs/small_png.png \
        zig-out/test-outputs/small_png.png \
        diff.png

# Check file sizes
ls -lh testdata/golden/v0.4.0/outputs/small_png.png
ls -lh zig-out/test-outputs/small_png.png

# Check perceptual difference (if you have dssim installed)
dssim testdata/golden/v0.4.0/outputs/small_png.png \
       zig-out/test-outputs/small_png.png
```

**3. Determine if Change is Intentional**

- **Intentional**: Algorithm improvement, new codec, etc.
  - ✅ Update golden baseline: `--update-golden`
  - ✅ Document change in commit message
  - ✅ Update CHANGELOG.md

- **Unintentional**: Regression, bug, etc.
  - ❌ DO NOT update golden baseline
  - 🐛 Fix the bug
  - ✅ Verify tests pass after fix

### Common Issues

#### Issue 1: "Golden manifest not found"

**Cause**: Manifest file doesn't exist or path is wrong

**Solution**:
```bash
# Create golden baseline first
pyjamaz --update-golden \
        --golden-manifest testdata/golden/v0.4.0/manifest.tsv \
        --out testdata/golden/v0.4.0/outputs \
        testdata/conformance/
```

#### Issue 2: "Test not in golden manifest (NEW)"

**Cause**: Test case added after golden baseline created

**Solution**:
```bash
# Update golden baseline to include new tests
pyjamaz --update-golden \
        --golden-manifest testdata/golden/v0.4.0/manifest.tsv \
        --out testdata/golden/v0.4.0/outputs \
        testdata/conformance/
```

#### Issue 3: All tests show MISMATCH

**Cause**: Likely a determinism issue (timestamps, random seeds)

**Solution**:
1. Check for non-deterministic behavior in optimizer
2. Ensure consistent encoding parameters
3. Verify EXIF/metadata stripping is consistent

#### Issue 4: Flaky tests (sometimes pass, sometimes fail)

**Cause**: Non-deterministic encoding, race conditions

**Solution**:
1. Disable parallel encoding for golden tests: `parallel_encoding = false`
2. Use fixed random seed if applicable
3. Investigate thread safety issues

---

## Best Practices

### 1. Version Golden Snapshots

**Structure**:
```
testdata/golden/
├── v0.4.0/
│   ├── manifest.tsv
│   └── outputs/
│       ├── small_png.png
│       └── rgb_png.jpeg
├── v0.5.0/
│   ├── manifest.tsv
│   └── outputs/
│       └── ...
└── current -> v0.4.0  (symlink to active version)
```

**Benefits**:
- Track changes across versions
- Compare between versions
- Rollback if needed

### 2. Commit Golden Manifests, Not Outputs

**Recommended**:
- ✅ Commit `manifest.tsv` (small, text file)
- ❌ Don't commit output images (large, binary)

**Rationale**:
- Manifest is small (~1KB per 100 tests)
- Outputs can be regenerated from manifest
- Keeps repository size manageable

### 3. Use Descriptive Test Names

```zig
// ✅ GOOD: Descriptive test names
.{ .name = "kodak/kodim01_landscape_high_detail", .path = "..." },
.{ .name = "pngsuite/basn0g01_1x1_grayscale", .path = "..." },

// ❌ BAD: Generic test names
.{ .name = "test1", .path = "..." },
.{ .name = "img2", .path = "..." },
```

### 4. Document Breaking Changes

**When updating golden baseline**, document WHY:

```bash
# Commit message:
git commit -m "perf: Improve JPEG quality estimation

- Updated quality-to-size search algorithm
- Reduces overshooting by 10% on average
- Golden snapshots updated (v0.4.0 → v0.5.0)
- All tests show 5-10% size reduction with same quality
- See docs/CHANGELOG.md for detailed results"
```

### 5. Run Golden Tests in CI

**Prevent merging regressions**:

```yaml
# .github/workflows/ci.yml
- name: Golden Snapshot Tests
  run: zig build test-integration

- name: Verify No Regressions
  run: |
    ./zig-out/bin/pyjamaz \
      --golden-manifest testdata/golden/current/manifest.tsv \
      --out zig-out/ci-outputs \
      testdata/conformance/
```

---

## Advanced Usage

### Custom Test Suites

**Create a custom golden test**:

```zig
// src/test/integration/my_golden_test.zig
const test_inputs = [_]struct {
    name: []const u8,
    path: []const u8,
}{
    .{ .name = "my_test_1", .path = "testdata/custom/img1.png" },
    .{ .name = "my_test_2", .path = "testdata/custom/img2.jpg" },
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const golden_path = "testdata/golden/my_suite/manifest.tsv";
    const output_dir = "testdata/golden/my_suite/outputs";

    if (should_update) {
        try golden.generateGolden(allocator, output_dir, golden_path);
    } else {
        const all_match = try golden.compareAgainstGolden(allocator, output_dir, golden_path);
        std.process.exit(if (all_match) 0 else 1);
    }
}
```

### Diff Visualization

**Generate visual diffs**:

```bash
# Install ImageMagick
brew install imagemagick

# Generate diff image
compare -metric PSNR \
        testdata/golden/v0.4.0/outputs/test.png \
        zig-out/test-outputs/test.png \
        diff.png

# Red = differences, white = same
```

### Hash Verification Tool

**Verify manifest integrity**:

```bash
# src/tools/verify_golden.zig
pub fn main() !void {
    // 1. Load manifest
    const manifest = try golden.GoldenManifest.loadFromFile(allocator, path);

    // 2. Recompute hashes for all output files
    for (manifest.entries.items) |entry| {
        const actual_hash = try golden.hashFile(output_path);
        if (!std.mem.eql(u8, &entry.output_hash, &actual_hash)) {
            std.log.err("HASH MISMATCH: {s}", .{entry.test_name});
        }
    }
}
```

---

## Maintenance

### When to Update Golden Baselines

**Update golden baseline when**:

1. **Performance Improvements**
   - Algorithm changes that reduce size
   - Better format selection logic
   - Improved quality estimation

2. **New Features**
   - New codec support (AVIF, JXL)
   - New optimization strategies
   - New transform options

3. **Bug Fixes**
   - Fixing incorrect behavior
   - Correcting quality metrics
   - Resolving edge cases

### Versioning Strategy

**Version golden snapshots per milestone**:

- v0.4.0: Current baseline (DSSIM integration)
- v0.5.0: Next baseline (Butteraugli integration)
- v1.0.0: Production baseline

**Naming convention**:
- `testdata/golden/v{MAJOR}.{MINOR}.{PATCH}/manifest.tsv`

### Cleanup Policy

**Keep at least**:
- Current version
- Previous version (for comparison)

**Archive old versions**:
```bash
# Compress old baselines
tar -czf testdata/golden/archive/v0.3.0.tar.gz testdata/golden/v0.3.0/
rm -rf testdata/golden/v0.3.0/
```

---

## FAQ

### Q: How often should I update golden baselines?

**A**: Update when:
- Releasing a new version (v0.4.0 → v0.5.0)
- Making intentional algorithm changes
- Adding significant new features

**Don't update** after every commit. Golden baselines should be stable.

### Q: What if I'm working on an experimental branch?

**A**: Use a temporary golden baseline:

```bash
# Create branch-specific baseline
pyjamaz --update-golden \
        --golden-manifest testdata/golden/experimental/manifest.tsv \
        --out testdata/golden/experimental/outputs \
        testdata/conformance/

# Test against it
pyjamaz --golden-manifest testdata/golden/experimental/manifest.tsv \
        testdata/conformance/
```

Don't commit experimental baselines to main branch.

### Q: How do I handle platform-specific differences?

**A**: Use platform-specific manifests:

```
testdata/golden/v0.4.0/
├── manifest-linux.tsv
├── manifest-macos.tsv
└── manifest-windows.tsv
```

Then select based on platform:
```zig
const manifest_path = switch (builtin.os.tag) {
    .linux => "manifest-linux.tsv",
    .macos => "manifest-macos.tsv",
    .windows => "manifest-windows.tsv",
    else => "manifest.tsv",
};
```

### Q: Can I use golden snapshots for performance testing?

**A**: Yes! Track encoding times:

```zig
pub const GoldenEntry = struct {
    test_name: []const u8,
    input_hash: HashDigest,
    output_hash: HashDigest,
    format: []const u8,
    output_size: u64,
    encoding_time_ns: u64,  // Add timing
};
```

Then detect performance regressions:
```zig
if (actual_time_ns > expected_time_ns * 1.1) {
    std.log.warn("Performance regression: {s} took {d}ns (expected <{d}ns)",
                 .{test_name, actual_time_ns, expected_time_ns});
}
```

---

## Summary

Golden snapshot testing provides:

1. **Regression Detection**: Catch unintended changes
2. **Determinism Verification**: Ensure consistent outputs
3. **Quality Assurance**: Validate output stability
4. **CI/CD Integration**: Automate testing in pipelines

**Workflow recap**:
```bash
# 1. Generate baseline (once)
pyjamaz --update-golden --golden-manifest golden.tsv testdata/

# 2. Test against baseline (every change)
pyjamaz --golden-manifest golden.tsv testdata/

# 3. Update baseline (after verification)
pyjamaz --update-golden --golden-manifest golden.tsv testdata/
```

**Key principle**: Golden snapshots are a **safety net**, not a replacement for understanding changes.

---

## References

- [Golden Module Implementation](../src/golden.zig)
- [Integration Tests](../src/test/integration/golden_snapshot.zig)
- [CLI Documentation](./CLI_REFERENCE.md)
- [Testing Strategy](./TESTING_STRATEGY.md)

---

**Last Updated**: 2025-10-30
**Version**: 1.0.0

This is a living document - update as golden snapshot testing evolves!
