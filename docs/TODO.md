# Pyjamaz 1.0.0 Roadmap - Production-Ready Image Optimization Library

**Last Updated**: 2025-10-31
**Current Status**: Pre-1.0 (v0.5.0 foundation complete)
**Project**: Pyjamaz - High-performance, perceptual-quality image optimizer library

---

## Vision: 1.0.0 Release

Transform Pyjamaz from a CLI tool into a **production-ready library** that can be embedded in:
- Node.js applications (web servers, build tools)
- Python scripts (data pipelines, batch processing)
- Rust applications (via FFI)
- Any language supporting C FFI

**Core Value Proposition:**
- Single-function API: `optimizeImage(input, constraints) → output`
- Multiple format support (JPEG/PNG/WebP/AVIF)
- Perceptual quality guarantees (DSSIM, SSIMULACRA2)
- Size budget enforcement
- Zero configuration needed (smart defaults)

---

## Completed Foundation (v0.1.0 - v0.5.0 Phase 3)

### ✅ What's Already Working

**Core Engine:**
- ✅ Image optimization pipeline (decode → transform → encode → select)
- ✅ 4 codec support: JPEG, PNG, WebP, AVIF (via libvips)
- ✅ Perceptual metrics: DSSIM, SSIMULACRA2
- ✅ Dual-constraint validation (size + quality)
- ✅ Parallel candidate generation (1.2-1.4x speedup)
- ✅ Original file baseline (prevents size regressions)

**CLI Interface:**
- ✅ Full-featured command-line tool
- ✅ Advanced flags: `--metric`, `--sharpen`, `--flatten`, `-v/-vv/-vvv`, `--seed`
- ✅ Exit codes (0, 1, 10-14) for different scenarios
- ✅ Manifest generation (JSONL format)
- ✅ Batch processing with directory discovery

**Testing:**
- ✅ 75/115 unit tests passing (some leaks to fix)
- ✅ 197/211 conformance tests (93% pass rate)
- ✅ PNGSuite, Kodak, WebP, TestImages suites

**Build System:**
- ✅ Zig 0.15.1 build configuration
- ✅ Cross-platform support (macOS primary)
- ✅ Linked libraries: libvips, libjpeg, libdssim

---

## 1.0.0 Roadmap - 6 Major Milestones

### Milestone 1: Stabilize Core (Test Fixes & Quality)

**Goal**: Fix all test failures, eliminate memory leaks, achieve 100% test pass rate
**Status**: ⚪ Not Started
**Priority**: 🔴 CRITICAL (blocking for 1.0)

#### Tasks:
- [ ] **Fix memory leaks in tests** (currently 2 leaks in optimizer tests)
  - [ ] Fix `selectBestCandidate: format tiebreak` leak (line 717)
  - [ ] Audit all `allocator.dupe()` calls for proper cleanup
  - [ ] Add cleanup in test teardown
- [ ] **Fix signal 6 crash in search tests**
  - [ ] Debug `binarySearchQuality: converges to target size` crash
  - [ ] Investigate thread safety issues
- [ ] **Re-enable skipped tests** (40 currently skipped)
  - [ ] Identify why tests are skipped (SKIP_VIPS_TESTS flag?)
  - [ ] Fix or document intentionally skipped tests
- [ ] **Achieve 100% pass rate**
  - [ ] Target: 115/115 unit tests passing
  - [ ] Target: 211/211 conformance tests passing
- [ ] **Memory safety verification**
  - [ ] Run all tests with `testing.allocator`
  - [ ] Verify zero leaks across entire test suite
  - [ ] Add leak detection to CI

**Success Criteria:**
- All unit tests pass (115/115)
- All conformance tests pass (211/211)
- Zero memory leaks detected
- No test crashes or signals

**Estimated Effort**: 3-5 days

---

### Milestone 2: C API Layer (Foundation for Bindings)

**Goal**: Create stable C API for library usage from any language
**Status**: ⚪ Not Started
**Priority**: 🔴 CRITICAL (required for bindings)

#### Phase 1: C API Design

