# pyslapi
Python bindings for the official SketchUp API and a SketchUp importer addon for Blender.

> ⚠️ **Warning:** Large or deeply nested SketchUp models may cause Blender to freeze or crash. Save your work and keep autosave enabled before importing.

## Installation

### Direct Install (Recommended)
1. Download the latest release from [the releases page](https://github.com/venkateshraju04/skp-importer/releases)
2. In Blender: **Edit > Preferences > Add-ons > Install…** → select the downloaded zip
3. Search for "Sketchup", enable the checkbox, and save preferences

### Manual Install
Unpack the release zip into Blender's addons folder:
- **Windows:** `%APPDATA%\Blender Foundation\Blender\[version]\scripts\addons`
- **macOS:** `~/Library/Application Support/Blender/[version]/scripts/addons`
- **Linux:** `~/.config/blender/[version]/scripts/addons`

Then restart Blender and enable the addon as above.

## Usage
**File > Import > Import Sketchup Scene (.skp)** → select your `.skp` file → click **Import**.

## Compatibility
- Blender 5.x (tested on 5.0.1)
- Python 3.11 · macOS Apple Silicon (arm64)
- SketchUp files up to version 2025.1

> **Linux** is not supported — the SketchUp SDK doesn't provide Linux libraries.

## Changelog

### v0.25.2 — macOS Crash Fixes
*macOS-specific errors fixed by [Venkatesh Raju](https://github.com/venkateshraju04)*

- **Fixed Blender 5.x crash (SIGSEGV):** Recompiled the native extension against matching Python 3.11 headers + Cython 3.x to resolve ABI mismatch crashes.
- **Upgraded Cython to 3.x** for CPython 3.11 compatibility.
- **Improved build script:** `build_release_macos.sh` now auto-detects Blender's Python, verifies ABI, falls back to Homebrew `python@3.11`, and runs post-build checks.

### v0.25.1
*macOS-specific errors fixed by [Venkatesh Raju](https://github.com/venkateshraju04)*

- **Fixed KeyError on nested/duplicate components:** resolves definitions from instances instead of the top-level list.
- **Fixed duplicate processing** of components.
- **macOS Apple Silicon support** with native `arm64` builds and `setuptools`.
- **Added `build_release_macos.sh`** for one-command addon packaging.

### v0.25
*Improvements by [Peter Kirkham](https://pkirkham.github.io/blog/importing-from-sketchup-into-blender/)*

- Preserved SketchUp hierarchy in Blender's outliner
- Fixed nested component/group issues and name collisions
- Fixed transformation errors on mixed-content groups

> **Note:** Some complex multi-transform groups may still import incorrectly. Explode and re-group the geometry in SketchUp before importing as a workaround.

## Building from Source (macOS)

### Prerequisites
- Xcode CLI tools (`xcode-select --install`)
- Blender 5.x in `/Applications`
- Homebrew Python 3.11 (`brew install python@3.11`)
- [SketchUp SDK](https://extensions.sketchup.com/sketchup-sdk) — copy `SketchUpAPI.framework` into the repo root

### Quick Build
```bash
./build_release_macos.sh
```
Then install the output zip in Blender: **Edit > Preferences > Add-ons > Install**.

### Manual Build
```bash
export PYTHON=$(brew --prefix python@3.11)/bin/python3.11
$PYTHON -m pip install "Cython>=3.0.0" setuptools
rm -rf build/ sketchup.cpp
$PYTHON setup.py build_ext --inplace

# Fix framework paths
SO_FILE=$(ls sketchup.cpython-311-darwin.so)
install_name_tool -change \
  @rpath/SketchUpAPI.framework/Versions/A/SketchUpAPI \
  @loader_path/SketchUpAPI.framework/Versions/A/SketchUpAPI \
  "$SO_FILE"
```

> ⚠️ **Do NOT build with a non-3.11 Python.** The resulting `.so` will crash Blender with a SIGSEGV due to ABI mismatch.
