#!/usr/bin/env node

/**
 * Batch Image Processor CLI
 *
 * A command-line tool for batch optimizing images using Pyjamaz.
 * Features progress bars, detailed reporting, and parallel processing.
 */

import { Command } from 'commander';
import * as pyjamaz from 'pyjamaz';
import * as fs from 'fs';
import * as path from 'path';
import chalk from 'chalk';
import ora from 'ora';
import cliProgress from 'cli-progress';

const program = new Command();

interface ProcessingOptions {
  inputDir: string;
  outputDir: string;
  maxBytes?: number;
  maxDiff?: number;
  metric: 'dssim' | 'ssimulacra2' | 'none';
  formats?: pyjamaz.ImageFormat[];
  concurrency: number;
  recursive: boolean;
  verbose: boolean;
}

interface ProcessResult {
  success: boolean;
  filename: string;
  originalSize: number;
  optimizedSize?: number;
  compressionRatio?: number;
  format?: string;
  qualityScore?: number;
  processingTime?: number;
  error?: string;
}

// Configure CLI
program
  .name('batch-optimize')
  .description('Batch optimize images using Pyjamaz')
  .version(pyjamaz.getVersion())
  .argument('<input-dir>', 'Input directory containing images')
  .argument('<output-dir>', 'Output directory for optimized images')
  .option('-b, --max-bytes <bytes>', 'Maximum file size in bytes', parseInt)
  .option('-d, --max-diff <diff>', 'Maximum perceptual difference', parseFloat)
  .option('-m, --metric <metric>', 'Perceptual metric (dssim|ssimulacra2|none)', 'dssim')
  .option('-f, --formats <formats>', 'Comma-separated list of formats (jpeg,png,webp,avif)')
  .option('-c, --concurrency <num>', 'Number of parallel workers', '4')
  .option('-r, --recursive', 'Process subdirectories recursively', false)
  .option('-v, --verbose', 'Verbose output', false)
  .action(async (inputDir: string, outputDir: string, options: any) => {
    const processingOptions: ProcessingOptions = {
      inputDir,
      outputDir,
      maxBytes: options.maxBytes,
      maxDiff: options.maxDiff,
      metric: options.metric,
      formats: options.formats ? options.formats.split(',').map((f: string) => f.trim()) : undefined,
      concurrency: parseInt(options.concurrency, 10),
      recursive: options.recursive,
      verbose: options.verbose,
    };

    await processBatch(processingOptions);
  });

/**
 * Main batch processing function
 */
async function processBatch(options: ProcessingOptions): Promise<void> {
  console.log(chalk.cyan('='.repeat(60)));
  console.log(chalk.cyan.bold('Pyjamaz Batch Image Processor'));
  console.log(chalk.cyan('='.repeat(60)));
  console.log();

  // Validate input directory
  if (!fs.existsSync(options.inputDir)) {
    console.error(chalk.red(`❌ Input directory not found: ${options.inputDir}`));
    process.exit(1);
  }

  // Create output directory
  if (!fs.existsSync(options.outputDir)) {
    fs.mkdirSync(options.outputDir, { recursive: true });
  }

  // Find all images
  const spinner = ora('Scanning for images...').start();
  const images = findImages(options.inputDir, options.recursive);
  spinner.succeed(`Found ${chalk.green(images.length)} images to process`);

  if (images.length === 0) {
    console.log(chalk.yellow('No images found. Exiting.'));
    process.exit(0);
  }

  // Display configuration
  console.log();
  console.log(chalk.gray('Configuration:'));
  console.log(chalk.gray(`  Input:       ${options.inputDir}`));
  console.log(chalk.gray(`  Output:      ${options.outputDir}`));
  if (options.maxBytes) console.log(chalk.gray(`  Max Size:    ${formatBytes(options.maxBytes)}`));
  if (options.maxDiff) console.log(chalk.gray(`  Max Diff:    ${options.maxDiff}`));
  console.log(chalk.gray(`  Metric:      ${options.metric}`));
  if (options.formats) console.log(chalk.gray(`  Formats:     ${options.formats.join(', ')}`));
  console.log(chalk.gray(`  Workers:     ${options.concurrency}`));
  console.log();

  // Process images with progress bar
  const progressBar = new cliProgress.SingleBar({
    format: 'Progress |' + chalk.cyan('{bar}') + '| {percentage}% | {value}/{total} | {filename}',
    barCompleteChar: '\u2588',
    barIncompleteChar: '\u2591',
  });

  progressBar.start(images.length, 0, { filename: '' });

  const results: ProcessResult[] = [];
  const startTime = Date.now();

  // Process with concurrency control
  for (let i = 0; i < images.length; i += options.concurrency) {
    const batch = images.slice(i, i + options.concurrency);
    const batchResults = await Promise.all(
      batch.map((imagePath) => processImage(imagePath, options))
    );

    results.push(...batchResults);
    progressBar.update(results.length, { filename: path.basename(batch[batch.length - 1]) });
  }

  progressBar.stop();

  const totalTime = (Date.now() - startTime) / 1000;

  // Print detailed results if verbose
  if (options.verbose) {
    console.log();
    console.log(chalk.gray('Detailed Results:'));
    console.log(chalk.gray('-'.repeat(60)));

    for (const result of results) {
      if (result.success) {
        const reduction = result.compressionRatio!.toFixed(1);
        console.log(
          chalk.green('✓'),
          chalk.white(result.filename.padEnd(30)),
          chalk.gray(`${formatBytes(result.originalSize)} →`),
          chalk.green(formatBytes(result.optimizedSize!)),
          chalk.gray(`(${reduction}%)`)
        );
      } else {
        console.log(
          chalk.red('✗'),
          chalk.white(result.filename.padEnd(30)),
          chalk.red(result.error || 'Failed')
        );
      }
    }
  }

  // Print summary
  printSummary(results, totalTime);
}

