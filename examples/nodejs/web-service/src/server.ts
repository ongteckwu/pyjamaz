/**
 * Fastify Image Optimization Microservice
 *
 * A high-performance REST API for image optimization using Fastify and Pyjamaz.
 * Features structured logging, request validation, and production-ready patterns.
 */

import Fastify from 'fastify';
import multipart from '@fastify/multipart';
import * as pyjamaz from 'pyjamaz';

const fastify = Fastify({
  logger: {
    level: process.env.LOG_LEVEL || 'info',
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true,
        translateTime: 'HH:MM:ss Z',
        ignore: 'pid,hostname',
      },
    },
  },
});

// Register multipart for file uploads
fastify.register(multipart, {
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max
    files: 10, // Max 10 files per request
  },
});

/**
 * Health check endpoint
 */
fastify.get('/health', async () => {
  return {
    status: 'healthy',
    version: pyjamaz.getVersion(),
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  };
});

/**
 * Readiness check endpoint (for Kubernetes)
 */
fastify.get('/ready', async () => {
  return {
    status: 'ready',
    checks: {
      pyjamaz: 'ok',
    },
  };
});

/**
 * Version information
 */
fastify.get('/version', async () => {
  return {
    service: '1.0.0',
    pyjamaz: pyjamaz.getVersion(),
    node: process.version,
  };
});

/**
 * Optimize a single image
 *
 * POST /api/v1/optimize
 */
fastify.post<{
  Querystring: {
    maxBytes?: string;
    maxDiff?: string;
    metric?: string;
    formats?: string;
  };
}>('/api/v1/optimize', async (request, reply) => {
  const data = await request.file();

  if (!data) {
    return reply.code(400).send({
      error: 'BadRequest',
      message: 'No file provided',
    });
  }

  // Validate file type
  const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/avif'];
  if (!allowedTypes.includes(data.mimetype)) {
    return reply.code(400).send({
      error: 'BadRequest',
      message: 'Invalid file type. Only JPEG, PNG, WebP, and AVIF are supported.',
    });
  }

  try {
    // Read file buffer
    const buffer = await data.toBuffer();
    const originalSize = buffer.length;

    // Parse query parameters
    const maxBytes = request.query.maxBytes ? parseInt(request.query.maxBytes, 10) : undefined;
    const maxDiff = request.query.maxDiff ? parseFloat(request.query.maxDiff) : undefined;
    const metric = (request.query.metric || 'dssim') as 'dssim' | 'ssimulacra2' | 'none';
    const formats = request.query.formats?.split(',').map((f) => f.trim());

    // Validate parameters
    if (maxBytes !== undefined && (isNaN(maxBytes) || maxBytes <= 0)) {
      return reply.code(400).send({
        error: 'BadRequest',
        message: 'Invalid maxBytes parameter',
      });
    }

    if (maxDiff !== undefined && (isNaN(maxDiff) || maxDiff < 0)) {
      return reply.code(400).send({
        error: 'BadRequest',
        message: 'Invalid maxDiff parameter',
      });
    }

    // Optimize image
    const startTime = Date.now();
    const result = await pyjamaz.optimizeImageFromBuffer(buffer, {
      maxBytes,
      maxDiff,
      metric,
      formats: formats as pyjamaz.ImageFormat[] | undefined,
      cacheEnabled: true,
    });

    const processingTime = Date.now() - startTime;

    // Check if optimization succeeded
    if (!result.passed) {
      return reply.code(422).send({
        error: 'OptimizationFailed',
        message: result.errorMessage || 'Could not meet constraints',
        metadata: {
          originalSize,
          constraints: {
            maxBytes,
            maxDiff,
            metric,
          },
        },
      });
    }

    // Calculate metrics
    const compressionRatio = ((1 - result.size / originalSize) * 100).toFixed(2);

    // Log success
    request.log.info({
      operation: 'optimize',
      originalSize,
      optimizedSize: result.size,
      compressionRatio: `${compressionRatio}%`,
      format: result.format,
      processingTime: `${processingTime}ms`,
    });

    // Set response headers
    reply.header('Content-Type', getContentType(result.format));
    reply.header('X-Original-Size', originalSize.toString());
    reply.header('X-Optimized-Size', result.size.toString());
    reply.header('X-Compression-Ratio', compressionRatio);
    reply.header('X-Output-Format', result.format);
    reply.header('X-Quality-Score', result.diffValue.toFixed(6));
    reply.header('X-Processing-Time', `${processingTime}ms`);

    return reply.send(result.data);
  } catch (error) {
    request.log.error({ error }, 'Optimization failed');

    return reply.code(500).send({
      error: 'InternalServerError',
      message: error instanceof Error ? error.message : 'Unknown error',
    });
  }
});

