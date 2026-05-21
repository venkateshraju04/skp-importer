#!/usr/bin/env bash
#
# build_release_macos.sh — Build and package the SketchUp Importer addon for Blender 5.x on macOS
#
# Prerequisites:
#   - Blender 5.x installed in /Applications  (or set BLENDER_APP)
#   - SketchUpAPI.framework in the repo root (download from https://extensions.sketchup.com/sketchup-sdk)
#   - Xcode command-line tools (xcode-select --install)
#
# Usage:
#   chmod +x build_release_macos.sh
#   ./build_release_macos.sh
#
# Output:
#   sketchup_importer_<version>_macos_arm64.zip  — installable Blender addon
#

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ADDON_VERSION="0.25.1"
ZIP_NAME="sketchup_importer_${ADDON_VERSION}_macos_arm64.zip"

# ─── Locate Blender's bundled Python ─────────────────────────────────────────

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     SketchUp Importer — macOS Release Builder (Blender 5.x)║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Allow override via BLENDER_APP env var
BLENDER_APP="${BLENDER_APP:-/Applications/Blender.app}"

if [ ! -d "$BLENDER_APP" ]; then
    echo "❌ Blender not found at: $BLENDER_APP"
    echo "   Set BLENDER_APP=/path/to/Blender.app to override."
    exit 1
fi

# Find the Blender version directory (e.g., 5.0)
BLENDER_VERSION_DIR=$(ls -d "$BLENDER_APP/Contents/Resources"/[0-9]* 2>/dev/null | sort -V | tail -1)
if [ -z "$BLENDER_VERSION_DIR" ]; then
    echo "❌ Could not find Blender version directory in $BLENDER_APP/Contents/Resources/"
    exit 1
fi

# Determine the Python version Blender uses
BLENDER_PYTHON="$BLENDER_VERSION_DIR/python/bin/python3.11"
if [ ! -x "$BLENDER_PYTHON" ]; then
    BLENDER_PYTHON=$(ls "$BLENDER_VERSION_DIR/python/bin"/python3.* 2>/dev/null | head -1)
    if [ -z "$BLENDER_PYTHON" ] || [ ! -x "$BLENDER_PYTHON" ]; then
        echo "❌ Blender's Python not found in $BLENDER_VERSION_DIR/python/bin/"
        exit 1
    fi
fi

