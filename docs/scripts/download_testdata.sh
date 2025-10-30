#!/usr/bin/env bash
set -euo pipefail

TESTDATA_DIR="testdata/conformance"
mkdir -p "$TESTDATA_DIR"

echo "Downloading conformance test suites..."

# Kodak Image Suite
echo "→ Kodak Image Suite (24 images)"
mkdir -p "$TESTDATA_DIR/kodak"
for i in $(seq -f "%02g" 1 24); do
  curl -o "$TESTDATA_DIR/kodak/kodim$i.png" \
    "http://r0k.us/graphics/kodak/kodak/kodim$i.png" || true
done

# PngSuite
echo "→ PNG Suite"
mkdir -p "$TESTDATA_DIR/pngsuite"
curl -o "$TESTDATA_DIR/pngsuite.tar.gz" \
  "http://www.schaik.com/pngsuite/PngSuite-2017jul19.tgz"
tar -xzf "$TESTDATA_DIR/pngsuite.tar.gz" -C "$TESTDATA_DIR/pngsuite"
rm "$TESTDATA_DIR/pngsuite.tar.gz"

# WebP Gallery (sample)
echo "→ WebP Gallery (sample images)"
mkdir -p "$TESTDATA_DIR/webp"
WEBP_URLS=(
  "https://www.gstatic.com/webp/gallery/1.webp"
  "https://www.gstatic.com/webp/gallery/2.webp"
  "https://www.gstatic.com/webp/gallery/3.webp"
)
for url in "${WEBP_URLS[@]}"; do
  curl -o "$TESTDATA_DIR/webp/$(basename $url)" "$url" || true
done

echo "✓ Test suites downloaded to $TESTDATA_DIR"
echo "Note: Some downloads may fail (404/moved). Update script as needed."
