#!/bin/bash
# What a Windows program under Wine reaches of the Mac, three ways (docs/ENTWURF-LAUFWERKE.md), in a
# prefix of its own – never Nightforge's:
#
#   tests/laufwerke/probe-zugriff.sh [work folder]
#
# 1. as today (z: → /), 2. with a macOS sandbox that denies one folder (sandbox-exec), also for a
# child process and with a wineserver started outside the sandbox, 3. with z: on a folder that
# mirrors only what's allowed. A "secret" and an "open" file in the work folder are read through Z:
# and through \\?\unix\. WINE_ROOT picks the engine (default: the newest installed winecx, only read).
# Exit code 0 when the sandbox keeps the secret out both ways and the open file stays readable.
set -uo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
WORK="${1:-$here/../../build/laufwerke}"
mkdir -p "$WORK" && WORK="$(cd "$WORK" && pwd -P)"
if [ -z "${WINE_ROOT:-}" ]; then
  WINE_ROOT="$(ls -d "$HOME/Library/Application Support/Nightforge/Components/winecx/"*/Libraries/Wine 2>/dev/null | tail -1)"
fi
WINE="$WINE_ROOT/bin/wine"
SERVER="$WINE_ROOT/bin/wineserver"
[ -x "$WINE" ] || { echo "no winecx engine (set WINE_ROOT)" >&2; exit 1; }

x86_64-w64-mingw32-gcc -O2 -o "$WORK/readprobe.exe" "$here/readprobe.c" || exit 1
mkdir -p "$WORK/secret" "$WORK/open"
echo geheim > "$WORK/secret/token.json"
echo offen > "$WORK/open/data.txt"

export WINEPREFIX="$WORK/prefix" WINEDEBUG=-all
[ -f "$WINEPREFIX/system.reg" ] || WINEDLLOVERRIDES="mscoree,mshtml=" "$WINE" wineboot -i >/dev/null 2>&1

windows() { printf '%s' "$1" | sed 's|/|\\|g'; }
SECRET_Z="Z:$(windows "$WORK/secret/token.json")"
SECRET_UNIX="\\\\?\\unix$(windows "$WORK/secret/token.json")"
OPEN_Z="Z:$(windows "$WORK/open/data.txt")"
PROFILE="(version 1)(allow default)(deny file-read* file-write* (subpath \"$WORK/secret\"))"

# Into a file, not a pipe: Wine's console helpers can hold a pipe open after the program has ended.
probe() {  # probe <title> <command…>
  local title="$1"; shift
  echo "== $title"
  (cd "$WORK" && "$@" "$SECRET_Z" "$SECRET_UNIX" "$OPEN_Z" > "$WORK/last.log" 2>&1) &
  local pid=$! waited=0
  # At most a minute; then this prefix's Wine session ends, whatever still hangs in it.
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
  "$SERVER" -k 2>/dev/null
  wait "$pid" 2>/dev/null
  grep -a -E "^(drives|cwd|READ|DENIED|OPEN-ONLY|Z:)" "$WORK/last.log" | sed 's/^/   /'
}

probe "today: z: -> /" "$WINE" "$WORK/readprobe.exe"
probe "sandbox denies the secret's folder" /usr/bin/sandbox-exec -p "$PROFILE" "$WINE" "$WORK/readprobe.exe"
SANDBOXED="$(cat "$WORK/last.log")"

# A game is a child of Steam's process; Nightforge may have started the wineserver without the sandbox.
"$SERVER" -p 5
probe "sandbox, child of cmd.exe, wineserver outside" /usr/bin/sandbox-exec -p "$PROFILE" "$WINE" cmd.exe /c "Z:$(windows "$WORK/readprobe.exe")"

# z: on a folder that only mirrors the open folder, at its real place.
VIEW="$WINEPREFIX/drive_z"
rm -rf "$VIEW" && mkdir -p "$VIEW$(dirname "$WORK/open")" && ln -s "$WORK/open" "$VIEW$WORK/open"
mv "$WINEPREFIX/dosdevices/z:" "$WINEPREFIX/dosdevices/z.root"
ln -s ../drive_z "$WINEPREFIX/dosdevices/z:"
probe "z: on a mirror of the open folder" "$WINE" "$WORK/readprobe.exe"
rm "$WINEPREFIX/dosdevices/z:" && mv "$WINEPREFIX/dosdevices/z.root" "$WINEPREFIX/dosdevices/z:"

printf '%s\n' "$SANDBOXED" | grep -q "^DENIED .*secret" || exit 1
[ "$(printf '%s\n' "$SANDBOXED" | grep -c "^DENIED .*secret")" = 2 ] || exit 1
printf '%s\n' "$SANDBOXED" | grep -q "^READ .*open" || exit 1
exit 0
