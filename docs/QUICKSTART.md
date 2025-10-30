# Pyjamaz Quick Start

**Status**: MVP Foundation in Progress
**Last Updated**: 2025-10-30

## What's Been Built So Far

Pyjamaz is now at **Milestone 0.1.0 Phase 1-2** completion. Here's what's ready:

### ✅ Completed Infrastructure

#### 1. Build System (`build.zig`)
- Configured for Zig 0.15.1
- C library integration placeholders (libvips, mozjpeg, libpng, libwebp)
- Test runner configured
- Build commands working

#### 2. Project Structure
```
pyjamaz/
├── src/
│   ├── main.zig              # Entry point
│   ├── cli.zig               # Argument parser
│   └── types/
│       ├── image_buffer.zig  # Raw pixel data storage
│       └── image_metadata.zig # Format/EXIF/ICC metadata
├── src/test/
│   ├── unit/                 # Unit tests (empty)
│   ├── integration/          # Integration tests (empty)
│   └── benchmark/            # Benchmarks (empty)
├── testdata/conformance/
│   ├── kodak/                # Kodak test suite
│   ├── pngsuite/             # PNG Suite
│   ├── webp/                 # WebP gallery
│   └── testimages/           # Standard test images
└── docs/scripts/
    └── download_testdata.sh  # Test data downloader
```

#### 3. Core Data Structures

**ImageBuffer** (`src/types/image_buffer.zig`)
- Raw pixel storage (RGB/RGBA)
- Memory-safe operations (bounds checking)
- Tiger Style compliant (2+ assertions, explicit types)
- Full test coverage (6/6 tests passing)

**ImageMetadata** (`src/types/image_metadata.zig`)
- Format detection (JPEG, PNG, WebP, AVIF)
- EXIF orientation handling
- ICC profile storage
- Full test coverage (8/8 tests passing)

**CLI Parser** (`src/cli.zig`)
- Complete argument parsing
- Input/output configuration
- Format selection
- Perceptual quality settings
- Full test coverage (4/4 tests passing)

### 📊 Test Results

```
Build Summary: 18/18 tests passed
✅ ImageBuffer: 6 tests
✅ ImageMetadata: 8 tests
✅ CLI: 4 tests
✅ Memory leak checks: All passing
```

## Quick Commands

### Build & Test
```bash
# Run all tests
zig build test

# Build executable
zig build

# Run CLI (currently stub)
./zig-out/bin/pyjamaz --help
./zig-out/bin/pyjamaz --version
./zig-out/bin/pyjamaz test.jpg --verbose --max-kb 100
```

### Download Test Data
```bash
# Download conformance test suites
./docs/scripts/download_testdata.sh

# This will fetch:
# - Kodak Image Suite (24 images)
# - PNG Suite (comprehensive PNG test cases)
# - WebP Gallery (sample images)
```

### Format Code
```bash
zig fmt src/
```

## What Works Right Now

1. **CLI Argument Parsing**: All flags recognized and validated
2. **Core Data Structures**: Ready for image processing pipeline
3. **Test Infrastructure**: Unit test framework operational
4. **Build System**: Clean compilation with Zig 0.15.1

## What Doesn't Work Yet

- ❌ Image decoding (libvips integration pending)
- ❌ Image encoding (codec integration pending)
- ❌ Perceptual metrics (Butteraugli/DSSIM pending)
- ❌ Optimization pipeline (not implemented)
- ❌ File I/O (no actual image processing)

## Next Steps (Milestone 0.1.0)

According to `docs/TODO.md`, these are the immediate next tasks:

### Phase 3: libvips Integration
- Create `src/vips.zig` FFI wrapper
- Implement image decode/normalize
- Implement resize operations

### Phase 4: Codec Integration
- JPEG encoder (mozjpeg)
- PNG encoder (libpng/pngquant)
- Basic binary search for size targeting

### Phase 5: Optimization Pipeline
- Single-image optimizer
- Candidate generation
- Output file writing

## Development Workflow

### Before Writing Code
1. Check `docs/TODO.md` for current phase
2. Review `docs/ARCHITECTURE.md` (to be updated)
3. Read `src/CLAUDE.md` for patterns
4. Follow `docs/TIGER_STYLE_GUIDE.md`

### While Writing Code
1. Write assertions first (pre/post conditions)
2. Use `u32` for counts (not `usize`)
3. Keep functions under 70 lines
4. Run `zig fmt` continuously

### After Writing Code
1. Write unit tests (mirror src/ structure)
2. Run `zig build test`
3. Verify no memory leaks
4. Update documentation

## Tiger Style Compliance

All code follows Tiger Style:
- ✅ 2+ assertions per function
- ✅ Explicit types (u32, not usize)
- ✅ Bounded loops/operations
- ✅ Functions ≤70 lines
- ✅ Memory safety (testing.allocator checks)

## Architecture Highlights

### ImageBuffer Design
- Owns its pixel data (RAII pattern)
- Stride-aware for efficient row access
- Color space tracking
- Deep copy support

### ImageMetadata Design
- Format-agnostic structure
- Optional ICC profile management
- EXIF orientation normalization
- Memory-safe ICC profile storage

### CLI Design
- Zero-copy string handling
- Exhaustive flag validation
- Sensible defaults
- Error messages with help text

## Example Usage (Future)

Once the MVP is complete, usage will look like:

```bash
# Basic optimization
pyjamaz image.jpg

# With constraints
pyjamaz --max-kb 100 --max-diff 1.0 --formats avif,webp image.jpg

# Batch processing
pyjamaz images/*.jpg --out ./optimized --resize 1920x1080

# Generate manifest
pyjamaz images/ --manifest report.jsonl --verbose
```

## Contributing

See `docs/CONTRIBUTING.md` for:
- Code review standards
- PR process
- Testing requirements

## Performance Targets

| Operation           | Target     | Status |
|---------------------|------------|--------|
| Optimize 1 image    | <500ms     | ⚪ TBD  |
| Optimize 100 images | <10s (8c)  | ⚪ TBD  |
| Memory per image    | <100MB     | ⚪ TBD  |

## Known Issues

- C library dependencies are commented out in `build.zig` (will fail to link until installed)
- No actual image processing yet (MVP foundation only)

## Resources

- Full roadmap: `docs/TODO.md`
- Architecture: `docs/ARCHITECTURE.md` (to be updated)
- Tiger Style: `docs/TIGER_STYLE_GUIDE.md`
- Testing: `docs/TESTING_STRATEGY.md`

---

**Ready to contribute?** Pick a task from `docs/TODO.md` Phase 3 and start building!