/**
 * Process a single image
 */
async function processImage(
  inputPath: string,
  options: ProcessingOptions
): Promise<ProcessResult> {
  const filename = path.basename(inputPath);
  const originalSize = fs.statSync(inputPath).size;

  try {
    const startTime = Date.now();

    const result = await pyjamaz.optimizeImage(inputPath, {
      maxBytes: options.maxBytes,
      maxDiff: options.maxDiff,
      metric: options.metric,
      formats: options.formats,
      concurrency: 1, // Already managing concurrency at batch level
      cacheEnabled: true,
    });

    const processingTime = Date.now() - startTime;

    if (result.passed) {
      // Determine output filename
      const outputFilename = path.basename(inputPath, path.extname(inputPath)) + `.${result.format}`;
      const outputPath = path.join(options.outputDir, outputFilename);

      // Save optimized image
      await result.save(outputPath);

      const compressionRatio = ((1 - result.size / originalSize) * 100);

      return {
        success: true,
        filename,
        originalSize,
        optimizedSize: result.size,
        compressionRatio,
        format: result.format,
        qualityScore: result.diffValue,
        processingTime,
      };
    } else {
      return {
        success: false,
        filename,
        originalSize,
        error: result.errorMessage || 'Optimization failed',
      };
    }
  } catch (error) {
    return {
      success: false,
      filename,
      originalSize,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Find all image files in directory
 */
function findImages(dir: string, recursive: boolean): string[] {
  const images: string[] = [];
  const imageExtensions = new Set(['.jpg', '.jpeg', '.png', '.webp', '.avif']);

  function scan(directory: string) {
    const files = fs.readdirSync(directory);

    for (const file of files) {
      const filePath = path.join(directory, file);
      const stat = fs.statSync(filePath);

      if (stat.isDirectory() && recursive) {
        scan(filePath);
      } else if (stat.isFile()) {
        const ext = path.extname(file).toLowerCase();
        if (imageExtensions.has(ext)) {
          images.push(filePath);
        }
      }
    }
  }

  scan(dir);
  return images;
}

/**
 * Print summary statistics
 */
function printSummary(results: ProcessResult[], totalTime: number): void {
  const successful = results.filter((r) => r.success);
  const failed = results.filter((r) => !r.success);

  console.log();
  console.log(chalk.cyan('='.repeat(60)));
  console.log(chalk.cyan.bold('Summary'));
  console.log(chalk.cyan('='.repeat(60)));

  console.log();
  console.log(chalk.white(`Total images:     ${results.length}`));
  console.log(chalk.green(`Successful:       ${successful.length}`));
  if (failed.length > 0) {
    console.log(chalk.red(`Failed:           ${failed.length}`));
  }

  if (successful.length > 0) {
    const totalOriginal = successful.reduce((sum, r) => sum + r.originalSize, 0);
    const totalOptimized = successful.reduce((sum, r) => sum + (r.optimizedSize || 0), 0);
    const totalReduction = ((1 - totalOptimized / totalOriginal) * 100);
    const avgProcessingTime = successful.reduce((sum, r) => sum + (r.processingTime || 0), 0) / successful.length;

    console.log();
    console.log(chalk.white(`Original size:    ${formatBytes(totalOriginal)}`));
    console.log(chalk.green(`Optimized size:   ${formatBytes(totalOptimized)}`));
    console.log(chalk.green(`Saved:            ${formatBytes(totalOriginal - totalOptimized)} (${totalReduction.toFixed(1)}%)`));
    console.log();
    console.log(chalk.white(`Total time:       ${totalTime.toFixed(2)}s`));
    console.log(chalk.white(`Avg per image:    ${avgProcessingTime.toFixed(0)}ms`));
  }

  console.log(chalk.cyan('='.repeat(60)));
}

/**
 * Format bytes to human-readable string
 */
function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

// Parse and run CLI
program.parse();
