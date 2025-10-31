# Image Compression Test Suites

This document lists all test suites used for conformance testing in Pyjamaz, along with their sources and characteristics.

## Currently Implemented (in download script)

### 1. Kodak PhotoCD Image Suite
- **URL**: http://r0k.us/graphics/kodak/
- **Count**: 24 images
- **Size**: ~5 MB
- **Format**: PNG
- **Purpose**: Standard photographic test images for compression algorithms
- **Coverage**: Natural scenes, portraits, landscapes
- **Status**: ✅ Working

### 2. PngSuite
- **URL**: http://www.schaik.com/pngsuite/
- **Count**: ~176 images
- **Size**: ~2 MB
- **Format**: PNG
- **Purpose**: Edge case testing for PNG decoder/encoder
- **Coverage**: All PNG features, bit depths, color types, interlacing
- **Includes**: Invalid test files (prefixed with 'x')
- **Status**: ✅ Working

### 3. WebP Gallery
- **URL**: https://www.gstatic.com/webp/gallery/
- **Count**: 5 images
- **Size**: ~5 MB
- **Format**: WebP
- **Purpose**: WebP format testing
- **Coverage**: Lossy WebP compression samples
- **Status**: ✅ Working

### 4. JPEG Test Samples
- **URL**: https://github.com/libjpeg-turbo/libjpeg-turbo/tree/main/testimages
- **Count**: 2 images (testorig.jpg, testimgint.jpg)
- **Size**: ~11 KB total
- **Format**: JPEG
- **Purpose**: Standard JPEG codec testing
- **Coverage**: Baseline JPEG compression (Huffman coding)
- **Note**: testimgari.jpg excluded (arithmetic coding not widely supported)
- **Status**: ✅ Working

### 5. USC-SIPI Image Database
- **URL**: https://sipi.usc.edu/database/
- **Count**: 5 classic images
- **Size**: ~10 MB
- **Format**: PNG (converted from TIFF)
- **Purpose**: Classic benchmark images
- **Coverage**: Lena, Peppers, Baboon, House, Splash
- **Status**: ⚠️ Requires proper URL formatting

### 6. Additional JPEG Samples
- **URL**: https://sample-videos.com/
- **Count**: 3 images
- **Size**: ~15 MB
- **Format**: JPEG
- **Purpose**: Size-diverse JPEG testing
- **Coverage**: 500KB, 1MB, 2MB file sizes
- **Status**: ⚠️ May fail (source instability)

### 7. AVIF Test Suite
- **URL**: https://github.com/AOMediaCodec/av1-avif/tree/master/testFiles
- **Count**: Planned (5-10 images)
- **Size**: ~10 MB
- **Format**: AVIF
- **Purpose**: AVIF format testing and quality validation
- **Coverage**: Various AVIF encoding profiles (speed, quality)
- **Implementation Plan**:
  - Add once AVIF encoder is fully tested (v0.5.0+)
  - Include samples: kimono.avif, fox.avif, autumn_leaves.avif
  - Test both lossy and lossless AVIF compression
- **Status**: 🔄 Deferred to v0.5.0 (AVIF encoder operational, needs production testing)

---

## Recommended Additional Suites

### 8. CLIC Professional Dataset
- **URL**: https://www.compression.cc/challenge/
- **Count**: 30+ professional images
- **Size**: ~500 MB
- **Format**: PNG (high-quality)
- **Purpose**: Professional compression challenge dataset
- **Coverage**: High-resolution professional photos
- **Implementation**: Manual download (too large for script)
- **Status**: 📝 Documented for manual use

### 9. Tecnick Test Images
- **URL**: https://tecnick.com/
- **Count**: 10+ test patterns
- **Size**: ~20 MB
- **Format**: PNG/TIFF
- **Purpose**: Professional test charts and patterns
- **Coverage**: Color charts, resolution targets, gradient tests
- **Status**: 🔄 URLs need verification

