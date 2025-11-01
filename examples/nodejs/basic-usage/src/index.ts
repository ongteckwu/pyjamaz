/**
 * Basic Usage Examples for Pyjamaz
 *
 * This example demonstrates:
 * - Simple image optimization with size constraints
 * - Quality-based optimization with perceptual metrics
 * - Both async and sync APIs
 * - Caching for performance improvements
 */

import * as pyjamaz from 'pyjamaz';
import * as fs from 'fs';
import * as path from 'path';

const SAMPLE_IMAGE = path.join(__dirname, '../test-images/sample.jpg');

async function main() {
  console.log('='.repeat(60));
  console.log('Pyjamaz Basic Usage Examples');
  console.log(`Version: ${pyjamaz.getVersion()}`);
  console.log('='.repeat(60));
  console.log();

  // Check if sample image exists
  if (!fs.existsSync(SAMPLE_IMAGE)) {
    console.error(`❌ Sample image not found: ${SAMPLE_IMAGE}`);
    console.log('\nPlease add a sample.jpg file to the test-images directory.');
    console.log('You can use any JPEG image for testing.\n');
    process.exit(1);
  }

  const originalSize = fs.statSync(SAMPLE_IMAGE).size;
  console.log(`📁 Sample image: ${path.basename(SAMPLE_IMAGE)}`);
  console.log(`📊 Original size: ${formatBytes(originalSize)}\n`);

  // Example 1: Simple size optimization (async)
  await example1_sizeOptimization();

  // Example 2: Quality-based optimization
  await example2_qualityOptimization();

  // Example 3: Synchronous API
  example3_syncAPI();

  // Example 4: Multiple format selection
  await example4_formatSelection();

  // Example 5: Caching demonstration
  example5_caching();

  // Example 6: Dual constraints
  await example6_dualConstraints();

  console.log('\n' + '='.repeat(60));
  console.log('✅ All examples completed!');
  console.log('='.repeat(60));
}

/**
 * Example 1: Simple size optimization
 */
async function example1_sizeOptimization() {
  console.log('📝 Example 1: Size Optimization (Async)');
  console.log('-'.repeat(60));

  try {
    const result = await pyjamaz.optimizeImage(SAMPLE_IMAGE, {
      maxBytes: 100_000, // 100KB target
    });

    if (result.passed) {
      const outputPath = path.join(__dirname, '../output/example1_size.jpg');
      await result.save(outputPath);

      console.log(`✅ Success!`);
      console.log(`   Output: ${formatBytes(result.size)}`);
      console.log(`   Format: ${result.format}`);
      console.log(`   Quality: ${result.diffValue.toFixed(6)}`);
      console.log(`   Saved to: ${path.basename(outputPath)}`);
    } else {
      console.log(`❌ Failed: ${result.errorMessage}`);
    }
  } catch (error) {
    console.error(`❌ Error: ${error}`);
  }
  console.log();
}

/**
 * Example 2: Quality-based optimization with SSIMULACRA2
 */
async function example2_qualityOptimization() {
  console.log('📝 Example 2: Quality-Based Optimization (SSIMULACRA2)');
  console.log('-'.repeat(60));

  try {
    const result = await pyjamaz.optimizeImage(SAMPLE_IMAGE, {
      maxDiff: 0.002, // Maximum perceptual difference
      metric: 'ssimulacra2',
    });

    if (result.passed) {
      const outputPath = path.join(__dirname, '../output/example2_quality.webp');
      await result.save(outputPath);

      console.log(`✅ Success!`);
      console.log(`   Output: ${formatBytes(result.size)}`);
      console.log(`   Format: ${result.format}`);
      console.log(`   Quality: ${result.diffValue.toFixed(6)} (target: ≤0.002)`);
      console.log(`   Saved to: ${path.basename(outputPath)}`);
    } else {
      console.log(`❌ Failed: ${result.errorMessage}`);
    }
  } catch (error) {
    console.error(`❌ Error: ${error}`);
  }
  console.log();
}

/**
 * Example 3: Synchronous API
 */
