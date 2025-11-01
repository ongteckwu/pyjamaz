# Pyjamaz Node.js Examples

Comprehensive TypeScript/JavaScript examples demonstrating how to use Pyjamaz in real-world Node.js applications.

## 📁 Examples Overview

| Example | Description | Key Features |
|---------|-------------|--------------|
| **[basic-usage](./basic-usage)** | Simple API usage examples | Async/sync APIs, caching, constraints |
| **[express-server](./express-server)** | REST API with Express.js | File uploads, batch processing, error handling |
| **[batch-processor](./batch-processor)** | CLI batch processing tool | Progress bars, parallel processing, reporting |
| **[web-service](./web-service)** | Production microservice with Fastify | Health checks, metrics, Kubernetes-ready |

## 🚀 Quick Start

### Prerequisites

1. **Build the Pyjamaz library**:
   ```bash
   cd ../../  # Go to project root
   zig build
   ```

2. **Build the Node.js bindings**:
   ```bash
   cd bindings/nodejs
   npm install
   npm run build
   ```

3. **Prepare test images**:
   Each example needs sample images in `test-images/` directory. You can:
   - Copy your own images
   - Or use the shared test images from the project root

### Running Examples

Each example is self-contained with its own `package.json` and dependencies.

#### 1. Basic Usage

```bash
cd basic-usage
npm install
npm start
```

This will demonstrate:
- Size-based optimization
- Quality-based optimization
- Async vs sync APIs
- Format selection
- Caching speedup

#### 2. Express Server

```bash
cd express-server
npm install
npm start
```

Then test the API:
```bash
# Optimize a single image
curl -X POST http://localhost:3000/optimize \
  -F "image=@test-images/sample.jpg" \
  -F "maxBytes=100000" \
  -o output.jpg -v

# Batch optimization
curl -X POST http://localhost:3000/optimize/batch \
  -F "images=@test-images/image1.jpg" \
  -F "images=@test-images/image2.png" \
  -F "maxBytes=100000"
```

#### 3. Batch Processor

```bash
cd batch-processor
npm install
npm run build

# Process all images in a directory
npm run cli -- test-images/ output/ --max-bytes 100000 --verbose
```

#### 4. Web Service (Fastify)

```bash
cd web-service
npm install
npm start
```

Then test the API:
```bash
# Health check
curl http://localhost:3000/health

# Optimize image
curl -X POST "http://localhost:3000/api/v1/optimize?maxBytes=100000" \
  -F "file=@test-images/sample.jpg" \
  -o optimized.jpg
```

## 📚 What You'll Learn

### Basic Usage Example
- How to use the TypeScript API
- Async vs synchronous operations
- Working with constraints (size and quality)
- Format selection
- Leveraging caching for performance

### Express Server Example
- Building a REST API for image optimization
- Handling file uploads with multer
- Request validation and error handling
- Response headers and metadata
- Batch processing endpoints

### Batch Processor Example
- Building CLI tools with Commander
- Progress tracking with colored output
- Parallel processing with concurrency control
- Directory scanning and file operations
- Detailed reporting and statistics

### Web Service Example
- Production-ready microservice architecture
- Fastify for high performance
- Structured logging with Pino
- Health and readiness checks (Kubernetes)
- Prometheus metrics
- Error handling best practices

## 🔧 Common Setup

All examples share similar setup requirements:

### 1. Install Dependencies

Each example has its own dependencies:

```bash
# In each example directory
npm install
```

### 2. Build TypeScript

```bash
npm run build
```

### 3. Run

```bash
# Production mode
npm start

# Development mode (most examples)
npm run dev
```

## 📦 Project Structure

```
examples/nodejs/
├── README.md                    # This file
├── basic-usage/                 # Simple API usage
│   ├── package.json
│   ├── tsconfig.json
│   ├── src/
│   │   └── index.ts
│   ├── test-images/            # Sample images
│   └── output/                 # Generated output
├── express-server/             # Express.js REST API
│   ├── package.json
│   ├── tsconfig.json
│   ├── src/
│   │   └── server.ts
│   └── test-images/
├── batch-processor/            # CLI batch tool
│   ├── package.json
│   ├── tsconfig.json
│   ├── src/
│   │   └── cli.ts
│   └── test-images/
└── web-service/                # Fastify microservice
    ├── package.json
    ├── tsconfig.json
    ├── src/
    │   └── server.ts
    └── test-images/
```

## 🧪 Testing

Each example includes testing instructions in its README.

### Quick Test Commands

```bash
# Basic usage
cd basic-usage && npm start

# Express server
cd express-server && npm start &
curl http://localhost:3000/health

# Batch processor
cd batch-processor && npm run cli -- --help

# Web service
cd web-service && npm start &
curl http://localhost:3000/health
```

## 🐛 Troubleshooting

### "Cannot find module 'pyjamaz'"

The examples use a local file dependency. Make sure you've built the bindings:

```bash
cd ../../bindings/nodejs
npm install
npm run build
```

### "Library not found" error

Build the Pyjamaz native library:

```bash
cd ../../../  # Project root
zig build
```

The library should be at: `zig-out/lib/libpyjamaz.dylib` (macOS) or `.so` (Linux)

### "Sample image not found"

Add test images to each example's `test-images/` directory:

```bash
# From project root
cp testdata/samples/sample1.jpg examples/nodejs/basic-usage/test-images/sample.jpg
```

Or use your own images (JPEG, PNG, WebP supported).

### TypeScript errors

Make sure you have TypeScript installed:

```bash
npm install -g typescript
# Or use the local version
npx tsc --version
```

### Port already in use

For server examples (Express, Fastify):

```bash
# Find process using port 3000
lsof -ti:3000 | xargs kill -9

# Or use a different port
PORT=8080 npm start
```

## 🎯 Use Cases

### For Learning

Start with **basic-usage** to understand the core API, then explore the server examples.

### For Web Applications

Use **express-server** as a starting point for integrating image optimization into your web app.

### For Build Pipelines

Use **batch-processor** to optimize images as part of your build process or deployment pipeline.

### For Microservices

Use **web-service** as a template for a production-ready image optimization service with monitoring and health checks.

## 📖 Additional Resources

- [Pyjamaz Documentation](../../README.md)
- [Node.js API Reference](../../docs/NODEJS_API.md)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
- [Express.js Guide](https://expressjs.com/en/guide/routing.html)
- [Fastify Documentation](https://www.fastify.io/docs/latest/)

## 🤝 Contributing

Found an issue or want to add a new example? Contributions are welcome!

1. Fork the repository
2. Create your feature branch
3. Add your example in a new directory
4. Update this README with your example
5. Submit a pull request

## 📄 License

MIT - See [LICENSE](../../LICENSE) for details.

---

**Happy optimizing!** 🚀

If you have questions or run into issues, please open an issue on GitHub.
