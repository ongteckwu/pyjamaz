# Pyjamaz Python Bindings

**High-performance image optimizer with perceptual quality guarantees for Python.**

Python bindings for [Pyjamaz](https://github.com/yourusername/pyjamaz) - a blazing-fast CLI image optimizer built with Zig.

## Features

- 🚀 **Blazing Fast**: 50-100ms per image with parallel encoding
- 💾 **Intelligent Caching**: 15-20x speedup on repeated optimizations
- 🎯 **Smart Optimization**: Automatic format selection (JPEG/PNG/WebP/AVIF)
- 📊 **Perceptual Quality**: DSSIM & SSIMULACRA2 metrics
- 🔒 **Size Guarantees**: Never exceed max_bytes constraint
- 🧹 **Auto Memory Management**: Context managers handle cleanup automatically
- 🐍 **Pythonic API**: Clean, idiomatic Python interface

## Installation

### From Source (Development)

```bash
# Clone the repository
git clone https://github.com/yourusername/pyjamaz.git
cd pyjamaz

# Build the shared library
zig build

# Install Python bindings
cd bindings/python
uv pip install -e .
```

### From PyPI (Coming Soon)

```bash
uv pip install pyjamaz
```

## Quick Start

```python
import pyjamaz

# Optimize with size constraint
result = pyjamaz.optimize_image(
    'input.jpg',
    max_bytes=100_000,  # 100KB max
)

if result.passed:
    result.save('output.jpg')
    print(f"Optimized to {result.size:,} bytes")
```

## API Reference

### `optimize_image()`

Main optimization function.

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

**Parameters:**

- `input_path`: Path to image file or image bytes
- `max_bytes`: Maximum output size in bytes (None = no limit)
- `max_diff`: Maximum perceptual difference (None = no limit)
- `metric`: Perceptual metric - `'dssim'`, `'ssimulacra2'`, or `'none'`
- `formats`: List of formats to try - `['jpeg', 'png', 'webp', 'avif']` (None = all)
- `concurrency`: Number of parallel encoding threads (1-8)
- `cache_enabled`: Enable caching for faster repeated optimizations
- `cache_dir`: Custom cache directory (None = default `~/.cache/pyjamaz`)
- `cache_max_size`: Maximum cache size in bytes (default 1GB)

**Returns:**

`OptimizeResult` object with:
- `output_buffer`: Optimized image bytes
- `format`: Selected format (`'jpeg'`, `'png'`, `'webp'`, `'avif'`)
- `diff_value`: Perceptual difference score
- `passed`: Whether optimization met all constraints
- `error_message`: Error message if failed
- `size`: Size of optimized image (property)
- `save(path)`: Save to file (method)

### `OptimizeResult`

Result object returned by `optimize_image()`.

```python
@dataclass
class OptimizeResult:
    output_buffer: bytes
    format: str
    diff_value: float
    passed: bool
    error_message: Optional[str]

    @property
    def size(self) -> int:
        """Size of optimized image in bytes."""

    def save(self, path: Union[str, Path]) -> None:
        """Save optimized image to file."""
```

### `get_version()`

Get Pyjamaz library version.

```python
version = pyjamaz.get_version()
print(f"Pyjamaz version: {version}")
```

## Usage Examples

### Basic Optimization

```python
import pyjamaz

# Size constraint
result = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)

if result.passed:
    result.save('output.jpg')
    print(f"✓ Saved {result.size:,} bytes as {result.format}")
else:
    print(f"✗ Failed: {result.error_message}")
```

### Quality Constraint

```python
# Optimize with perceptual quality guarantee
result = pyjamaz.optimize_image(
    'input.png',
    max_diff=0.002,  # DSSIM threshold
    metric='dssim',
)

print(f"Quality score: {result.diff_value:.6f}")
```

### Specific Formats

```python
# Try modern formats only
result = pyjamaz.optimize_image(
    'input.jpg',
    formats=['webp', 'avif'],
    max_bytes=50_000,
)
```

### From Bytes

```python
# Optimize from memory
with open('input.jpg', 'rb') as f:
    image_data = f.read()

result = pyjamaz.optimize_image(
    image_data,
    max_bytes=100_000,
)

# Save result
with open('output.webp', 'wb') as f:
    f.write(result.output_buffer)
```

### Batch Processing

```python
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

def optimize_image_file(input_path, output_dir):
    result = pyjamaz.optimize_image(
        str(input_path),
        max_bytes=100_000,
        cache_enabled=True,  # Use cache for speed
    )

    if result.passed:
        output_path = output_dir / f"{input_path.stem}.{result.format}"
        result.save(output_path)
        return f"✓ {input_path.name}: {result.size:,} bytes"
    else:
        return f"✗ {input_path.name}: {result.error_message}"

# Process directory in parallel
input_dir = Path('images')
output_dir = Path('optimized')
output_dir.mkdir(exist_ok=True)

images = list(input_dir.glob('*.jpg'))

with ThreadPoolExecutor(max_workers=4) as executor:
    results = executor.map(
        lambda img: optimize_image_file(img, output_dir),
        images
    )

    for result in results:
        print(result)
```

### Caching

```python
import time

# First run (cache miss)
start = time.time()
result1 = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)
time1 = time.time() - start

# Second run (cache hit - 15-20x faster!)
start = time.time()
result2 = pyjamaz.optimize_image('input.jpg', max_bytes=100_000)
time2 = time.time() - start

print(f"First run: {time1*1000:.1f}ms")
print(f"Second run: {time2*1000:.1f}ms (cache hit)")
print(f"Speedup: {time1/time2:.1f}x")
```

### Custom Cache Settings

```python
result = pyjamaz.optimize_image(
    'input.jpg',
    cache_enabled=True,
    cache_dir='/tmp/my-cache',
    cache_max_size=2 * 1024 * 1024 * 1024,  # 2GB
)
```

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
    image_file = request.files['image']
    image_data = image_file.read()

    # Optimize
    result = pyjamaz.optimize_image(
        image_data,
        max_bytes=100_000,
        metric='ssimulacra2',
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
```

### FastAPI Server

```python
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import Response
import pyjamaz

app = FastAPI()

@app.post("/optimize")
async def optimize_image_endpoint(
    file: UploadFile = File(...),
    max_bytes: int = 100000,
):
    # Read file
    image_data = await file.read()

    # Optimize
    result = pyjamaz.optimize_image(
        image_data,
        max_bytes=max_bytes,
    )

    if not result.passed:
        return {"error": result.error_message}

    # Return optimized image
    return Response(
        content=result.output_buffer,
        media_type=f"image/{result.format}",
    )
```

## Development

### Running Tests

```bash
# Install dev dependencies
uv pip install -e ".[dev]"

# Run tests
pytest

# With coverage
pytest --cov=pyjamaz --cov-report=html
```

### Code Quality

```bash
# Format code
black pyjamaz/ tests/ examples/

# Lint
ruff pyjamaz/ tests/ examples/

# Type checking
mypy pyjamaz/
```

## Performance

**Platform**: Apple M1 Pro, macOS 15.0

| Operation | Time | Notes |
|-----------|------|-------|
| Optimize (first run) | 50-100ms | Full optimization |
| Optimize (cache hit) | 5-10ms | 15-20x faster |
| Batch (100 images, 4 workers) | ~3s | Parallel processing |

## Requirements

- Python 3.8+
- libpyjamaz shared library (built from Zig source)
- System dependencies: libvips, libjpeg-turbo, libdssim

## Troubleshooting

### Library Not Found

If you get `RuntimeError: Could not find libpyjamaz shared library`:

1. Build the shared library:
   ```bash
   cd /path/to/pyjamaz
   zig build
   ```

2. Set `PYJAMAZ_LIB_PATH`:
   ```bash
   export PYJAMAZ_LIB_PATH=/path/to/pyjamaz/zig-out/lib/libpyjamaz.dylib
   ```

3. Or install system-wide:
   ```bash
   sudo cp zig-out/lib/libpyjamaz.* /usr/local/lib/
   ```

### Import Errors

Make sure you're in the correct directory or have installed the package:

```bash
uv pip install -e .
```

## License

MIT License - see [LICENSE](../../LICENSE) for details.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](../../docs/CONTRIBUTING.md) for guidelines.

## Links

- **Documentation**: [Main README](../../README.md)
- **Issues**: [GitHub Issues](https://github.com/yourusername/pyjamaz/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/pyjamaz/discussions)
