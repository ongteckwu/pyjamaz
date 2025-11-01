# Pyjamaz Express Server Example

A production-ready REST API for image optimization using Express.js and Pyjamaz.

## Features

- ✅ Image upload via multipart/form-data
- ✅ Single image optimization endpoint
- ✅ Batch image optimization endpoint
- ✅ Comprehensive error handling
- ✅ Response headers with optimization metadata
- ✅ File type validation
- ✅ Size limits and constraints
- ✅ Caching for improved performance

## Installation

```bash
npm install
```

## Usage

### Start the server

```bash
# Build and start in production mode
npm start

# Or run in development mode with ts-node
npm run dev
```

The server will start on `http://localhost:3000`.

## API Endpoints

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "version": "1.0.0",
  "timestamp": "2025-10-31T12:00:00.000Z"
}
```

### GET /version

Get version information.

**Response:**
```json
{
  "pyjamaz": "1.0.0",
  "node": "v20.10.0"
}
```

### POST /optimize

Optimize a single image.

**Request (multipart/form-data):**
- `image` (file, required): Image file to optimize
- `maxBytes` (number, optional): Maximum file size in bytes
- `maxDiff` (number, optional): Maximum perceptual difference
- `metric` (string, optional): Perceptual metric (`dssim`, `ssimulacra2`, `none`)
- `formats` (string, optional): Comma-separated list of formats (e.g., `webp,avif`)

**Response:**
- Binary image data
- Headers:
  - `Content-Type`: Image MIME type
  - `X-Pyjamaz-Original-Size`: Original file size in bytes
  - `X-Pyjamaz-Optimized-Size`: Optimized file size in bytes
  - `X-Pyjamaz-Compression-Ratio`: Compression percentage
  - `X-Pyjamaz-Format`: Output format
  - `X-Pyjamaz-Quality-Score`: Perceptual quality score
  - `X-Pyjamaz-Processing-Time`: Processing time in milliseconds

**Example:**
```bash
curl -X POST http://localhost:3000/optimize \
  -F "image=@test-images/sample.jpg" \
  -F "maxBytes=100000" \
  -F "metric=dssim" \
  -o optimized.jpg -v
```

### POST /optimize/batch

Optimize multiple images in a single request.

**Request (multipart/form-data):**
- `images` (files, required): Multiple image files (max 10)
- `maxBytes` (number, optional): Maximum file size in bytes
- `maxDiff` (number, optional): Maximum perceptual difference
- `metric` (string, optional): Perceptual metric

**Response:**
```json
{
  "total": 3,
  "successful": 3,
  "failed": 0,
  "results": [
    {
      "index": 0,
      "filename": "image1.jpg",
      "success": true,
      "originalSize": 500000,
      "optimizedSize": 95000,
      "compressionRatio": "81.00%",
      "format": "jpeg",
      "qualityScore": 0.000123,
      "processingTime": "85ms"
    },
    ...
  ]
}
```

**Example:**
```bash
curl -X POST http://localhost:3000/optimize/batch \
  -F "images=@image1.jpg" \
  -F "images=@image2.png" \
  -F "images=@image3.webp" \
  -F "maxBytes=100000"
```

## Testing Examples

### 1. Basic optimization with size constraint

```bash
curl -X POST http://localhost:3000/optimize \
  -F "image=@test-images/sample.jpg" \
  -F "maxBytes=100000" \
  -o output.jpg -v
```

Check the response headers for optimization metadata:
```
X-Pyjamaz-Original-Size: 524288
X-Pyjamaz-Optimized-Size: 98304
X-Pyjamaz-Compression-Ratio: 81.25
X-Pyjamaz-Format: jpeg
X-Pyjamaz-Quality-Score: 0.000245
X-Pyjamaz-Processing-Time: 87ms
```

### 2. Quality-based optimization

```bash
curl -X POST http://localhost:3000/optimize \
  -F "image=@test-images/sample.jpg" \
  -F "maxDiff=0.002" \
  -F "metric=ssimulacra2" \
  -o output.webp -v
```

### 3. Format selection

```bash
curl -X POST http://localhost:3000/optimize \
  -F "image=@test-images/sample.jpg" \
  -F "formats=webp,avif" \
  -F "maxBytes=50000" \
  -o output.webp -v
