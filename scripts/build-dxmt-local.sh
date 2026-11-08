#!/bin/bash
# Builds DXMT on this Mac the way .github/workflows/graphics.yml does, for experiments only: what reaches
# players comes from the GitHub build. Every pin and patch is read from the given git ref.
#
#   scripts/build-dxmt-local.sh <git ref> [build folder]
#
# Needs Xcode, used through DEVELOPER_DIR alone (xcode-select stays as it is), with its Metal Toolchain,
# plus cmake, ninja, mingw-w64 and meson 1.10.0. The build folder holds LLVM (built once), the Wine
# headers and one work folder per ref; the result lands in <build folder>/out/<ref>.
set -euo pipefail

REF="${1:?usage: $0 <git ref> [build folder]}"
ROOT="${2:-$HOME/Library/Caches/nightforge-dxmt-build}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
JOBS="${NF_BUILD_JOBS:-4}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# The floor the GitHub build ends up with (LC_BUILD_VERSION of the shipped winemetal.so). Xcode's own
# default would be its SDK, and the result wouldn't load on an older macOS.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
export PATH="$HOME/Library/Python/3.9/bin:$PATH"

pin() { git -C "$REPO" show "$REF:.github/workflows/graphics.yml" | sed -n "s/^  $1: *\"\{0,1\}\([^\" ]*\)\"\{0,1\}.*/\1/p" | head -1; }
LLVM_VERSION="$(pin LLVM_VERSION)"; LLVM_COMMIT="$(pin LLVM_COMMIT)"
DXMT_VERSION="$(pin DXMT_VERSION)"; DXMT_COMMIT="$(pin DXMT_COMMIT)"
WINE_TOOLCHAIN_URL="$(pin WINE_TOOLCHAIN_URL)"; WINE_TOOLCHAIN_SHA256="$(pin WINE_TOOLCHAIN_SHA256)"
for value in "$LLVM_VERSION" "$LLVM_COMMIT" "$DXMT_VERSION" "$DXMT_COMMIT" "$WINE_TOOLCHAIN_URL" "$WINE_TOOLCHAIN_SHA256"; do
  [ -n "$value" ] || { echo "A pin is missing from $REF's graphics.yml" >&2; exit 1; }
done

missing=""
for tool in cmake ninja meson git xxd x86_64-w64-mingw32-g++ i686-w64-mingw32-g++; do
  command -v "$tool" > /dev/null || missing="$missing $tool"
done
[ -z "$missing" ] || { echo "Missing:$missing" >&2; exit 1; }
[ "$(meson --version)" = 1.10.0 ] || { echo "meson 1.10.0 is pinned, found $(meson --version)" >&2; exit 1; }

mkdir -p "$ROOT"
ROOT="$(cd "$ROOT" && pwd)"
stamp() { echo "$(date '+%F %T') $*" | tee -a "$ROOT/times.log"; }

# LLVM, as the workflow's llvm job.
if [ ! -f "$ROOT/llvm-darwin/lib/libLLVMCore.a" ]; then
  stamp "LLVM $LLVM_VERSION: start"
  started=$SECONDS
  rm -rf "$ROOT/llvm-project" "$ROOT/llvm-build"
  git clone -q --depth 1 --branch "$LLVM_VERSION" https://github.com/llvm/llvm-project.git "$ROOT/llvm-project"
  [ "$(git -C "$ROOT/llvm-project" rev-parse HEAD)" = "$LLVM_COMMIT" ] || { echo "$LLVM_VERSION isn't commit $LLVM_COMMIT any more" >&2; exit 1; }
  cmake -B "$ROOT/llvm-build" -S "$ROOT/llvm-project/llvm" \
    -DCMAKE_INSTALL_PREFIX="$ROOT/llvm-darwin" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
    -DLLVM_ENABLE_ASSERTIONS=On \
    -DLLVM_ENABLE_ZSTD=Off \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_TARGETS_TO_BUILD="" \
    -DLLVM_BUILD_TOOLS=Off \
    -G Ninja > "$ROOT/llvm-configure.log" 2>&1 || { tail -20 "$ROOT/llvm-configure.log" >&2; exit 1; }
  nice -n 10 cmake --build "$ROOT/llvm-build" -j "$JOBS" > "$ROOT/llvm-build.log" 2>&1 || { tail -30 "$ROOT/llvm-build.log" >&2; exit 1; }
  cmake --install "$ROOT/llvm-build" > /dev/null
  stamp "LLVM: done in $((SECONDS - started)) s"
fi

# Stops here without the Metal compiler; LLVM above doesn't need it.
if ! xcrun -sdk macosx metal --version > /dev/null 2>&1; then
  echo "The Metal compiler doesn't run: $(xcrun -sdk macosx metal --version 2>&1 | head -1)" >&2
  exit 3
fi