function example3_syncAPI() {
  console.log('📝 Example 3: Synchronous API');
  console.log('-'.repeat(60));

  try {
    const result = pyjamaz.optimizeImageSync(SAMPLE_IMAGE, {
      maxBytes: 80_000,
      metric: 'dssim',
    });

    if (result.passed) {
      const outputPath = path.join(__dirname, '../output/example3_sync.jpg');
      result.saveSync(outputPath);

      console.log(`✅ Success!`);
      console.log(`   Output: ${formatBytes(result.size)}`);
      console.log(`   Format: ${result.format}`);
      console.log(`   Quality: ${result.diffValue.toFixed(6)}`);
      console.log(`   Saved to: ${path.basename(outputPath)}`);
    } else {
      console.log(`❌ Failed: ${result.errorMessage}`);
    }
  } catch (error) {
    console.error(`❌ Error: ${error}`);
  }
  console.log();
}

/**
 * Example 4: Format selection (WebP and AVIF only)
 */
async function example4_formatSelection() {
  console.log('📝 Example 4: Format Selection (WebP & AVIF only)');
  console.log('-'.repeat(60));

  try {
    const inputData = fs.readFileSync(SAMPLE_IMAGE);
    const result = await pyjamaz.optimizeImageFromBuffer(inputData, {
      formats: ['webp', 'avif'],
      maxBytes: 50_000,
    });

    if (result.passed) {
      const outputPath = path.join(__dirname, `../output/example4_formats.${result.format}`);
      await result.save(outputPath);

      console.log(`✅ Success!`);
      console.log(`   Output: ${formatBytes(result.size)}`);
      console.log(`   Format: ${result.format} (from [webp, avif])`);
      console.log(`   Quality: ${result.diffValue.toFixed(6)}`);
      console.log(`   Saved to: ${path.basename(outputPath)}`);
    } else {
      console.log(`❌ Failed: ${result.errorMessage}`);
    }
  } catch (error) {
    console.error(`❌ Error: ${error}`);
  }
  console.log();
}

/**
 * Example 5: Caching demonstration
 */
function example5_caching() {
  console.log('📝 Example 5: Caching Performance');
  console.log('-'.repeat(60));

  try {
    const options: pyjamaz.OptimizeOptions = {
      maxBytes: 100_000,
      cacheEnabled: true,
    };

    // First run - cache miss
    const start1 = Date.now();
    const result1 = pyjamaz.optimizeImageSync(SAMPLE_IMAGE, options);
    const time1 = Date.now() - start1;

    // Second run - cache hit
    const start2 = Date.now();
    const result2 = pyjamaz.optimizeImageSync(SAMPLE_IMAGE, options);
    const time2 = Date.now() - start2;

    console.log(`✅ Cache demonstration:`);
    console.log(`   First run:  ${time1}ms (cache miss)`);
    console.log(`   Second run: ${time2}ms (cache hit)`);
    console.log(`   Speedup:    ${(time1 / time2).toFixed(1)}x faster`);
    console.log(`   Size:       ${formatBytes(result1.size)}`);
  } catch (error) {
    console.error(`❌ Error: ${error}`);
  }
  console.log();
}

/**
 * Example 6: Dual constraints (size + quality)
 */
async function example6_dualConstraints() {
  console.log('📝 Example 6: Dual Constraints (Size + Quality)');
  console.log('-'.repeat(60));

  try {
    const result = await pyjamaz.optimizeImage(SAMPLE_IMAGE, {
      maxBytes: 75_000,     // Size constraint
      maxDiff: 0.001,       // Quality constraint
      metric: 'dssim',
    });

    if (result.passed) {
      const outputPath = path.join(__dirname, '../output/example6_dual.jpg');
      await result.save(outputPath);

      console.log(`✅ Success!`);
      console.log(`   Output: ${formatBytes(result.size)} (target: ≤75KB)`);
      console.log(`   Quality: ${result.diffValue.toFixed(6)} (target: ≤0.001)`);
      console.log(`   Format: ${result.format}`);
      console.log(`   Saved to: ${path.basename(outputPath)}`);
    } else {
      console.log(`❌ Failed: ${result.errorMessage}`);
    }
  } catch (error) {
    console.error(`❌ Error: ${error}`);
  }
  console.log();
}

/**
 * Helper: Format bytes to human-readable string
 */
function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

// Create output directory and run examples
const outputDir = path.join(__dirname, '../output');
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