```

### 4. Batch optimization

```bash
curl -X POST http://localhost:3000/optimize/batch \
  -F "images=@test-images/sample1.jpg" \
  -F "images=@test-images/sample2.png" \
  -F "images=@test-images/sample3.webp" \
  -F "maxBytes=100000" \
  | jq .
```

## Using from JavaScript/TypeScript

```typescript
import FormData from 'form-data';
import fs from 'fs';
import fetch from 'node-fetch';

async function optimizeImage() {
  const form = new FormData();
  form.append('image', fs.createReadStream('input.jpg'));
  form.append('maxBytes', '100000');
  form.append('metric', 'dssim');

  const response = await fetch('http://localhost:3000/optimize', {
    method: 'POST',
    body: form,
  });

  if (response.ok) {
    const buffer = await response.buffer();
    fs.writeFileSync('output.jpg', buffer);

    console.log('Optimized!');
    console.log('Original size:', response.headers.get('X-Pyjamaz-Original-Size'));
    console.log('Optimized size:', response.headers.get('X-Pyjamaz-Optimized-Size'));
    console.log('Compression:', response.headers.get('X-Pyjamaz-Compression-Ratio'));
  }
}
```

## Integration with Frontend

### HTML Form

```html
<!DOCTYPE html>
<html>
<body>
  <h1>Image Optimizer</h1>
  <form action="http://localhost:3000/optimize" method="POST" enctype="multipart/form-data">
    <input type="file" name="image" accept="image/*" required>
    <input type="number" name="maxBytes" placeholder="Max size (bytes)" value="100000">
    <select name="metric">
      <option value="dssim">DSSIM</option>
      <option value="ssimulacra2">SSIMULACRA2</option>
      <option value="none">None</option>
    </select>
    <button type="submit">Optimize</button>
  </form>
</body>
</html>
```

### React Example

```tsx
import React, { useState } from 'react';

function ImageOptimizer() {
  const [file, setFile] = useState<File | null>(null);
  const [result, setResult] = useState<any>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!file) return;

    const formData = new FormData();
    formData.append('image', file);
    formData.append('maxBytes', '100000');

    const response = await fetch('http://localhost:3000/optimize', {
      method: 'POST',
      body: formData,
    });

    if (response.ok) {
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      setResult({
        url,
        size: response.headers.get('X-Pyjamaz-Optimized-Size'),
        format: response.headers.get('X-Pyjamaz-Format'),
      });
    }
  };

  return (
    <div>
      <form onSubmit={handleSubmit}>
        <input
          type="file"
          accept="image/*"
          onChange={(e) => setFile(e.target.files?.[0] || null)}
        />
        <button type="submit">Optimize</button>
      </form>
      {result && (
        <div>
          <img src={result.url} alt="Optimized" />
          <p>Size: {result.size} bytes</p>
          <p>Format: {result.format}</p>
        </div>
      )}
    </div>
  );
}
```

## Error Handling

The API returns appropriate HTTP status codes:

- `200 OK`: Successful optimization
- `400 Bad Request`: Invalid request parameters
- `413 Payload Too Large`: File exceeds 10MB limit
- `422 Unprocessable Entity`: Optimization failed (constraints not met)
- `500 Internal Server Error`: Server error

Error response format:
```json
{
  "error": "Error type",
  "message": "Detailed error message"
}
```

## Production Considerations

### Environment Variables

```bash
export PORT=3000
export NODE_ENV=production
```

### Rate Limiting

Add rate limiting middleware:

```typescript
import rateLimit from 'express-rate-limit';

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
});

app.use('/optimize', limiter);
```

### CORS

Enable CORS for frontend access:

```typescript
import cors from 'cors';

app.use(cors({
  origin: 'https://your-frontend-domain.com',
}));
```

### Logging

Add request logging:

```typescript
import morgan from 'morgan';

app.use(morgan('combined'));
```

## Troubleshooting

### Port already in use

```bash
# Kill process on port 3000
lsof -ti:3000 | xargs kill -9

# Or use a different port
PORT=8080 npm start
```

### Module not found

```bash
cd ../../../bindings/nodejs
npm install
npm run build
cd ../../examples/nodejs/express-server
npm install
```

### Library not found

Make sure the Pyjamaz library is built:

```bash
cd ../../../
zig build
```

## License

MIT
