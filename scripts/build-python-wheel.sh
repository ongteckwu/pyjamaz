#!/usr/bin/env bash
# Build Python wheel locally for testing
# Usage: ./scripts/build-python-wheel.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Building Pyjamaz Python Wheel ==="
echo "Project root: $PROJECT_ROOT"
echo ""

# Step 1: Build Zig library
echo "[1/4] Building Zig library..."
cd "$PROJECT_ROOT"
zig build
echo "✓ Zig library built: zig-out/lib/libpyjamaz.dylib"
echo ""

# Step 2: Verify libavif is available
echo "[2/4] Checking libavif dependency..."
if [ "$(uname)" == "Darwin" ]; then
    LIBAVIF_PATH="/opt/homebrew/opt/libavif/lib/libavif.16.dylib"
    if [ ! -f "$LIBAVIF_PATH" ]; then
        echo "ERROR: libavif not found at $LIBAVIF_PATH"
        echo "Install with: brew install libavif"
        exit 1
    fi
    echo "✓ libavif found: $LIBAVIF_PATH"
elif [ "$(uname)" == "Linux" ]; then
    if ! ldconfig -p | grep -q libavif; then
        echo "ERROR: libavif not found"
        echo "Install with: sudo apt-get install libavif-dev"
        exit 1
    fi
    echo "✓ libavif found"
else
    echo "Warning: Unsupported platform $(uname)"
fi
echo ""

# Step 3: Build wheel
echo "[3/4] Building Python wheel..."
cd "$PROJECT_ROOT/bindings/python"
python -m pip install --upgrade pip build
python -m build --wheel --outdir "$PROJECT_ROOT/dist"
echo "✓ Wheel built"
echo ""

# Step 4: Show results
echo "[4/4] Build complete!"
echo ""
echo "Output:"
ls -lh "$PROJECT_ROOT/dist/"*.whl
echo ""
echo "To install locally:"
echo "  pip install $PROJECT_ROOT/dist/*.whl"
echo ""
echo "To test:"
echo "  python -c 'import pyjamaz; print(pyjamaz.get_version())'"
echo "  python bindings/python/examples/basic_usage.py"