- [ ] **Design C API interface** (create `include/pyjamaz.h`)
  ```c
  // Core optimization function
  typedef struct {
      const uint8_t* input_bytes;
      size_t input_len;
      uint32_t max_bytes;        // 0 = no limit
      double max_diff;           // 0.0 = no limit
      const char* metric_type;   // "dssim", "ssimulacra2", "none"
      const char* formats;       // "jpeg,png,webp,avif" or NULL for all
  } PyjOptimizeOptions;

  typedef struct {
      uint8_t* output_bytes;
      size_t output_len;
      const char* format;        // Selected format
      double diff_value;         // Perceptual metric score
      bool passed;               // Met all constraints
      char* error_message;       // NULL if no error
  } PyjOptimizeResult;

  // Main API function
  PyjOptimizeResult* pyj_optimize(const PyjOptimizeOptions* options);
  void pyj_free_result(PyjOptimizeResult* result);

  // Utility functions
  const char* pyj_version(void);
  void pyj_init(void);
  void pyj_cleanup(void);
  ```

- [ ] **Implement C API in `src/c_api.zig`**
  - [ ] Export functions with `export` keyword
  - [ ] Handle allocations with C-compatible allocator
  - [ ] Error handling (return error codes, populate error messages)
  - [ ] Thread-safe initialization (libvips vips_init/vips_shutdown)

- [ ] **Build shared library** (update `build.zig`)
  - [ ] Add `libpyjamaz.so` / `libpyjamaz.dylib` / `pyjamaz.dll` target
  - [ ] Static library option (`libpyjamaz.a`)
  - [ ] Install headers to `include/`
  - [ ] Pkg-config support (`pyjamaz.pc`)

#### Phase 2: C API Testing

- [ ] **Create C example programs** (`examples/c/`)
  - [ ] `basic_optimize.c` - Simple single-image optimization
  - [ ] `batch_optimize.c` - Process multiple images
  - [ ] `custom_constraints.c` - Size + quality constraints
  - [ ] `error_handling.c` - Demonstrate error paths

- [ ] **C API unit tests** (`src/test/c_api/`)
  - [ ] Test all exported functions
  - [ ] Test error conditions (NULL inputs, invalid options)
  - [ ] Test memory cleanup (no leaks)
  - [ ] Test thread safety (concurrent calls)

- [ ] **Build system integration**
  - [ ] `zig build c-examples` - Compile C examples
  - [ ] `zig build c-api-test` - Run C API tests
  - [ ] CMake support for C projects using libpyjamaz

**Success Criteria:**
- C API compiles on Linux, macOS, Windows
- C examples run successfully
- No memory leaks in C API usage
- Header file documented (comments for all functions)

**Estimated Effort**: 5-7 days

---

### Milestone 3: Python Bindings

**Goal**: `pip install pyjamaz` for Python users
**Status**: ⚪ Not Started
**Priority**: 🟡 HIGH (major user base)

#### Phase 1: Python FFI Wrapper

- [ ] **Create Python package** (`bindings/python/`)
  ```
  bindings/python/
  ├── pyjamaz/
  │   ├── __init__.py
  │   ├── _native.py      # ctypes/cffi bindings
  │   ├── api.py          # High-level Python API
  │   └── types.py        # Python type hints
  ├── setup.py
  ├── pyproject.toml
  ├── README.md
  └── tests/
      ├── test_basic.py
      ├── test_constraints.py
      └── test_errors.py
  ```

- [ ] **Implement Python wrapper** (choose cffi or ctypes)
  ```python
  from pyjamaz import optimize_image, OptimizeOptions

  # Simple usage
  result = optimize_image("input.jpg", max_bytes=100_000)
  result.save("output.jpg")

  # Advanced usage
  options = OptimizeOptions(
      max_bytes=100_000,
      max_diff=0.002,
      metric="ssimulacra2",
      formats=["webp", "avif", "jpeg"]
  )
  result = optimize_image("input.png", options)
  print(f"Format: {result.format}, Size: {result.size}, Quality: {result.diff_value}")
  ```

