#!/bin/bash
# Builds KosmicKrisp – Mesa's Vulkan driver on Metal – for x86_64, with the Khronos Vulkan loader,
# into the archive the `kosmickrisp` component points to. Under winecx DXVK then draws through it
# instead of MoltenVK, which lacks what DXVK's Direct3D 9 needs (geometryShader,
# shaderCullDistance). winecx runs as x86_64 under Rosetta, so an arm64 driver can't load there:
#
#   scripts/build-kosmickrisp.sh <work folder> [output folder]
#
# Mesa's build tools (mesa_clc, vtn_bindgen2, kk_clc) are built for this Mac first and need LLVM;
# the driver is then cross-built for x86_64 and links nothing outside macOS. Pins and the Mesa
# patches carried on top are in scripts/kosmickrisp/. Needs Homebrew's cmake, ninja, pkg-config,
# llvm, spirv-llvm-translator and spirv-tools, and Python 3.10 or later with meson, mako, packaging
# and pyyaml first in PATH (a venv is fine). Network for the sources, about 2 GB in the work folder.
# JOBS limits the parallel compiles (default: all cores). EXTRA_PATCHES names a folder of Mesa patches
# to try on top (scripts/kosmickrisp/proposed); the archive's version then ends in "-test".
#
# The archive holds libvulkan.1.dylib (the loader), libvulkan_kosmickrisp.dylib, kosmickrisp_icd.json
# (library path relative to it), the licences (Mesa MIT, loader and headers Apache-2.0) and
# SOURCE.txt with the pins. Recipe after shadexternals/mesa-kosmickrisp (MIT) and the KosmicKrisp
# lane in dappermint/winecx-gptk.
set -euo pipefail

here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=kosmickrisp/pins.env
source "$here/kosmickrisp/pins.env"
WORK="${1:?usage: $0 <work folder> [output folder]}"
OUTDIR="${2:-$WORK/out}"
mkdir -p "$WORK" "$OUTDIR"
WORK="$(cd "$WORK" && pwd -P)"
OUTDIR="$(cd "$OUTDIR" && pwd -P)"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
export MACOSX_DEPLOYMENT_TARGET=26.0
LLVM_CONFIG="${LLVM_CONFIG:-$(brew --prefix llvm)/bin/llvm-config}"

# Mesa's build runs on Python 3.10 or later with mako, pyyaml and packaging, and on meson; when
# they're missing, a venv in the work folder brings them.
if ! python3 -c 'import sys, mako, yaml, packaging; assert sys.version_info >= (3, 10)' 2>/dev/null \
  || ! command -v meson >/dev/null; then
  if [ ! -x "$WORK/venv/bin/python3" ]; then
    PYTHON="$(brew --prefix python@3.13 2>/dev/null)/bin/python3.13"
    [ -x "$PYTHON" ] || PYTHON=python3
    "$PYTHON" -m venv "$WORK/venv"
  fi
  # Every file by its SHA-256 (review A5): what's built here ends up named in the signed component list.
  "$WORK/venv/bin/python3" -m pip install -q --require-hashes -r "$here/kosmickrisp/requirements.txt"
  export PATH="$WORK/venv/bin:$PATH"
fi
python3 -c 'import sys, mako, yaml, packaging; assert sys.version_info >= (3, 10)' \
  || { echo "needs Python 3.10 or later with mako, pyyaml and packaging" >&2; exit 1; }
for tool in meson ninja cmake pkg-config; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done
[ -x "$LLVM_CONFIG" ] || { echo "no llvm-config at $LLVM_CONFIG (brew install llvm)" >&2; exit 1; }

# A pinned commit, fetched alone; a work folder used before is reused.
checkout() {
  local url="$1" commit="$2" dir="$3"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
  fi
  if [ "$(git -C "$dir" rev-parse -q --verify HEAD || true)" != "$commit" ]; then
    git -C "$dir" fetch -q --depth=1 origin "$commit"
    git -C "$dir" checkout -q --detach FETCH_HEAD
  fi
  # Earlier patches go, so each run applies them to the pinned tree once; one that no longer
  # applies stops the build.
  git -C "$dir" reset -q --hard "$commit"
  [ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ]
}

