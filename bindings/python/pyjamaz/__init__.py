"""
Pyjamaz - High-performance image optimizer with perceptual quality guarantees.

Python bindings for the Pyjamaz image optimization library.
Provides automatic memory management via context managers.
"""

import ctypes
import os
import sys
from pathlib import Path
from typing import Optional, List, Union, Tuple, Any
from dataclasses import dataclass

__version__ = "1.0.0"

# Locate the shared library
def _find_library():
    """Find libpyjamaz shared library."""
    # Check environment variable first
    if "PYJAMAZ_LIB_PATH" in os.environ:
        lib_path = os.environ["PYJAMAZ_LIB_PATH"]
        if os.path.exists(lib_path):
            return lib_path

    # Platform-specific library names
    if sys.platform == "darwin":
        lib_name = "libpyjamaz.dylib"
        libavif_name = "libavif.16.dylib"
    elif sys.platform == "win32":
        lib_name = "pyjamaz.dll"
        libavif_name = "avif.dll"
    else:
        lib_name = "libpyjamaz.so"
        libavif_name = "libavif.so.16"

    # 1. Check bundled libraries (uv pip install - highest priority)
    package_dir = Path(__file__).parent
    native_dir = package_dir / "native"
    bundled_lib = native_dir / lib_name
    bundled_avif = native_dir / libavif_name

    if bundled_lib.exists():
        # Pre-load libavif if bundled (required dependency)
        if bundled_avif.exists():
            try:
                ctypes.CDLL(str(bundled_avif))
            except Exception as e:
                print(f"Warning: Failed to load bundled libavif: {e}", file=sys.stderr)
        return str(bundled_lib)

    # 2. Check development install (relative to this file)
    dev_package_dir = package_dir.parent.parent.parent
    lib_dir = dev_package_dir / "zig-out" / "lib"
    dev_lib_path = lib_dir / lib_name

    if dev_lib_path.exists():
        return str(dev_lib_path)

    # 3. Check system paths (last resort)
    try:
        result = ctypes.util.find_library("pyjamaz")
        if result:
            return result
    except Exception as e:
        print(f"Warning: ctypes.util.find_library failed: {e}", file=sys.stderr)

    raise RuntimeError(
        "Could not find libpyjamaz shared library. "
        "Tried locations:\n"
        f"  1. Bundled: {bundled_lib}\n"
        f"  2. Development: {dev_lib_path}\n"
        f"  3. System paths (via ctypes.util.find_library)\n"
        "Set PYJAMAZ_LIB_PATH environment variable to override."
    )

# Load library
_lib_path = _find_library()
_lib = ctypes.CDLL(_lib_path)

# Define C structures
class _OptimizeOptions(ctypes.Structure):
    _fields_: List[Tuple[str, Any]] = [
        ("input_bytes", ctypes.POINTER(ctypes.c_ubyte)),
        ("input_len", ctypes.c_size_t),
        ("max_bytes", ctypes.c_uint32),
        ("max_diff", ctypes.c_double),
        ("metric_type", ctypes.c_char_p),
        ("formats", ctypes.c_char_p),
        ("concurrency", ctypes.c_uint8),
        ("cache_enabled", ctypes.c_uint8),
        ("cache_dir", ctypes.c_char_p),
        ("cache_max_size", ctypes.c_uint64),
    ]

class _OptimizeResult(ctypes.Structure):
    _fields_: List[Tuple[str, Any]] = [
        ("output_bytes", ctypes.POINTER(ctypes.c_ubyte)),
        ("output_len", ctypes.c_size_t),
        ("format", ctypes.c_char_p),
        ("diff_value", ctypes.c_double),
        ("passed", ctypes.c_uint8),
        ("error_message", ctypes.c_char_p),
    ]

# Define function signatures
_lib.pyjamaz_init.argtypes = []
_lib.pyjamaz_init.restype = None

_lib.pyjamaz_cleanup.argtypes = []
_lib.pyjamaz_cleanup.restype = None

_lib.pyjamaz_version.argtypes = []
_lib.pyjamaz_version.restype = ctypes.c_char_p

_lib.pyjamaz_optimize.argtypes = [ctypes.POINTER(_OptimizeOptions)]
_lib.pyjamaz_optimize.restype = ctypes.POINTER(_OptimizeResult)

_lib.pyjamaz_free_result.argtypes = [ctypes.POINTER(_OptimizeResult)]
_lib.pyjamaz_free_result.restype = None

# Initialize library
_lib.pyjamaz_init()

def get_version() -> str:
    """Get Pyjamaz library version."""
    return _lib.pyjamaz_version().decode('utf-8')

@dataclass
class OptimizeResult:
    """Result of image optimization.

    Attributes:
        output_buffer: Optimized image bytes (empty if failed)
        format: Selected output format ('jpeg', 'png', 'webp', 'avif')
        diff_value: Perceptual difference score
        passed: Whether optimization met all constraints
        error_message: Error message if optimization failed
        size: Size of optimized image in bytes
    """
    output_buffer: bytes
    format: str
    diff_value: float
    passed: bool
    error_message: Optional[str]

    @property
    def size(self) -> int:
        """Size of optimized image in bytes."""
        return len(self.output_buffer)

    def save(self, path: Union[str, Path]) -> None:
        """Save optimized image to file.

        Args:
            path: Output file path

        Raises:
            RuntimeError: If optimization failed
        """
        if not self.passed:
            raise RuntimeError(f"Optimization failed: {self.error_message}")

        with open(path, 'wb') as f:
            f.write(self.output_buffer)

