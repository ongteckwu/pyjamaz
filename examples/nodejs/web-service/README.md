# Pyjamaz Web Service (Fastify)

A production-ready, high-performance image optimization microservice built with Fastify and Pyjamaz.

## Features

- ✅ High-performance Fastify server
- ✅ Structured logging with Pino
- ✅ Request validation and error handling
- ✅ Health and readiness checks (Kubernetes-ready)
- ✅ Prometheus metrics endpoint
- ✅ Single and batch image optimization
- ✅ Query parameter configuration
- ✅ Production-ready patterns

## Installation

```bash
npm install
```

## Usage

### Development Mode

```bash
npm run dev
```

### Production Mode

```bash
npm run build
npm start
```

The service will start on `http://0.0.0.0:3000` by default.

## Environment Variables

```bash
PORT=3000              # Server port (default: 3000)
HOST=0.0.0.0          # Server host (default: 0.0.0.0)
LOG_LEVEL=info        # Log level (trace|debug|info|warn|error|fatal)
```

## API Documentation

### GET /health

Health check endpoint for monitoring.

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2025-10-31T12:00:00.000Z",
  "uptime": 123.456
}
```

### GET /ready

Readiness check for Kubernetes deployments.

**Response:**
```json
{
  "status": "ready",
  "checks": {
    "pyjamaz": "ok"
  }
}
```

### GET /version

Version information.

**Response:**
```json
{
  "service": "1.0.0",
  "pyjamaz": "1.0.0",
  "node": "v20.10.0"
}
```

### POST /api/v1/optimize

Optimize a single image.

**Query Parameters:**
- `maxBytes` (optional): Maximum file size in bytes
- `maxDiff` (optional): Maximum perceptual difference
- `metric` (optional): Perceptual metric (`dssim`, `ssimulacra2`, `none`)
- `formats` (optional): Comma-separated format list (e.g., `webp,avif`)

**Request:**
- Content-Type: `multipart/form-data`
- Field: `file` - Image file

**Response:**
- Binary image data
- Headers:
  - `Content-Type`: Image MIME type
  - `X-Original-Size`: Original file size
  - `X-Optimized-Size`: Optimized file size
  - `X-Compression-Ratio`: Compression percentage
  - `X-Output-Format`: Output format
  - `X-Quality-Score`: Perceptual quality score
  - `X-Processing-Time`: Processing time

**Example:**
```bash
curl -X POST "http://localhost:3000/api/v1/optimize?maxBytes=100000&metric=dssim" \
  -F "file=@image.jpg" \
  -o optimized.jpg \
  -v
```

### POST /api/v1/optimize/batch

Optimize multiple images in one request.

**Query Parameters:**
- `maxBytes` (optional): Maximum file size in bytes
- `maxDiff` (optional): Maximum perceptual difference
- `metric` (optional): Perceptual metric

**Request:**
- Content-Type: `multipart/form-data`
- Multiple file fields

**Response:**
```json
{
  "summary": {
    "total": 3,
    "successful": 3,
    "failed": 0
  },
  "results": [
    {
      "index": 0,
      "filename": "image1.jpg",
      "success": true,
      "originalSize": 500000,
      "optimizedSize": 95000,
      "compressionRatio": "81.00%",
      "format": "jpeg",
      "qualityScore": 0.000245,
      "processingTime": "87ms"
    }
  ]
}
```

**Example:**
```bash
curl -X POST "http://localhost:3000/api/v1/optimize/batch?maxBytes=100000" \
  -F "file1=@image1.jpg" \
  -F "file2=@image2.png" \
  -F "file3=@image3.webp"
```

### GET /metrics

Prometheus-style metrics.

**Response:**
```
# HELP pyjamaz_memory_usage Memory usage in bytes
# TYPE pyjamaz_memory_usage gauge
pyjamaz_memory_usage{type="rss"} 123456789
pyjamaz_memory_usage{type="heapTotal"} 87654321
pyjamaz_memory_usage{type="heapUsed"} 45678901
pyjamaz_memory_usage{type="external"} 12345678

# HELP pyjamaz_uptime_seconds Service uptime in seconds
# TYPE pyjamaz_uptime_seconds counter
pyjamaz_uptime_seconds 123.456
```

## Usage Examples

### 1. Basic Optimization

```bash
curl -X POST "http://localhost:3000/api/v1/optimize?maxBytes=100000" \
  -F "file=@test.jpg" \
  -o optimized.jpg
```

### 2. Quality-Based Optimization

```bash
curl -X POST "http://localhost:3000/api/v1/optimize?maxDiff=0.002&metric=ssimulacra2" \
  -F "file=@test.jpg" \
  -o optimized.webp
```

### 3. Format Selection

```bash
curl -X POST "http://localhost:3000/api/v1/optimize?formats=webp,avif&maxBytes=50000" \
  -F "file=@test.jpg" \
  -o optimized.webp