- [ ] **Handle library loading**
  - [ ] Auto-detect platform (Linux/macOS/Windows)
  - [ ] Load `libpyjamaz.so/.dylib/.dll`
  - [ ] Graceful error if library not found
  - [ ] Optional: Bundle native library in wheel

#### Phase 2: Python Package Distribution

- [ ] **Build wheels** (manylinux, macOS, Windows)
  - [ ] GitHub Actions workflow for wheel building
  - [ ] Bundle native library in wheel (optional)
  - [ ] Test on Python 3.8, 3.9, 3.10, 3.11, 3.12

- [ ] **Documentation** (`bindings/python/docs/`)
  - [ ] API reference (Sphinx or MkDocs)
  - [ ] Usage examples
  - [ ] Integration guide (Django, Flask, FastAPI)
  - [ ] Troubleshooting guide

- [ ] **Publish to PyPI**
  - [ ] Test on test.pypi.org first
  - [ ] Publish stable release to pypi.org
  - [ ] Set up automatic uploads from GitHub releases

- [ ] **Testing**
  - [ ] Unit tests with pytest
  - [ ] Integration tests (process real images)
  - [ ] Type checking with mypy
  - [ ] Linting with ruff/black

**Success Criteria:**
- `pip install pyjamaz` works on Linux, macOS, Windows
- API is Pythonic (follows PEP 8)
- Type hints for all public functions
- 90%+ test coverage
- Documentation published online

**Estimated Effort**: 7-10 days

---

### Milestone 4: Node.js Bindings

**Goal**: `npm install pyjamaz` for JavaScript/TypeScript users
**Status**: ⚪ Not Started
**Priority**: 🟡 HIGH (web developers, build tools)

#### Phase 1: Node.js N-API Wrapper

- [ ] **Create Node.js package** (`bindings/nodejs/`)
  ```
  bindings/nodejs/
  ├── src/
  │   ├── binding.c       # N-API bindings to C API
  │   └── index.ts        # TypeScript wrapper
  ├── test/
  │   ├── basic.test.ts
  │   └── errors.test.ts
  ├── examples/
  │   ├── cli.js
  │   └── express-server.js
  ├── package.json
  ├── tsconfig.json
  └── README.md
  ```

- [ ] **Implement N-API bindings** (use node-gyp or cmake-js)
  ```typescript
  import { optimizeImage, OptimizeOptions } from 'pyjamaz';

  // Simple usage
  const result = await optimizeImage('input.jpg', { maxBytes: 100000 });
  await result.save('output.jpg');

  // Advanced usage
  const options: OptimizeOptions = {
    maxBytes: 100000,
    maxDiff: 0.002,
    metric: 'ssimulacra2',
    formats: ['webp', 'avif', 'jpeg']
  };
  const result = await optimizeImage(Buffer.from(...), options);
  console.log(`Format: ${result.format}, Size: ${result.buffer.length}`);
  ```

- [ ] **Handle async/await properly**
  - [ ] Use `napi_create_async_work` for non-blocking
  - [ ] Return Promises from all async functions
  - [ ] Handle errors properly (reject with Error objects)

#### Phase 2: Node.js Package Distribution

- [ ] **Build prebuilds** (for major platforms)
  - [ ] Use `prebuildify` to create prebuilt binaries
  - [ ] Support Node.js 16, 18, 20, 22
  - [ ] Platforms: Linux x64/arm64, macOS x64/arm64, Windows x64

- [ ] **TypeScript support**
  - [ ] Full type definitions (.d.ts files)
  - [ ] JSDoc comments for IDE autocomplete
  - [ ] Type-safe API (no `any` types)

- [ ] **Documentation**
  - [ ] API reference (TypeDoc)
  - [ ] Usage examples (Express, Next.js, Vite)
  - [ ] Integration guides
  - [ ] Performance best practices

- [ ] **Testing**
  - [ ] Unit tests with Jest or Vitest
  - [ ] Integration tests with real images
  - [ ] Test on multiple Node.js versions
  - [ ] Memory leak detection

