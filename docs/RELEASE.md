# Pyjamaz Release Process

**Last Updated**: 2025-11-01
**Current Version**: 0.9.x (pre-release)
**Target Version**: 1.0.0

This document outlines the human-intervention steps required to publish Pyjamaz to PyPI and npm after automated builds complete.

---

## Quick Reference: Build & Test Scripts

Before diving into the release process, here are the key scripts and commands:

| Task                  | Script                              | Location     | Output                  |
| --------------------- | ----------------------------------- | ------------ | ----------------------- |
| Build Python wheel    | `./scripts/build-python-wheel.sh`   | Project root | `dist/*.whl`            |
| Build Node.js package | `./scripts/build-nodejs-package.sh` | Project root | `bindings/nodejs/*.tgz` |
| Test Python wheel     | See Phase 1.2                       | -            | Smoke tests + examples  |
| Test Node.js package  | See Phase 2.2                       | -            | Smoke tests + 30+ tests |

**Test Files Included**:

**Python**:

- `bindings/python/tests/test_pyjamaz.py` - Main test suite (unit tests)
- `bindings/python/tests/memory/` - Memory safety tests:
  - `buffer_memory_test.py` - Buffer handling
  - `ctypes_memory_test.py` - ctypes FFI memory
  - `error_recovery_test.py` - Error handling
  - `gc_verification_test.py` - Garbage collection
- `bindings/python/examples/basic.py` - Simple usage example
- `bindings/python/examples/batch.py` - Batch processing example
- `bindings/python/examples/test_bundled_package.py` - **Comprehensive bundled package test** ⭐

**Node.js**:

- `bindings/nodejs/tests/index.test.ts` - Main test suite (30+ tests)
- `bindings/nodejs/tests/memory/` - Memory safety tests:
  - `buffer_memory_test.js` - Buffer handling
  - `ffi_memory_test.js` - FFI memory management
  - `error_recovery_test.js` - Error handling
  - `gc_verification_test.js` - Garbage collection
- `bindings/nodejs/examples/basic.ts` - TypeScript example
- `bindings/nodejs/examples/basic.js` - JavaScript example
- `bindings/nodejs/examples/batch.ts` - Batch processing example
- `bindings/nodejs/examples/test-bundled-package.ts` - **Comprehensive bundled package test** ⭐

---

## Prerequisites

Before starting the release process, ensure:

- ✅ All tests pass (`zig build test` - 126/127 tests, 99.2%)
- ✅ Static linking complete (only libavif.dylib dependency)
- ✅ Platform-specific wheels/packages built (use scripts above)
- ✅ Documentation updated (README, CHANGELOG, migration guides)
- ✅ Version numbers bumped in all relevant files
- ✅ **Local testing complete** (Python wheel + Node.js package)

**Pre-Release Checklist**:

```bash
# 1. Build and test Python wheel locally
./scripts/build-python-wheel.sh
# Follow Phase 1.2 for testing

# 2. Build and test Node.js package locally
./scripts/build-nodejs-package.sh
# Follow Phase 2.2 for testing

# 3. Verify all tests pass
zig build test

# 4. Check version consistency
grep -r "version.*1.0.0" bindings/python/pyproject.toml bindings/nodejs/package.json
```

---

## Phase 1: Python Distribution (PyPI)

### 1.0 Build Wheels Locally (Optional)

Before using CI/CD, you can build and test wheels locally:

```bash
# Build wheel using our custom script
./scripts/build-python-wheel.sh

# This script will:
# 1. Build the Zig library (zig build)
# 2. Verify libavif dependency exists
# 3. Bundle libpyjamaz.dylib + libavif.16.dylib
# 4. Create platform-specific wheel in dist/
# 5. Show installation instructions
```

**Output**: Wheel file in `dist/` directory (e.g., `pyjamaz-1.0.0-py3-none-macosx_11_0_arm64.whl`)

### 1.1 Verify Wheel Builds

After CI/CD completes (or local build), verify wheels were built for all platforms:

```bash
ls -lh dist/
# Should see:
# pyjamaz-1.0.0-cp38-abi3-macosx_11_0_x86_64.whl    (macOS Intel)
# pyjamaz-1.0.0-cp38-abi3-macosx_11_0_arm64.whl     (macOS Apple Silicon)
# pyjamaz-1.0.0-cp38-abi3-manylinux2014_x86_64.whl  (Linux x86_64)
```

### 1.2 Test Wheels Locally

**CRITICAL**: Test on a clean system WITHOUT Homebrew dependencies to verify bundled libraries work.

