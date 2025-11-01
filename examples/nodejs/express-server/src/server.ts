/**
 * Express.js Image Optimization Server
 *
 * A REST API for image optimization using Pyjamaz.
 * Demonstrates production-ready integration with Express.js.
 */

import express, { Request, Response, NextFunction } from 'express';
import multer from 'multer';
import * as pyjamaz from 'pyjamaz';

const app = express();
const PORT = process.env.PORT || 3000;

// Configure multer for handling file uploads (in-memory storage)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max
  },
  fileFilter: (_req, file, cb) => {
    // Accept only image files
    const allowedMimes = ['image/jpeg', 'image/png', 'image/webp', 'image/avif'];
    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only JPEG, PNG, WebP, and AVIF are allowed.'));
    }
  },
});

// Middleware
app.use(express.json());

// Health check endpoint
app.get('/health', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    version: pyjamaz.getVersion(),
    timestamp: new Date().toISOString(),
  });
});

// Get version endpoint
app.get('/version', (_req: Request, res: Response) => {
  res.json({
    pyjamaz: pyjamaz.getVersion(),
    node: process.version,
  });
});

/**
 * POST /optimize
 *
 * Optimize an uploaded image with various constraints.
 *
 * Body (multipart/form-data):
 * - image: File (required) - The image to optimize
 * - maxBytes: number (optional) - Maximum file size in bytes
 * - maxDiff: number (optional) - Maximum perceptual difference
 * - metric: string (optional) - Perceptual metric ('dssim' | 'ssimulacra2' | 'none')
 * - formats: string (optional) - Comma-separated list of formats to try
 *
 * Response:
 * - Binary image data with appropriate Content-Type header
 * - X-Pyjamaz-* headers with optimization metadata
 */
app.post('/optimize', upload.single('image'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    // Validate uploaded file
    if (!req.file) {
      return res.status(400).json({ error: 'No image file provided' });
    }

    // Parse options from form data
    const maxBytes = req.body.maxBytes ? parseInt(req.body.maxBytes, 10) : undefined;
    const maxDiff = req.body.maxDiff ? parseFloat(req.body.maxDiff) : undefined;
    const metric = req.body.metric as 'dssim' | 'ssimulacra2' | 'none' | undefined;
    const formats = req.body.formats ? req.body.formats.split(',').map((f: string) => f.trim()) : undefined;

    // Validate options
    if (maxBytes !== undefined && (isNaN(maxBytes) || maxBytes <= 0)) {
      return res.status(400).json({ error: 'Invalid maxBytes value' });
    }
    if (maxDiff !== undefined && (isNaN(maxDiff) || maxDiff < 0)) {
      return res.status(400).json({ error: 'Invalid maxDiff value' });
    }

    // Optimize image
    const startTime = Date.now();
    const result = await pyjamaz.optimizeImageFromBuffer(req.file.buffer, {
      maxBytes,
      maxDiff,
      metric: metric || 'dssim',
      formats: formats as pyjamaz.ImageFormat[] | undefined,
      cacheEnabled: true,
    });

    const processingTime = Date.now() - startTime;

    // Check if optimization succeeded
    if (!result.passed) {
      return res.status(422).json({
        error: 'Optimization failed',
        message: result.errorMessage || 'Could not meet constraints',
        originalSize: req.file.size,
      });
    }

    // Calculate compression ratio
    const compressionRatio = ((1 - result.size / req.file.buffer.length) * 100).toFixed(2);

    // Set response headers with optimization metadata
    res.setHeader('Content-Type', getContentType(result.format));
    res.setHeader('X-Pyjamaz-Original-Size', req.file.buffer.length.toString());
    res.setHeader('X-Pyjamaz-Optimized-Size', result.size.toString());
    res.setHeader('X-Pyjamaz-Compression-Ratio', compressionRatio);
    res.setHeader('X-Pyjamaz-Format', result.format);
    res.setHeader('X-Pyjamaz-Quality-Score', result.diffValue.toFixed(6));
    res.setHeader('X-Pyjamaz-Processing-Time', `${processingTime}ms`);

    // Send optimized image
    res.send(result.data);

  } catch (error) {
    next(error);
  }
});

/**
 * POST /optimize/batch
 *
 * Optimize multiple images in a single request.
 */
app.post('/optimize/batch', upload.array('images', 10), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const files = req.files as Express.Multer.File[];

    if (!files || files.length === 0) {
      return res.status(400).json({ error: 'No image files provided' });
    }

    // Parse options
    const maxBytes = req.body.maxBytes ? parseInt(req.body.maxBytes, 10) : undefined;
    const maxDiff = req.body.maxDiff ? parseFloat(req.body.maxDiff) : undefined;
    const metric = req.body.metric as 'dssim' | 'ssimulacra2' | 'none' | undefined;

    // Optimize all images
    const results = await Promise.all(
      files.map(async (file, index) => {
        try {
          const startTime = Date.now();
          const result = await pyjamaz.optimizeImageFromBuffer(file.buffer, {
            maxBytes,
            maxDiff,
            metric: metric || 'dssim',
            cacheEnabled: true,
          });

          const processingTime = Date.now() - startTime;
          const compressionRatio = ((1 - result.size / file.buffer.length) * 100).toFixed(2);

          return {
            index,
            filename: file.originalname,
            success: result.passed,
            originalSize: file.buffer.length,
            optimizedSize: result.size,
            compressionRatio: `${compressionRatio}%`,
            format: result.format,
            qualityScore: result.diffValue,
            processingTime: `${processingTime}ms`,
            error: result.errorMessage,
          };
        } catch (error) {
          return {
            index,
            filename: file.originalname,
            success: false,
            error: error instanceof Error ? error.message : 'Unknown error',
          };
        }
      })
    );

    // Return summary
    res.json({
      total: files.length,
      successful: results.filter((r) => r.success).length,
      failed: results.filter((r) => !r.success).length,
      results,
    });

  } catch (error) {
    next(error);
  }
});

/**
 * Error handler
 */
app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error('Error:', err);

  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ error: 'File too large. Maximum size is 10MB.' });
    }
    return res.status(400).json({ error: err.message });
  }

  res.status(500).json({
    error: 'Internal server error',
    message: err.message,
  });
});

// Helper function to get Content-Type from image format
function getContentType(format: string): string {
  const contentTypes: Record<string, string> = {
    jpeg: 'image/jpeg',
    jpg: 'image/jpeg',
    png: 'image/png',
    webp: 'image/webp',
    avif: 'image/avif',
  };
  return contentTypes[format] || 'application/octet-stream';
}

// Start server
app.listen(PORT, () => {
  console.log('='.repeat(60));
  console.log('🚀 Pyjamaz Express Server');
  console.log('='.repeat(60));
  console.log(`📍 Server running on http://localhost:${PORT}`);
  console.log(`📦 Pyjamaz version: ${pyjamaz.getVersion()}`);
  console.log(`\n📡 Endpoints:`);
  console.log(`   GET  /health          - Health check`);
  console.log(`   GET  /version         - Get version info`);
  console.log(`   POST /optimize        - Optimize single image`);
  console.log(`   POST /optimize/batch  - Optimize multiple images`);
  console.log('='.repeat(60));
});
