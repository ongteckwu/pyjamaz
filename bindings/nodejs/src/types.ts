/**
 * Image format types supported by Pyjamaz
 */
export type ImageFormat = 'jpeg' | 'png' | 'webp' | 'avif';

/**
 * Perceptual quality metrics
 */
export type MetricType = 'dssim' | 'ssimulacra2' | 'none';

/**
 * Options for image optimization
 */
export interface OptimizeOptions {
  /**
   * Maximum output size in bytes (undefined = no limit)
   */
  maxBytes?: number;

  /**
   * Maximum perceptual difference (undefined = no limit)
   */
  maxDiff?: number;

  /**
   * Perceptual metric to use
   * @default 'dssim'
   */
  metric?: MetricType;

  /**
   * List of formats to try (undefined = try all formats)
   */
  formats?: ImageFormat[];

  /**
   * Number of parallel encoding threads (1-8)
   * @default 4
   */
  concurrency?: number;

  /**
   * Enable caching for faster repeated optimizations
   * @default true
   */
  cacheEnabled?: boolean;

  /**
   * Custom cache directory (undefined = default ~/.cache/pyjamaz)
   */
  cacheDir?: string;

  /**
   * Maximum cache size in bytes
   * @default 1073741824 (1GB)
   */
  cacheMaxSize?: number;
}

/**
 * Result of image optimization
 */
export interface OptimizeResult {
  /**
   * Optimized image data as Buffer
   */
  data: Buffer;

  /**
   * Selected output format
   */
  format: ImageFormat;

  /**
   * Perceptual difference score
   */
  diffValue: number;

  /**
   * Whether optimization met all constraints
   */
  passed: boolean;

  /**
   * Error message if failed (undefined if passed)
   */
  errorMessage?: string;

  /**
   * Size of optimized image in bytes
   */
  readonly size: number;

  /**
   * Save the optimized image to a file (async)
   * @param outputPath - Path to save the output file
   */
  save(outputPath: string): Promise<void>;

  /**
   * Save the optimized image to a file (sync)
   * @param outputPath - Path to save the output file
   */
  saveSync(outputPath: string): void;
}

/**
 * Internal FFI structures (not exported)
 */

/** @internal */
export interface COptimizeOptions {
  input_bytes: Buffer;
  input_len: number;
  max_bytes: number;
  max_diff: number;
  metric: number;
  formats: Buffer;
  formats_len: number;
  concurrency: number;
  cache_enabled: number;
  cache_dir: Buffer;
  cache_dir_len: number;
  cache_max_size: number;
}

/** @internal */
export interface COptimizeResult {
  output_bytes: Buffer;
  output_len: number;
  format: number;
  diff_value: number;
  passed: number;
  error_message: Buffer;
  error_len: number;
}

/**
 * Error thrown by Pyjamaz operations
 */
export class PyjamazError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PyjamazError';
  }
}