MESA="$WORK/mesa"
checkout "$MESA_URL" "$MESA_COMMIT" "$MESA"
PATCHES=("$here"/kosmickrisp/patches/*.patch)
[ -n "${EXTRA_PATCHES:-}" ] && PATCHES+=("$(cd "$EXTRA_PATCHES" && pwd -P)"/*.patch)
for patch in "${PATCHES[@]}"; do
  [ -e "$patch" ] || continue
  git -C "$MESA" apply --index "$patch"
done
checkout "$VULKAN_LOADER_URL" "$VULKAN_LOADER_COMMIT" "$WORK/loader"
checkout "$VULKAN_HEADERS_URL" "$VULKAN_HEADERS_COMMIT" "$WORK/headers"

COMMON=(-Dplatforms=macos -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dopengl=false -Dzstd=disabled)
setup() {
  local dir="$1"; shift
  if [ -f "$dir/build.ninja" ]; then meson setup --reconfigure "$dir" "$MESA" "$@"; else meson setup "$dir" "$MESA" "$@"; fi
}

# 1. Mesa's own compilers, for this Mac.
TOOLS="$WORK/build-tools"
LLVM_CONFIG="$LLVM_CONFIG" setup "$TOOLS" --buildtype=release \
  -Dinstall-mesa-clc=true -Dinstall-precomp-compiler=true "${COMMON[@]}"
LLVM_CONFIG="$LLVM_CONFIG" meson compile -C "$TOOLS" -j "$JOBS" mesa_clc vtn_bindgen2 kk_clc

# 2. The driver for x86_64, with those compilers. Apple's clang by path: Homebrew's LLVM must not
#    build the driver, or it links Homebrew's libraries.
CROSS="$WORK/x86_64-darwin.ini"
cat > "$CROSS" <<'EOF'
[binaries]
c = '/usr/bin/clang'
cpp = '/usr/bin/clang++'
objc = '/usr/bin/clang'
objcpp = '/usr/bin/clang++'
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'

[built-in options]
c_args = ['-target', 'x86_64-apple-macos26.0']
cpp_args = ['-target', 'x86_64-apple-macos26.0']
objc_args = ['-target', 'x86_64-apple-macos26.0']
objcpp_args = ['-target', 'x86_64-apple-macos26.0']
c_link_args = ['-target', 'x86_64-apple-macos26.0']
cpp_link_args = ['-target', 'x86_64-apple-macos26.0']
objc_link_args = ['-target', 'x86_64-apple-macos26.0']
objcpp_link_args = ['-target', 'x86_64-apple-macos26.0']

[host_machine]
system = 'darwin'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
TARGET="$WORK/build-x86_64"
TOOL_PATH="$TOOLS/src/compiler/clc:$TOOLS/src/compiler/spirv:$TOOLS/src/kosmickrisp/clc"
PATH="$TOOL_PATH:$PATH" setup "$TARGET" --buildtype=release --cross-file="$CROSS" \
  -Dmesa-clc=system -Dprecomp-compiler=system -Dspirv-tools=disabled -Dllvm=disabled "${COMMON[@]}"
PATH="$TOOL_PATH:$PATH" meson compile -C "$TARGET" -j "$JOBS" vulkan_kosmickrisp kosmickrisp_mesa_icd

# 3. The Khronos loader, which winecx loads through CX_LIBVULKAN; it finds the driver through
#    VK_DRIVER_FILES.
cmake -S "$WORK/headers" -B "$WORK/headers-build" -DCMAKE_INSTALL_PREFIX="$WORK/headers-install" >/dev/null
cmake --install "$WORK/headers-build" >/dev/null
cmake --fresh -S "$WORK/loader" -B "$WORK/loader-build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DBUILD_TESTS=OFF -DCMAKE_PREFIX_PATH="$WORK/headers-install" -DVULKAN_HEADERS_INSTALL_DIR="$WORK/headers-install"
cmake --build "$WORK/loader-build" --parallel "$JOBS"

# 4. The archive.
VERSION="$(tr -d '[:space:]' < "$MESA/VERSION")-${MESA_COMMIT:0:8}${EXTRA_PATCHES:+-test}"
NAME="nightforge-kosmickrisp-$VERSION"
STAGE="$OUTDIR/$NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE/licenses"
cp -L "$TARGET/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib" "$STAGE/"
cp -L "$WORK/loader-build/loader/libvulkan.1.dylib" "$STAGE/"
# Without a zlib for x86_64 Mesa builds its own; should it come out as a library of its own, it
# goes along and is linked from next to the driver.
if otool -L "$STAGE/libvulkan_kosmickrisp.dylib" | grep -q '@rpath/libz.1.dylib'; then
  cp -L "$(find "$TARGET/subprojects" -name libz.1.dylib | head -1)" "$STAGE/"
  install_name_tool -change '@rpath/libz.1.dylib' '@loader_path/libz.1.dylib' "$STAGE/libvulkan_kosmickrisp.dylib"
  cp "$(find "$MESA/subprojects" -maxdepth 2 -path '*zlib*' -name LICENSE | head -1)" "$STAGE/licenses/zlib.txt" 2>/dev/null \
    || cp "$(find "$MESA/subprojects" -maxdepth 2 -path '*zlib*' -name README | head -1)" "$STAGE/licenses/zlib.txt"
fi
ICD="$(ls "$TARGET"/src/kosmickrisp/vulkan/kosmickrisp_mesa_icd.*json | head -1)"
python3 - "$ICD" "$STAGE/kosmickrisp_icd.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
# Relative to the manifest: the folder may move (another drive, a new version).
manifest["ICD"]["library_path"] = "./libvulkan_kosmickrisp.dylib"
with open(sys.argv[2], "w") as out:
    json.dump(manifest, out, indent=2)
    out.write("\n")
PY

# Nothing from Homebrew and nothing for arm64 may go along.
for library in "$STAGE"/*.dylib; do
  [ "$(lipo -archs "$library")" = x86_64 ] || { echo "$library is not x86_64 only" >&2; exit 1; }
  install_name_tool -id "@loader_path/$(basename "$library")" "$library"
  otool -L "$library" | tail -n +3 | while read -r dependency _; do
    case "$dependency" in
      /usr/lib/*|/System/Library/*) ;;
      @loader_path/libz.1.dylib) [ -f "$STAGE/libz.1.dylib" ] ;;
      *) echo "$library links $dependency, which doesn't go along" >&2; exit 1 ;;
    esac
  done
  codesign --force --sign - --timestamp=none "$library"
  codesign --verify --strict "$library"
done

cp "$MESA/docs/license.rst" "$STAGE/licenses/mesa.rst"
cp -R "$MESA/licenses" "$STAGE/licenses/mesa"
cp "$WORK/loader/LICENSE.txt" "$STAGE/licenses/vulkan-loader.txt"
cp "$WORK/headers/LICENSE.md" "$STAGE/licenses/vulkan-headers.md"
{
  echo "KosmicKrisp (Mesa's Vulkan driver on Metal) for x86_64 with the Khronos Vulkan loader, built by"
  echo "Nightforge's scripts/build-kosmickrisp.sh. Mesa is MIT-licensed, the loader and headers Apache-2.0."
  echo
  grep -E '^[A-Z_]+=' "$here/kosmickrisp/pins.env"
  for patch in "${PATCHES[@]}"; do
    [ -e "$patch" ] && echo "PATCH=$(basename "$patch") $(shasum -a 256 "$patch" | cut -d' ' -f1)"
  done
  echo
  /usr/bin/clang --version | head -1
  echo "meson $(meson --version), cmake $(cmake --version | head -1 | awk '{print $3}'), $(python3 --version)"
  brew list --versions llvm spirv-llvm-translator spirv-tools 2>/dev/null
} > "$STAGE/SOURCE.txt"

ARCHIVE="$OUTDIR/$NAME.tar.gz"
tar -czf "$ARCHIVE" -C "$OUTDIR" "$NAME"
echo "$ARCHIVE"
shasum -a 256 "$ARCHIVE"
