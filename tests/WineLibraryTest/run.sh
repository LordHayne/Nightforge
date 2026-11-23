#!/bin/bash
# hide-steam-dock.dylib in real Wine: Wine still finds what its unix side loads with dlopen. On 23.11.2026 a build
# that interposed dlopen (bdbd92a) left Steam unable to start – dyld resolves @rpath and @loader_path from the
# caller, and the caller had become the library: "Wine cannot find the FreeType font library", "Failed to dlopen
# D3DMetal". Built as build.sh builds it, into a Windows program in a prefix of its own made for the test.
# Needs the installed winecx engine, Rosetta and mingw-w64; without them it says so and passes.
# tests/WineLibraryTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk

# Nothing in the library may stand in for dlopen or dlsym: Wine's own loading goes by who calls them.
failed=0
if grep -nE '__interpose|DYLD_INTERPOSE' wrapper/*.m wrapper/*.c | grep -iE 'dlopen|dlsym|dladdr'; then
  echo "✗ the library interposes dlopen/dlsym: Wine's unix side would no longer find its own libraries"
  failed=1
fi

WINE_DIR="$(ls -d "$HOME/Library/Application Support/Nightforge/Components/winecx"/*/Libraries/Wine/bin 2>/dev/null | head -1 || true)"
MINGW="$(command -v x86_64-w64-mingw32-gcc || true)"
if [ -z "$WINE_DIR" ] || [ -z "$MINGW" ] || ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "– real Wine with the library: skipped (needs the installed winecx engine, mingw-w64 and Rosetta)"
  exit $failed
fi

WORK="$(mktemp -d)"
PREFIX="$WORK/prefix"
mkdir -p "$PREFIX"
# Only this test's own Wine session ever ends here: WINEPREFIX names the test's prefix, inside $WORK.
end_session() {
  case "$PREFIX" in "$WORK"/*) [ -d "$PREFIX" ] && WINEPREFIX="$PREFIX" "$WINE_DIR/wineserver" -k >/dev/null 2>&1 || true ;; esac
}
trap 'end_session; rm -rf "$WORK"' EXIT

# The library from build.sh's own line, with its output in $WORK.
line="$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' build.sh | grep '^clang .*/hide-steam-dock.dylib')"
OUT="$WORK/out"
mkdir -p "$OUT/Contents/Resources"
eval "$line"
LIBRARY="$OUT/Contents/Resources/hide-steam-dock.dylib"
"$MINGW" -O2 -Wall -o "$WORK/font-probe.exe" tests/WineLibraryTest/font-probe.c -lgdi32

export WINEPREFIX="$PREFIX" WINEMSYNC=0 WINEDEBUG=-all,err+font WINEDLLOVERRIDES="mscoree,mshtml="
unset DYLD_INSERT_LIBRARIES
"$WINE_DIR/wine" wineboot -i >/dev/null 2>&1 || true
"$WINE_DIR/wineserver" -w
answer="$(DYLD_INSERT_LIBRARIES="$LIBRARY" "$WINE_DIR/wine" "$WORK/font-probe.exe" 2>"$WORK/errors")" || true
"$WINE_DIR/wineserver" -w
if grep -q "FreeType" "$WORK/errors" || ! echo "$answer" | grep -qE '^families [1-9][0-9]* height [1-9]'; then
  echo "✗ with the library, Wine doesn't find its fonts: ${answer:-no answer}"
  grep -m3 -E 'FreeType|Assertion|dlopen' "$WORK/errors" | sed 's/^/  /' || true
  failed=1
else
  echo "✓ real Wine with the library: its fonts are there ($answer), nothing stands in for dlopen"
fi
exit $failed
