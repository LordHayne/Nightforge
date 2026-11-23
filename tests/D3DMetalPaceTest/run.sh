#!/bin/bash
# Nightforge's frame limit on D3DMetal (wrapper/d3dmetal-pace.m, part of hide-steam-dock.dylib): the rules on made-up
# values, then the library built as build.sh builds it, in an x86_64 program like a Wine process on D3DMetal.
# tests/D3DMetalPaceTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

clang -O2 -Wall -Wextra -Werror -I wrapper -o "$WORK/rules" tests/D3DMetalPaceTest/rules.c wrapper/d3dmetal-pace-rules.c
"$WORK/rules"

if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "– the library in a process: skipped, no Rosetta"
  exit 0
fi
line="$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' build.sh | grep '^clang .*/hide-steam-dock.dylib')"
for source in wrapper/d3dmetal-pace.m wrapper/d3dmetal-pace-rules.c; do
  case "$line" in *" $source"*) ;; *) echo "✗ build.sh doesn't build $source into hide-steam-dock.dylib"; exit 1 ;; esac
done
# The library with build.sh's own line, only the output put here.
eval "$(echo "$line" | sed -e "s|-o \"\$OUT/Contents/Resources/hide-steam-dock.dylib\"|-o \"\$WORK/hide-steam-dock.dylib\"|")"
clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall -framework Metal -framework QuartzCore -o "$WORK/probe" tests/D3DMetalPaceTest/probe.m
# Something dyld loads under D3DMetal's name, and another under a name that isn't.
mkdir -p "$WORK/D3DMetal.framework/Versions/A" "$WORK/other"
echo 'int nightforge_test_image(void) { return 1; }' > "$WORK/image.c"
clang -arch x86_64 -dynamiclib -o "$WORK/D3DMetal.framework/Versions/A/D3DMetal" "$WORK/image.c"
clang -arch x86_64 -dynamiclib -o "$WORK/other/winemetal.so" "$WORK/image.c"
D3DMETAL="$WORK/D3DMetal.framework/Versions/A/D3DMetal"
GAME='C:\Program Files (x86)\Steam\steamapps\common\Test Game\bin\game.exe'
mkdir -p "$WORK/home/Library/Application Support/Nightforge"
PERMIT="$WORK/home/Library/Application Support/Nightforge/d3dmetal-pace"

failed=0
# run <what> <expected output> <program name> <image> [VAR=value …]: the probe as that program, with the library.
run() {
  local what="$1" expected="$2" program="$3" image="$4"
  shift 4
  local got
  # DYLD_INSERT_LIBRARIES only after bash: macOS drops it on the way into a system program like /bin/bash.
  got="$( (env -i HOME="$WORK/home" PATH="/usr/bin:/bin" LIBRARY="$WORK/hide-steam-dock.dylib" "$@" \
          /bin/bash -c 'export DYLD_INSERT_LIBRARIES="$LIBRARY"; exec -a "$0" "$1" "$2"' "$program" "$WORK/probe" "$image") 2> "$WORK/stderr")"
  if [ "$got" = "no-class" ]; then echo "– $what: Metal has no _MTLCommandBuffer here"; return; fi
  if [ "$got" != "$expected" ]; then
    echo "✗ $what: expected \"$expected\", got \"$got\""
    failed=1
  fi
  local lines
  lines="$(grep -c 'D3DMetal frame limit' "$WORK/stderr" || true)"
  case "$expected" in
    "redirected 3 sync 1") [ "$lines" = 1 ] || { echo "✗ $what: $lines log lines, not one"; failed=1; } ;;
    *) [ "$lines" = 0 ] || { echo "✗ $what: a log line though nothing was hooked"; failed=1; } ;;
  esac
}

printf '60\nC:\\Program Files (x86)\\Steam\\steamapps\\common\\Test Game\n' > "$PERMIT"
run "D3DMetal, limit, permit and the game's program" "redirected 3 sync 1" "$GAME" "$D3DMETAL" D3DM_MAX_FPS=60
run "no D3DMetal loaded (DXMT, DXVK, Steam)" "redirected 0 sync 0" "$GAME" "$WORK/other/winemetal.so" D3DM_MAX_FPS=60
run "nothing loaded" "redirected 0 sync 0" "$GAME" "-" D3DM_MAX_FPS=60
run "no D3DM_MAX_FPS (an anti-cheat game's environment)" "redirected 0 sync 0" "$GAME" "$D3DMETAL"
run "another game than the permit's (Steam's environment from the game before)" "redirected 0 sync 0" \
  'C:\Program Files (x86)\Steam\steamapps\common\Overwatch\Overwatch.exe' "$D3DMETAL" D3DM_MAX_FPS=60
run "a limit other than the permit's" "redirected 0 sync 0" "$GAME" "$D3DMETAL" D3DM_MAX_FPS=30
# Metal handing on to presentDrawable: from inside afterMinimumDuration: Metal's own, once – no loop, no crash (S1).
run "Metal calls presentDrawable: back from inside" "redirected 3 sync 1" "$GAME" "$D3DMETAL" D3DM_MAX_FPS=60 NIGHTFORGE_TEST_REENTER=1
rm -f "$PERMIT"
run "no permit (Nightforge took it away for a game with an anti-cheat)" "redirected 0 sync 0" "$GAME" "$D3DMETAL" D3DM_MAX_FPS=60

if [ $failed = 0 ]; then echo "✓ the library: hooks D3DMetal's presents only where limit, permit, program and D3DMetal agree"; fi
exit $failed