- [ ] **Publish to npm**
  - [ ] Test on npm (unpublished package)
  - [ ] Publish stable release
  - [ ] Set up automatic publishing from GitHub releases

**Success Criteria:**
- `npm install pyjamaz` works on all major platforms
- Full TypeScript support with types
- Async/await API (non-blocking)
- 90%+ test coverage
- Documentation site live

**Estimated Effort**: 7-10 days

---

### Milestone 5: Production Features

**Goal**: Production-ready reliability, performance, and developer experience
**Status**: ⚪ Not Started
**Priority**: 🟠 MEDIUM (polish before 1.0)

#### Phase 1: Caching Layer (Optional but Recommended)

- [ ] **Design cache strategy**
  - [ ] Content-addressed keys: Blake3(input_bytes + options)
  - [ ] Cache location: `~/.cache/pyjamaz/` (XDG_CACHE_HOME)
  - [ ] Cache format: `{hash}.{format}` + metadata JSON
  - [ ] Eviction policy: LRU or size-based (configurable max size)

- [ ] **Implement `src/cache.zig`**
  ```zig
  pub const Cache = struct {
      cache_dir: []const u8,
      max_size_bytes: u64,

      pub fn init(allocator: Allocator, cache_dir: []const u8) !Cache;
      pub fn get(self: *Cache, key: []const u8) ?CachedResult;
      pub fn put(self: *Cache, key: []const u8, result: OptimizedImage) !void;
      pub fn evict(self: *Cache) !void;  // Remove oldest entries
      pub fn clear(self: *Cache) !void;  // Delete all entries
  };
  ```

- [ ] **Integrate with optimizer**
  - [ ] Check cache before encoding (early return if hit)
  - [ ] Store results after successful optimization
  - [ ] CLI flags: `--cache-dir`, `--no-cache`, `--cache-max-size`
  - [ ] API: `cache_enabled` in options struct

- [ ] **Testing**
  - [ ] Cache hit/miss scenarios
  - [ ] Eviction when over max size
  - [ ] Concurrent access (thread safety)
  - [ ] Corrupted cache entries (graceful fallback)

**Decision**: Caching is optional for 1.0, can be 1.1 feature if time-constrained.

#### Phase 2: Config File Support (Optional)

- [ ] **Support TOML config** (`.pyjamazrc` or `pyjamaz.toml`)
  ```toml
  [optimization]
  max_bytes = 100000
  max_diff = 0.002
  metric = "ssimulacra2"
  formats = ["webp", "avif", "jpeg"]

  [cache]
  enabled = true
  max_size = "1GB"
  directory = "~/.cache/pyjamaz"

  [advanced]
  sharpen = "auto"
  flatten_color = "#FFFFFF"
  ```

- [ ] **Config precedence**: CLI args > env vars > config file > defaults
- [ ] **Config validation** (error on unknown keys)
- [ ] **Config discovery** (current dir → home dir → system)

**Decision**: Config file is optional for 1.0, nice-to-have for power users.

#### Phase 3: Security Audit

- [ ] **Input validation**
  - [ ] Max file size limit (prevent memory exhaustion)
  - [ ] Decompression bomb detection (e.g., 1KB PNG → 1GB bitmap)
  - [ ] Malformed image handling (fuzz testing)
  - [ ] Path traversal prevention (sanitize file paths)

- [ ] **Dependency audit**
  - [ ] Review libvips CVEs (Common Vulnerabilities and Exposures)
  - [ ] Pin exact library versions in build
  - [ ] Document security policy (SECURITY.md)
  - [ ] Generate SBOM (Software Bill of Materials) - CycloneDX format

- [ ] **Fuzzing**
  - [ ] Set up AFL or libFuzzer for optimizer
  - [ ] Fuzz decoder with malformed images
  - [ ] Fuzz CLI argument parsing
  - [ ] Run fuzzer for 24+ hours, fix all crashes

**Success Criteria:**
- No known critical security issues
- Fuzzer runs clean for 24+ hours
- SBOM generated and published
- Security policy documented