/**
 * Batch optimization endpoint
 *
 * POST /api/v1/optimize/batch
 */
fastify.post<{
  Querystring: {
    maxBytes?: string;
    maxDiff?: string;
    metric?: string;
  };
}>('/api/v1/optimize/batch', async (request, reply) => {
  try {
    const parts = request.parts();
    const files: Array<{ filename: string; buffer: Buffer; mimetype: string }> = [];

    // Collect all files
    for await (const part of parts) {
      if (part.type === 'file') {
        const buffer = await part.toBuffer();
        files.push({
          filename: part.filename,
          buffer,
          mimetype: part.mimetype,
        });
      }
    }

    if (files.length === 0) {
      return reply.code(400).send({
        error: 'BadRequest',
        message: 'No files provided',
      });
    }

    // Parse parameters
    const maxBytes = request.query.maxBytes ? parseInt(request.query.maxBytes, 10) : undefined;
    const maxDiff = request.query.maxDiff ? parseFloat(request.query.maxDiff) : undefined;
    const metric = (request.query.metric || 'dssim') as 'dssim' | 'ssimulacra2' | 'none';

    // Process all files
    const results = await Promise.all(
      files.map(async (file, index) => {
        try {
          const startTime = Date.now();
          const result = await pyjamaz.optimizeImageFromBuffer(file.buffer, {
            maxBytes,
            maxDiff,
            metric,
            cacheEnabled: true,
          });

          const processingTime = Date.now() - startTime;
          const compressionRatio = ((1 - result.size / file.buffer.length) * 100).toFixed(2);

          return {
            index,
            filename: file.filename,
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
            filename: file.filename,
            success: false,
            error: error instanceof Error ? error.message : 'Unknown error',
          };
        }
      })
    );

    const successful = results.filter((r) => r.success);
    const failed = results.filter((r) => !r.success);

    // Log batch results
    request.log.info({
      operation: 'batch_optimize',
      total: files.length,
      successful: successful.length,
      failed: failed.length,
    });

    return {
      summary: {
        total: files.length,
        successful: successful.length,
        failed: failed.length,
      },
      results,
    };
  } catch (error) {
    request.log.error({ error }, 'Batch optimization failed');

    return reply.code(500).send({
      error: 'InternalServerError',
      message: error instanceof Error ? error.message : 'Unknown error',
    });
  }
});

/**
 * Metrics endpoint (Prometheus-style)
 */
fastify.get('/metrics', async () => {
  const memUsage = process.memoryUsage();

  return `# HELP pyjamaz_memory_usage Memory usage in bytes
# TYPE pyjamaz_memory_usage gauge
pyjamaz_memory_usage{type="rss"} ${memUsage.rss}
pyjamaz_memory_usage{type="heapTotal"} ${memUsage.heapTotal}
pyjamaz_memory_usage{type="heapUsed"} ${memUsage.heapUsed}
pyjamaz_memory_usage{type="external"} ${memUsage.external}

# HELP pyjamaz_uptime_seconds Service uptime in seconds
# TYPE pyjamaz_uptime_seconds counter
pyjamaz_uptime_seconds ${process.uptime()}
`;
});

/**
 * Helper: Get Content-Type from format
 */
function getContentType(format: string): string {
  const types: Record<string, string> = {
    jpeg: 'image/jpeg',
    jpg: 'image/jpeg',
    png: 'image/png',
    webp: 'image/webp',
    avif: 'image/avif',
  };
  return types[format] || 'application/octet-stream';
}

/**
 * Start server
 */
const start = async () => {
  try {
    const port = parseInt(process.env.PORT || '3000', 10);
    const host = process.env.HOST || '0.0.0.0';

    await fastify.listen({ port, host });

    console.log('');
    console.log('='.repeat(60));
    console.log('🚀 Pyjamaz Image Optimization Microservice');
    console.log('='.repeat(60));
    console.log(`📍 Server:    http://${host}:${port}`);
    console.log(`📦 Pyjamaz:   v${pyjamaz.getVersion()}`);
    console.log(`⚡ Fastify:   v${fastify.version}`);
    console.log('');
    console.log('📡 Endpoints:');
    console.log('   GET  /health              - Health check');
    console.log('   GET  /ready               - Readiness check');
    console.log('   GET  /version             - Version info');
    console.log('   GET  /metrics             - Prometheus metrics');
    console.log('   POST /api/v1/optimize     - Optimize single image');
    console.log('   POST /api/v1/optimize/batch - Optimize multiple images');
    console.log('='.repeat(60));
    console.log('');
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();