**Test Script**: `bindings/python/tests/test_installation.py` (included in repo)

```bash
# macOS (current platform)
uv venv test-env
source test-env/bin/activate
uv pip install dist/pyjamaz-*.whl

# Run basic smoke test
uv run python -c "import pyjamaz; print('Version:', pyjamaz.get_version())"

# ⭐ RECOMMENDED: Run comprehensive bundled package test
uv run python bindings/python/examples/test_bundled_package.py
# This single script tests:
# - Import and version
# - Library location and bundling
# - Basic optimization
# - All format support (JPEG, PNG, WebP, AVIF)
# - Error handling
# - No Homebrew dependencies

# Run individual example scripts
uv run python bindings/python/examples/basic.py
uv run python bindings/python/examples/batch.py

# Run full test suite
cd bindings/python
uv run python -m pytest tests/ -v
cd ../..

# Cleanup
deactivate
rm -rf test-env
```

**What to verify**:

- ✅ Installation completes without errors
- ✅ No "library not found" errors (bundled libs work)
- ✅ Version prints correctly
- ✅ Examples run successfully
- ✅ No Homebrew dependencies required

**If tests fail**: Check `bindings/python/pyjamaz/__init__.py` library search paths

### 1.3 Upload to Test PyPI

First, test the release process on Test PyPI:

```bash
# Install twine if not already installed
uv pip install twine

# Upload to Test PyPI
twine upload --repository testpypi dist/*

# Test installation from Test PyPI
uv pip install --index-url https://test.pypi.org/simple/ pyjamaz
```

### 1.4 Upload to Production PyPI

**⚠️ WARNING**: This step is irreversible. Once published, versions cannot be deleted.

```bash
# Upload to production PyPI
twine upload dist/*

# Verify installation
uv pip install pyjamaz
uv run python -c "import pyjamaz; print(pyjamaz.__version__)"
```

### 1.5 Create PyPI Release Notes

Go to https://pypi.org/project/pyjamaz/ and add release notes:

- Link to GitHub release
- Highlight key features
- Note platform support (macOS Intel/ARM, Linux x86_64)
- Include migration guide link

---

## Phase 2: Node.js Distribution (npm)

### 2.0 Build Package Locally (Optional)

Before using CI/CD, you can build and test packages locally:

```bash
# Build package using our custom script
./scripts/build-nodejs-package.sh

# This script will:
# 1. Build the Zig library (zig build)
# 2. Detect platform and architecture
# 3. Bundle libpyjamaz + libavif into native/ directory
# 4. Build TypeScript (npm run build)
# 5. Create tarball (npm pack)
```

**Output**: Tarball in `bindings/nodejs/` (e.g., `pyjamaz-1.0.0.tgz`)

### 2.1 Verify Package Builds

After CI/CD completes (or local build), verify platform-specific packages:

```bash
# Local build
ls -lh bindings/nodejs/pyjamaz-*.tgz

# CI/CD artifacts (downloaded from GitHub Actions)
ls -lh packages/
# Should see subdirectories:
# packages/package-darwin-x64/pyjamaz-1.0.0.tgz
# packages/package-darwin-arm64/pyjamaz-1.0.0.tgz
# packages/package-linux-x64/pyjamaz-1.0.0.tgz
```

### 2.2 Test Packages Locally

**CRITICAL**: Test on a clean system WITHOUT Homebrew dependencies to verify bundled libraries work.

**Test Files Available**:

- `bindings/nodejs/tests/index.test.ts` - Comprehensive test suite
- `bindings/nodejs/examples/basic.ts` - Basic usage example
- `bindings/nodejs/examples/batch.ts` - Batch processing example

```bash
# Test local build
cd bindings/nodejs

# Install the package
npm install ./pyjamaz-1.0.0.tgz

# Run basic smoke test
node -e "const { version } = require('pyjamaz'); console.log('Version:', version())"

# ⭐ RECOMMENDED: Run comprehensive bundled package test
npx ts-node examples/test-bundled-package.ts
# This single script tests:
# - Import and version
# - Library location and bundling
# - Basic optimization
# - All format support (JPEG, PNG, WebP, AVIF)
# - Error handling
# - Memory management (10 iterations)
# - No Homebrew dependencies

# Run individual example scripts
npx ts-node examples/basic.ts  # TypeScript version
node examples/basic.js          # JavaScript version
npx ts-node examples/batch.ts   # Batch processing

# Run comprehensive test suite (30+ tests)
npm test

# Optional: Run memory safety tests individually
node tests/memory/buffer_memory_test.js
node tests/memory/ffi_memory_test.js
node tests/memory/error_recovery_test.js
node tests/memory/gc_verification_test.js

# Cleanup
npm uninstall pyjamaz
```

