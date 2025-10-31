# Changelog

All notable changes to Pyjamaz will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added - Comprehensive Memory Testing Suite (2025-10-31)

- 12 test files: 3 Zig + 4 Node.js + 4 Python (~3,200 lines)
- Zig: `memory_leak_test.zig` (10K cycles), `arena_allocator_test.zig` (5K ops), `error_recovery_test.zig` (3 tests)
- Node.js: GC verification (10K ops), FFI tracking (5K ops), error recovery, buffer management
- Python: GC verification (psutil), ctypes tracking, exception cleanup, buffer management
- Build integration: `zig build memory-test` (~1 min), manual binding tests
- Documentation: `MEMORY_TESTS.md` (600+ lines), updated README/TODO
- Results: 8/8 Zig tests passing, 0 memory leaks, Tiger Style compliant

### Fixed - Polish & Code Quality Improvements (2025-10-31)

- Node.js: Added `pyjamaz_cleanup` FFI binding, `PyjamazBindingError` class, standardized error types
- Cache: Bounds checking in `parseMetadata` (7 validation points), prevents panic on malformed data
- Python: Type hints for ctypes structures, fixed bare except clause in `_find_library`

### Fixed - Tiger Style Compliance & Safety Improvements (2025-10-31)

- Bounded loops: `MAX_FORMATS = 10` in `src/api.zig` with pre/post assertions
- FFI assertions: 4+ checks in `pyjamaz_optimize` (input_len, concurrency, result integrity)
- Memory leak fix: `error_message_allocated` flag for heap vs static messages
- Cache eviction: Fixed assertion for >1000 entries (`src/cache.zig:404-416`)
- Type safety: `file_size` changed from `u32` to `u64` (supports >4GB files)
- Python validation: Parameter bounds, 100MB file limit, empty file rejection, metric enum checks
- Node.js safety: Null pointer checks, size bounds (100MB output, 1KB errors), UTF-8 validation
- Function length: `optimizeImage` refactored 168→62 lines (extracted `tryCacheHit`, `storeCacheResult`)
- Result: Zero critical issues, all tests passing, production ready

### Added - Intelligent Caching System (2025-10-31)

**Core Implementation**:

- Content-addressed caching with Blake3 hashing
- Cache key: `Blake3(input_bytes + max_bytes + max_diff + metric_type + format)`
- LRU eviction policy with configurable max size (default 1GB)
- Cache location: `~/.cache/pyjamaz/` or `$XDG_CACHE_HOME/pyjamaz/`
- 15-20x speedup on cache hits (~5ms vs 100ms full optimization)

**CLI Integration**:

- New flags: `--cache-dir`, `--no-cache`, `--cache-max-size`
- Added fields to `CliConfig`: `cache_dir`, `cache_enabled`, `cache_max_size`
- Cache enabled by default (can disable with `--no-cache`)

**Optimizer Integration**:

- Added `cache_ptr: ?*Cache` field to `OptimizationJob`
- Cache lookup at start of `optimizeImage()` and `optimizeImageFromBuffer()`
- Cache storage after successful optimization
- Optional caching (null pointer = disabled)
- Graceful degradation (cache failures don't break optimization)

**Test Coverage**:

- 18 tests: config, key computation, init/deinit, put/get, clear, metadata parsing
- Edge cases: large files (1MB), disabled cache, multiple formats
- All tests passing with zero memory leaks

**Technical Notes**:

- Tiger Style compliant (bounded loops, 2+ assertions per function)
- Zig 0.15 compatible (manual JSON serialization, direct file.writeAll())
- Same input + same options = same cache key = instant result
- Different options = different keys (no collisions)

**Future Enhancements**:

- Cache support for C API, Python bindings, Node.js bindings
- Cache statistics and monitoring
- Cache warming strategies
- Distributed cache (Redis, Memcached)

---

## [0.5.0] - 2025-10-31

### Added

- SSIMULACRA2 perceptual metric (native Zig via fssimu2)
- CLI flags: `--metric`, `--sharpen`, `--flatten`, `-v/-vv/-vvv`, `--seed`
- Exit codes: 0 (success), 1 (failure), 10-14 (specific errors)
- Manifest generation (JSONL format)
- Comprehensive error classification system

### Changed

- Conformance test pass rate: 197/211 (93%)
- Enhanced CLI help text with examples

---

## [0.4.0] - 2025-10-31

### Added

- DSSIM metric calculations (FFI bindings to libdssim)
- Dual-constraint validation (size + quality)
- Enhanced manifest output with perceptual scores
- Perceptual metrics framework

### Changed

- Conformance test pass rate: 197/211 (93%)

---

## [0.3.0] - 2025-10-30

### Added

- WebP encoder support (via libvips)
- AVIF encoder support (via libvips)
- Original file baseline candidate (prevents size regressions)
- Format preference ordering

### Changed

- Conformance test pass rate: 168/205 (92%)

---

## [0.2.0] - 2025-10-30

### Added

- Parallel candidate generation (1.2-1.4x speedup with 4 cores)
- Configurable concurrency (1-8 threads)
- Benchmark suite for performance testing

---

## [0.1.0] - 2025-10-30 (MVP)

### Added

- Core optimization pipeline (decode → transform → encode → select)
- libvips integration for image processing
- JPEG encoder (via libjpeg-turbo)
- PNG encoder (via libpng)
- Binary search for size targeting
- CLI tool with batch processing
- 67 unit tests, 208 conformance tests
- Tiger Style methodology (2+ assertions, bounded loops, ≤70 lines)

### Features

- Automatic format selection
- Size budget enforcement
- Perceptual quality metrics foundation
- Batch processing with directory discovery
- Zero memory leaks (verified with testing.allocator)

---

## Changelog Guidelines

### Format Rules

- **Use point-form** (bullets and sub-bullets, not paragraphs)
- **Be concise** (1-2 lines per bullet max)
- **Group related items** (use sub-bullets)
- **Technical details** (mention file names, line counts, key functions)

### When to Update

- After completing major milestone or feature
- Keep `[Unreleased]` section current during development
- Move to versioned section before release

### Structure

- `### Added` - New features, files, capabilities
- `### Changed` - Modifications to existing functionality
- `### Deprecated` - Soon-to-be-removed features
- `### Removed` - Deleted features or files
- `### Fixed` - Bug fixes
- `### Security` - Security vulnerability fixes

**Last Updated**: 2025-10-31
**Project**: Pyjamaz - High-performance image optimizer
