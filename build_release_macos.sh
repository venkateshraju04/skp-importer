#!/usr/bin/env bash
#
# build_release_macos.sh — Build and package the SketchUp Importer addon for Blender on macOS
#
# Prerequisites:
#   - Python 3.11+ with Cython installed  (pip install Cython)
#   - SketchUpAPI.framework in the repo root (download from https://extensions.sketchup.com/sketchup-sdk)
#
# Usage:
#   chmod +x build_release_macos.sh
#   ./build_release_macos.sh
#
# Output:
#   sketchup_importer_<version>_macos.zip  — installable Blender addon
#

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ADDON_VERSION="0.25.1"
PYTHON_CMD="${PYTHON:-python3}"
ZIP_NAME="sketchup_importer_${ADDON_VERSION}_macos.zip"

# ─── Pre-flight checks ──────────────────────────────────────────────────────

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     SketchUp Importer — macOS Release Builder               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check for Python
if ! command -v "$PYTHON_CMD" &>/dev/null; then
    echo "❌ Python not found. Set PYTHON env var or install Python 3.11+."
    exit 1
fi

PYTHON_VERSION=$("$PYTHON_CMD" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "✅ Python: $PYTHON_VERSION ($("$PYTHON_CMD" --version 2>&1))"

# Check for Cython
if ! "$PYTHON_CMD" -c "import Cython" 2>/dev/null; then
    echo "❌ Cython not found. Install it: pip install Cython"
    exit 1
fi
CYTHON_VERSION=$("$PYTHON_CMD" -c "import Cython; print(Cython.__version__)")
echo "✅ Cython: $CYTHON_VERSION"

# Check for SketchUpAPI.framework
if [ ! -d "SketchUpAPI.framework" ]; then
    echo "❌ SketchUpAPI.framework not found in repo root."
    echo "   Download the macOS SDK from: https://extensions.sketchup.com/sketchup-sdk"
    echo "   Copy SketchUpAPI.framework into: $SCRIPT_DIR/"
    exit 1
fi
echo "✅ SketchUpAPI.framework found"

# Detect architecture
ARCH=$(uname -m)
echo "✅ Architecture: $ARCH"
echo ""

# ─── Step 1: Build Cython extension ─────────────────────────────────────────

echo "🔨 Building Cython extension..."
"$PYTHON_CMD" setup.py build_ext --inplace 2>&1 | tail -5

# Find the built .so file
SO_FILE=$(ls sketchup.cpython-*.so 2>/dev/null || true)
if [ -z "$SO_FILE" ]; then
    echo "❌ Build failed — no .so file produced"
    exit 1
fi
echo "✅ Built: $SO_FILE"

# ─── Step 2: Fix framework load paths ───────────────────────────────────────

echo ""
echo "🔧 Fixing framework load paths with install_name_tool..."

install_name_tool -change \
    "@rpath/SketchUpAPI.framework/Versions/Current/SketchUpAPI" \
    "@loader_path/SketchUpAPI.framework/Versions/Current/SketchUpAPI" \
    "$SO_FILE" 2>/dev/null || true

install_name_tool -change \
    "@rpath/SketchUpAPI.framework/Versions/A/SketchUpAPI" \
    "@loader_path/SketchUpAPI.framework/Versions/A/SketchUpAPI" \
    "$SO_FILE" 2>/dev/null || true

echo "✅ Load paths fixed"

# Verify with otool
echo ""
echo "📋 Library dependencies:"
otool -L "$SO_FILE" | grep -i sketch || true

# ─── Step 3: Remove quarantine attributes ───────────────────────────────────

echo ""
echo "🔓 Removing quarantine attributes from framework..."
xattr -r -d com.apple.quarantine SketchUpAPI.framework 2>/dev/null || true
echo "✅ Quarantine attributes cleared"

# ─── Step 4: Package as Blender addon zip ────────────────────────────────────

echo ""
echo "📦 Packaging Blender addon..."

# Clean up any previous build
STAGING_DIR=$(mktemp -d)
ADDON_DIR="$STAGING_DIR/sketchup_importer"

mkdir -p "$ADDON_DIR/SKPutil"

# Copy addon files
cp sketchup_importer/__init__.py  "$ADDON_DIR/"
cp sketchup_importer/SKPutil/__init__.py "$ADDON_DIR/SKPutil/"

# Copy compiled extension (rename to sketchup.so for simplicity)
cp "$SO_FILE" "$ADDON_DIR/sketchup.so"

# Copy SketchUp framework
cp -R SketchUpAPI.framework "$ADDON_DIR/"

# Also copy LayOutAPI.framework if present (some SDK versions include it)
if [ -d "LayOutAPI.framework" ]; then
    cp -R LayOutAPI.framework "$ADDON_DIR/"
    echo "   + LayOutAPI.framework included"
fi

# Create the zip
rm -f "$ZIP_NAME"
(cd "$STAGING_DIR" && zip -r -q "$SCRIPT_DIR/$ZIP_NAME" sketchup_importer/)

# Clean up staging
rm -rf "$STAGING_DIR"

# ─── Done ────────────────────────────────────────────────────────────────────

ZIP_SIZE=$(du -h "$ZIP_NAME" | cut -f1)
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅ Release built successfully!                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Output: $ZIP_NAME"
echo "║  Size:   $ZIP_SIZE"
echo "║  Arch:   $ARCH"
echo "║  Python: $PYTHON_VERSION"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Install in Blender:                                        ║"
echo "║    Edit > Preferences > Add-ons > Install > select zip      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
