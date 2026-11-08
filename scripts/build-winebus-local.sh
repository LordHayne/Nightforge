#!/bin/bash
# Builds the gamepad package's winebus.so on this Mac as .github/workflows/gamepad.yml does, for
# experiments only: what reaches players comes from the GitHub build. Pins and patches come from the
# given git ref; the Command Line Tools are used as they are (xcode-select isn't touched).
#
#   scripts/build-winebus-local.sh <git ref> [build folder]
#
# Needs bison, flex, pkg-config and mingw-w64 from Homebrew. The result lands in <build folder>/out/<ref>.
set -euo pipefail

REF="${1:?usage: $0 <git ref> [build folder]}"
ROOT="${2:-$HOME/Library/Caches/nightforge-winebus-build}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
JOBS="${NF_BUILD_JOBS:-2}"
export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"

pin() { git -C "$REPO" show "$REF:.github/workflows/gamepad.yml" | sed -n "s/^  $1: *\"\{0,1\}\([^\" ]*\)\"\{0,1\}.*/\1/p" | head -1; }
WINECX_COMMIT="$(pin WINECX_COMMIT)"; SDL_TAG="$(pin SDL_HEADERS_TAG)"
[ -n "$WINECX_COMMIT" ] && [ -n "$SDL_TAG" ] || { echo "A pin is missing from $REF's gamepad.yml" >&2; exit 1; }

mkdir -p "$ROOT"
ROOT="$(cd "$ROOT" && pwd)"
NAME="$(printf '%s' "$REF" | tr -c 'A-Za-z0-9._-' '_')"
OUT="$ROOT/out/$NAME"
rm -rf "$OUT"; mkdir -p "$OUT"

# Source once per commit, kept; each build starts from an untouched copy of it.
if [ ! -d "$ROOT/winecx-$WINECX_COMMIT/.git" ]; then
  rm -rf "$ROOT/winecx-$WINECX_COMMIT"
  mkdir -p "$ROOT/winecx-$WINECX_COMMIT"
  git -C "$ROOT/winecx-$WINECX_COMMIT" init -q
  git -C "$ROOT/winecx-$WINECX_COMMIT" remote add origin https://github.com/dappermint/winecx.git
  git -C "$ROOT/winecx-$WINECX_COMMIT" fetch -q --depth 1 origin "$WINECX_COMMIT"
  git -C "$ROOT/winecx-$WINECX_COMMIT" checkout -q FETCH_HEAD
fi
[ -d "$ROOT/sdl-$SDL_TAG" ] || git clone -q --depth 1 --branch "$SDL_TAG" https://github.com/libsdl-org/SDL.git "$ROOT/sdl-$SDL_TAG"

SRC="$ROOT/winecx-$WINECX_COMMIT"
git -C "$SRC" reset -q --hard
git -C "$SRC" clean -qfd
mkdir -p "$ROOT/patches-$NAME"
git -C "$REPO" archive "$REF" engine/patches | tar -x -C "$ROOT/patches-$NAME"
for patch in "$ROOT/patches-$NAME"/engine/patches/winebus-winecx-*.patch; do
  echo "Applying $(basename "$patch")"
  git -C "$SRC" apply "$patch"
done

SDL="$ROOT/sdl-$SDL_TAG"
BUILD="$ROOT/build-$WINECX_COMMIT"
if [ ! -f "$BUILD/Makefile" ]; then
  rm -rf "$BUILD"; mkdir -p "$BUILD"
  ( cd "$BUILD" && "$SRC/configure" --host=x86_64-apple-darwin --enable-win64 --disable-tests \
      --without-freetype --without-x --without-gstreamer --without-cups --without-sane \
      --without-krb5 --without-gssapi --without-usb --without-pcap --without-netapi --without-gnutls \
      CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
      SDL2_CFLAGS="-I$SDL/include" \
      CFLAGS="-O2 -Wno-error -mmacosx-version-min=11.0" \
      LDFLAGS="-mmacosx-version-min=11.0" > "$ROOT/configure.log" 2>&1 ) || { tail -20 "$ROOT/configure.log" >&2; exit 1; }
  # As gamepad.yml: winebus only dlopens SDL by name, and configure can't link it across architectures.
  if grep -q "SONAME_LIBSDL2" "$BUILD/include/config.h"; then
    sed -i '' 's|^.*SONAME_LIBSDL2.*$|#define SONAME_LIBSDL2 "libSDL2-2.0.0.dylib"|' "$BUILD/include/config.h"
  else
    echo '#define SONAME_LIBSDL2 "libSDL2-2.0.0.dylib"' >> "$BUILD/include/config.h"
  fi
  if grep -q "^SDL2_CFLAGS" "$BUILD/Makefile"; then
    sed -i '' "s|^SDL2_CFLAGS *=.*|SDL2_CFLAGS = -I$SDL/include|" "$BUILD/Makefile"
  else
    echo "SDL2_CFLAGS = -I$SDL/include" >> "$BUILD/Makefile"
  fi
fi

( cd "$BUILD" && nice -n 10 make -j"$JOBS" dlls/winebus.sys/winebus.so > "$ROOT/make.log" 2>&1 ) || { grep -E 'error|Error' "$ROOT/make.log" | head -20 >&2; exit 1; }
so="$BUILD/dlls/winebus.sys/winebus.so"
strings "$so" | grep -q "libSDL2-2.0.0.dylib" || { echo "winebus.so without SDL" >&2; exit 1; }
strings "$so" | grep -q "Controller (XBOX 360 For Windows)" || { echo "winebus.so without the Xbox 360 IDs" >&2; exit 1; }
strings "$so" | grep -q "nightforge.pad-silence" || { echo "winebus.so without the pad's silence" >&2; exit 1; }
nm "$so" | grep -q "sdl_bus_init" || { echo "no SDL bus" >&2; exit 1; }
cp "$so" "$OUT/winebus.so"
install_name_tool -add_rpath @loader_path/../../ "$OUT/winebus.so"
codesign -fs - "$OUT/winebus.so"
echo "$OUT/winebus.so"
