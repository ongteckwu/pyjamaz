# Pyjamaz Quick Start Guide

## What is Pyjamaz?

Pyjamaz is a **Zig-powered, budget-aware, perceptual-guarded image optimizer** that:

- 🎯 **Tries multiple formats**: AVIF, WebP, JPEG, PNG
- 📦 **Hits byte budgets**: Automatically targets file size limits
- 👁️ **Guards quality**: Uses Butteraugli/DSSIM perceptual metrics
- 🚀 **Ships as single binary**: Cross-platform, no dependencies
- 🌐 **Optional HTTP mode**: Run as optimization service

## Project Status

**Current Status**: Planning Phase (TODO created, RFC refined)

**Next Steps**:
1. Set up build.zig with C dependencies (libvips, mozjpeg, libpng)
2. Download conformance test suites
3. Implement core data structures

See [docs/TODO.md](./TODO.md) for detailed roadmap.

## Documentation Map

### For Users
- **[README.md](../README.md)** - Overview and installation (coming soon)
- **[docs/QUICKSTART.md](./QUICKSTART.md)** - This file!

### For Developers
- **[docs/RFC.md](./RFC.md)** - Full design specification and rationale
- **[docs/TODO.md](./TODO.md)** - Detailed implementation roadmap
- **[docs/ARCHITECTURE.md](./ARCHITECTURE.md)** - System design (coming soon)
- **[CLAUDE.md](../CLAUDE.md)** - Project navigation hub

### For Contributors
- **[docs/CONTRIBUTING.md](./CONTRIBUTING.md)** - Contribution guidelines (coming soon)
- **[docs/TIGER_STYLE_GUIDE.md](./TIGER_STYLE_GUIDE.md)** - Coding standards

## Development Setup

### Prerequisites

- **Zig 0.15.0+** - [Download here](https://ziglang.org/download/)
- **C libraries** (will be added to build.zig):
  - libvips (image processing)
  - mozjpeg (JPEG encoding)
  - libpng/pngquant (PNG encoding)
  - libwebp (WebP encoding)
  - libavif (AVIF encoding)
  - butteraugli (perceptual metrics)

### Clone the Repository

```bash
git clone https://github.com/yourusername/pyjamaz.git
cd pyjamaz
```

### Build (Coming Soon)

```bash
zig build        # Build the binary
zig build test   # Run unit tests
zig build conformance  # Run conformance tests (after downloading test data)
```

### Download Test Data

Conformance tests require ~150MB of standard image test suites:

```bash
./docs/scripts/download_testdata.sh
```

This downloads:
- Kodak Image Suite (24 photographic images)
- PNG Suite (edge cases)
- WebP Gallery (reference images)
- TESTIMAGES (standard test images)

## Roadmap Overview

### Milestone 0.1.0 - MVP (Current)
- Core CLI functionality
- libvips integration
- JPEG + PNG codecs
- Basic size targeting
- Conformance tests

### Milestone 0.2.0 - Perceptual Quality
- All 4 codecs (AVIF, WebP, JPEG, PNG)
- Butteraugli perceptual metrics
- Dual-constraint validation (size + quality)
- Enhanced manifest output

### Milestone 0.3.0 - Advanced Features
- HTTP mode
- Caching layer
- Config file support
- Animation support
- Content-aware heuristics

### Milestone 1.0.0 - Production Ready
- API stabilization
- Security audit
- >90% test coverage
- Cross-platform releases
- Complete documentation

See [docs/TODO.md](./TODO.md) for detailed breakdown.

## Design Principles

### Tiger Style (Safety-First)

Pyjamaz follows [Tiger Style](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md) methodology:

1. **Safety First**
   - 2+ assertions per function
   - Bounded loops (no infinite loops)
   - Explicit error handling

2. **Predictable Performance**
   - Use `u32` for counts (not `usize`)
   - O(n) guarantees documented
   - No unbounded allocations

3. **Developer Experience**
   - Functions ≤70 lines
   - Clear naming (no abbreviations)
   - Comments explain WHY, not WHAT

See [docs/TIGER_STYLE_GUIDE.md](./TIGER_STYLE_GUIDE.md) for full guidelines.

### Architecture Philosophy

```
Input Image(s)
      ↓
  Decode & Normalize (libvips)
      ↓
  Generate Candidates (parallel)
    ├─ AVIF encoder
    ├─ WebP encoder
    ├─ JPEG encoder
    └─ PNG encoder
      ↓
  Score Candidates (perceptual metrics)
      ↓
  Select Best (smallest passing both constraints)
      ↓
  Write Output + Manifest
```

Key constraints:
- `bytes <= max_bytes` (budget)
- `diff <= max_diff` (perceptual quality)

See [docs/RFC.md](./RFC.md) for detailed pipeline design.

## Testing Strategy

### Test Organization

```
src/test/
├── unit/              # Unit tests (mirror src/ structure)
├── integration/       # End-to-end tests
├── benchmark/         # Performance tests
└── conformance_runner.zig  # Conformance test harness
```

### Test Data

```
testdata/
├── conformance/       # Downloaded test suites
│   ├── kodak/        # Kodak Image Suite
│   ├── pngsuite/     # PNG edge cases
│   ├── webp/         # WebP gallery
│   └── testimages/   # Standard test images
└── golden/           # Expected outputs (version snapshots)
```

### Running Tests

```bash
# Unit tests
zig build test

# Integration tests
zig build test -Dtest-filter=integration

# Conformance tests (after downloading test data)
zig build conformance

# Benchmarks
zig build benchmark
```

## Contributing

We welcome contributions! Before starting:

1. Read [docs/CONTRIBUTING.md](./CONTRIBUTING.md) (coming soon)
2. Check [docs/TODO.md](./TODO.md) for open tasks
3. Review [docs/TIGER_STYLE_GUIDE.md](./TIGER_STYLE_GUIDE.md) for coding standards
4. Read [docs/RFC.md](./RFC.md) for design context

### Good First Issues

Look for tasks marked "⚪ Not Started" in [docs/TODO.md](./TODO.md). Examples:
- Implement core data structures (Phase 2)
- Create unit tests for existing modules
- Improve documentation

### Development Workflow

1. Create branch: `git checkout -b feature/my-feature`
2. Write code following Tiger Style
3. Write tests (unit + integration)
4. Run `zig fmt src/` to format
5. Ensure `zig build test` passes
6. Update [docs/TODO.md](./TODO.md) to mark tasks complete
7. Submit PR with clear description

## Questions?

- **Design decisions**: See [docs/RFC.md](./RFC.md) §27 (Implementation Notes)
- **Roadmap**: See [docs/TODO.md](./TODO.md)
- **Architecture**: See [docs/ARCHITECTURE.md](./ARCHITECTURE.md) (coming soon)
- **Coding standards**: See [docs/TIGER_STYLE_GUIDE.md](./TIGER_STYLE_GUIDE.md)
- **Issues**: [GitHub Issues](https://github.com/yourusername/pyjamaz/issues)

---

**Status**: ⚪ Not Started (planning phase)

**Next Milestone**: 0.1.0 MVP

**Last Updated**: 2025-10-28
