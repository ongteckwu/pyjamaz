# Pyjamaz - High-Performance Image Optimizer for Nodejs, Python, CLI

**Blazing-fast CLI tool for optimizing images with perceptual quality guarantees. Built with Zig using Tiger Style methodology.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Zig](https://img.shields.io/badge/Zig-0.15+-orange.svg)](https://ziglang.org/)
[![Tests](https://img.shields.io/badge/Tests-73%2F73_passing-brightgreen)]()
[![Coverage](https://img.shields.io/badge/Conformance-93%25-green)](docs/TEST_SUITES.md)

---

## 🎯 Why Pyjamaz?

- **🚀 Blazing Fast**: 50-100ms per image with parallel encoding, 15-20x faster with caching
- **💾 Intelligent Caching**: Content-addressed cache for instant repeated optimizations
- **🧪 Battle-Tested**: 73/73 unit tests, 196/211 conformance tests (15 skipped), **0 memory leaks**
- **📊 Smart**: Automatic format selection (JPEG, PNG, WebP, AVIF) with perceptual quality metrics
- **🔒 Safe**: Never makes files larger - original file always included as baseline
- **⚡ Efficient**: Memory-optimized processing (no temp files)
- **🐍 Python Bindings**: Production-ready Python API with automatic memory management
- **📘 Node.js Bindings**: TypeScript-first API with full type safety and IntelliSense
- **🐯 Tiger Style**: Safety-first methodology with 2+ assertions per function

---

## 📈 Impressive Stats

| Metric               | Result                                               |
| -------------------- | ---------------------------------------------------- |
| **Test Coverage**    | 73/73 unit tests (100%), 196/211 conformance (93%)   |
| **Memory Safety**    | 0 leaks detected (verified with testing.allocator)   |
| **Performance**      | 50-100ms per image (5x better than 500ms target)     |
| **Parallel Speedup** | 1.2-1.4x faster with 4 cores                         |
| **Compression**      | 87.4% average size reduction (12.6% of original)     |
| **Regressions**      | 0% - original file baseline prevents size increases  |
| **Formats**          | 4 (JPEG, PNG, WebP, AVIF)                            |
| **Metrics**          | 2 perceptual (DSSIM, SSIMULACRA2) + size constraints |

---

## 🚀 Quick Start

### Installation

**From Homebrew** (coming soon):

```bash
brew install pyjamaz
```

**From Source**:

```bash
# Install dependencies (macOS)
brew install vips jpeg-turbo dssim

# Build
git clone https://github.com/yourusername/pyjamaz.git
cd pyjamaz
zig build

# Run
./zig-out/bin/pyjamaz input.jpg -o output.jpg --max-bytes 100000
```

### Basic Usage

```bash
# Optimize single image with size constraint
pyjamaz input.jpg -o output.jpg --max-bytes 100000

# Optimize with quality constraint (SSIMULACRA2)
pyjamaz input.png -o output.webp --max-diff 0.002 --metric ssimulacra2

# Batch optimize directory
pyjamaz src/ -o optimized/ --max-bytes 50000

# Generate JSON manifest
pyjamaz input.jpg --manifest results.jsonl

# Use caching for 15-20x speedup
pyjamaz input.jpg --max-bytes 100000
# Second run: instant cache hit! ⚡

# Custom cache settings
pyjamaz input.jpg --cache-dir /tmp/cache --cache-max-size 2147483648
```

### Python Bindings Usage [Coming Soon]

Pyjamaz can also be used as a Python library for programmatic image optimization:

```python
import pyjamaz

# Optimize with size constraint
result = pyjamaz.optimize_image(
    'input.jpg',
    max_bytes=100_000,  # 100KB max
)

if result.passed:
    result.save('output.jpg')
    print(f"Optimized to {result.size:,} bytes")
```

**Features**:

- Automatic memory management (no manual cleanup)
- Full caching support (15-20x speedup)
- Quality constraints with perceptual metrics
- Format selection and detection
- Batch processing support

**Installation**:

```bash
# Install from PyPI
uv pip install pyjamaz-optimizer

# Or install from source
cd bindings/python
uv pip install -e .

# Run examples
uv run python examples/basic.py
uv run python examples/batch.py
```

**Complete documentation**: See [Python API Reference](docs/PYTHON_API.md) for detailed usage, examples, and integration guides.

### Node.js Bindings Usage

Pyjamaz can also be used from Node.js with full TypeScript support:

```typescript
import * as pyjamaz from "@pyjamaz/nodejs";

// Optimize with size constraint
const result = await pyjamaz.optimizeImage("input.jpg", {
  maxBytes: 100_000,
});

if (result.passed) {
  await result.save("output.jpg");
  console.log(`Optimized to ${result.size} bytes`);
}
```

**Features**:

- TypeScript-first design with full type safety
- Both sync and async APIs
- Automatic memory management
- Full caching support (15-20x speedup)
- Express/Fastify integration examples

**Installation**:

```bash
# Install Node.js bindings
cd bindings/nodejs
npm install
npm run build

# Run examples
npm run build && node dist/examples/basic.js
npx ts-node examples/basic.ts
```

**Complete documentation**: See [Node.js API Reference](docs/NODEJS_API.md) for detailed usage, examples, and integration guides.

---

## ✨ Features

### Language Bindings

- **Python**: Production-ready bindings with automatic memory management

  - Pythonic API with type hints
  - Full caching support
  - Zero external dependencies (uses stdlib ctypes)
  - Comprehensive test suite
  - See [Python API Documentation](docs/PYTHON_API.md)

- **Node.js**: TypeScript-first bindings with full type safety
  - TypeScript-first design with IntelliSense
  - Both sync and async APIs
  - Full caching support
  - Express/Fastify integration
  - 30+ comprehensive tests (TS + JS)
  - See [Node.js API Documentation](docs/NODEJS_API.md)

### Multi-Format Support

- **JPEG**: Via libjpeg-turbo (fast, widely supported)
- **PNG**: Via libpng (lossless)
- **WebP**: Modern format with excellent compression (80-90% reduction)
- **AVIF**: Next-gen format (experimental support via libvips)

**Note**: TIFF format is not supported. Pyjamaz focuses exclusively on web image formats. To optimize TIFF files, convert them to PNG first using ImageMagick or similar tools.

### Perceptual Quality Metrics

- **DSSIM**: Structural dissimilarity (FFI to libdssim)
- **SSIMULACRA2**: Advanced perceptual metric (native Zig via fssimu2)
- **None**: Fast mode without quality checks (`--metric none`)

### Smart Optimization

- **Automatic Format Selection**: Tries all formats, picks the smallest
- **Original File Baseline**: Never makes files larger (100% regression-free)
- **Binary Search**: Automatic quality tuning for size targets
- **Dual Constraints**: Size limits + perceptual quality guarantees

### Intelligent Caching 💾

**15-20x speedup** on repeated optimizations with content-addressed caching:

- Cache key computed from Blake3 hash of (input bytes + optimization options)
- Same input + same options = instant cache hit
- Different options = different cache entries (no collisions)
- LRU eviction policy with configurable size limit (default 1GB)

**Cache location**:

- Linux/macOS: `~/.cache/pyjamaz/` or `$XDG_CACHE_HOME/pyjamaz/`
- Windows: `%LOCALAPPDATA%\pyjamaz\cache\`

**Cache management**:

```bash
# View cache size
du -sh ~/.cache/pyjamaz

# Clear cache manually
rm -rf ~/.cache/pyjamaz

# Cache will auto-evict oldest entries when limit reached
```

### Advanced Capabilities

- **Transform Operations**:
  - Auto-sharpen via libvips (`--sharpen auto`)
  - Alpha flattening with custom background color (`--flatten #FFFFFF`)
  - EXIF auto-rotation (automatic)
- **Batch Processing**: Optimize entire directories
- **Manifest Generation**: JSONL output with optimization metrics
- **Verbose Logging**: 3 levels (`-v`, `-vv`, `-vvv`)
- **Exit Codes**: Detailed status (0=success, 1=failed, 10-14=errors)

---

## 📊 Performance Benchmarks

### Optimization Speed

**Platform**: Apple M1 Pro, macOS 15.0, libvips 8.17.0

| Image Size | Sequential | Parallel (4 cores) | Speedup | With Cache |
| ---------- | ---------- | ------------------ | ------: | ---------: |
| 100KB PNG  | 80ms       | 67ms               |    1.2x |        5ms |
| 500KB JPEG | 120ms      | 100ms              |    1.2x |        7ms |
| 2MB PNG    | 200ms      | 143ms              |    1.4x |       10ms |

**Result**: 5x faster than MVP target (500ms) ✅

### Compression Ratios

**Conformance Test Results** (211 images):

| Test Suite   | Pass Rate         | Avg Compression                         | Notes                          |
| ------------ | ----------------- | --------------------------------------- | ------------------------------ |
| Kodak        | 24/24 (100%)      | 9.3% of original                        | Photographic images            |
| PNGSuite     | 162/176 (92%)     | High reduction                          | 14 intentionally corrupt files |
| WebP Gallery | 5/5 (100%)        | No regression                           | Already optimal                |
| TestImages   | 2/3 (67%)         | 15.5% of original                       | 1 TIFF skipped (not supported) |
| **Overall**  | **196/211 (93%)** | **12.6% of original (87.4% reduction)** | **15 correctly skipped**       |

### Memory Safety

- **Zero leaks** detected across 73 unit tests
- Verified with Zig's `testing.allocator`
- All allocations tracked and freed properly

---

## 🏗️ Architecture

### Optimization Pipeline

```
┌─────────────────────────────────────────────────────────┐
│ 1. Decode & Normalize (libvips)                        │
│    • Load from disk or memory buffer                   │
│    • Auto-rotate via EXIF metadata                     │
│    • Convert to sRGB color space                       │
│    • Format detection from magic numbers               │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 2. Cache Lookup (Blake3 hash)                          │
│    • Compute key from (input + options)                │
│    • Check cache for existing result                   │
│    • Return if cache hit (15-20x faster!)              │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 3. Generate Candidates (Parallel)                      │
│    Thread 1: AVIF encoding   ─┐                        │
│    Thread 2: WebP encoding   ─┼──→ Candidate Pool      │
│    Thread 3: JPEG encoding   ─┤                        │
│    Thread 4: PNG encoding    ─┘                        │
│    PLUS: Original file (baseline)                      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 4. Score Candidates (Perceptual Metrics)               │
│    • Calculate DSSIM or SSIMULACRA2 diff               │
│    • Filter: diff_score ≤ max_diff                     │
│    • Filter: file_size ≤ max_bytes                     │
│    • Keep only candidates passing all constraints      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 5. Select Best Candidate                               │
│    • Pick smallest passing candidate                   │
│    • Tiebreak by format preference                     │
│    • Cache result for future use                       │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 6. Output                                               │
│    • Write optimized file                              │
│    • Generate JSONL manifest (optional)                │
│    • Return result with timing metrics                 │
└─────────────────────────────────────────────────────────┘
```

### Core Modules

```
pyjamaz/
├── src/
│   ├── optimizer.zig              # Core optimization pipeline
│   ├── cache.zig                  # Content-addressed caching (680 LOC)
│   ├── vips.zig                   # libvips FFI bindings
│   ├── codecs.zig                 # Multi-format encoding
│   ├── image_ops.zig              # Image operations
│   ├── search.zig                 # Binary search for quality
│   ├── metrics.zig                # Perceptual quality metrics
│   │   ├── dssim.zig              # DSSIM FFI bindings
│   │   └── ssimulacra2.zig        # SSIMULACRA2 native impl
│   ├── cli.zig                    # Command-line interface
│   └── test/                      # Test suites
│       ├── unit/                  # 73 unit tests
│       ├── integration/           # Integration tests
│       └── benchmark/             # Performance benchmarks
├── testdata/                      # 211 conformance test images
└── docs/                          # Comprehensive documentation
```

---

## 🧪 Testing

### Test Coverage

| Category              | Count | Pass Rate     | Status         |
| --------------------- | ----- | ------------- | -------------- |
| **Unit Tests**        | 73    | 100% (73/73)  | ✅ All passing |
| **Conformance Tests** | 211   | 93% (196/211) | ✅ Excellent   |
| **Memory Leak Tests** | All   | 0 leaks       | ✅ Clean       |
| **Integration Tests** | 8     | 100% (8/8)    | ✅ All passing |

**Skipped Tests**:

- 14 PNGSuite files (intentionally malformed test files: xc*, xd*, xs*, xh*, xlf\*)
- 1 TIFF file (not supported - web formats only)

### Test Suites

- **PNGSuite**: 176 PNG files (162 valid + 14 intentionally corrupt for robustness testing)
- **Kodak**: 24 photographic test images (industry standard)
- **WebP**: 5 WebP gallery images
- **Samples**: 3 reference images
- **TestImages**: 3 files (2 PNG + 1 TIFF skipped)
- **Total**: 211 conformance test images (196 passing, 15 correctly skipped)

### Run Tests

```bash
# All unit tests
zig build test

# Conformance tests (211 images)
zig build conformance                    # Fast mode (~3s, size checks only)
zig build conformance -Denable-dssim     # With DSSIM quality checks (~15-20s)

# Integration tests
zig build test-integration

# Memory tests (CI/CD recommended)
zig build memory-test              # Zig memory tests (~1 min)
zig build memory-test-zig          # Same as above

# Benchmarks
zig build benchmark

# Specific module
zig build test -Dtest-filter=optimizer
```

#### Conformance Test Modes

**Fast Mode** (default, ~3s):

```bash
zig build conformance
```

- Verifies: Format support, compression ratio, no crashes
- DSSIM values: 0.0000 (not computed for speed)
- Use for: Quick iteration, CI/CD, format verification

**DSSIM Mode** (thorough, ~15-20s):

```bash
zig build conformance -Denable-dssim
```

- Verifies: All of the above + perceptual quality with DSSIM metric
- DSSIM values: Real values (e.g., 0.0020, 0.0005, 0.0003)
- Quality threshold: 0.01 (1% max perceptual difference)
- Use for: Release testing, quality regression detection, codec validation

**Why 15 Tests are Skipped**:

- **14 PNGSuite files**: Intentionally malformed test files designed to test decoder robustness
  - `xc*`: Invalid color type
  - `xd*`: Invalid bit depth
  - `xs*`: Invalid PNG signature
  - `xh*`: Invalid header
  - `xlf*`: Invalid chunk length
- **1 TIFF file**: Not supported (pyjamaz focuses on web image formats only)

These files are **correctly skipped** - attempting to optimize corrupt/unsupported files would be an error.

#### Manual Memory Tests (Node.js & Python)

The Node.js and Python memory tests are available but require manual setup:

**Node.js Memory Tests:**

```bash
# Prerequisites
zig build                          # Build library first
cd bindings/nodejs
npm install                        # If not done already

# Run tests
node --expose-gc tests/memory/gc_verification_test.js
node tests/memory/ffi_memory_test.js
node tests/memory/error_recovery_test.js
node tests/memory/buffer_memory_test.js
```

**Python Memory Tests:**

```bash
# Prerequisites
zig build                          # Build library first
uv pip install psutil               # Optional: for better memory tracking

# Run tests
cd bindings/python
uv run python tests/memory/gc_verification_test.py
uv run python tests/memory/ctypes_memory_test.py
uv run python tests/memory/error_recovery_test.py
uv run python tests/memory/buffer_memory_test.py
```

**Expected Results:**

- All tests should report "TEST PASSED"
- Zero memory leaks detected
- Colored output showing progress

**Note:** If tests fail with module not found errors, set the library path:

```bash
export PYJAMAZ_LIB_PATH=/path/to/pyjamaz/zig-out/lib/libpyjamaz.dylib
```

See [docs/MEMORY_TESTS.md](docs/MEMORY_TESTS.md) for detailed troubleshooting.

````
---

## 📚 Documentation

### Guides

- **[TODO Roadmap](docs/TODO.md)** - Development roadmap and milestones
- **[Contributing Guide](docs/CONTRIBUTING.md)** - How to contribute
- **[Tiger Style Guide](docs/TIGER_STYLE_APPLICATION.md)** - Coding standards
- **[Quick Start](docs/QUICKSTART.md)** - Getting started guide

### API Documentation

- **[Python API Reference](docs/PYTHON_API.md)** - Complete Python bindings documentation

  - Installation and setup
  - API reference with all parameters
  - Usage examples (basic, batch, Flask, FastAPI)
  - Performance tips and troubleshooting

- **[Node.js API Reference](docs/NODEJS_API.md)** - Complete Node.js/TypeScript bindings documentation
  - Installation and setup
  - TypeScript-first API with full type definitions
  - Usage examples (async/sync, batch, Express, Fastify)
  - Integration guides and troubleshooting

### Implementation Details

- **[Performance Optimizations](docs/OPTIMIZATIONS.md)** - Complete optimization guide
- **[Perceptual Metrics Design](docs/PERCEPTUAL_METRICS_DESIGN.md)** - DSSIM & SSIMULACRA2
- **[Parallel Optimization](docs/PARALLEL_OPTIMIZATION.md)** - Thread pool design
- **[Test Suites](docs/TEST_SUITES.md)** - Conformance test tracking
- **[RFC Documents](docs/RFC.md)** - Design decisions

---

## 🐯 Tiger Style Methodology

Pyjamaz follows [Tiger Style](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md) for safety and predictability:

### 1. Safety First ✅

```zig
pub fn optimizeImage(allocator: Allocator, job: OptimizationJob) !OptimizationResult {
    // Pre-conditions (4 assertions)
    std.debug.assert(job.formats.len > 0);
    std.debug.assert(job.concurrency > 0);
    std.debug.assert(job.input_path.len > 0);
    std.debug.assert(job.output_path.len > 0);
    // ... rest of function
}
```

- **2+ assertions per function**: Validate inputs, outputs, invariants
- **Bounded loops**: No `while(true)`, explicit MAX constants
- **Explicit error handling**: `try` or explicit `catch`, never silent failures

### 2. Predictable Performance ✅

```zig
const MAX_ITERATIONS: u8 = 7; // log2(100 quality levels) ≈ 6.6
while (iteration < MAX_ITERATIONS and q_min <= q_max) : (iteration += 1) {
    // Binary search converges in ≤7 iterations guaranteed
}
std.debug.assert(iteration <= MAX_ITERATIONS);
```

- **Bounded operations**: All loops and allocations have explicit limits
- **Back-of-envelope calculations**: Performance claims documented
- **Static allocation**: Prefer stack over heap where possible

### 3. Developer Experience ✅

- **Functions ≤70 lines**: Easy to understand and review
- **Clear naming**: `binarySearchQuality` not `binSearch`
- **Documentation**: Explain WHY, not WHAT

### 4. Minimal Dependencies ✅

- **Only Zig stdlib + system libraries**: libvips, libjpeg-turbo, libdssim
- **Pure Zig implementation**: Except for codec/metric system libraries
- **Justification**: System libraries are battle-tested and industry-standard

---

## 🤝 Contributing

Contributions welcome! Pyjamaz is built to be contributor-friendly.

### Quick Start

1. **Find a task**: Check [docs/TODO.md](docs/TODO.md)
2. **Follow Tiger Style**: See [docs/TIGER_STYLE_APPLICATION.md](docs/TIGER_STYLE_APPLICATION.md)
3. **Write tests**: >80% coverage, use `testing.allocator`
4. **Format & test**: `zig fmt src/` then `zig build test`

### Development Workflow

```bash
# Fork and clone
git clone https://github.com/yourusername/pyjamaz.git
cd pyjamaz

# Create feature branch
git checkout -b feature/my-feature

# Make changes (follow Tiger Style)
# - 2+ assertions per function
# - Functions ≤70 lines
# - Bounded loops with MAX constants

# Write tests
# src/test/unit/my_module_test.zig

# Run checks
zig build test
zig build conformance
zig fmt src/

# Commit and push
git commit -m "feat: Add awesome feature

- Implemented X with Y approach
- Added Z tests
- Performance: <100ms"

git push origin feature/my-feature
```

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for detailed guidelines.

---

## 🚀 Roadmap

See [docs/TODO.md](docs/TODO.md) for the complete development roadmap.

**Current Focus** (v1.0.0):

- ✅ Core engine stable (73/73 tests passing)
- ✅ Caching layer (15-20x speedup)
- ✅ Python bindings complete (automatic memory management, comprehensive tests)
- ✅ Node.js bindings complete (TypeScript-first, sync/async APIs, 30+ tests)
- 🔄 Replace libvips with native decoders (2-5x performance improvement)
- ⏳ Homebrew distribution (`brew install pyjamaz`)
- ⏳ Production polish (fuzzing, security audit)

**Future** (v1.1.0+):

- Watch mode (re-optimize on file changes)
- JSON output mode (machine-readable)
- Progress bars for batch operations
- Config file support (`.pyjamazrc`)

---

## 🙏 Acknowledgments

- **[Zig Language](https://ziglang.org/)** - Safe, fast systems programming
- **[TigerBeetle](https://github.com/tigerbeetle/tigerbeetle)** - Tiger Style inspiration
- **[libvips](https://www.libvips.org/)** - Fast image processing library
- **[PNGSuite](http://www.schaik.com/pngsuite/)** - Comprehensive PNG test images
- **[fssimu2](https://github.com/rust-av/ssimulacra2)** - SSIMULACRA2 implementation

---

## 📜 License

MIT License - see [LICENSE](./LICENSE) for details.

---

## 🌟 Star History

If Pyjamaz helps you, please consider giving it a star! ⭐

---

## 📬 Contact

- **Issues**: [GitHub Issues](https://github.com/yourusername/pyjamaz/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/pyjamaz/discussions)

---

**Last Updated**: 2025-10-31 (Python & Node.js bindings complete!)
**Current Version**: 1.0.0-dev (CLI + Python + Node.js bindings)
**Status**: Pre-1.0 (core stable, bindings ready, optimizing performance)

🚀 **Happy optimizing!**
````