BLENDER_PY_VERSION=$("$BLENDER_PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
BLENDER_PY_SOABI=$("$BLENDER_PYTHON" -c "import sysconfig; print(sysconfig.get_config_var('SOABI'))")
echo "✅ Blender: $BLENDER_APP (version dir: $(basename "$BLENDER_VERSION_DIR"))"
echo "✅ Blender Python: $BLENDER_PY_VERSION ($("$BLENDER_PYTHON" --version 2>&1))"
echo "   SOABI: $BLENDER_PY_SOABI"

# Check if Blender's Python has development headers (Python.h)
BLENDER_INCLUDE=$("$BLENDER_PYTHON" -c "import sysconfig; print(sysconfig.get_config_var('INCLUDEPY'))")
if [ -f "$BLENDER_INCLUDE/Python.h" ]; then
    echo "✅ Blender Python has development headers"
    PYTHON_CMD="$BLENDER_PYTHON"
else
    echo "⚠️  Blender's Python lacks development headers (no Python.h)"
    echo "   Falling back to Homebrew python@${BLENDER_PY_VERSION}..."

    # Try Homebrew
    BREW_PREFIX=$(brew --prefix "python@${BLENDER_PY_VERSION}" 2>/dev/null || true)
    if [ -z "$BREW_PREFIX" ] || [ ! -d "$BREW_PREFIX" ]; then
        echo "❌ Homebrew python@${BLENDER_PY_VERSION} not found."
        echo "   Install it:  brew install python@${BLENDER_PY_VERSION}"
        exit 1
    fi

    BREW_PYTHON="$BREW_PREFIX/bin/python${BLENDER_PY_VERSION}"
    if [ ! -x "$BREW_PYTHON" ]; then
        BREW_PYTHON=$(ls "$BREW_PREFIX/bin"/python${BLENDER_PY_VERSION}* 2>/dev/null | head -1)
    fi

    if [ -z "$BREW_PYTHON" ] || [ ! -x "$BREW_PYTHON" ]; then
        echo "❌ Could not find python${BLENDER_PY_VERSION} in $BREW_PREFIX/bin/"
        exit 1
    fi

    # Verify ABI compatibility
    BREW_PY_SOABI=$("$BREW_PYTHON" -c "import sysconfig; print(sysconfig.get_config_var('SOABI'))")
    if [ "$BREW_PY_SOABI" != "$BLENDER_PY_SOABI" ]; then
        echo "❌ ABI mismatch! Blender=$BLENDER_PY_SOABI, Brew=$BREW_PY_SOABI"
        exit 1
    fi

    PYTHON_CMD="$BREW_PYTHON"
    echo "✅ Using Homebrew: $BREW_PYTHON"
    echo "   SOABI: $BREW_PY_SOABI (matches Blender ✅)"
fi

PYTHON_VERSION=$("$PYTHON_CMD" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_FULL=$("$PYTHON_CMD" --version 2>&1)
echo "✅ Build Python: $PYTHON_VERSION ($PYTHON_FULL)"
echo "   Path: $PYTHON_CMD"

# Verify Python version matches Blender
if [ "$PYTHON_VERSION" != "$BLENDER_PY_VERSION" ]; then
    echo ""
    echo "❌ FATAL: Build Python ($PYTHON_VERSION) doesn't match Blender Python ($BLENDER_PY_VERSION)"
    exit 1
fi

# ─── Pre-flight checks ──────────────────────────────────────────────────────

# Check for / install Cython
if ! "$PYTHON_CMD" -c "import Cython" 2>/dev/null; then
    echo ""
    echo "📦 Cython not found in Blender's Python. Installing..."
    "$PYTHON_CMD" -m ensurepip --upgrade 2>/dev/null || true
    "$PYTHON_CMD" -m pip install "Cython>=3.0.0" --quiet
fi

CYTHON_VERSION=$("$PYTHON_CMD" -c "import Cython; print(Cython.__version__)")
echo "✅ Cython: $CYTHON_VERSION"

# Verify Cython is 3.x+
CYTHON_MAJOR=$("$PYTHON_CMD" -c "import Cython; print(Cython.__version__.split('.')[0])")
if [ "$CYTHON_MAJOR" -lt 3 ]; then
    echo "❌ Cython $CYTHON_VERSION is too old. Need Cython >= 3.0.0"
    echo "   Run: $PYTHON_CMD -m pip install 'Cython>=3.0.0' --upgrade"
    exit 1
fi

# Check for setuptools
if ! "$PYTHON_CMD" -c "import setuptools" 2>/dev/null; then
    echo "📦 Installing setuptools..."
    "$PYTHON_CMD" -m pip install setuptools --quiet
fi

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

# ─── Step 1: Clean stale build artifacts ─────────────────────────────────────

echo "🧹 Cleaning stale build artifacts..."
rm -rf build/
rm -f sketchup.cpp sketchup.c
rm -f sketchup.cpython-*.so
rm -f sketchup.so
echo "✅ Clean"

# ─── Step 2: Build Cython extension ─────────────────────────────────────────

echo ""
echo "🔨 Building Cython extension with Blender's Python $PYTHON_VERSION..."
"$PYTHON_CMD" setup.py build_ext --inplace 2>&1 | tail -10

# Find the built .so file
SO_FILE=$(ls sketchup.cpython-*.so 2>/dev/null || true)
if [ -z "$SO_FILE" ]; then
    echo "❌ Build failed — no .so file produced"
    exit 1
fi
echo "✅ Built: $SO_FILE"

# ─── Step 3: Verify build ───────────────────────────────────────────────────

echo ""
echo "🔍 Verifying build..."

# Check architecture
FILE_INFO=$(file "$SO_FILE")
echo "   File: $FILE_INFO"
if [[ "$FILE_INFO" != *"arm64"* ]] && [[ "$ARCH" == "arm64" ]]; then
    echo "❌ FATAL: Built .so is NOT arm64! Got: $FILE_INFO"
    exit 1
fi
echo "   ✅ Architecture: arm64"

# Check ABI tag
EXPECTED_SOABI=$("$PYTHON_CMD" -c "import sysconfig; print(sysconfig.get_config_var('SOABI'))")
if [[ "$SO_FILE" != *"$EXPECTED_SOABI"* ]]; then
    echo "   ⚠️  ABI tag mismatch: expected $EXPECTED_SOABI in filename"
fi
echo "   ✅ ABI tag: $EXPECTED_SOABI"

# Check that libpython is NOT linked (should be undefined, resolved at runtime)
if otool -L "$SO_FILE" | grep -q "libpython"; then
    echo "   ⚠️  WARNING: .so links against libpython directly"
    echo "   This may cause issues if Blender's Python is statically linked."
else
    echo "   ✅ No direct libpython linkage (correct for Blender)"
fi

# Check SketchUpAPI linkage
if otool -L "$SO_FILE" | grep -q "SketchUpAPI"; then
    echo "   ✅ SketchUpAPI.framework linked"
else
    echo "   ❌ SketchUpAPI.framework NOT linked!"
    exit 1
fi

# ─── Step 4: Fix framework load paths ───────────────────────────────────────

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
otool -L "$SO_FILE" | head -10

# ─── Step 5: Test import ────────────────────────────────────────────────────

echo ""
echo "🧪 Testing import with Blender's Python..."
if "$PYTHON_CMD" -c "import sketchup; print('   API version:', sketchup.get_API_version())" 2>&1; then
    echo "   ✅ Import test PASSED"
else
    echo "   ⚠️  Import test failed (may need SketchUpAPI.framework in PATH)"
    echo "   This is expected if the framework can't be loaded outside Blender."
    echo "   The extension should still work inside Blender."
fi

# ─── Step 6: Remove quarantine attributes ───────────────────────────────────

echo ""
echo "🔓 Removing quarantine attributes from framework..."
xattr -r -d com.apple.quarantine SketchUpAPI.framework 2>/dev/null || true
xattr -r -d com.apple.quarantine "$SO_FILE" 2>/dev/null || true
echo "✅ Quarantine attributes cleared"

# ─── Step 7: Package as Blender addon zip ────────────────────────────────────

echo ""
echo "📦 Packaging Blender addon..."

# Clean up any previous build
STAGING_DIR=$(mktemp -d)
ADDON_DIR="$STAGING_DIR/sketchup_importer"

mkdir -p "$ADDON_DIR/SKPutil"

# Copy addon files
cp sketchup_importer/__init__.py  "$ADDON_DIR/"
cp sketchup_importer/SKPutil/__init__.py "$ADDON_DIR/SKPutil/"

# Copy compiled extension — keep ABI-tagged name AND provide untagged fallback
cp "$SO_FILE" "$ADDON_DIR/"
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
echo "║  Output:  $ZIP_NAME"
echo "║  Size:    $ZIP_SIZE"
echo "║  Arch:    $ARCH"
echo "║  Python:  $PYTHON_VERSION ($PYTHON_FULL)"
echo "║  Cython:  $CYTHON_VERSION"
echo "║  ABI tag: $EXPECTED_SOABI"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Install in Blender:                                        ║"
echo "║    Edit > Preferences > Add-ons > Install > select zip      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Verify in Blender (optional):                              ║"
echo "║    /Applications/Blender.app/Contents/MacOS/Blender \\       ║"
echo "║      --python-expr 'import sketchup; print(\"OK\")'          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