def optimize_image(
    input_path: Union[str, Path, bytes],
    max_bytes: Optional[int] = None,
    max_diff: Optional[float] = None,
    metric: str = "dssim",
    formats: Optional[List[str]] = None,
    concurrency: int = 4,
    cache_enabled: bool = True,
    cache_dir: Optional[str] = None,
    cache_max_size: int = 1024 * 1024 * 1024,  # 1GB
) -> OptimizeResult:
    """Optimize an image with perceptual quality guarantees.

    Args:
        input_path: Path to input image or image bytes
        max_bytes: Maximum output size in bytes (0 or None = no limit)
        max_diff: Maximum perceptual difference (0.0 or None = no limit)
        metric: Perceptual metric to use ('dssim', 'ssimulacra2', 'none')
        formats: List of output formats to try (['jpeg', 'png', 'webp', 'avif'] or None for all)
        concurrency: Number of parallel encoding threads (1-8)
        cache_enabled: Enable caching for faster repeated optimizations
        cache_dir: Cache directory path (None = default ~/.cache/pyjamaz)
        cache_max_size: Maximum cache size in bytes

    Returns:
        OptimizeResult with optimization details

    Examples:
        >>> # Optimize with size constraint
        >>> result = optimize_image('input.jpg', max_bytes=100_000)
        >>> if result.passed:
        ...     result.save('output.jpg')

        >>> # Optimize with quality constraint
        >>> result = optimize_image('input.png', max_diff=0.002, metric='ssimulacra2')

        >>> # Optimize from bytes
        >>> with open('input.jpg', 'rb') as f:
        ...     data = f.read()
        >>> result = optimize_image(data, max_bytes=50_000)
    """
    # Validation: Check parameters before FFI call (Tiger Style: validate at boundary)
    MAX_INPUT_SIZE = 100 * 1024 * 1024  # 100MB

    if concurrency < 1 or concurrency > 16:
        raise ValueError(f"concurrency must be 1-16, got {concurrency}")

    if max_bytes is not None and max_bytes < 0:
        raise ValueError(f"max_bytes must be non-negative, got {max_bytes}")

    if max_diff is not None and (max_diff < 0.0 or max_diff > 1.0):
        raise ValueError(f"max_diff must be 0.0-1.0, got {max_diff}")

    if metric not in ('dssim', 'ssimulacra2', 'none'):
        raise ValueError(f"metric must be 'dssim', 'ssimulacra2', or 'none', got {metric}")

    # Read input bytes with size validation
    if isinstance(input_path, bytes):
        input_bytes = input_path
        if len(input_bytes) == 0:
            raise ValueError("Input bytes cannot be empty")
        if len(input_bytes) > MAX_INPUT_SIZE:
            raise ValueError(f"Input too large: {len(input_bytes)} bytes (max {MAX_INPUT_SIZE})")
    else:
        # Check file size before reading
        import os
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        file_size = os.path.getsize(input_path)
        if file_size == 0:
            raise ValueError(f"Input file is empty: {input_path}")
        if file_size > MAX_INPUT_SIZE:
            raise ValueError(f"File too large: {file_size} bytes (max {MAX_INPUT_SIZE})")

        with open(input_path, 'rb') as f:
            input_bytes = f.read()

    # Prepare input buffer
    input_array = (ctypes.c_ubyte * len(input_bytes)).from_buffer_copy(input_bytes)

    # Prepare formats string
    if formats is None:
        formats_str = b"jpeg,png,webp,avif"
    else:
        formats_str = ",".join(formats).encode('utf-8')

    # Prepare cache dir
    cache_dir_bytes = cache_dir.encode('utf-8') if cache_dir else b""

    # Create options
    options = _OptimizeOptions(
        input_bytes=input_array,
        input_len=len(input_bytes),
        max_bytes=max_bytes or 0,
        max_diff=max_diff or 0.0,
        metric_type=metric.encode('utf-8'),
        formats=formats_str,
        concurrency=concurrency,
        cache_enabled=1 if cache_enabled else 0,
        cache_dir=cache_dir_bytes,
        cache_max_size=cache_max_size,
    )

    # Call optimization
    result_ptr = _lib.pyjamaz_optimize(ctypes.byref(options))

    if not result_ptr:
        return OptimizeResult(
            output_buffer=b"",
            format="",
            diff_value=0.0,
            passed=False,
            error_message="Optimization failed: null result"
        )

    try:
        # Extract result
        result = result_ptr.contents

        # Copy output bytes (Python manages memory from here)
        if result.passed and result.output_len > 0:
            output_buffer = bytes(result.output_bytes[:result.output_len])
        else:
            output_buffer = b""

        # Extract format
        format_str = result.format.decode('utf-8') if result.format else ""

        # Extract error message
        error_msg = result.error_message.decode('utf-8') if result.error_message else None

        return OptimizeResult(
            output_buffer=output_buffer,
            format=format_str,
            diff_value=result.diff_value,
            passed=bool(result.passed),
            error_message=error_msg
        )
    finally:
        # Free C memory automatically
        _lib.pyjamaz_free_result(result_ptr)

def cleanup():
    """Clean up library resources. Called automatically at exit."""
    _lib.pyjamaz_cleanup()

# Register cleanup
import atexit
atexit.register(cleanup)

__all__ = [
    'optimize_image',
    'OptimizeResult',
    'get_version',
    'cleanup',
]
