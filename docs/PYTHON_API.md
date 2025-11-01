# Pyjamaz Python API Documentation

**Complete API reference for Pyjamaz Python bindings.**

Last Updated: 2025-10-31
Version: 1.0.0

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [API Reference](#api-reference)
  - [optimize_image()](#optimize_image)
  - [OptimizeResult](#optimizeresult)
  - [get_version()](#get_version)
- [Usage Examples](#usage-examples)
- [Integration Examples](#integration-examples)
- [Performance Tips](#performance-tips)
- [Troubleshooting](#troubleshooting)

---

## Installation

### From Source

```bash
# Clone repository and build shared library
git clone https://github.com/yourusername/pyjamaz.git
cd pyjamaz
zig build

# Install Python bindings
cd bindings/python
uv pip install -e .
```

### Verify Installation

```python
import pyjamaz
print(f"Pyjamaz version: {pyjamaz.get_version()}")
```

---

## Quick Start

```python
import pyjamaz

# Optimize with size constraint
result = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)

if result.passed:
    result.save('output.jpg')
    print(f"✓ Optimized to {result.size:,} bytes as {result.format}")
    print(f"  Quality score: {result.diff_value:.6f}")
else:
    print(f"✗ Failed: {result.error_message}")
```

---

## API Reference

### `optimize_image()`

Main optimization function with perceptual quality guarantees.

#### Signature

```python
def optimize_image(
    input_path: Union[str, Path, bytes],
    max_bytes: Optional[int] = None,
    max_diff: Optional[float] = None,
    metric: str = "dssim",
    formats: Optional[List[str]] = None,
    concurrency: int = 4,
    cache_enabled: bool = True,
    cache_dir: Optional[str] = None,
    cache_max_size: int = 1024 * 1024 * 1024,
) -> OptimizeResult
```

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `input_path` | `str \| Path \| bytes` | *required* | Path to image file or raw image bytes |
| `max_bytes` | `int \| None` | `None` | Maximum output file size in bytes (None = no limit) |
| `max_diff` | `float \| None` | `None` | Maximum perceptual difference (None = no limit) |
| `metric` | `str` | `"dssim"` | Perceptual metric: `"dssim"`, `"ssimulacra2"`, or `"none"` |
| `formats` | `List[str] \| None` | `None` | Output formats to try: `["jpeg", "png", "webp", "avif"]` (None = all) |
| `concurrency` | `int` | `4` | Number of parallel encoding threads (1-8) |
| `cache_enabled` | `bool` | `True` | Enable caching for 15-20x speedup on repeated calls |
| `cache_dir` | `str \| None` | `None` | Custom cache directory (None = `~/.cache/pyjamaz`) |
| `cache_max_size` | `int` | `1073741824` | Maximum cache size in bytes (default: 1GB) |

#### Returns

`OptimizeResult` object containing:
- `output_buffer: bytes` - Optimized image data
- `format: str` - Selected format (`"jpeg"`, `"png"`, `"webp"`, `"avif"`)
- `diff_value: float` - Perceptual difference score
- `passed: bool` - Whether all constraints were met
- `error_message: Optional[str]` - Error message if optimization failed
- `size: int` (property) - Size of optimized image in bytes
- `save(path)` (method) - Save optimized image to file

#### Examples

**Basic size constraint:**
```python
result = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)
```

**Quality constraint:**
```python
result = pyjamaz.optimize_image(
    'input.png',
    max_diff=0.002,
    metric='ssimulacra2'
)
```

**From bytes:**
```python
with open('input.jpg', 'rb') as f:
    data = f.read()
result = pyjamaz.optimize_image(data, max_bytes=50_000)
```

**Specific formats:**
```python
result = pyjamaz.optimize_image(
    'input.jpg',
    formats=['webp', 'avif'],  # Try modern formats only
    max_bytes=100_000
)
```

**Custom concurrency:**
```python
result = pyjamaz.optimize_image(
    'input.png',
    concurrency=8,  # Use 8 threads
    max_bytes=100_000
)
```

**Custom cache settings:**
```python
result = pyjamaz.optimize_image(
    'input.jpg',
    cache_enabled=True,
    cache_dir='/tmp/my-cache',
    cache_max_size=2 * 1024 * 1024 * 1024  # 2GB
)
```

---

### `OptimizeResult`

Result object returned by `optimize_image()`.

#### Attributes

```python
@dataclass
class OptimizeResult:
    output_buffer: bytes           # Optimized image data
    format: str                    # Selected format
    diff_value: float              # Perceptual difference score
    passed: bool                   # Whether constraints met
    error_message: Optional[str]   # Error message if failed
```

#### Properties

**`size: int`**
Returns the size of the optimized image in bytes.

```python
result = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)
print(f"Output size: {result.size:,} bytes")
```

#### Methods

**`save(path: Union[str, Path]) -> None`**

Save optimized image to file.

```python
result = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)
if result.passed:
    result.save('output.webp')
else:
    print(f"Failed: {result.error_message}")
```

**Raises:**
- `RuntimeError` if optimization failed (`passed == False`)

---

### `get_version()`

Get Pyjamaz library version string.

#### Signature

```python
def get_version() -> str
```

#### Returns

Version string in semantic versioning format (e.g., `"1.0.0"`)

#### Example

```python
import pyjamaz
print(f"Using Pyjamaz version {pyjamaz.get_version()}")
```

---

## Usage Examples

### Basic Optimization

```python
import pyjamaz

# Size constraint (100KB max)
result = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)

if result.passed:
    result.save('output.jpg')
    original_size = Path('input.jpg').stat().st_size
    reduction = (1 - result.size / original_size) * 100
    print(f"✓ Optimized: {original_size:,} → {result.size:,} bytes ({reduction:.1f}% reduction)")
else:
    print(f"✗ Failed: {result.error_message}")
```

### Quality-Focused Optimization

```python
# Optimize with perceptual quality guarantee
result = pyjamaz.optimize_image(
    'input.png',
    max_diff=0.002,  # DSSIM threshold
    metric='dssim',
    formats=['webp', 'avif', 'png']  # Try modern formats
)

if result.passed:
    result.save(f'output.{result.format}')
    print(f"✓ Format: {result.format}")
    print(f"✓ Quality score: {result.diff_value:.6f}")
    print(f"✓ Size: {result.size:,} bytes")
```

### Batch Processing

```python
from pathlib import Path
import pyjamaz

input_dir = Path('images')
output_dir = Path('optimized')
output_dir.mkdir(exist_ok=True)

for image_path in input_dir.glob('*.jpg'):
    result = pyjamaz.optimize_image(
        str(image_path),
        max_bytes=100_000,
        cache_enabled=True
    )

    if result.passed:
        output_path = output_dir / f"{image_path.stem}.{result.format}"
        result.save(output_path)
        print(f"✓ {image_path.name}: {result.size:,} bytes")
    else:
        print(f"✗ {image_path.name}: {result.error_message}")
```

### Parallel Batch Processing

```python
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import pyjamaz

def optimize_single(image_path, output_dir):
    result = pyjamaz.optimize_image(
        str(image_path),
        max_bytes=100_000,
        cache_enabled=True
    )

    if result.passed:
        output_path = output_dir / f"{image_path.stem}.{result.format}"
        result.save(output_path)
        return f"✓ {image_path.name}: {result.size:,} bytes"
    else:
        return f"✗ {image_path.name}: {result.error_message}"

input_dir = Path('images')
output_dir = Path('optimized')
output_dir.mkdir(exist_ok=True)

images = list(input_dir.glob('*.jpg'))

with ThreadPoolExecutor(max_workers=4) as executor:
    futures = {
        executor.submit(optimize_single, img, output_dir): img
        for img in images
    }

    for future in as_completed(futures):
        print(future.result())
```

### Caching Performance

```python
import time
import pyjamaz

# First run (cache miss)
start = time.time()
result1 = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)
time1 = time.time() - start

# Second run (cache hit - 15-20x faster!)
start = time.time()
result2 = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)
time2 = time.time() - start

print(f"First run:  {time1*1000:.1f}ms (cache miss)")
print(f"Second run: {time2*1000:.1f}ms (cache hit)")
print(f"Speedup: {time1/time2:.1f}x faster!")
```

### Error Handling

```python
import pyjamaz

try:
    result = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)

    if result.passed:
        result.save('output.jpg')
        print(f"✓ Success: {result.size:,} bytes")
    else:
        print(f"⚠ Constraints not met: {result.error_message}")
        # Still have result.output_buffer if you want to use it

except FileNotFoundError:
    print("✗ Input file not found")
except PermissionError:
    print("✗ Permission denied")
except Exception as e:
    print(f"✗ Unexpected error: {e}")
```

---

## Integration Examples

### Flask Web Server

```python
from flask import Flask, request, send_file
import pyjamaz
import io

app = Flask(__name__)

@app.route('/optimize', methods=['POST'])
def optimize():
    # Get uploaded image
    image_file = request.files.get('image')
    if not image_file:
        return {'error': 'No image provided'}, 400

    image_data = image_file.read()

    # Get parameters
    max_bytes = request.form.get('max_bytes', 100_000, type=int)
    metric = request.form.get('metric', 'ssimulacra2')

    # Optimize
    result = pyjamaz.optimize_image(
        image_data,
        max_bytes=max_bytes,
        metric=metric,
    )

    if not result.passed:
        return {'error': result.error_message}, 400

    # Return optimized image
    return send_file(
        io.BytesIO(result.output_buffer),
        mimetype=f'image/{result.format}',
        as_attachment=True,
        download_name=f'optimized.{result.format}'
    )

if __name__ == '__main__':
    app.run(debug=True)
```

### FastAPI Server

```python
from fastapi import FastAPI, File, UploadFile, Form
from fastapi.responses import Response
import pyjamaz

app = FastAPI()

@app.post("/optimize")
async def optimize_endpoint(
    file: UploadFile = File(...),
    max_bytes: int = Form(100_000),
    max_diff: float = Form(None),
    metric: str = Form("ssimulacra2"),
):
    # Read file
    image_data = await file.read()

    # Optimize
    result = pyjamaz.optimize_image(
        image_data,
        max_bytes=max_bytes if max_bytes > 0 else None,
        max_diff=max_diff,
        metric=metric,
    )

    if not result.passed:
        return {"error": result.error_message}

    # Return optimized image
    return Response(
        content=result.output_buffer,
        media_type=f"image/{result.format}",
        headers={
            "Content-Disposition": f"attachment; filename=optimized.{result.format}"
        }
    )
```

### Django View

```python
from django.http import HttpResponse, JsonResponse
from django.views.decorators.http import require_POST
from django.views.decorators.csrf import csrf_exempt
import pyjamaz

@csrf_exempt
@require_POST
def optimize_image_view(request):
    # Get uploaded file
    image_file = request.FILES.get('image')
    if not image_file:
        return JsonResponse({'error': 'No image provided'}, status=400)

    # Read image data
    image_data = image_file.read()

    # Get parameters
    max_bytes = int(request.POST.get('max_bytes', 100_000))

    # Optimize
    result = pyjamaz.optimize_image(
        image_data,
        max_bytes=max_bytes,
    )

    if not result.passed:
        return JsonResponse({'error': result.error_message}, status=400)

    # Return optimized image
    response = HttpResponse(result.output_buffer, content_type=f'image/{result.format}')
    response['Content-Disposition'] = f'attachment; filename="optimized.{result.format}"'
    return response
```

---

## Performance Tips

### 1. Enable Caching

Caching provides **15-20x speedup** on repeated optimizations:

```python
# Always enable caching for development/testing
result = pyjamaz.optimize_image(
    'input.jpg',
    max_bytes=100_000,
    cache_enabled=True  # Default: True
)
```

### 2. Use Appropriate Concurrency

More threads = faster parallel encoding:

```python
# For CPU-bound workloads, use all cores
import os
concurrency = os.cpu_count() or 4

result = pyjamaz.optimize_image(
    'input.jpg',
    concurrency=concurrency,
    max_bytes=100_000
)
```

### 3. Batch Processing

Process multiple images in parallel:

```python
from concurrent.futures import ThreadPoolExecutor

def process_batch(image_paths, max_workers=4):
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(pyjamaz.optimize_image, path, max_bytes=100_000): path
            for path in image_paths
        }
        return {path: future.result() for future, path in futures.items()}
```

### 4. Use `metric="none"` for Speed

Skip perceptual metrics when quality is not critical:

```python
# 2-3x faster without quality calculation
result = pyjamaz.optimize_image(
    'input.jpg',
    max_bytes=100_000,
    metric="none"  # Skip DSSIM/SSIMULACRA2
)
```

### 5. Limit Format Search

Only try formats you need:

```python
# Faster: only try WebP and AVIF
result = pyjamaz.optimize_image(
    'input.jpg',
    formats=['webp', 'avif'],  # Skip JPEG/PNG
    max_bytes=100_000
)
```

---

## Troubleshooting

### Library Not Found

**Error**: `RuntimeError: Could not find libpyjamaz shared library`

**Solution**:

1. Build the shared library:
   ```bash
   cd /path/to/pyjamaz
   zig build
   ```

2. Set environment variable:
   ```bash
   export PYJAMAZ_LIB_PATH=/path/to/pyjamaz/zig-out/lib/libpyjamaz.dylib
   ```

3. Or install system-wide:
   ```bash
   sudo cp zig-out/lib/libpyjamaz.* /usr/local/lib/
   ```

### Import Errors

**Error**: `ModuleNotFoundError: No module named 'pyjamaz'`

**Solution**:

```bash
cd bindings/python
uv pip install -e .
```

### Optimization Always Fails

**Check constraints**:
```python
result = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)

if not result.passed:
    print(f"Error: {result.error_message}")

    # Try without constraints to see base size
    result2 = pyjamaz.optimize_image('input.jpg')
    print(f"Unconstrained size: {result2.size:,} bytes")
```

### Cache Issues

**Clear cache**:
```bash
rm -rf ~/.cache/pyjamaz
```

**Disable cache temporarily**:
```python
result = pyjamaz.optimize_image(
    'input.jpg',
    cache_enabled=False
)
```

---

## Type Hints

Full type hints for IDEs and type checkers:

```python
from typing import Union, Optional, List
from pathlib import Path

def optimize_image(
    input_path: Union[str, Path, bytes],
    max_bytes: Optional[int] = None,
    max_diff: Optional[float] = None,
    metric: str = "dssim",
    formats: Optional[List[str]] = None,
    concurrency: int = 4,
    cache_enabled: bool = True,
    cache_dir: Optional[str] = None,
    cache_max_size: int = 1073741824,
) -> OptimizeResult: ...
```

---

## License

MIT License - see [LICENSE](../LICENSE) for details.

## Links

- **Main Documentation**: [README.md](../README.md)
- **Python Bindings README**: [bindings/python/README.md](../bindings/python/README.md)
- **GitHub Issues**: [Issues](https://github.com/yourusername/pyjamaz/issues)