**Estimated Effort**: 5-7 days

---

### Milestone 6: Release Engineering

**Goal**: Cross-platform releases, documentation, and 1.0 launch
**Status**: ⚪ Not Started
**Priority**: 🔴 CRITICAL (required for 1.0)

#### Phase 1: Cross-Platform Builds

- [ ] **Set up CI/CD** (GitHub Actions)
  - [ ] Linux x86_64 (Ubuntu 22.04, glibc)
  - [ ] Linux aarch64 (cross-compile or native runner)
  - [ ] macOS x86_64 (Intel Macs)
  - [ ] macOS aarch64 (Apple Silicon)
  - [ ] Windows x86_64 (MinGW or MSVC)

- [ ] **Binary artifacts**
  - [ ] CLI: Static binaries for each platform
  - [ ] Library: Shared libraries (.so/.dylib/.dll)
  - [ ] Headers: `pyjamaz.h` for C users
  - [ ] Generate SHA256 checksums
  - [ ] Sign binaries (macOS: codesign, Windows: optional)

- [ ] **Test matrix**
  - [ ] Run conformance tests on all platforms
  - [ ] Verify binaries work on target systems
  - [ ] Test library bindings on all platforms

#### Phase 2: Distribution

- [ ] **Homebrew formula** (macOS/Linux)
  ```ruby
  class Pyjamaz < Formula
    desc "High-performance image optimizer with perceptual quality"
    homepage "https://github.com/yourusername/pyjamaz"
    url "https://github.com/yourusername/pyjamaz/archive/v1.0.0.tar.gz"
    sha256 "..."

    depends_on "vips"
    depends_on "jpeg-turbo"
    # ...
  end
  ```

- [ ] **Scoop manifest** (Windows)
  ```json
  {
    "version": "1.0.0",
    "description": "High-performance image optimizer",
    "homepage": "https://github.com/yourusername/pyjamaz",
    "license": "MIT",
    "url": "https://github.com/.../pyjamaz-1.0.0-windows-x64.zip",
    "bin": "pyjamaz.exe"
  }
  ```

- [ ] **Docker image** (multi-arch)
  ```dockerfile
  FROM alpine:3.18
  RUN apk add --no-cache vips-dev jpeg-turbo-dev
  COPY pyjamaz /usr/local/bin/
  ENTRYPOINT ["/usr/local/bin/pyjamaz"]
  ```
  - [ ] Push to Docker Hub: `pyjamaz/pyjamaz:1.0.0`
  - [ ] Support linux/amd64, linux/arm64

- [ ] **GitHub Releases**
  - [ ] Attach all binaries to release
  - [ ] Include checksums (SHA256SUMS)
  - [ ] Include SBOM (pyjamaz-1.0.0-sbom.json)
  - [ ] Write detailed release notes

#### Phase 3: Documentation

- [ ] **Complete README.md**
  - [ ] Feature showcase with examples
  - [ ] Installation instructions (all platforms)
  - [ ] Quick start guide (CLI + library)
  - [ ] Performance characteristics
  - [ ] Comparison with alternatives (ImageMagick, Sharp, Pillow)

- [ ] **API Documentation**
  - [ ] C API reference (Doxygen or manual)
  - [ ] Python API reference (Sphinx)
  - [ ] Node.js API reference (TypeDoc)
  - [ ] Code examples for each language

- [ ] **User Guide** (`docs/USER_GUIDE.md`)
  - [ ] Common use cases
  - [ ] Best practices (format selection, quality tuning)
  - [ ] Troubleshooting guide
  - [ ] FAQ

- [ ] **Developer Documentation**
  - [ ] Architecture overview (already exists, update)
  - [ ] Contributing guide (already exists, update)
  - [ ] Building from source
  - [ ] Extending with custom metrics (plugin system?)

#### Phase 4: Website (Optional)

- [ ] **Documentation site** (GitHub Pages, Vercel, or Netlify)
  - [ ] Landing page with examples
  - [ ] API reference (auto-generated)
  - [ ] Playground (WASM build for browser testing)
  - [ ] Blog post announcing 1.0

