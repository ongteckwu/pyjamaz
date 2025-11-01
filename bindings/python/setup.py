"""Setup script for Pyjamaz Python bindings."""

import os
import sys
import platform
import shutil
from setuptools import setup, find_packages
from setuptools.command.build_py import build_py
from pathlib import Path

# Read README
readme_file = Path(__file__).parent / "README.md"
long_description = readme_file.read_text() if readme_file.exists() else ""


class BuildPyWithNativeLibs(build_py):
    """Custom build command that bundles native libraries."""

    def run(self):
        # Run standard build_py
        super().run()

        # Determine platform and architecture
        system = platform.system()
        machine = platform.machine()

        # Path to project root (../../ from bindings/python/)
        project_root = Path(__file__).parent.parent.parent
        zig_out_lib = project_root / "zig-out" / "lib"

        # Determine library names and paths
        if system == "Darwin":
            libpyjamaz = "libpyjamaz.dylib"
            libavif = "libavif.16.dylib"
            libavif_source = Path("/opt/homebrew/opt/libavif/lib") / libavif
        elif system == "Linux":
            libpyjamaz = "libpyjamaz.so"
            libavif = "libavif.so.16"
            libavif_source = Path("/usr/lib") / libavif  # Adjust based on distro
        else:
            print(f"Warning: Unsupported platform {system}, skipping native lib bundling")
            return

        # Create native libs directory in build
        build_lib = Path(self.build_lib)
        native_dir = build_lib / "pyjamaz" / "native"
        native_dir.mkdir(parents=True, exist_ok=True)

        # Copy libpyjamaz
        libpyjamaz_source = zig_out_lib / libpyjamaz
        if libpyjamaz_source.exists():
            print(f"Bundling {libpyjamaz} into wheel...")
            shutil.copy2(libpyjamaz_source, native_dir / libpyjamaz)
        else:
            print(f"Warning: {libpyjamaz} not found at {libpyjamaz_source}")

        # Copy libavif
        if libavif_source.exists():
            print(f"Bundling {libavif} into wheel...")
            shutil.copy2(libavif_source, native_dir / libavif)
        else:
            print(f"Warning: {libavif} not found at {libavif_source}")


setup(
    name="pyjamaz",
    version="1.0.0",
    author="Your Name",
    author_email="your.email@example.com",
    description="High-performance image optimizer with perceptual quality guarantees",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/yourusername/pyjamaz",
    packages=find_packages(),
    package_data={
        "pyjamaz": ["native/*"],  # Include bundled native libraries
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Multimedia :: Graphics :: Graphics Conversion",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: MacOS :: MacOS X",
        "Operating System :: POSIX :: Linux",
    ],
    python_requires=">=3.8",
    install_requires=[
        # No dependencies - uses ctypes (stdlib)
    ],
    extras_require={
        "dev": [
            "pytest>=7.0",
            "pytest-cov>=4.0",
            "black>=23.0",
            "mypy>=1.0",
            "ruff>=0.1",
        ],
    },
    cmdclass={
        "build_py": BuildPyWithNativeLibs,
    },
    include_package_data=True,
    zip_safe=False,
)
