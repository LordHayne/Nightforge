#!/bin/bash
# Builds Nightforge's engine fixes for winecx: ntdll.so with the msync fix and winecoreaudio.so
# with Wine 11.21's SpatialMixer downmix (engine/patches/winecx-*.patch), from the winecx commit
# the pinned runtime was built from, the way dappermint/winecx-gptk built it (its configure flags,
# macOS 26.0 as the floor). .github/workflows/enginefix.yml runs it; it runs on a Mac as well:
#
#   scripts/build-enginefix.sh <winecx source> <work folder> [the runtime's lib/wine/x86_64-unix]
#
# Wine's own tools are built for the machine first and the real build uses them, so nothing but
# the two results is an x86_64 program (on macOS 27 every Rosetta start costs an analysis that can
# pile up). Given the runtime's x86_64-unix folder, the results are held against the originals
# there: the same exported symbols, libraries and rpaths, else it stops. The results land in
# <work folder>/out.
set -euo pipefail

SRC="$(cd "${1:?usage: $0 <winecx source> <work folder> [runtime x86_64-unix]}" && pwd)"
WORK="${2:?usage: $0 <winecx source> <work folder> [runtime x86_64-unix]}"
ORIGINALS="${3:-}"
PATCHES="$(cd "$(dirname "$0")/../engine/patches" && pwd)"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
export MACOSX_DEPLOYMENT_TARGET=26.0
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
JOBS="$(sysctl -n hw.logicalcpu)"
for tool in bison flex; do
  if prefix="$(brew --prefix "$tool" 2>/dev/null)" && [ -d "$prefix/bin" ]; then export PATH="$prefix/bin:$PATH"; fi
done

# The patches, once: a tree they're already in is taken as it is.
for patch in "$PATCHES"/winecx-ntdll-*.patch "$PATCHES"/winecx-winecoreaudio-*.patch; do
  if git -C "$SRC" apply --check "$patch" 2>/dev/null; then
    echo "Applying $(basename "$patch")"
    git -C "$SRC" apply "$patch"
  elif git -C "$SRC" apply --check --reverse "$patch" 2>/dev/null; then
    echo "Already in: $(basename "$patch")"
  else
    echo "$(basename "$patch") doesn't fit this tree" >&2
    exit 1
  fi
done
grep -q 'if (!do_msync()) close( data->alert_fd );' "$SRC/dlls/ntdll/unix/thread.c"
grep -q 'kAudioUnitSubType_SpatialMixer' "$SRC/dlls/winecoreaudio.drv/coreaudio.c"

COMMON=(--enable-archs=i386,x86_64 --disable-tests
        --without-x --without-wayland --without-oss --without-alsa --without-pulse --without-sane
        --without-usb --without-v4l2 --without-pcap --without-capi --without-opencl --without-cups)

# Wine's tools, for this machine.
if [ ! -x "$WORK/tools/tools/winebuild/winebuild" ]; then
  mkdir -p "$WORK/tools"
  (cd "$WORK/tools" && CC=/usr/bin/clang "$SRC/configure" "${COMMON[@]}" \
     --without-freetype --without-gstreamer --without-ffmpeg --without-gnutls --without-sdl --without-krb5 \
     > configure.log 2>&1) || { tail -40 "$WORK/tools/configure.log"; exit 1; }
  make -C "$WORK/tools" -j"$JOBS" __tooldeps__ > "$WORK/tools/make.log" 2>&1 || { tail -40 "$WORK/tools/make.log"; exit 1; }
  # wrc finds its locale data next to itself (tools/tools.h get_nlsdir).
  rm -rf "$WORK/tools/nls" && mkdir "$WORK/tools/nls" && ln -s "$SRC/nls/locale.nls" "$WORK/tools/nls/locale.nls"
fi

# The two modules, x86_64, as dappermint configures the runtime. Libraries only the rest of the
# engine needs (fonts, TLS, media, SDL) are left out: neither module links them.
mkdir -p "$WORK/build"
if [ ! -f "$WORK/build/Makefile" ]; then
  (cd "$WORK/build" && \
     CC="/usr/bin/clang -arch x86_64" CXX="/usr/bin/clang++ -arch x86_64" \
     CFLAGS="-O2 -Wno-error=implicit-function-declaration -Werror=unguarded-availability-new" CROSSCFLAGS="-O2" \
     ac_cv_func_pipe2=no \
     "$SRC/configure" --host=x86_64-apple-darwin24 --with-wine-tools="$WORK/tools" "${COMMON[@]}" \
       --without-freetype --without-gstreamer --without-ffmpeg --without-gnutls --without-sdl --without-krb5 \
       --without-gssapi --without-netapi --prefix=/opt/winecx \
     > configure.log 2>&1) || { tail -40 "$WORK/build/configure.log"; exit 1; }
fi
make -C "$WORK/build" -j"$JOBS" dlls/ntdll/ntdll.so dlls/winecoreaudio.drv/winecoreaudio.so 2>&1 | tee "$WORK/build/make.log" | tail -5
# An API above the floor links weakly and is a null pointer there (dappermint's pipe2 lesson).
if grep -q "has been marked as being introduced in macOS" "$WORK/build/make.log"; then
  grep "has been marked as being introduced in macOS" "$WORK/build/make.log" >&2
  exit 1
fi

OUT="$WORK/out"
rm -rf "$OUT" && mkdir -p "$OUT"
cp "$WORK/build/dlls/ntdll/ntdll.so" "$WORK/build/dlls/winecoreaudio.drv/winecoreaudio.so" "$OUT/"
rpaths() { otool -l "$1" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }'; }
for so in "$OUT"/*.so; do
  name="$(basename "$so")"
  [ "$(lipo -archs "$so")" = "x86_64" ] || { echo "$name isn't x86_64 only" >&2; exit 1; }
  minos="$(otool -l "$so" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "minos" { print $2; exit }')"
  [ "$minos" = "$MACOSX_DEPLOYMENT_TARGET" ] || { echo "$name: minos $minos, not $MACOSX_DEPLOYMENT_TARGET" >&2; exit 1; }
  if [ -n "$ORIGINALS" ]; then
    original="$ORIGINALS/$name"
    # The engine looks for its libraries through the original's rpaths (Wine's build sets only
    # @loader_path/; dappermint adds the engine's lib folder, two up).
    for path in $(rpaths "$so"); do
      rpaths "$original" | grep -qx "$path" || install_name_tool -delete_rpath "$path" "$so"
    done
    for path in $(rpaths "$original"); do
      rpaths "$so" | grep -qx "$path" || install_name_tool -add_rpath "$path" "$so"
    done
    diff <(rpaths "$original" | sort) <(rpaths "$so" | sort) || { echo "$name: other rpaths than the original" >&2; exit 1; }
    diff <(otool -L "$original" | tail -n +2 | awk '{ print $1 }' | sort) <(otool -L "$so" | tail -n +2 | awk '{ print $1 }' | sort) \
      || { echo "$name: other libraries than the original" >&2; exit 1; }
    # D3DMetal patches ntdll's unixcall internals when it loads: what it looks up must all be there.
    diff <(nm -gU "$original" | awk '{ print $NF }' | sort) <(nm -gU "$so" | awk '{ print $NF }' | sort) \
      || { echo "$name: other exported symbols than the original" >&2; exit 1; }
  fi
  codesign -fs - "$so"
done
strings "$OUT/winecoreaudio.so" | grep -q "Couldn't create a SpatialMixer" || { echo "winecoreaudio.so without the mixer" >&2; exit 1; }
ls -l "$OUT"