**Success Criteria:**
- Binaries available for 5+ platforms
- Package managers updated (Homebrew, Scoop, PyPI, npm)
- Complete documentation published
- GitHub release created with v1.0.0 tag

**Estimated Effort**: 10-14 days

---

## Post-1.0 Roadmap (Future Enhancements)

### v1.1.0 - Performance & Ecosystem

- [ ] **Caching layer** (if not in 1.0)
- [ ] **Config file support** (if not in 1.0)
- [ ] **Rust bindings** (via FFI, for Rust ecosystem)
- [ ] **Go bindings** (via CGo)
- [ ] **CLI improvements**
  - [ ] Progress bars for batch operations
  - [ ] Watch mode (re-optimize on file changes)
  - [ ] JSON output mode (machine-readable)

### v1.2.0 - Advanced Features

- [ ] **WASM build** (for browser-based optimization)
- [ ] **HDR support** (PQ/HLG tone mapping)
- [ ] **Video thumbnail extraction** (single frame from video)
- [ ] **Additional metrics** (VMAF, Butteraugli if needed)
- [ ] **Custom quality presets** (web, print, archive)

### v2.0.0 - Distributed & GPU

- [ ] **Distributed optimization** (worker pool, horizontal scaling)
- [ ] **GPU-accelerated encoding** (research CUDA/Metal)
- [ ] **Multi-pass optimization** (refine candidates iteratively)
- [ ] **Batch resume** (checkpoint large jobs for crash recovery)

---

## Testing Strategy

### Unit Tests (Target: 100% pass rate)
- Fix current failures (2 leaks, 1 crash)
- Re-enable 40 skipped tests
- Add tests for new C API
- Memory leak detection for all tests

### Integration Tests
- End-to-end workflows (file input → optimized output)
- Error recovery (corrupt files, disk full, OOM)
- Concurrent optimization (thread safety)

### Conformance Tests
- PNGSuite: 176 tests (target 100%)
- Kodak: 24 tests (photographic content)
- WebP: 5 tests
- TestImages: 6 tests
- **Add compressible images** (current suite is mostly optimal PNGs)

### Benchmark Suite
- Single image optimization (median, p95 latency)
- Batch processing (100 images)
- Concurrency scaling (1, 2, 4, 8 threads)
- Cache hit vs miss (if caching implemented)
- Publish results in README

### Security Testing
- Fuzz testing (AFL/libFuzzer for 24+ hours)
- Decompression bomb handling
- Path traversal prevention
- CVE scanning for dependencies

---

## Timeline Estimate

| Milestone                  | Effort       | Dependencies         | ETA          |
|----------------------------|--------------|----------------------|--------------|
| 1. Stabilize Core          | 3-5 days     | None                 | Week 1       |
| 2. C API Layer             | 5-7 days     | Milestone 1          | Week 2       |
| 3. Python Bindings         | 7-10 days    | Milestone 2          | Week 3-4     |
| 4. Node.js Bindings        | 7-10 days    | Milestone 2          | Week 3-4     |
| 5. Production Features     | 5-7 days     | Milestone 1          | Week 4-5     |
| 6. Release Engineering     | 10-14 days   | All above            | Week 5-7     |

**Total Estimated Time**: 37-53 days (6-8 weeks)

**Parallelization Opportunities**:
- Python and Node.js bindings can be developed in parallel (both depend on C API)
- Production features (caching, security audit) can overlap with bindings work
- Documentation can be written incrementally throughout

**Critical Path**:
1. Stabilize Core (blocking everything)
2. C API Layer (blocking bindings)
3. Language Bindings (Python + Node.js in parallel)
4. Release Engineering (final step)

---

## Success Metrics for 1.0.0

### Quality
- ✅ 100% test pass rate (115/115 unit tests, 211/211 conformance)
- ✅ Zero memory leaks detected
- ✅ Zero crashes in fuzzer (24+ hour run)
- ✅ Security audit complete (no critical issues)