```

### 4. Batch Optimization

```bash
curl -X POST "http://localhost:3000/api/v1/optimize/batch?maxBytes=100000" \
  -F "image1=@photo1.jpg" \
  -F "image2=@photo2.png" \
  -F "image3=@photo3.webp" \
  | jq .
```

## Client Examples

### JavaScript/TypeScript

```typescript
import FormData from 'form-data';
import fs from 'fs';
import fetch from 'node-fetch';

async function optimizeImage(filePath: string) {
  const form = new FormData();
  form.append('file', fs.createReadStream(filePath));

  const response = await fetch(
    'http://localhost:3000/api/v1/optimize?maxBytes=100000',
    {
      method: 'POST',
      body: form,
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Optimization failed: ${error.message}`);
  }

  const buffer = await response.buffer();
  const optimizedSize = response.headers.get('X-Optimized-Size');
  const compressionRatio = response.headers.get('X-Compression-Ratio');

  console.log(`Optimized to ${optimizedSize} bytes (${compressionRatio}% reduction)`);

  fs.writeFileSync('optimized.jpg', buffer);
}
```

### Python

```python
import requests

def optimize_image(file_path: str):
    with open(file_path, 'rb') as f:
        files = {'file': f}
        params = {'maxBytes': 100000, 'metric': 'dssim'}

        response = requests.post(
            'http://localhost:3000/api/v1/optimize',
            files=files,
            params=params
        )

        if response.ok:
            with open('optimized.jpg', 'wb') as out:
                out.write(response.content)

            print(f"Optimized size: {response.headers['X-Optimized-Size']}")
            print(f"Compression: {response.headers['X-Compression-Ratio']}%")
        else:
            print(f"Error: {response.json()['message']}")
```

### cURL with jq

```bash
# Get detailed information
curl -X POST "http://localhost:3000/api/v1/optimize?maxBytes=100000" \
  -F "file=@test.jpg" \
  -o optimized.jpg \
  -v 2>&1 | grep "^< X-"
```

## Kubernetes Deployment

### Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pyjamaz-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pyjamaz-service
  template:
    metadata:
      labels:
        app: pyjamaz-service
    spec:
      containers:
      - name: pyjamaz
        image: your-registry/pyjamaz-service:latest
        ports:
        - containerPort: 3000
        env:
        - name: PORT
          value: "3000"
        - name: LOG_LEVEL
          value: "info"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: pyjamaz-service
spec:
  selector:
    app: pyjamaz-service
  ports:
  - port: 80
    targetPort: 3000
  type: LoadBalancer
```

### Horizontal Pod Autoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: pyjamaz-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: pyjamaz-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Docker Deployment

### Dockerfile

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Install Zig and build dependencies
RUN apk add --no-cache zig vips-dev

# Copy project files
COPY . .

# Build Pyjamaz library
RUN zig build

# Install Node.js dependencies and build
WORKDIR /app/examples/nodejs/web-service
RUN npm ci
RUN npm run build

# Expose port
EXPOSE 3000

# Start service
CMD ["node", "dist/server.js"]
```

### docker-compose.yml

```yaml
version: '3.8'

services:
  pyjamaz:
    build: .
    ports:
      - "3000:3000"
    environment:
      - PORT=3000
      - LOG_LEVEL=info
      - NODE_ENV=production
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## Monitoring

### Prometheus Configuration

```yaml
scrape_configs:
  - job_name: 'pyjamaz'
    static_configs:
      - targets: ['localhost:3000']
    metrics_path: '/metrics'
```

### Logging

Structured JSON logs with Pino:

```json
{
  "level": 30,
  "time": 1698765432000,
  "pid": 12345,
  "hostname": "server-1",
  "operation": "optimize",
  "originalSize": 524288,
  "optimizedSize": 98304,
  "compressionRatio": "81.25%",
  "format": "jpeg",
  "processingTime": "87ms"
}
```

## Performance

- **Throughput**: ~100-200 requests/second (single instance)
- **Latency**: 50-100ms per image (with caching: <10ms)
- **Memory**: ~256MB baseline, scales with concurrent requests
- **Concurrency**: Handles 100+ concurrent connections

## Error Responses

All errors follow a consistent format:

```json
{
  "error": "ErrorType",
  "message": "Human-readable error message"
}
```

**Error Codes:**
- `400` - Bad Request (invalid parameters)
- `413` - Payload Too Large (file > 10MB)
- `422` - Unprocessable Entity (optimization failed)
- `500` - Internal Server Error

## Production Best Practices

1. **Rate Limiting**: Use nginx or Fastify rate limit plugin
2. **HTTPS**: Always use TLS in production
3. **Monitoring**: Set up Prometheus + Grafana
4. **Logging**: Centralize logs with ELK or similar
5. **Caching**: Enable CDN caching for repeated images
6. **Scaling**: Use horizontal scaling with load balancer

## Troubleshooting

### High memory usage

Reduce concurrent connections or add more instances.

### Slow response times

Check if caching is enabled and working.

### Module not found

```bash
cd ../../../bindings/nodejs
npm install && npm run build
cd ../../examples/nodejs/web-service
npm install
```

## License

MIT
