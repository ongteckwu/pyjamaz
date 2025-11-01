/**
 * FFI bindings layer for Pyjamaz shared library
 */

import ffi from 'ffi-napi';
import ref from 'ref-napi';
import path from 'path';
import fs from 'fs';

/**
 * Error thrown by FFI binding layer
 */
export class PyjamazBindingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PyjamazBindingError';
  }
}

// Define C types
const CharPtr = ref.refType(ref.types.char);
const VoidPtr = ref.refType(ref.types.void);

// OptimizeOptions struct layout
const OptimizeOptionsStruct = ffi.Struct({
  input_bytes: CharPtr,
  input_len: ref.types.size_t,
  max_bytes: ref.types.uint32,
  max_diff: ref.types.double,
  metric: ref.types.uint8,
  formats: CharPtr,
  formats_len: ref.types.size_t,
  concurrency: ref.types.uint32,
  cache_enabled: ref.types.uint8,
  cache_dir: CharPtr,
  cache_dir_len: ref.types.size_t,
  cache_max_size: ref.types.uint64,
});

// OptimizeResult struct layout
const OptimizeResultStruct = ffi.Struct({
  output_bytes: CharPtr,
  output_len: ref.types.size_t,
  format: ref.types.uint8,
  diff_value: ref.types.double,
  passed: ref.types.uint8,
  error_message: CharPtr,
  error_len: ref.types.size_t,
});

const OptimizeOptionsPtr = ref.refType(OptimizeOptionsStruct);
const OptimizeResultPtr = ref.refType(OptimizeResultStruct);

/**
 * Find the Pyjamaz shared library
 *
 * Search order:
 * 1. PYJAMAZ_LIB_PATH environment variable
 * 2. Bundled library (for npm package installations)
 * 3. Development build (zig-out/lib)
 * 4. System paths
 */
function findLibrary(): string {
  // 1. Check environment variable first (highest priority)
  const envPath = process.env.PYJAMAZ_LIB_PATH;
  if (envPath && fs.existsSync(envPath)) {
    return envPath;
  }

  const possiblePaths: string[] = [];

  // 2. Check bundled library (npm package installation)
  // When installed via npm, libraries are in ../native/ relative to dist/
  const bundledPaths = [
    path.join(__dirname, '..', 'native', 'libpyjamaz.dylib'),
    path.join(__dirname, '..', 'native', 'libpyjamaz.so'),
    path.join(__dirname, '..', 'native', 'pyjamaz.dll'),
  ];
  possiblePaths.push(...bundledPaths);

  // 3. Check development build (from source)
  // From bindings/nodejs/dist to zig-out/lib
  const devPaths = [
    path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'libpyjamaz.dylib'),
    path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'libpyjamaz.so'),
    path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'pyjamaz.dll'),
  ];
  possiblePaths.push(...devPaths);

  // 4. Check system paths
  const systemPaths = [
    '/usr/local/lib/libpyjamaz.dylib',
    '/usr/local/lib/libpyjamaz.so',
    '/usr/lib/libpyjamaz.so',
  ];
  possiblePaths.push(...systemPaths);

  // Try all paths in order
  for (const libPath of possiblePaths) {
    if (fs.existsSync(libPath)) {
      return libPath;
    }
  }

  throw new Error(
    'Could not find libpyjamaz shared library. Tried:\n' +
    possiblePaths.map(p => `  - ${p}`).join('\n') + '\n\n' +
    'Please either:\n' +
    '  1. Install via npm (npm install pyjamaz)\n' +
    '  2. Build from source (zig build)\n' +
    '  3. Set PYJAMAZ_LIB_PATH environment variable'
  );
}

/**
 * Load the Pyjamaz shared library
 */
const libPath = findLibrary();
const lib = ffi.Library(libPath, {
  pyjamaz_version: ['string', []],
  pyjamaz_optimize: [OptimizeResultPtr, [OptimizeOptionsPtr]],
  pyjamaz_free_result: ['void', [OptimizeResultPtr]],
  pyjamaz_cleanup: ['void', []],
});

/**
 * Cleanup function to be called on process exit
 */
let cleanupRegistered = false;

export function registerCleanup(): void {
  if (cleanupRegistered) return;
  cleanupRegistered = true;

  // Register cleanup handlers
  const cleanup = () => {
    try {
      if (lib.pyjamaz_cleanup) {
        lib.pyjamaz_cleanup();
      }
    } catch (err) {
      console.error('Error during cleanup:', err);
    }
  };

  process.on('exit', cleanup);
  process.on('SIGINT', () => {
    cleanup();
    process.exit(130);
  });
  process.on('SIGTERM', () => {
    cleanup();
    process.exit(143);
  });
}

