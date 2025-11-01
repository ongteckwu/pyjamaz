# Pyjamaz Batch Processor

A powerful command-line tool for batch optimizing images using Pyjamaz with progress tracking and detailed reporting.

## Features

- ✅ Batch process entire directories
- ✅ Recursive directory scanning
- ✅ Parallel processing with configurable workers
- ✅ Beautiful progress bars and colored output
- ✅ Detailed statistics and reporting
- ✅ Format selection and constraints
- ✅ Caching for improved performance

## Installation

```bash
npm install
npm run build
```

## Usage

### Basic Usage

```bash
# Process all images in a directory
npm run cli -- input-dir output-dir

# Or use the built version
node dist/cli.js input-dir output-dir
```

### With Options

```bash
# Optimize with size constraint
npm run cli -- images/ optimized/ --max-bytes 100000

# Optimize with quality constraint
npm run cli -- images/ optimized/ --max-diff 0.002 --metric ssimulacra2

# Use specific formats
npm run cli -- images/ optimized/ --formats webp,avif --max-bytes 50000

# Recursive processing with 8 workers
npm run cli -- images/ optimized/ --recursive --concurrency 8

# Verbose output
npm run cli -- images/ optimized/ --verbose
```

## Command-Line Options

```
Usage: batch-optimize [options] <input-dir> <output-dir>

Batch optimize images using Pyjamaz

Arguments:
  input-dir                 Input directory containing images
  output-dir                Output directory for optimized images

Options:
  -V, --version             output the version number
  -b, --max-bytes <bytes>   Maximum file size in bytes
  -d, --max-diff <diff>     Maximum perceptual difference
  -m, --metric <metric>     Perceptual metric (dssim|ssimulacra2|none) (default: "dssim")
  -f, --formats <formats>   Comma-separated list of formats (jpeg,png,webp,avif)
  -c, --concurrency <num>   Number of parallel workers (default: "4")
  -r, --recursive           Process subdirectories recursively
  -v, --verbose             Verbose output
  -h, --help                display help for command
```

## Examples

### Example 1: Basic size optimization

```bash
npm run cli -- test-images/ output/ --max-bytes 100000
```

Output:
```
============================================================
Pyjamaz Batch Image Processor
============================================================

✔ Found 15 images to process

Configuration:
  Input:       test-images/
  Output:      output/
  Max Size:    97.66 KB
  Metric:      dssim
  Workers:     4

Progress |████████████████████████████| 100% | 15/15 | image15.jpg

============================================================
Summary
============================================================

Total images:     15
Successful:       15

Original size:    12.45 MB
Optimized size:   1.42 MB
Saved:            11.03 MB (88.6%)

Total time:       3.24s
Avg per image:    216ms
============================================================
```

### Example 2: Recursive processing with verbose output

```bash
npm run cli -- images/ optimized/ \
  --recursive \
  --max-bytes 100000 \
  --concurrency 8 \
  --verbose
```

Output:
```
Detailed Results:
------------------------------------------------------------
✓ photo1.jpg                      1.25 MB → 95.23 KB      (92.4%)
✓ photo2.png                      2.34 MB → 98.45 KB      (95.8%)
✓ photo3.webp                     856.00 KB → 87.12 KB    (89.8%)
✓ screenshot1.png                 445.00 KB → 42.34 KB    (90.5%)
...
```

### Example 3: Format selection for modern formats

```bash
npm run cli -- images/ optimized/ \
  --formats webp,avif \
  --max-bytes 50000 \
  --metric ssimulacra2
```

This will only output WebP or AVIF files, choosing the smaller format.

### Example 4: Quality-based optimization

```bash
npm run cli -- images/ optimized/ \
  --max-diff 0.001 \
  --metric dssim \
  --verbose
```

Optimizes images while ensuring perceptual quality stays within threshold.

## Directory Structure

```
batch-processor/
├── src/
│   └── cli.ts              # Main CLI implementation
├── dist/                   # Compiled JavaScript (after build)
├── test-images/            # Sample input images
├── output/                 # Optimized output (created automatically)
├── package.json
├── tsconfig.json
└── README.md
```

## TypeScript API

You can also use the batch processor programmatically:

