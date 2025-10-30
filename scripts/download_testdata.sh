#!/usr/bin/env bash
#
# Download conformance test suites for Pyjamaz
#
# Usage: ./docs/scripts/download_testdata.sh
#
# This script downloads standard image test suites used for conformance testing.
# Downloaded files go to testdata/conformance/

set -euo pipefail

TESTDATA_DIR="testdata/conformance"
TOTAL_SIZE_ESTIMATE="~150 MB"

echo "=== Pyjamaz Conformance Test Suite Downloader ==="
echo ""
echo "This will download ${TOTAL_SIZE_ESTIMATE} of test images to ${TESTDATA_DIR}/"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read -r

mkdir -p "$TESTDATA_DIR"

# Track success/failures
declare -i SUCCESS=0
declare -i FAILED=0

# Kodak Image Suite (24 images, ~5MB)
echo ""
echo "→ Downloading Kodak Image Suite (24 images)"
mkdir -p "$TESTDATA_DIR/kodak"
for i in $(seq -f "%02g" 1 24); do
  URL="http://r0k.us/graphics/kodak/kodak/kodim$i.png"
  OUTPUT="$TESTDATA_DIR/kodak/kodim$i.png"

  if curl -f -o "$OUTPUT" "$URL" 2>/dev/null; then
    echo "  ✓ kodim$i.png"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  ✗ kodim$i.png (failed)"
    FAILED=$((FAILED + 1))
  fi
done

# PngSuite (edge cases, ~2MB)
echo ""
echo "→ Downloading PNG Suite (edge cases)"
mkdir -p "$TESTDATA_DIR/pngsuite"
PNGSUITE_URL="http://www.schaik.com/pngsuite/PngSuite-2017jul19.tgz"
PNGSUITE_TAR="$TESTDATA_DIR/pngsuite.tar.gz"

if curl -f -o "$PNGSUITE_TAR" "$PNGSUITE_URL" 2>/dev/null; then
  tar -xzf "$PNGSUITE_TAR" -C "$TESTDATA_DIR/pngsuite" 2>/dev/null || true
  rm "$PNGSUITE_TAR"
  COUNT=$(find "$TESTDATA_DIR/pngsuite" -name "*.png" | wc -l | xargs)
  echo "  ✓ Extracted $COUNT PNG files"
  SUCCESS=$((SUCCESS + COUNT))
else
  echo "  ✗ PNG Suite download failed"
  FAILED=$((FAILED + 1))
fi

# WebP Gallery (sample images, ~5MB)
echo ""
echo "→ Downloading WebP Gallery (sample images)"
mkdir -p "$TESTDATA_DIR/webp"
WEBP_URLS=(
  "https://www.gstatic.com/webp/gallery/1.webp"
  "https://www.gstatic.com/webp/gallery/2.webp"
  "https://www.gstatic.com/webp/gallery/3.webp"
  "https://www.gstatic.com/webp/gallery/4.webp"
  "https://www.gstatic.com/webp/gallery/5.webp"
)
for url in "${WEBP_URLS[@]}"; do
  FILENAME=$(basename "$url")
  OUTPUT="$TESTDATA_DIR/webp/$FILENAME"

  if curl -f -o "$OUTPUT" "$url" 2>/dev/null; then
    echo "  ✓ $FILENAME"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  ✗ $FILENAME (failed)"
    FAILED=$((FAILED + 1))
  fi
done

# TESTIMAGES samples (various formats)
echo ""
echo "→ Downloading TESTIMAGES samples"
mkdir -p "$TESTDATA_DIR/testimages"
TESTIMAGES_URLS=(
  "http://testimages.org/images/lena.png"
  "http://testimages.org/images/baboon.png"
  "http://testimages.org/images/peppers.png"
)
for url in "${TESTIMAGES_URLS[@]}"; do
  FILENAME=$(basename "$url")
  OUTPUT="$TESTDATA_DIR/testimages/$FILENAME"

  if curl -f -o "$OUTPUT" "$url" 2>/dev/null; then
    echo "  ✓ $FILENAME"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  ✗ $FILENAME (failed - might be moved/unavailable)"
    FAILED=$((FAILED + 1))
  fi
done

# Summary
echo ""
echo "=== Download Summary ==="
echo "Successful: $SUCCESS files"
echo "Failed:     $FAILED downloads"
echo ""

# Calculate total size
if command -v du &> /dev/null; then
  TOTAL_SIZE=$(du -sh "$TESTDATA_DIR" | cut -f1)
  echo "Total size: $TOTAL_SIZE"
fi

echo ""
echo "Test suites downloaded to: $TESTDATA_DIR/"
echo ""
echo "Note: Some downloads may fail if sources have moved or are unavailable."
echo "This is normal and won't prevent testing with available images."
echo ""
echo "To run conformance tests:"
echo "  zig build conformance"

exit 0
