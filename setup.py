# <pep8-80 compliant>
# -*- coding: utf-8 -*-

__author__ = "Martijn Berger"

import platform
import struct
import sys
import sysconfig

from setuptools import setup, Extension

from Cython.Distutils import build_ext

# ─── Safety: warn if building with the wrong Python ─────────────────────
# Blender 5.x bundles Python 3.11. Building with any other version
# produces a .so that will SIGSEGV on import due to ABI mismatch.
if sys.version_info[:2] != (3, 11):
    print(
        f"\n"
        f"  ⚠️  WARNING: Building with Python {sys.version_info.major}"
        f".{sys.version_info.minor}, but Blender 5.x requires 3.11.\n"
        f"  ⚠️  The resulting .so will crash Blender on import!\n"
        f"  ⚠️  Use Blender's bundled Python instead:\n"
        f"  ⚠️    /Applications/Blender.app/Contents/Resources/5.0"
        f"/python/bin/python3.11 setup.py build_ext --inplace\n"
    )

# Detect Python ABI tag for naming the compiled extension
_abi_tag = sysconfig.get_config_var("SOABI") or "cpython"

if platform.system() == "Linux":
    libraries = ["SketchUpAPI"]
    extra_compile_args = []
    extra_link_args = ["-Lbinaries/sketchup/x86-64"]

elif platform.system() == "Darwin":  # macOS
    libraries = []

    # Detect architecture for Apple Silicon vs Intel
    _is_arm64 = platform.machine() == "arm64"

    extra_compile_args = [
        "-mmacosx-version-min=11.0",
        "-F.",
        "-std=c++14",
    ]
    extra_link_args = [
        "-mmacosx-version-min=11.0",
        "-F",
        ".",
        "-framework",
        "SketchUpAPI",
    ]

    # Add rpath search for framework resolution at runtime
    extra_link_args += ["-Wl,-rpath,@loader_path"]

else:  # Windows
    libraries = ["SketchUpAPI"]
    extra_compile_args = ["/Zp8"]
    extra_link_args = ["/LIBPATH:binaries/sketchup/x64/"]

ext_modules = [
    Extension(
        "sketchup",  # name of extension
        ["sketchup.pyx"],  # filename of our Pyrex/Cython source
        language="c++",  # this causes Pyrex/Cython to create C++ source
        include_dirs=["headers"],  # usual stuff
        libraries=libraries,  # ditto
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
    )
]

for e in ext_modules:
    e.cython_directives = {"language_level": "3"}  # all are Python-3

setup(name="Sketchup", cmdclass={"build_ext": build_ext}, ext_modules=ext_modules)

# Post-build steps for macOS (run manually or via build_release_macos.sh):
#   install_name_tool -change \
#     "@rpath/SketchUpAPI.framework/Versions/Current/SketchUpAPI" \
#     "@loader_path/SketchUpAPI.framework/Versions/Current/SketchUpAPI" \
#     sketchup.<ABI_TAG>-darwin.so
#   install_name_tool -change \
#     "@rpath/SketchUpAPI.framework/Versions/A/SketchUpAPI" \
#     "@loader_path/SketchUpAPI.framework/Versions/A/SketchUpAPI" \
#     sketchup.<ABI_TAG>-darwin.so
#   sudo xattr -r -d com.apple.quarantine SketchUpAPI.framework
