# Quick Start Guide - Node.js Examples

## 🚀 Fastest Way to Get Started

### Step 1: Build Prerequisites

```bash
# From project root
cd /Users/ongteckwu/pyjamaz
zig build

# Build Node.js bindings
cd bindings/nodejs
npm install
npm run build
```

### Step 2: Try the Basic Usage Example

```bash
cd ../../examples/nodejs/basic-usage
npm install
npm start
```

**Expected Output:**
```
============================================================
Pyjamaz Basic Usage Examples
Version: 1.0.0
============================================================

📁 Sample image: sample.jpg
📊 Original size: 5.62 KB

📝 Example 1: Size Optimization (Async)
------------------------------------------------------------
✅ Success!
   Output: 5.62 KB
   Format: jpeg
   Quality: 0.000000
   Saved to: example1_size.jpg
...
```

You should see 6 examples run successfully and output files in the `output/` directory.

### Step 3: Try Other Examples

```bash
# Express Server
cd ../express-server
npm install
npm start &

# Test it
curl -X POST http://localhost:3000/optimize \
  -F "image=@test-images/sample.jpg" \
  -F "maxBytes=100000" \
  -o optimized.jpg -v

# Batch Processor
cd ../batch-processor
npm install
npm run build
npm run cli -- test-images/ output/ --max-bytes 100000 --verbose

# Web Service
cd ../web-service
npm install
npm start &

# Test it
curl http://localhost:3000/health
```

## ✅ Verification Checklist

Run this to verify everything works:

```bash
# From examples/nodejs directory
cd /Users/ongteckwu/pyjamaz/examples/nodejs

# Test basic-usage
cd basic-usage && npm start && cd ..

# Test builds for all examples
cd express-server && npm run build && cd ..
cd batch-processor && npm run build && cd ..
cd web-service && npm run build && cd ..

echo "✅ All examples working!"
```

## 🐛 Troubleshooting

### Sample image not found

Make sure you're in the correct directory when running:
```bash
cd /Users/ongteckwu/pyjamaz/examples/nodejs/basic-usage
npm start
```

### Library not found

Build the native library first:
```bash
cd /Users/ongteckwu/pyjamaz
zig build
```

### Module not found

Build the Node.js bindings:
```bash
cd /Users/ongteckwu/pyjamaz/bindings/nodejs
npm install
npm run build
```

## 📊 What You'll See

After running `basic-usage`, you'll have these files in the `output/` directory:

```
output/
├── example1_size.jpg         # Size-constrained optimization
├── example2_quality.webp     # Quality-constrained (SSIMULACRA2)
├── example3_sync.jpg         # Synchronous API demo
├── example4_formats.jpeg     # Format selection demo
└── example6_dual.jpg         # Dual constraints (size + quality)
```

## 🎯 Next Steps

1. **Explore the code** - Look at `src/index.ts` to understand the API
2. **Modify constraints** - Try different `maxBytes` and `maxDiff` values
3. **Add your own images** - Replace `test-images/sample.jpg` with your images
4. **Try the servers** - Run Express or Fastify examples for REST APIs
5. **Build something** - Use these examples as templates for your project

## 📚 Full Documentation

- **Main README**: `examples/nodejs/README.md`
- **Summary**: `examples/nodejs/EXAMPLES_SUMMARY.md`
- **API Docs**: `docs/NODEJS_API.md` (project root)
- **Each Example**: Has its own detailed README

---

**Status**: ✅ All examples tested and working
**Last Updated**: 2025-11-01
**Node Version**: 14.0.0+
**TypeScript**: 5.3.3