### API Stability
- ✅ C API documented and stable (semantic versioning committed)
- ✅ Breaking change policy documented
- ✅ API examples for C, Python, Node.js

### Distribution
- ✅ Binaries for 5+ platforms (Linux, macOS, Windows)
- ✅ Published to package managers (PyPI, npm, Homebrew)
- ✅ Docker image available (multi-arch)

### Documentation
- ✅ Complete API reference for all languages
- ✅ User guide with examples
- ✅ Contributing guide updated
- ✅ Installation instructions for all platforms

### Performance
- ✅ Benchmark results published
- ✅ No performance regressions from v0.5.0
- ✅ Optimization time <500ms for typical images

### Community
- ✅ GitHub releases set up with auto-publish
- ✅ Issue templates created
- ✅ Security policy (SECURITY.md)
- ✅ Code of conduct (CODE_OF_CONDUCT.md)

---

## Decision Log

### 2025-10-31: Focus on Library Usage for 1.0

**Context**: Original roadmap included HTTP server mode (v0.5.0 Phase 6)

**Decision**: Remove HTTP mode from 1.0 scope, focus on library/FFI usage instead

**Rationale**:
- Users can build HTTP servers using library bindings (Express.js, FastAPI, etc.)
- HTTP mode adds complexity (authentication, rate limiting, deployment)
- Library-first approach maximizes reusability
- Node.js/Python bindings provide better DX than HTTP API

**Alternatives Considered**:
- A) Include HTTP mode in 1.0 (rejected: scope creep)
- B) HTTP mode in 1.1 (possible future addition)
- C) Library-only (chosen: simpler, more flexible)

### 2025-10-31: Caching is Optional for 1.0

**Context**: Caching provides 15-20x speedup on repeated operations

**Decision**: Caching is nice-to-have for 1.0, not required

**Rationale**:
- Core optimization works without cache
- Can be added in 1.1 without breaking API
- Allows focus on stability and bindings
- Users can implement application-level caching if needed

**Implementation Note**: If time permits, add caching in Milestone 5. Otherwise, defer to 1.1.

### 2025-10-31: Rust Bindings Deferred to Post-1.0

**Context**: Rust has strong FFI support via `bindgen`

**Decision**: Python and Node.js bindings for 1.0, Rust bindings in 1.1+

**Rationale**:
- Python and Node.js have larger user bases for image processing
- Rust users comfortable with FFI can use C API directly
- Rust bindings are lower priority (can be community-contributed)

---

## Archived Completions (v0.1.0 - v0.5.0)

<details>
<summary>Click to expand completed milestones</summary>

### ✅ v0.1.0 - MVP Foundation (2025-10-30)
- libvips integration + JPEG/PNG codecs
- Binary search for size targeting
- Complete optimization pipeline
- 67 unit tests, 208 conformance tests (100% pass rate)

### ✅ v0.2.0 - Parallel Optimization (2025-10-30)
- Parallel candidate generation (1.2-1.4x speedup)
- Configurable concurrency, benchmark suite

### ✅ v0.3.0 - Full Codec Support (2025-10-30)
- WebP + AVIF encoders via libvips
- Perceptual metrics framework (DSSIM/SSIMULACRA2)
- Original file baseline candidate
- 168/205 conformance tests passing (92%)

### ✅ v0.4.0 - Perceptual Metrics (2025-10-31)
- Real DSSIM metric calculations (FFI bindings)
- Dual-constraint validation (size + quality)
- Enhanced manifest with perceptual scores
- 197/211 conformance tests (93% pass rate)

### ✅ v0.5.0 Phase 1-3 (2025-10-31)
- SSIMULACRA2 integration (native Zig via fssimu2)
- Advanced CLI flags (--metric, --sharpen, --flatten, -v/-vv/-vvv, --seed)
- Exit codes (0, 1, 10-14 for various scenarios)

</details>

---

**Last Updated**: 2025-10-31
**Roadmap Version**: 4.0.0 (1.0-focused)
**Next Review**: After Milestone 1 completion

This is a living document - update as implementation progresses!
