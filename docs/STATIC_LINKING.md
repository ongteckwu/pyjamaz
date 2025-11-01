# Static Linking Configuration

**Last Updated**: 2025-11-01
**Status**: ✅ Phase 1 Complete - Partial Static Linking Achieved

---

## Overview

Pyjamaz has been configured to use static linking for most codec dependencies, reducing external dependencies from **12+ libraries** (libvips + glib ecosystem) to just **1 external library** (libavif).

This enables:
- **Simpler distribution** - Fewer runtime dependencies to manage
- **Better portability** - Less chance of version conflicts
- **Smaller wheel/package size** - Only need to bundle libavif.dylib

---

## Current Dependency Status

### ✅ Statically Linked (Embedded in libpyjamaz.dylib)

| Library | Version | Size | Purpose |
|---------|---------|------|---------|
| libjpeg-turbo | 8.3.2 | ~500KB | JPEG encode/decode |
| libpng16 | 1.6.x | ~200KB | PNG encode/decode |
| libwebp | 1.4.x | ~400KB | WebP encode/decode |
| libsharpyuv | (part of webp) | ~50KB | YUV conversion for WebP |
| libdssim | 3.x | ~100KB | DSSIM perceptual metric |
| zlib | 1.3.x | ~100KB | Compression (required by libpng) |

**Total static size**: ~1.4MB (embedded in libpyjamaz.dylib)

### 🟡 Dynamically Linked (Runtime Dependency)

| Library | Version | Size | Reason |
|---------|---------|------|--------|
| libavif.16.dylib | 1.3.0 | ~2MB | Static build complex (needs aom + dav1d) |

### ✅ System Dependencies (Always Available)

| Framework/Library | Purpose |
|-------------------|---------|
| Accelerate.framework | SIMD operations for libdssim (macOS system framework) |
| libSystem.B.dylib | System C library (always present) |

---

## Build Configuration

### build.zig Changes

```zig
// Phase 1: Static linking for native codecs
// Static libraries (from Homebrew) - using absolute paths
lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/jpeg-turbo/lib/libjpeg.a" });
lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/libpng/lib/libpng16.a" });
lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/webp/lib/libwebp.a" });
lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/webp/lib/libsharpyuv.a" });
lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/lib/libdssim.a" });
lib.addObjectFile(.{ .cwd_relative = "/opt/homebrew/opt/zlib/lib/libz.a" });

// libavif: Keep dynamic for now
lib.linkSystemLibrary("avif");

// System frameworks
lib.linkFramework("Accelerate");
lib.linkLibC();
```

### Verification

```bash
# Check dependencies
otool -L zig-out/lib/libpyjamaz.dylib

# Output:
# @rpath/libpyjamaz.dylib
# /opt/homebrew/opt/libavif/lib/libavif.16.dylib  ← Only external dep
# /System/Library/Frameworks/Accelerate.framework/... ← System framework
# /usr/lib/libSystem.B.dylib  ← System library
```

---

## Distribution Strategy

### Phase 2: Python Wheel Distribution

**Approach**: Bundle libavif.dylib in platform-specific wheels

```
pyjamaz-1.0.0-cp311-cp311-macosx_11_0_arm64.whl
├── pyjamaz/
│   ├── __init__.py
│   ├── libpyjamaz.dylib (includes static-linked codecs)
│   └── libs/
│       └── libavif.16.dylib (bundled dynamic library)
```

**Installation**: `uv pip install pyjamaz` → works immediately, no brew needed

### Phase 3: Node.js Package Distribution

**Approach**: Platform-specific optional dependencies

```json
{
  "name": "pyjamaz",
  "optionalDependencies": {
    "@pyjamaz/darwin-arm64": "^1.0.0",
    "@pyjamaz/darwin-x64": "^1.0.0",
    "@pyjamaz/linux-x64": "^1.0.0"
  }
}
```

Each platform package bundles libpyjamaz.dylib + libavif.dylib

**Installation**: `npm install pyjamaz` → works immediately, no brew needed

---

## Why Not Fully Static?

### libavif Challenges

**Attempted Approach**: Build from source with `-DAVIF_BUILD_STATIC=ON`

**Blockers**:
1. Requires building libaom (AV1 encoder) from source
2. Requires building libdav1d (AV1 decoder) from source
3. Both require additional build tools (meson, nasm, etc.)
4. Complex dependency tree (~30 min build time)

**Decision**: Bundle libavif.dylib in distribution packages instead

### Tradeoffs

| Approach | Pros | Cons |
|----------|------|------|
| **Current (partial static)** | ✅ Simple build<br>✅ Fast compile<br>✅ Only 1 external dep | ⚠️ Must bundle libavif.dylib |
| **Full static (build avif)** | ✅ Zero external deps | ❌ Complex build<br>❌ 30+ min compile<br>❌ Need meson/nasm |

**Conclusion**: Partial static linking achieves 95% of the goal with 5% of the complexity.

---

## Future: Full Static Linking

If demand exists for truly standalone binaries (zero .dylib bundling), we can:

1. **Pre-build static libavif** in CI/CD
2. **Cache artifacts** for faster builds
3. **Provide build script** for users who need it

Estimated effort: 2-3 days (vs current approach: 0.5 days)

---

## Platform Support

### macOS (Current Implementation)

- ✅ Static linking works
- ✅ Homebrew provides .a files for most libraries
- ✅ System frameworks available (Accelerate)

### Linux (Future)

- ✅ Static linking should work similarly
- Need to verify library paths (e.g., `/usr/lib/x86_64-linux-gnu/`)
- May need different framework (no Accelerate on Linux)

### Windows (Future)

- 🟡 Static linking possible but different tools
- Need MSVC .lib files or MinGW .a files
- Different system libraries (no Accelerate)

---

## Testing

### Verify Static Linking Works

```python
import sys
sys.path.insert(0, 'bindings/python')
from pyjamaz import optimize_image

with open('test.png', 'rb') as f:
    data = f.read()

result = optimize_image(input_path=data, max_bytes=50000)
print(f"Works! {len(result.output_buffer)} bytes")
```

### Check Dependencies

```bash
otool -L zig-out/lib/libpyjamaz.dylib
# Should show only: libavif.dylib, Accelerate.framework, libSystem
```

---

## Success Metrics

✅ **Achieved (Phase 1)**:
- libvips removed (12+ deps → 1 dep)
- 4 codecs statically linked
- Library size: 1.7MB → 3.1MB (includes embedded codecs)
- Build time: ~5 seconds (no change)
- Tests pass: 126/127 (99.2%)

🎯 **Target (Phase 2-3)**:
- Python wheel: `uv pip install pyjamaz` works immediately
- Node.js package: `npm install pyjamaz` works immediately
- No `brew install` prerequisites
- Platform-specific packages (macOS Intel/ARM, Linux x64)

---

**Last Updated**: 2025-11-01 (Phase 1 complete)
**Next Steps**: Phase 2 - Python wheel distribution with bundled libavif.dylib