**What to verify**:

- ✅ Installation completes without errors
- ✅ Post-install script verifies bundled binaries
- ✅ No "library not found" errors
- ✅ Version prints correctly
- ✅ Examples run successfully
- ✅ Tests pass (30+ tests)
- ✅ No Homebrew dependencies required

**If tests fail**:

- Check `bindings/nodejs/src/bindings.ts` library search paths
- Verify `native/` directory contains libpyjamaz and libavif
- Check `install.js` output for warnings

### 2.3 Publish to npm (Scoped Test)

First, publish under a test scope to verify the process:

```bash
# Login to npm
npm login

# Publish platform-specific packages (test scope)
cd npm-packages
npm publish pyjamaz-darwin-x64-1.0.0.tgz --tag beta
npm publish pyjamaz-darwin-arm64-1.0.0.tgz --tag beta
npm publish pyjamaz-linux-x64-1.0.0.tgz --tag beta

# Publish main package
npm publish pyjamaz-1.0.0.tgz --tag beta

# Test installation
npm install pyjamaz@beta
```

### 2.4 Publish to npm (Production)

**⚠️ WARNING**: This step is irreversible. Once published, versions cannot be deleted.

```bash
# Publish platform-specific packages
npm publish pyjamaz-darwin-x64-1.0.0.tgz
npm publish pyjamaz-darwin-arm64-1.0.0.tgz
npm publish pyjamaz-linux-x64-1.0.0.tgz

# Publish main package
npm publish pyjamaz-1.0.0.tgz

# Verify installation
npm install pyjamaz
node -e "const pyjamaz = require('pyjamaz'); console.log(pyjamaz.version)"
```

### 2.5 Add npm Tags

Set appropriate dist-tags:

```bash
# Mark as latest stable release
npm dist-tag add pyjamaz@1.0.0 latest

# Verify tags
npm dist-tag ls pyjamaz
```

---

## Phase 3: GitHub Release

### 3.1 Create Git Tag

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release 1.0.0 - Standalone Distribution"

# Push tag to remote
git push origin v1.0.0
```

### 3.2 Create GitHub Release

Go to https://github.com/yourusername/pyjamaz/releases/new and:

1. **Tag**: Select `v1.0.0`
2. **Title**: `v1.0.0 - Standalone Distribution`
3. **Description**: Include the following sections:

````markdown
## 🎉 Pyjamaz 1.0.0 - Production Ready!

After [X weeks] of development, Pyjamaz is now production-ready with standalone installation!

### ✨ Highlights

- **Zero Prerequisites**: `uv pip install pyjamaz` or `npm install pyjamaz` works immediately
- **Native Performance**: 2-5x faster with native codecs (JPEG, PNG, WebP, AVIF)
- **Self-Contained**: Static linking, no runtime dependencies
- **Multi-Platform**: macOS (Intel/ARM), Linux x86_64

### 📦 Installation

**Python**:

```bash
uv pip install pyjamaz
```
````

**Node.js**:

```bash
npm install pyjamaz
```

**CLI** (Homebrew):

```bash
brew install pyjamaz  # Coming soon
```

### 🚀 Quick Start

**Python**:

```bash
uv run python
```

```python
import pyjamaz
result = pyjamaz.optimize_image("input.jpg", max_bytes=100_000)
```

**Node.js**:

```javascript
const pyjamaz = require("pyjamaz");
const result = pyjamaz.optimizeImage("input.jpg", { maxBytes: 100000 });
```

**CLI**:

```bash
pyjamaz input.jpg -o output.jpg --max-bytes 100KB
```

### 📊 What's New

- Native codec integration (replaces libvips)
- Platform-specific wheels and npm packages
- Static linking (minimal dependencies)
- Comprehensive test suite (126/127 tests, 99.2%)
- Complete documentation overhaul

### 🔗 Links

- [Migration Guide](docs/MIGRATION.md)
- [Python Documentation](bindings/python/README.md)
- [Node.js Documentation](bindings/node/README.md)
- [Changelog](docs/CHANGELOG.md)

### 🙏 Acknowledgments

Built with Zig 0.15.1 following Tiger Style principles.

---

**Full Changelog**: https://github.com/yourusername/pyjamaz/compare/v0.9.0...v1.0.0

````

4. **Attach Binaries**: Upload the following artifacts:
   - All Python wheels from `dist/`
   - All npm packages from `npm-packages/`
   - CLI binary (if standalone CLI release)
   - Checksums file (SHA256SUMS.txt)

5. **Publish Release**

---

## Phase 4: Post-Release Tasks

### 4.1 Update Documentation Sites

If you have a documentation site (e.g., readthedocs, GitHub Pages):

1. Trigger documentation rebuild for v1.0.0
2. Update "latest" symlink to point to v1.0.0
3. Verify all examples work with new version

### 4.2 Announce Release

Post announcements on:

- [ ] Project README (update badges, latest version)
- [ ] GitHub Discussions (release announcement thread)
- [ ] Twitter/X (if applicable)
- [ ] Reddit (r/programming, r/rust, r/zig - if applicable)
- [ ] Hacker News (Show HN: if applicable)
- [ ] Dev.to / Hashnode (blog post if applicable)

### 4.3 Monitor Initial Feedback

For the first 48 hours after release:

- [ ] Monitor PyPI download stats
- [ ] Monitor npm download stats
- [ ] Watch GitHub issues for installation problems
- [ ] Check CI/CD for any platform-specific failures
- [ ] Respond to user questions promptly

### 4.4 Prepare Hotfix Plan

If critical bugs are discovered:

1. **Severity Assessment**: Determine if hotfix release (1.0.1) is needed
2. **Branch Strategy**: Create `hotfix/1.0.1` branch from `v1.0.0` tag
3. **Fix & Test**: Apply minimal fix, verify all tests pass
4. **Release**: Follow abbreviated release process (no announcement needed)

---

## Troubleshooting

### Common Issues During Testing

#### Python Wheel Issues

**Problem**: `ImportError: cannot find libpyjamaz` after installing wheel

**Solution**:
```bash
# Check if libraries were bundled
unzip -l dist/pyjamaz-*.whl | grep native
# Should see: pyjamaz/native/libpyjamaz.dylib and libavif.16.dylib

