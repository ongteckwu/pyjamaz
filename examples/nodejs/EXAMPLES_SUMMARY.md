# Pyjamaz Node.js Examples - Summary

## ✅ What Was Created

Four comprehensive TypeScript example projects demonstrating real-world usage of Pyjamaz:

### 1. Basic Usage (`basic-usage/`)
**Purpose**: Introduction to the Pyjamaz API  
**Complexity**: Beginner  
**Key Files**:
- `src/index.ts` - 6 self-contained examples
- `package.json` - Minimal dependencies
- Sample images in `test-images/`

**What it demonstrates**:
- Size-based optimization (async)
- Quality-based optimization (SSIMULACRA2)
- Synchronous API
- Format selection (WebP, AVIF)
- Caching performance (15-20x speedup)
- Dual constraints (size + quality)

**How to run**:
```bash
cd basic-usage
npm install
npm start
```

---

### 2. Express Server (`express-server/`)
**Purpose**: REST API for image optimization  
**Complexity**: Intermediate  
**Key Files**:
- `src/server.ts` - Full Express.js REST API
- Multer integration for file uploads
- Comprehensive error handling

**What it demonstrates**:
- Single image optimization endpoint
- Batch optimization endpoint
- Request validation
- Response headers with metadata
- Error handling middleware
- Health check endpoints

**API Endpoints**:
- `GET /health` - Health check
- `GET /version` - Version info
- `POST /optimize` - Optimize single image
- `POST /optimize/batch` - Batch optimization

**How to run**:
```bash
cd express-server
npm install
npm start

# Test with curl
curl -X POST http://localhost:3000/optimize \
  -F "image=@test-images/sample.jpg" \
  -F "maxBytes=100000" \
  -o output.jpg -v
```

---

### 3. Batch Processor (`batch-processor/`)
**Purpose**: CLI tool for batch image optimization  
**Complexity**: Intermediate  
**Key Files**:
- `src/cli.ts` - Feature-rich CLI with Commander
- Progress bars with colored output
- Detailed reporting

**What it demonstrates**:
- CLI argument parsing (Commander)
- Directory scanning (recursive)
- Progress tracking (cli-progress, ora)
- Parallel processing with concurrency control
- Colored terminal output (chalk)
- Statistics and reporting

**CLI Options**:
- `--max-bytes` - Size constraint
- `--max-diff` - Quality constraint
- `--metric` - Perceptual metric
- `--formats` - Format selection
- `--concurrency` - Parallel workers
- `--recursive` - Process subdirectories
- `--verbose` - Detailed output

**How to run**:
```bash
cd batch-processor
npm install
npm run build

# Process a directory
npm run cli -- test-images/ output/ --max-bytes 100000 --verbose
```

---

### 4. Web Service (`web-service/`)
**Purpose**: Production-ready microservice with Fastify  
**Complexity**: Advanced  
**Key Files**:
- `src/server.ts` - High-performance Fastify server
- Structured logging with Pino
- Kubernetes-ready health checks

**What it demonstrates**:
- High-performance Fastify server
- Structured JSON logging
- Health and readiness checks (Kubernetes)
- Prometheus metrics endpoint
- Request validation
- Production error handling
- Multipart file uploads
- Batch processing endpoint

**API Endpoints**:
- `GET /health` - Health check
- `GET /ready` - Readiness check (K8s)
- `GET /version` - Version info
- `GET /metrics` - Prometheus metrics
- `POST /api/v1/optimize` - Optimize single image
- `POST /api/v1/optimize/batch` - Batch optimization

**How to run**:
```bash
cd web-service
npm install
npm start

# Test endpoints
curl http://localhost:3000/health
curl -X POST "http://localhost:3000/api/v1/optimize?maxBytes=100000" \
  -F "file=@test-images/sample.jpg" \
  -o optimized.jpg
```

---

## 📊 Comparison Matrix

| Feature | Basic Usage | Express Server | Batch Processor | Web Service |
|---------|-------------|----------------|-----------------|-------------|
| **Complexity** | ⭐ Beginner | ⭐⭐ Intermediate | ⭐⭐ Intermediate | ⭐⭐⭐ Advanced |
| **LOC** | ~300 | ~250 | ~400 | ~350 |
| **Dependencies** | 3 | 5 | 7 | 4 |
| **Use Case** | Learning | Web apps | Build pipelines | Microservices |
| **TypeScript** | ✅ | ✅ | ✅ | ✅ |
| **API Type** | Direct | REST | CLI | REST |
| **Error Handling** | Basic | Comprehensive | Detailed | Production |
| **Logging** | Console | Basic | Colored CLI | Structured JSON |
| **Health Checks** | ❌ | ✅ | ❌ | ✅ (K8s ready) |
| **Metrics** | ❌ | ❌ | ❌ | ✅ (Prometheus) |
| **Batch Support** | ❌ | ✅ | ✅ | ✅ |
| **Progress UI** | ❌ | ❌ | ✅ | ❌ |
| **Production Ready** | ❌ | ⚠️ | ⚠️ | ✅ |

