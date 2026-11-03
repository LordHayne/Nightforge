#!/bin/bash
# Checks wrapper/unity-play.c under Wine against a stand-in of Unity's configuration window: it presses
# "Play!" in the game's own window (64- and 32-bit, title with or without spaces, a window that comes up
# late) and leaves alone another program's window and one with another title. In a prefix of its own,
# never Nightforge's, with Wine's null display driver (nothing shows on screen):
#   tests/UnityDialogTest/dialog.sh [prefix]
# Needs mingw-w64 (brew install mingw-w64) and a Wine engine Nightforge set up (or WINE=…/bin/wine).
set -euo pipefail
cd "$(dirname "$0")/../.."

WINE="${WINE:-$(ls -d "$HOME/Library/Application Support/Nightforge/Components/winecx/"*/Libraries/Wine/bin/wine 2>/dev/null | sort -V | tail -1)}"
if [ -z "$WINE" ] || [ ! -x "$WINE" ] || ! command -v x86_64-w64-mingw32-gcc >/dev/null || ! command -v i686-w64-mingw32-gcc >/dev/null; then
  echo "✗ needs mingw-w64 and a Wine engine (WINE=…/bin/wine)" >&2
  exit 1
fi
WINESERVER="$(dirname "$WINE")/wineserver"

DIR="$(mktemp -d)"
export WINEPREFIX="${1:-$DIR/prefix}"
mkdir -p "$WINEPREFIX"
if [ "$(cd "$WINEPREFIX" && pwd -P)" = "$(cd "$HOME/Library/Application Support/Nightforge/Prefix" 2>/dev/null && pwd -P)" ]; then
  echo "✗ not in Nightforge's own prefix" >&2
  exit 1
fi
export WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
finish() {
  "$WINESERVER" -k 2>/dev/null || true
  "$WINESERVER" -w 2>/dev/null || true
  rm -rf "$DIR"
}
trap finish EXIT

x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Werror -municode -mwindows -static -o "$DIR/unity-play.exe" wrapper/unity-play.c
for arch in x86_64 i686; do
  "$arch-w64-mingw32-windres" tests/UnityDialogTest/stand-in.rc -o "$DIR/stand-in-$arch.o"
  "$arch-w64-mingw32-gcc" -O2 -Wall -Wextra -Werror -municode -mwindows -static \
    -o "$DIR/stand-in-$arch.exe" tests/UnityDialogTest/stand-in.c "$DIR/stand-in-$arch.o"
done
cp "$DIR/stand-in-x86_64.exe" "$DIR/FakeGame.exe"
cp "$DIR/stand-in-i686.exe" "$DIR/FakeGame32.exe"
cp "$DIR/stand-in-x86_64.exe" "$DIR/OtherGame.exe"

"$WINE" wineboot -i >/dev/null 2>&1
"$WINE" reg add 'HKCU\Software\Wine\Drivers' /v Graphics /d null /f >/dev/null 2>&1
"$WINESERVER" -w

windows() { printf 'Z:%s' "${1//\//\\}"; }
failures=0
check() {  # check <what> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1: expected $2, got $3"; failures=$((failures + 1)); fi
}
# play <case> <program> <title> <stand-in seconds> <delay> <clicker seconds> <clicker arguments…>
# Starts the stand-in (after <delay> seconds) and the clicker; leaves the clicker's exit code in
# $DIR/<case>.rc, its log line in $DIR/<case>.log and what ended the stand-in in $DIR/<case>.result.
play() {
  local name="$1" program="$2" title="$3" lasts="$4" delay="$5"
  shift 5
  (sleep "$delay"; "$WINE" "$DIR/$program" "$title" "$(windows "$DIR/$name.result")" "$lasts" >/dev/null 2>&1) &
  local stand_in=$!
  set +e
  "$WINE" "$DIR/unity-play.exe" "$@" >/dev/null 2>"$DIR/$name.log"
  echo $? > "$DIR/$name.rc"
  set -e
  wait "$stand_in" || true
}

echo "Unity's window"
play spaces FakeGame.exe "Fake Game Configuration" 30 0 20 FakeGame.exe FakeGame
check "pressed in the game's window, its title with spaces" "0 play" "$(cat "$DIR/spaces.rc") $(cat "$DIR/spaces.result")"
grep -q 'Unity.s window "Fake Game Configuration": pressed Play!$' "$DIR/spaces.log" \
  && check "the game log has it" yes yes || check "the game log has it" yes "$(cat "$DIR/spaces.log")"

play bits32 FakeGame32.exe "FakeGame Configuration" 30 0 20 FakeGame32.exe FakeGame
check "a 32-bit game's window" "0 play" "$(cat "$DIR/bits32.rc") $(cat "$DIR/bits32.result")"

play late FakeGame.exe "FakeGame Configuration" 30 4 20 FakeGame.exe FakeGame
check "a window that comes up a few seconds later" "0 play" "$(cat "$DIR/late.rc") $(cat "$DIR/late.result")"

play several FakeGame32.exe "FakeGame Configuration" 30 0 20 FakeGame.exe FakeGame FakeGame32.exe FakeGame
check "any of the game's programs" "0 play" "$(cat "$DIR/several.rc") $(cat "$DIR/several.result")"

play other OtherGame.exe "FakeGame Configuration" 8 0 4 FakeGame.exe FakeGame
check "another program's window stays" "1 timeout" "$(cat "$DIR/other.rc") $(cat "$DIR/other.result")"
grep -q "didn't come up" "$DIR/other.log" && check "the log says so" yes yes || check "the log says so" yes "$(cat "$DIR/other.log")"

play title FakeGame.exe "FakeGame Settings" 8 0 4 FakeGame.exe FakeGame
check "a window with another title stays" "1 timeout" "$(cat "$DIR/title.rc") $(cat "$DIR/title.result")"

play product FakeGame.exe "Another Game Configuration" 8 0 4 FakeGame.exe FakeGame
check "the game's program, another product's title, stays" "1 timeout" "$(cat "$DIR/product.rc") $(cat "$DIR/product.result")"

set +e
"$WINE" "$DIR/unity-play.exe" >/dev/null 2>&1; none=$?
"$WINE" "$DIR/unity-play.exe" 0 FakeGame.exe FakeGame >/dev/null 2>&1; zero=$?
"$WINE" "$DIR/unity-play.exe" 20 FakeGame.exe >/dev/null 2>&1; half=$?
set -e
check "nothing to look for, no time or half a pair: usage" "64 64 64" "$none $zero $half"

if [ "$failures" -eq 0 ]; then echo "✓ unity-play"; else echo "✗ unity-play: $failures failed"; exit 1; fi