```typescript
import * as pyjamaz from 'pyjamaz';
import * as fs from 'fs';
import * as path from 'path';

async function batchOptimize(inputDir: string, outputDir: string) {
  const images = fs.readdirSync(inputDir).filter(file =>
    /\.(jpg|jpeg|png|webp)$/i.test(file)
  );

  const results = await Promise.all(
    images.map(async (filename) => {
      const inputPath = path.join(inputDir, filename);
      const result = await pyjamaz.optimizeImage(inputPath, {
        maxBytes: 100_000,
        cacheEnabled: true,
      });

      if (result.passed) {
        const outputPath = path.join(outputDir, `${path.basename(filename, path.extname(filename))}.${result.format}`);
        await result.save(outputPath);
        return { success: true, filename, size: result.size };
      }
      return { success: false, filename };
    })
  );

  const successful = results.filter(r => r.success).length;
  console.log(`Optimized ${successful}/${images.length} images`);
}
```

## Performance Tips

### 1. Adjust Concurrency

```bash
# For faster processing on powerful machines
npm run cli -- images/ output/ --concurrency 8

# For lower memory usage
npm run cli -- images/ output/ --concurrency 2
```

### 2. Use Caching

The tool automatically enables caching. Reprocessing the same images with the same options will be nearly instant!

```bash
# First run: ~3 seconds
npm run cli -- images/ output/ --max-bytes 100000

# Second run with same options: ~0.2 seconds (15x faster!)
npm run cli -- images/ output2/ --max-bytes 100000
```

### 3. Format Selection

Restrict to modern formats for better compression:

```bash
npm run cli -- images/ output/ --formats webp,avif
```

## Real-World Use Cases

### 1. Website Asset Optimization

```bash
# Optimize all images for web deployment
npm run cli -- src/assets/images/ dist/images/ \
  --recursive \
  --max-bytes 150000 \
  --formats webp,jpeg \
  --concurrency 4
```

### 2. Photo Gallery Compression

```bash
# Compress photo gallery with quality preservation
npm run cli -- photos/ compressed/ \
  --max-diff 0.002 \
  --metric ssimulacra2 \
  --recursive \
  --verbose
```

### 3. Social Media Image Preparation

```bash
# Optimize for social media size limits
npm run cli -- uploads/ social-ready/ \
  --max-bytes 5000000 \
  --formats jpeg,webp
```

### 4. E-commerce Product Images

```bash
# Optimize product images with size and quality constraints
npm run cli -- products/ optimized-products/ \
  --max-bytes 200000 \
  --max-diff 0.001 \
  --metric dssim \
  --recursive
```

## Integration with Build Systems

### npm scripts

Add to your `package.json`:

```json
{
  "scripts": {
    "optimize-images": "batch-optimize src/images dist/images --max-bytes 100000",
    "prebuild": "npm run optimize-images"
  }
}
```

### Webpack

Use in a webpack plugin or loader hook:

```javascript
const { exec } = require('child_process');

class ImageOptimizePlugin {
  apply(compiler) {
    compiler.hooks.afterEmit.tap('ImageOptimizePlugin', () => {
      exec('batch-optimize dist/images dist/optimized --max-bytes 100000');
    });
  }
}
```

### GitHub Actions

```yaml
name: Optimize Images

on: [push]

jobs:
  optimize:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build Pyjamaz
        run: zig build
      - name: Install dependencies
        run: |
          cd examples/nodejs/batch-processor
          npm install
      - name: Optimize images
        run: npm run cli -- images/ optimized/ --max-bytes 100000
      - name: Upload optimized images
        uses: actions/upload-artifact@v2
        with:
          name: optimized-images
          path: optimized/
```

## Troubleshooting

### No images found

Make sure your input directory contains supported image formats (JPEG, PNG, WebP, AVIF).

```bash
# Check what files are in the directory
ls -lh input-dir/
```

### Module not found

```bash
# Build the main library first
cd ../../../bindings/nodejs
npm install
npm run build

# Then install batch processor
cd ../../examples/nodejs/batch-processor
npm install
npm run build
```

### Out of memory errors

Reduce concurrency:

```bash
npm run cli -- images/ output/ --concurrency 2
```

### Permission errors

Make sure you have write permissions:

```bash
chmod +w output-dir/
```

## License

MIT