---

## 🎯 Which Example Should I Use?

### I want to learn the API
→ Start with **basic-usage**

### I'm building a web application
→ Use **express-server** as a template

### I need to optimize images in a build pipeline
→ Use **batch-processor** as a CLI tool

### I'm deploying to production/Kubernetes
→ Use **web-service** for a scalable microservice

### I want to understand TypeScript integration
→ All examples are TypeScript-first!

---

## 📦 Project Structure

```
examples/nodejs/
├── README.md                   # Main README with setup instructions
├── EXAMPLES_SUMMARY.md         # This file
├── basic-usage/
│   ├── src/index.ts           # 6 examples in ~300 LOC
│   ├── package.json           # 3 dependencies
│   ├── test-images/           # Sample images
│   └── output/                # Generated output
├── express-server/
│   ├── src/server.ts          # Express REST API
│   ├── package.json           # 5 dependencies
│   └── test-images/
├── batch-processor/
│   ├── src/cli.ts             # CLI tool
│   ├── package.json           # 7 dependencies (CLI tools)
│   └── test-images/
└── web-service/
    ├── src/server.ts          # Fastify microservice
    ├── package.json           # 4 dependencies
    └── test-images/
```

---

## ✅ Installation Verification

All examples have been tested with:

```bash
# All npm installs successful (0 vulnerabilities)
✅ basic-usage:      21 packages installed
✅ express-server:   121 packages installed  
✅ batch-processor:  57 packages installed
✅ web-service:      102 packages installed

# All TypeScript builds successful
✅ basic-usage:      Built successfully
✅ express-server:   Built successfully
✅ batch-processor:  Built successfully
✅ web-service:      Built successfully
```

---

## 🚀 Quick Start (All Examples)

```bash
# Prerequisites
cd ../../../  # Go to project root
zig build     # Build Pyjamaz library

cd bindings/nodejs
npm install
npm run build

# Run each example
cd ../../examples/nodejs/basic-usage
npm install && npm start

cd ../express-server
npm install && npm start &

cd ../batch-processor
npm install && npm run cli -- --help

cd ../web-service
npm install && npm start &
```

---

## 📝 Key Learnings from Examples

### 1. TypeScript Integration (all examples)
- Full type safety with IntelliSense
- Type definitions for all APIs
- Compile-time error checking

### 2. Error Handling (progressive)
- **Basic**: Try-catch with console.log
- **Express**: Middleware-based error handling
- **Batch**: Colored error messages with details
- **Web Service**: Structured error responses with codes

### 3. Async Patterns (various approaches)
- **Basic**: Both async/await and sync APIs
- **Express**: Async middleware
- **Batch**: Promise.all for parallelism
- **Web Service**: Fastify async handlers

### 4. Production Patterns (web-service)
- Health checks for monitoring
- Readiness checks for orchestration
- Metrics for observability
- Structured logging for debugging

---

## 🔧 Common Setup Issues & Solutions

### "Cannot find module 'pyjamaz'"
```bash
cd ../../bindings/nodejs
npm install && npm run build
```

### "Library not found"
```bash
cd ../../../  # Project root
zig build
```

### TypeScript errors
All examples use TypeScript 5.3+ with strict mode enabled.

### Port already in use
```bash
# For server examples
lsof -ti:3000 | xargs kill -9
# Or set PORT environment variable
PORT=8080 npm start
```

---

## 📚 Next Steps

1. **Start with basic-usage** to understand the API
2. **Explore express-server** for web integration
3. **Try batch-processor** for CLI workflows
4. **Study web-service** for production patterns

Each example builds on concepts from previous ones, but can be used independently.

---

## 🎓 Learning Path

```
Day 1: Basic Usage
└─ Run all 6 examples
└─ Understand async vs sync
└─ Learn about caching

Day 2: Web Integration
└─ Set up Express server
└─ Test with curl
└─ Build simple frontend

Day 3: Batch Processing
└─ Process directory of images
└─ Understand concurrency
└─ Add to build pipeline

Day 4: Production
└─ Deploy web service
└─ Set up monitoring
└─ Configure Kubernetes
```

---

**Created**: 2025-11-01  
**Author**: Claude Code  
**Version**: 1.0.0  

Happy optimizing! 🚀
