# Pyjamaz Basic Usage Example

This example demonstrates the core features of Pyjamaz Node.js bindings with simple, easy-to-understand examples.

## Features Demonstrated

- ✅ Simple size-based optimization
- ✅ Quality-based optimization with perceptual metrics (DSSIM, SSIMULACRA2)
- ✅ Both async and sync APIs
- ✅ Format selection (JPEG, PNG, WebP, AVIF)
- ✅ Caching for performance improvements
- ✅ Dual constraints (size + quality)

## Installation

```bash
# Install dependencies
npm install

# Build the TypeScript code
npm run build
```

## Usage

```bash
# Run the compiled JavaScript
npm start

# Or run directly with ts-node
npm run start:ts
```

## What You'll See

The example will:

1. Load a sample image from `test-images/sample.jpg`
2. Run 6 different optimization scenarios
3. Save optimized images to the `output/` directory
4. Display detailed results for each optimization

## Prerequisites

Before running, make sure you have:

1. A sample JPEG image in `test-images/sample.jpg`
   - You can use any JPEG image for testing
   - Recommended: 500KB - 2MB image size

2. Built the Pyjamaz library:
   ```bash
   # From the project root
   zig build
   ```

## Example Output

```
============================================================
Pyjamaz Basic Usage Examples
Version: 1.0.0
============================================================

📁 Sample image: sample.jpg
📊 Original size: 1.25 MB

📝 Example 1: Size Optimization (Async)
------------------------------------------------------------
✅ Success!
   Output: 97.84 KB
   Format: jpeg
   Quality: 0.000245
   Saved to: example1_size.jpg

📝 Example 2: Quality-Based Optimization (SSIMULACRA2)
------------------------------------------------------------
✅ Success!
   Output: 156.32 KB
   Format: webp
   Quality: 0.001894 (target: ≤0.002)
   Saved to: example2_quality.webp

...
```

## TypeScript Support

This example is written in TypeScript and provides full type safety:

```typescript
import * as pyjamaz from 'pyjamaz';

// TypeScript will provide IntelliSense and type checking
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  metric: 'ssimulacra2', // Type-checked!
});

// Result type is fully typed
if (result.passed) {
  console.log(`Size: ${result.size} bytes`);
  console.log(`Format: ${result.format}`);
}
```

## Next Steps

After running this example, check out:

- **express-server** - Image optimization REST API
- **batch-processor** - Process multiple images in parallel
- **web-service** - Fastify-based microservice

## Troubleshooting

### Module not found error

If you see `Cannot find module 'pyjamaz'`:

```bash
# Make sure the main library is built
cd ../../../bindings/nodejs
npm install
npm run build

# Then install this example
cd ../../examples/nodejs/basic-usage
npm install
```

### Sample image not found

Add a sample JPEG image to `test-images/sample.jpg` before running.

### Library not found error

Make sure you've built the Pyjamaz library:

```bash
# From project root
zig build
```

The library should be at: `zig-out/lib/libpyjamaz.dylib` (macOS) or `.so` (Linux)