### 10. BSD500 Berkeley Segmentation Dataset
- **URL**: https://www2.eecs.berkeley.edu/Research/Projects/CS/vision/grouping/resources.html
- **Count**: 500 images
- **Size**: ~150 MB
- **Format**: JPG
- **Purpose**: Natural image testing
- **Coverage**: Diverse real-world scenes
- **Status**: 🔄 Recommended for future addition

### 11. DIV2K High-Resolution Dataset
- **URL**: https://data.vision.ee.ethz.ch/cvl/DIV2K/
- **Count**: 900 images (train + validation)
- **Size**: ~17 GB
- **Format**: PNG (2K resolution)
- **Purpose**: High-resolution image compression testing
- **Coverage**: 2K resolution diverse images
- **Status**: 🔄 Too large for automatic download

### 12. JPEG AI Test Set
- **URL**: https://jpeg.org/jpegai/
- **Count**: TBD
- **Size**: TBD
- **Format**: JPEG, JPEG AI
- **Purpose**: Next-generation JPEG format testing
- **Status**: 🔄 Future consideration

---

## Test Suite Selection Criteria

When adding new test suites, consider:

1. **Size**: Keep automatic downloads under 500 MB total
2. **Diversity**: Cover different image types (photos, graphics, patterns)
3. **Format Coverage**: Include PNG, JPEG, WebP, AVIF test cases
4. **Edge Cases**: Include unusual bit depths, color spaces, metadata
5. **Availability**: Stable, publicly accessible URLs
6. **License**: Freely usable for testing purposes

---

## Current Coverage Summary

| Category | Coverage | Status |
|----------|----------|--------|
| PNG Edge Cases | ✅ Excellent | PngSuite (176 images) |
| Photographic | ✅ Good | Kodak (24 images) |
| WebP Format | ✅ Basic | WebP Gallery (5 images) |
| JPEG Samples | ⚠️ Limited | Various sources (~6 images) |
| AVIF Format | ❌ None | Planned |
| High-Resolution | ❌ None | Manual download recommended |
| Test Patterns | ⚠️ Limited | Need verification |

---

## Usage

### Download All Automatic Suites
```bash
./scripts/download_testdata.sh
```

### Force Re-download
```bash
./scripts/download_testdata.sh --force
```

### Run Conformance Tests
```bash
zig build conformance
```

---

## Adding New Test Suites

To add a new test suite to the download script:

1. Find a stable, publicly accessible source
2. Verify the URL returns valid image files
3. Add a new section to `scripts/download_testdata.sh`:
   ```bash
   echo ""
   echo "→ Downloading [Suite Name] (~[Size])"
   mkdir -p "$TESTDATA_DIR/[suite_name]"

   [SUITE]_IMAGES=(
     "URL1:filename1.ext"
     "URL2:filename2.ext"
   )

   for entry in "${[SUITE]_IMAGES[@]}"; do
     IFS=':' read -r url filename <<< "$entry"
     OUTPUT="$TESTDATA_DIR/[suite_name]/$filename"
     # ... download logic
   done
   ```
4. Update the test suite breakdown list
5. Document in this file (TEST_SUITES.md)
6. Update total size estimate in the script

---

## Known Issues

### JPEG Test Samples
The current JPEG sample sources (filesamples.com, sample-videos.com) may be unstable. Consider replacing with:
- **Alternative**: JPEG reference implementation test suite
- **URL**: https://github.com/libjpeg-turbo/libjpeg-turbo/tree/main/testimages

### USC-SIPI Images
Direct download links may require authentication or cookie handling. Consider:
- **Alternative**: Mirror on GitHub
- **Example**: https://github.com/bsxfan/ad-hoc/tree/master/images

### AVIF Support
AVIF test images are added but AVIF encoder is not yet implemented. These tests will be skipped until AVIF support is added.

---

## Performance Benchmarks

After downloading test suites, you can measure compression performance:

```bash
# Run conformance tests with timing
zig build conformance

# Run benchmarks on specific suite
zig build benchmark -- --suite kodak

# Measure compression ratio
zig build benchmark -- --metric compression
```

---

**Last Updated**: 2025-10-30
**Test Suites Version**: 1.0
**Total Available Images**: ~200+ (automatic download)