# The Wine headers and libraries DXMT builds against, the file the workflow pins.
TOOLCHAIN="$ROOT/wine-toolchain.tar.gz"
[ -f "$TOOLCHAIN" ] || curl -fsSL -o "$TOOLCHAIN" "$WINE_TOOLCHAIN_URL"
echo "$WINE_TOOLCHAIN_SHA256  $TOOLCHAIN" | shasum -a 256 -c - > /dev/null

NAME="$(printf '%s' "$REF" | tr -c 'A-Za-z0-9._-' '_')"
WORK="$ROOT/work/$NAME"
OUT="$ROOT/out/$NAME"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/nightforge" "$OUT"
started=$SECONDS
stamp "DXMT $REF: start"

git -C "$REPO" archive "$REF" engine/patches | tar -x -C "$WORK/nightforge"
git clone -q --depth 1 --branch "$DXMT_VERSION" --recurse-submodules --shallow-submodules \
  https://github.com/3Shain/dxmt.git "$WORK/dxmt" 2> /dev/null
[ "$(git -C "$WORK/dxmt" rev-parse HEAD)" = "$DXMT_COMMIT" ] || { echo "DXMT $DXMT_VERSION isn't commit $DXMT_COMMIT any more" >&2; exit 1; }
for patch in "$WORK"/nightforge/engine/patches/dxmt-*.patch; do
  git -C "$WORK/dxmt" apply "$patch"
done

# Xcode 27's Metal compiler wants one more argument for this private builtin, the value Apple's own
# metal_atomic passes when there are no flags. Xcode 16.1, the GitHub build's, refuses it, so this is no
# patch of ours but a step of the local build only.
sed -i '' 's/__METAL_MEMORY_SCOPE_THREADGROUP__);/__METAL_MEMORY_SCOPE_THREADGROUP__, __METAL_MEMORY_FLAGS_NONE__);/' \
  "$WORK/dxmt/src/airconv/shaders/air_tessellation.metal"
grep -q '__METAL_MEMORY_FLAGS_NONE__' "$WORK/dxmt/src/airconv/shaders/air_tessellation.metal"

mkdir -p "$WORK/dxmt/toolchains/wine"
tar -xz -C "$WORK/dxmt/toolchains/wine" -f "$TOOLCHAIN"
cp -cR "$ROOT/llvm-darwin" "$WORK/dxmt/toolchains/llvm-darwin"
# The one program DXMT's build runs out of that archive only stamps a finished DLL; this does the same
# (tools/winebuild, make_builtin_files), so nothing prebuilt from it is started on this Mac.
cat > "$WORK/dxmt/toolchains/wine/bin/winebuild" <<'STAMP'
#!/usr/bin/python3 -I
import sys
path = sys.argv[-1]
with open(path, "r+b") as f:
    head = f.read(64)
    assert head[:2] == b"MZ" and int.from_bytes(head[60:64], "little") >= 96, path
    f.seek(64)
    f.write(b"Wine builtin DLL".ljust(32, b"\0"))
STAMP
chmod +x "$WORK/dxmt/toolchains/wine/bin/winebuild"

cd "$WORK/dxmt"
meson setup --cross-file build-win64.txt -Denable_nvapi=true -Denable_nvngx=true \
  -Dnative_llvm_path=toolchains/llvm-darwin -Dwine_install_path=toolchains/wine \
  build --buildtype release --prefix "$PWD/install64" --strip > "$WORK/setup64.log" 2>&1 || { tail -20 "$WORK/setup64.log" >&2; exit 1; }
nice -n 10 meson compile -C build -j "$JOBS" > "$WORK/compile64.log" 2>&1 || { tail -30 "$WORK/compile64.log" >&2; exit 1; }
meson install -C build > "$WORK/install64.log" 2>&1 || { tail -20 "$WORK/install64.log" >&2; exit 1; }
meson setup --cross-file build-win32.txt -Dwine_install_path=toolchains/wine \
  build32 --buildtype release --prefix "$PWD/install32" --strip > "$WORK/setup32.log" 2>&1 || { tail -20 "$WORK/setup32.log" >&2; exit 1; }
nice -n 10 meson compile -C build32 -j "$JOBS" > "$WORK/compile32.log" 2>&1 || { tail -30 "$WORK/compile32.log" >&2; exit 1; }
meson install -C build32 > "$WORK/install32.log" 2>&1 || { tail -20 "$WORK/install32.log" >&2; exit 1; }

# The layout of the graphics package.
mkdir -p "$OUT/x86_64-windows" "$OUT/i386-windows" "$OUT/x86_64-unix"
find install64 -name '*.dll' -exec cp {} "$OUT/x86_64-windows/" \;
find install32 -name '*.dll' -exec cp {} "$OUT/i386-windows/" \;
find install64 install32 -name winemetal.so -exec cp {} "$OUT/x86_64-unix/" \;
stamp "DXMT $REF: done in $((SECONDS - started)) s, $OUT"