# If missing, rebuild wheel
./scripts/build-python-wheel.sh

# Check library search paths (after installing wheel)
uv run python -c "import pyjamaz; import os; print(os.path.dirname(pyjamaz.__file__))"
````

**Problem**: `dyld: Library not loaded: libavif.16.dylib`

**Solution**:

```bash
# Verify libavif was bundled
ls -lh dist/pyjamaz-*.whl
# Wheel should be 5-10MB (includes bundled libs)

# If wheel is only ~1MB, libavif wasn't bundled
# Check if libavif exists on system
ls -lh /opt/homebrew/opt/libavif/lib/libavif.16.dylib
```

#### Node.js Package Issues

**Problem**: `Error: Could not find libpyjamaz shared library`

**Solution**:

```bash
# Check if native directory exists
tar -tzf bindings/nodejs/pyjamaz-*.tgz | grep native/
# Should see: package/native/libpyjamaz.dylib and libavif.16.dylib

# Verify install.js ran
npm install ./pyjamaz-*.tgz 2>&1 | grep "native binaries"

# Check library search in bindings
node -e "const path = require('path'); console.log(path.join(__dirname, 'native'))"
```

**Problem**: `npm test` fails with FFI errors

**Solution**:

```bash
# Ensure dependencies are installed
cd bindings/nodejs
npm ci  # Clean install

# Verify TypeScript compiled
ls -lh dist/
# Should see: index.js, bindings.js, types.js

# Check if library loads
node -e "require('./dist/bindings.js')"
```

### Build Script Debugging

**Enable verbose output**:

```bash
# Python wheel build
bash -x ./scripts/build-python-wheel.sh

# Node.js package build
bash -x ./scripts/build-nodejs-package.sh
```

**Check bundled files**:

```bash
# Python wheel (no uv needed - just inspecting zip file)
python3 -m zipfile -l dist/pyjamaz-*.whl

# Node.js package
tar -tzf bindings/nodejs/pyjamaz-*.tgz
```

### Platform-Specific Issues

**macOS**: If `otool -L` shows Homebrew paths after bundling:

```bash
# Libraries should be bundled, not referenced
otool -L zig-out/lib/libpyjamaz.dylib
# Should only show: libavif.16.dylib, @rpath, /usr/lib/libSystem

# Check wheel/package includes libraries
# Python: Should bundle both .dylib files
# Node.js: Should bundle both .dylib files in native/
```

**Linux**: If `ldd` shows missing dependencies:

