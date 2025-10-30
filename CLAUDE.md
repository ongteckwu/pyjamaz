# Golden OSS - Zig Project Template

**Purpose**: A production-ready template for building high-quality Zig open-source projects with best practices built-in.

**Language**: Zig 0.15.0+
**Methodology**: Tiger Style (safety-first, predictable performance)

---

## Quick Start

This is a **template repository**. To use it for your project:

1. **Clone this template**:
   ```bash
   git clone https://github.com/yourusername/golden-oss.git my-project
   cd my-project
   ```

2. **Customize for your project**:
   - Replace `[Project Name]` in all documentation
   - Update `README.md` with your project description
   - Modify `build.zig` for your build needs
   - Add your source code to `src/`

3. **Build and test**:
   ```bash
   zig build        # Build your project
   zig build test   # Run tests
   zig fmt src/     # Format code
   ```

---

## Documentation Map

This template includes comprehensive documentation organized by purpose:

### 📖 For Users
- **[README.md](./README.md)** - Start here! User-facing documentation, features, quick start

### 🛠️ For Contributors
- **[docs/CONTRIBUTING.md](./docs/CONTRIBUTING.md)** - How to contribute, PR process, coding standards
- **[docs/TODO.md](./docs/TODO.md)** - Project roadmap, current tasks, progress tracking

### 🏗️ For Developers
- **[src/CLAUDE.md](./src/CLAUDE.md)** - Implementation patterns, memory management, Tiger Style examples
- **[docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)** - System design, module structure, data flow
- **[docs/TESTING_STRATEGY.md](./docs/TESTING_STRATEGY.md)** - Test organization, patterns, coverage

### 📋 Coding Standards
- **[docs/TIGER_STYLE_GUIDE.md](./docs/TIGER_STYLE_GUIDE.md)** - Safety-first methodology for Zig

---

## Project Structure

```
your-project/
├── CLAUDE.md              # This file - Navigation hub
├── README.md              # User documentation
├── build.zig              # Build configuration
├── src/
│   ├── main.zig          # Entry point
│   ├── CLAUDE.md         # Implementation guide
│   ├── [your-modules]/   # Your source code
│   └── test/             # All tests
│       ├── unit/         # Unit tests (mirror src/ structure)
│       ├── integration/  # Integration tests
│       └── benchmark/    # Performance tests
├── docs/                  # Documentation
│   ├── TODO.md           # Task tracking
│   ├── ARCHITECTURE.md   # System design
│   ├── CONTRIBUTING.md   # Contribution guidelines
│   ├── TESTING_STRATEGY.md  # Testing approach
│   └── TIGER_STYLE_GUIDE.md  # Coding standards
└── testdata/             # Test fixtures (NOT test code)
```

### Key Principles

1. **Tests in `src/test/`** - Tests alongside source code
2. **Test data in `testdata/`** - Fixtures separate from code
3. **Docs in `docs/`** - Centralized documentation
4. **One test file per source file** - Mirror directory structure

---

## Core Principles (Tiger Style)

This template follows **Tiger Style** methodology:

1. **Safety First**
   - 2+ assertions per function
   - Bounded loops (no infinite loops)
   - Explicit error handling

2. **Predictable Performance**
   - Static allocation where possible
   - O(n) performance guarantees
   - Back-of-envelope calculations documented

3. **Developer Experience**
   - Functions ≤70 lines
   - Clear, descriptive naming
   - 100-column line limit

4. **Zero Dependencies**
   - Only Zig standard library
   - Exceptions must be documented and justified

**See [docs/TIGER_STYLE_GUIDE.md](./docs/TIGER_STYLE_GUIDE.md) for detailed guidelines.**

---

## Quick Commands

```bash
# Format code
zig fmt src/

# Build project
zig build

# Run tests
zig build test

# Run specific test
zig build test -Dtest-filter=MyModule

# Clean build artifacts
rm -rf zig-out/ zig-cache/
```

---

## Development Workflow

### Before Writing Code

1. Check [docs/TODO.md](./docs/TODO.md) for current tasks
2. Review [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) for system design
3. Read [src/CLAUDE.md](./src/CLAUDE.md) for implementation patterns
4. Review [docs/TIGER_STYLE_GUIDE.md](./docs/TIGER_STYLE_GUIDE.md) for coding standards

### While Writing Code

1. Write assertions first (pre-conditions, post-conditions, invariants)
2. Use explicit types (`u32`, not `usize` unless necessary)
3. Keep functions under 70 lines
4. Add comments explaining **WHY**, not WHAT
5. Run `zig fmt` continuously

### After Writing Code

1. **Write unit tests** in `src/test/unit/` mirroring source structure
2. Run `zig build test` - all tests must pass
3. Run `zig fmt src/` - ensure consistent formatting
4. Update documentation if API changed
5. Update [docs/TODO.md](./docs/TODO.md) to check off completed tasks

---

## Testing Requirements

- **Unit Tests**: Every public function (target >80% coverage)
- **Integration Tests**: End-to-end workflows
- **Benchmark Tests**: Performance-critical paths
- **Memory Safety**: No leaks (verified with `testing.allocator`)

**See [docs/TESTING_STRATEGY.md](./docs/TESTING_STRATEGY.md) for detailed testing approach.**

---

## Type Conventions

```zig
// ✅ GOOD: Explicit types
const item_count: u32 = 100;
const index: u32 = 0;

// ❌ AVOID: Architecture-dependent sizes (unless truly needed)
const count: usize = 100;  // Changes between 32/64 bit
```

**Rationale**: Use `u32` for counts/indices (4GB limit acceptable for most use cases). Only use `usize` when required for memory addresses or stdlib APIs.

---

## Error Handling

```zig
// ✅ GOOD: Explicit propagation
const result = try riskyOperation();

// ✅ GOOD: Explicit handling
const result = riskyOperation() catch |err| {
    log.err("Operation failed: {}", .{err});
    return error.OperationFailed;
};

// ⚠️ USE SPARINGLY: Only with proof it can't fail
const result = infallibleOp() catch unreachable;

// ❌ BAD: Silent failure
const result = riskyOperation() catch null;
```

---

## Resources

### Documentation
- All project docs are in `docs/` directory
- Implementation guidance in `src/CLAUDE.md`
- Start with `README.md` for overview

### Zig Resources
- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Zig Build System](https://ziglang.org/learn/build-system/)

### Tiger Style
- [Tiger Style Guide](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md)
- [docs/TIGER_STYLE_GUIDE.md](./docs/TIGER_STYLE_GUIDE.md) - Applied to this template

---

## Getting Help

- **Documentation**: Check `docs/` directory first
- **Issues**: [GitHub Issues](https://github.com/yourusername/your-project/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/your-project/discussions)

---

## Template Usage Notes

### What to Customize

1. **README.md**: Replace with your project description
2. **build.zig**: Configure for your build needs
3. **src/main.zig**: Your entry point
4. **docs/TODO.md**: Your project milestones
5. **docs/ARCHITECTURE.md**: Your system design

### What to Keep

1. **File organization** (src/, docs/, tests/)
2. **Tiger Style principles** (safety, performance, DX)
3. **Documentation templates** (structure and format)
4. **Testing patterns** (unit, integration, benchmarks)

### How to Use This Template

1. Fork/clone this repository
2. Search and replace `[Project Name]` with your project name
3. Update all `[placeholders]` in docs with actual values
4. Delete example code, keep structure
5. Start building!

---

**Last Updated**: 2025-10-28
**Template Version**: 1.0.0

**This is a living template** - improve it as you discover better patterns!
- whenever finishing a todo task, update docs/TODO.md