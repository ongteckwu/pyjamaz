#!/bin/bash
# Build Node.js package with bundled native libraries
# Similar to Python wheel building but for npm packages

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NODEJS_DIR="$PROJECT_ROOT/bindings/nodejs"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Pyjamaz Node.js package with bundled libraries${NC}"

# Step 1: Build the native library
echo -e "\n${YELLOW}Step 1: Building native library...${NC}"
cd "$PROJECT_ROOT"
zig build

# Step 2: Detect platform and architecture
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$PLATFORM" in
  darwin)
    PLATFORM="darwin"
    LIB_EXT="dylib"
    LIBPYJAMAZ="libpyjamaz.dylib"
    LIBAVIF="libavif.16.dylib"
    LIBAVIF_SOURCE="/opt/homebrew/opt/libavif/lib/$LIBAVIF"
    ;;
  linux)
    PLATFORM="linux"
    LIB_EXT="so"
    LIBPYJAMAZ="libpyjamaz.so"
    LIBAVIF="libavif.so.16"
    LIBAVIF_SOURCE="/usr/lib/$LIBAVIF"
    ;;
  *)
    echo "Unsupported platform: $PLATFORM"
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64)
    ARCH="x64"
    ;;
  arm64|aarch64)
    ARCH="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

PLATFORM_TAG="${PLATFORM}-${ARCH}"
echo -e "${GREEN}Building for platform: ${PLATFORM_TAG}${NC}"

# Step 3: Create native directory in Node.js bindings
echo -e "\n${YELLOW}Step 2: Bundling native libraries...${NC}"
NATIVE_DIR="$NODEJS_DIR/native"
mkdir -p "$NATIVE_DIR"

# Copy libpyjamaz
LIBPYJAMAZ_SOURCE="$PROJECT_ROOT/zig-out/lib/$LIBPYJAMAZ"
if [ -f "$LIBPYJAMAZ_SOURCE" ]; then
  echo "Bundling $LIBPYJAMAZ..."
  cp "$LIBPYJAMAZ_SOURCE" "$NATIVE_DIR/"
else
  echo "Error: $LIBPYJAMAZ not found at $LIBPYJAMAZ_SOURCE"
  exit 1
fi

# Copy libavif
if [ -f "$LIBAVIF_SOURCE" ]; then
  echo "Bundling $LIBAVIF..."
  cp "$LIBAVIF_SOURCE" "$NATIVE_DIR/"
else
  echo "Warning: $LIBAVIF not found at $LIBAVIF_SOURCE"
  echo "Package will require libavif to be installed separately"
fi

# Step 4: Build TypeScript
echo -e "\n${YELLOW}Step 3: Building TypeScript...${NC}"
cd "$NODEJS_DIR"
npm run build

# Step 5: Create tarball
echo -e "\n${YELLOW}Step 4: Creating package tarball...${NC}"
npm pack

echo -e "\n${GREEN}✓ Package built successfully!${NC}"
echo -e "Platform: ${PLATFORM_TAG}"
echo -e "Tarball: $(ls -1 pyjamaz-nodejs-*.tgz | tail -1)"
echo -e "\nTo test installation:"
echo -e "  npm install ./$(ls -1 pyjamaz-nodejs-*.tgz | tail -1)"