```bash
ldd zig-out/lib/libpyjamaz.so
# Should only show: libavif.so.16, linux-vdso, libc, libm

# Ensure libavif is available
ls -lh /usr/lib/x86_64-linux-gnu/libavif.so.16
```

---

## Rollback Plan

If catastrophic issues are discovered immediately after release:

### PyPI Rollback (Limited)

⚠️ **PyPI does not allow deleting releases**. Instead:

1. **Yank Release**: Mark version as "yanked" (prevents new installs)

   ```bash
   uv pip install twine
   twine upload --repository pypi dist/* --skip-existing
   # Contact PyPI support to yank: https://pypi.org/help/#yanked
   ```

2. **Publish Hotfix**: Release 1.0.1 with fixes ASAP

### npm Rollback (Limited)

⚠️ **npm allows unpublishing only within 72 hours**:

```bash
# Unpublish (only works within 72 hours)
npm unpublish pyjamaz@1.0.0

# Deprecate (if too late to unpublish)
npm deprecate pyjamaz@1.0.0 "Critical bug, use 1.0.1 instead"
```

### GitHub Release Rollback

1. Mark release as "Pre-release" or delete it
2. Delete git tag locally and remotely:
   ```bash
   git tag -d v1.0.0
   git push origin :refs/tags/v1.0.0
   ```

---

## Checklist: Pre-Release

Before starting the release process, verify:

- [ ] All Milestone 4 phases complete
- [ ] Static linking configured (build.zig)
- [ ] Platform-specific wheels built (Python)
- [ ] Platform-specific packages built (Node.js)
- [ ] All tests pass (126/127, 99.2%)
- [ ] Documentation updated (README, CHANGELOG, migration guide)
- [ ] Version bumped in all files (pyproject.toml, package.json, build.zig)
- [ ] CHANGELOG.md has 1.0.0 entry
- [ ] Migration guide written (docs/MIGRATION.md)
- [ ] Examples tested with new packages
- [ ] CI/CD pipeline green
- [ ] Clean git status (all changes committed)

---

## Checklist: Post-Release

After publishing to PyPI and npm:

- [ ] PyPI release published
- [ ] npm release published
- [ ] GitHub release created with tag v1.0.0
- [ ] Release notes written
- [ ] Binaries attached to GitHub release
- [ ] Documentation site updated
- [ ] Announcement posts published
- [ ] Monitoring dashboards checked
- [ ] Initial feedback reviewed
- [ ] Hotfix plan ready (if needed)

---

## Notes

- **Irreversible Actions**: PyPI/npm releases cannot be deleted (only yanked/deprecated)
- **Timing**: Plan release during business hours for monitoring
- **Communication**: Have social media/blog posts ready before release
- **Support**: Be available for 48 hours post-release to handle issues

---

## Summary: Testing Commands Cheat Sheet

For quick reference, here are all the key testing commands:

### Python Wheel Testing

```bash
# Build
./scripts/build-python-wheel.sh

# Install and test
uv venv test-env
source test-env/bin/activate
uv pip install dist/pyjamaz-*.whl

# ⭐ Quick comprehensive test
uv run python bindings/python/examples/test_bundled_package.py

# Or run individual tests
uv run python -c "import pyjamaz; print('Version:', pyjamaz.get_version())"
uv run python bindings/python/examples/basic.py
cd bindings/python && uv run python -m pytest tests/ -v && cd ../..

deactivate && rm -rf test-env

# Verify bundling (shows bundled libraries)
unzip -l dist/pyjamaz-*.whl | grep native
```

### Node.js Package Testing

```bash
# Build
./scripts/build-nodejs-package.sh

# Install and test
cd bindings/nodejs
npm install ./pyjamaz-*.tgz

# ⭐ Quick comprehensive test
npx ts-node examples/test-bundled-package.ts

# Or run individual tests
node -e "const { version } = require('pyjamaz'); console.log('Version:', version())"
npx ts-node examples/basic.ts
npm test

npm uninstall pyjamaz

# Verify bundling
tar -tzf pyjamaz-*.tgz | grep native/
```

### CI/CD Trigger

```bash
# Create and push tag
git tag -a v1.0.0 -m "Release 1.0.0 - Standalone Distribution"
git push origin v1.0.0

# Monitor builds at:
# https://github.com/yourusername/pyjamaz/actions
```

---

**Questions?** See [docs/CONTRIBUTING.md](./CONTRIBUTING.md) or open a discussion.

**Last Updated**: 2025-11-01 (Updated with build scripts and testing procedures)
