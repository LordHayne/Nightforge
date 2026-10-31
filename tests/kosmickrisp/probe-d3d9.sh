#!/bin/bash
# Proves that DXVK's Direct3D 9 gets a device and draws on KosmicKrisp under winecx, in a prefix of
# its own (never Nightforge's):
#
#   tests/kosmickrisp/probe-d3d9.sh <KosmicKrisp folder> [work folder]
#
# The KosmicKrisp folder is what scripts/build-kosmickrisp.sh stages (libvulkan.1.dylib,
# libvulkan_kosmickrisp.dylib, kosmickrisp_icd.json). Runs d3d9probe.c, 32- and 64-bit, four ways:
# Wine's own Direct3D (baseline), DXVK on MoltenVK (today's way, fails for want of geometryShader),
# DXVK on KosmicKrisp with the environment Nightforge sets per start, and the same through the
# engine's "Nightforge Game" bundle as games run, where the Khronos loader also finds Nightforge's
# Vulkan layer (it logs the frame rate after 10 s, so that run lasts 12 s). WINE_ROOT picks the
# engine (default: the newest installed winecx, only read), DXVK the DXVK folder with x32/ and x64/
# (default: DXVK 3.1.1, fetched and checked). Exit code 0 when both KosmicKrisp runs draw right.
set -uo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
KK="$(cd "${1:?usage: $0 <KosmicKrisp folder> [work folder]}" && pwd -P)"
WORK="${2:-$here/../../build/kosmickrisp/probe}"
mkdir -p "$WORK" && WORK="$(cd "$WORK" && pwd -P)"
for file in libvulkan.1.dylib libvulkan_kosmickrisp.dylib kosmickrisp_icd.json; do
  [ -f "$KK/$file" ] || { echo "no $file in $KK" >&2; exit 1; }
done

if [ -z "${WINE_ROOT:-}" ]; then
  WINE_ROOT="$(ls -d "$HOME/Library/Application Support/Nightforge/Components/winecx/"*/Libraries/Wine 2>/dev/null | tail -1)"
fi
[ -x "$WINE_ROOT/bin/wine" ] || { echo "no winecx engine (set WINE_ROOT)" >&2; exit 1; }

if [ -z "${DXVK:-}" ]; then
  DXVK="$WORK/dxvk-3.1.1"
  if [ ! -f "$DXVK/x32/d3d9.dll" ]; then
    curl -sSL -o "$WORK/dxvk-3.1.1.tar.gz" https://github.com/doitsujin/dxvk/releases/download/v3.1.1/dxvk-3.1.1.tar.gz
    echo "40565b4a724aadc4433fa4e010b4b23916d9b1f1baeee64e17186db94f54e608  $WORK/dxvk-3.1.1.tar.gz" | shasum -a 256 -c - >/dev/null \
      || { echo "DXVK 3.1.1 download doesn't match its checksum" >&2; exit 1; }
    tar -xzf "$WORK/dxvk-3.1.1.tar.gz" -C "$WORK"
  fi
fi

for bits in 32 64; do
  compiler=$([ $bits = 32 ] && echo i686-w64-mingw32-gcc || echo x86_64-w64-mingw32-gcc)
  "$compiler" -O2 -o "$WORK/d3d9probe$bits.exe" "$here/d3d9probe.c" -ld3d9 -lgdi32 || exit 1
  # DXVK's d3d9.dll next to the program, taken first (d3d9=n,b), like placeDXVK does for a game.
  mkdir -p "$WORK/dxvk$bits"
  cp "$WORK/d3d9probe$bits.exe" "$WORK/dxvk$bits/"
  cp "$DXVK/x$bits/d3d9.dll" "$WORK/dxvk$bits/"
done

export WINEPREFIX="$WORK/prefix"
if [ ! -f "$WINEPREFIX/system.reg" ]; then
  WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" "$WINE_ROOT/bin/wine" wineboot -i >/dev/null 2>&1
fi

# run <name> <bits> <wine> <program> <seconds> [VAR=value …]
FAILED_KK=0
run() {
  local name="$1" bits="$2" wine="$3" program="$4" seconds="$5"; shift 5
  local log="$WORK/$name-$bits.log"
  # DXVK-macOS keeps a pipeline cache in the working folder: the work folder, not the repository.
  (cd "$WORK" && env -u VK_ICD_FILENAMES -u VK_ADD_DRIVER_FILES -u VK_LOADER_DRIVERS_SELECT -u VK_LOADER_DRIVERS_DISABLE \
    WINEDEBUG=-all DXVK_LOG_LEVEL=info DXVK_LOG_PATH=none DXVK_STATE_CACHE_PATH="$WORK" "$@" "$wine" "$program" "$seconds" > "$log" 2>&1)
  local rc=$?
  "$WINE_ROOT/bin/wineserver" -w
  local verdict
  verdict="$(grep -a -o 'D3D9PROBE [A-Z].*' "$log" | tail -1)"
  printf '%-22s %s-bit  rc=%s  %s\n' "$name" "$bits" "$rc" "${verdict:-no verdict}"
  grep -a -E '^(d3d9.dll|adapter|CreateDevice|pixels|present):|DXVK: v|Found device|Skipping|required feature|Failed to create|vkCreateDevice|No adapters|[0-9.]+ fps|FPS' "$log" \
    | sed 's/^/    /' | head -12
  return $rc
}

echo "engine: $WINE_ROOT"
echo "KosmicKrisp: $KK"
echo "DXVK: $DXVK"
WINE="$WINE_ROOT/bin/wine"
BUNDLE="$WINE_ROOT/Nightforge Game.app/Contents/MacOS/wine"
# What Nightforge sets for a start on DXVK with KosmicKrisp (Engine.kosmicKrispEnvironment):
# CrossOver's win32u loads CX_LIBVULKAN instead of MoltenVK while the backend is "wined3d".
KK_ENV=(CX_ACTIVE_GRAPHICS_BACKEND=wined3d CX_LIBVULKAN="$KK/libvulkan.1.dylib" VK_DRIVER_FILES="$KK/kosmickrisp_icd.json")
for bits in 32 64; do
  run wined3d "$bits" "$WINE" "$WORK/d3d9probe$bits.exe" 2 WINEDLLOVERRIDES="d3d9=b"
  run dxvk-moltenvk "$bits" "$WINE" "$WORK/dxvk$bits/d3d9probe$bits.exe" 2 WINEDLLOVERRIDES="d3d9=n,b"
  run dxvk-kosmickrisp "$bits" "$WINE" "$WORK/dxvk$bits/d3d9probe$bits.exe" 2 WINEDLLOVERRIDES="d3d9=n,b" "${KK_ENV[@]}" \
    || FAILED_KK=1
  if [ -x "$BUNDLE" ]; then
    run dxvk-kosmickrisp-app "$bits" "$BUNDLE" "$WORK/dxvk$bits/d3d9probe$bits.exe" 12 WINEDLLOVERRIDES="d3d9=n,b" "${KK_ENV[@]}" \
      || FAILED_KK=1
  fi
done
exit $FAILED_KK