/**
 * Get Pyjamaz library version
 */
export function getVersion(): string {
  return lib.pyjamaz_version();
}

/**
 * Internal: Map format string to enum value
 */
function formatToEnum(format: string): number {
  switch (format) {
    case 'jpeg': return 0;
    case 'png': return 1;
    case 'webp': return 2;
    case 'avif': return 3;
    default: return 0;
  }
}

/**
 * Internal: Map enum value to format string
 */
function enumToFormat(value: number): string {
  switch (value) {
    case 0: return 'jpeg';
    case 1: return 'png';
    case 2: return 'webp';
    case 3: return 'avif';
    default: return 'jpeg';
  }
}

/**
 * Internal: Map metric string to enum value
 */
function metricToEnum(metric: string): number {
  switch (metric) {
    case 'dssim': return 0;
    case 'ssimulacra2': return 1;
    case 'none': return 2;
    default: return 0;
  }
}

/**
 * Optimize an image using the Pyjamaz library
 */
export function optimize(
  inputData: Buffer,
  options: {
    maxBytes?: number;
    maxDiff?: number;
    metric?: string;
    formats?: string[];
    concurrency?: number;
    cacheEnabled?: boolean;
    cacheDir?: string;
    cacheMaxSize?: number;
  }
): { data: Buffer; format: string; diffValue: number; passed: boolean; errorMessage?: string } {
  registerCleanup();

  // Prepare formats array
  const formats = options.formats || ['jpeg', 'png', 'webp', 'avif'];
  const formatsBuffer = Buffer.from(formats.map(formatToEnum));

  // Prepare cache directory
  const cacheDir = options.cacheDir || '';
  const cacheDirBuffer = Buffer.from(cacheDir + '\0', 'utf8');

  // Create options struct
  const opts = new OptimizeOptionsStruct({
    input_bytes: inputData,
    input_len: inputData.length,
    max_bytes: options.maxBytes || 0,
    max_diff: options.maxDiff || 0.0,
    metric: metricToEnum(options.metric || 'dssim'),
    formats: formatsBuffer,
    formats_len: formatsBuffer.length,
    concurrency: options.concurrency || 4,
    cache_enabled: options.cacheEnabled === false ? 0 : 1,
    cache_dir: cacheDirBuffer,
    cache_dir_len: cacheDirBuffer.length,
    cache_max_size: options.cacheMaxSize || 1024 * 1024 * 1024,
  });

  // Call the FFI function
  const resultPtr = lib.pyjamaz_optimize(opts.ref());

  if (resultPtr.isNull()) {
    throw new PyjamazBindingError('Optimization failed: returned null pointer');
  }

  try {
    // Read the result struct
    const result = resultPtr.deref();

    // Tiger Style: Validate C memory before reading
    let data: Buffer;
    if (result.output_len > 0) {
      // Validate output pointer
      if (result.output_bytes.isNull()) {
        throw new PyjamazBindingError('Invalid result: output_bytes is null but output_len > 0');
      }

      // Sanity check size (max 100MB)
      const MAX_OUTPUT_SIZE = 100 * 1024 * 1024;
      if (result.output_len > MAX_OUTPUT_SIZE) {
        throw new PyjamazBindingError(`Output size too large: ${result.output_len} bytes (max ${MAX_OUTPUT_SIZE})`);
      }

      const outputData = ref.reinterpret(result.output_bytes, result.output_len, 0);
      data = Buffer.from(outputData);
    } else {
      data = Buffer.alloc(0);
    }

    // Read error message if present
    let errorMessage: string | undefined;
    if (result.error_len > 0) {
      if (result.error_message.isNull()) {
        errorMessage = 'Unknown error (null message)';
      } else {
        // Sanity check error length (max 1KB)
        const MAX_ERROR_LEN = 1024;
        const actualLen = Math.min(result.error_len, MAX_ERROR_LEN);

        try {
          const errorData = ref.reinterpret(result.error_message, actualLen, 0);
          errorMessage = errorData.toString('utf8');
        } catch (err) {
          errorMessage = 'Invalid UTF-8 in error message';
        }
      }
    }

    return {
      data,
      format: enumToFormat(result.format),
      diffValue: result.diff_value,
      passed: result.passed !== 0,
      errorMessage,
    };
  } finally {
    // Free the result
    lib.pyjamaz_free_result(resultPtr);
  }
}

export { OptimizeOptionsStruct, OptimizeResultStruct };
