#!/bin/bash
# Probe for docs/ENTWURF-STEAM-PAD.md, way B. Run by the coordinator, not by a worker; see README.md beside it.
#   probe.sh <demo app ID>
# Opens Steam's install dialog for a demo (steam://install/<ID>), sends it Tab twice and Esc, and checks that the
# dialog is closed again. Sends no Enter, no Space, no click (steam-keys.c knows only Esc and Tab). Prints window
# handles, classes and sizes, never titles, accounts or process arguments.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ID="${1:-}"
[[ "$ID" =~ ^[0-9]+$ ]] || { echo "PROBE ABGEBROCHEN: App-ID einer Demo als Argument fehlt"; exit 64; }
LOG="${PROBE_LOG:-$PWD/steam-pad-probe-$(date +%Y%m%d-%H%M%S).log}"
say() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

# Guards: not from 16:30 on, a Nightforge Steam session running, no game running.
now=$((10#$(date +%H%M)))
[ "$now" -lt 1630 ] || { say "PROBE ABGEBROCHEN: ab 16:30 keine Proben"; exit 1; }
command -v x86_64-w64-mingw32-gcc >/dev/null || { say "PROBE ABGEBROCHEN: mingw-w64 fehlt"; exit 1; }
SUPPORT="$HOME/Library/Application Support/Nightforge"
SERVER="$(ps -axo comm= | grep -F "$SUPPORT/Components/" | grep -E '/bin/wineserver$' | head -n 1)"
[ -n "$SERVER" ] || { say "PROBE ABGEBROCHEN: keine Wine-Sitzung von Nightforge (Steam erst starten)"; exit 1; }
WINE="$(dirname "$SERVER")/wine"
[ -x "$WINE" ] || { say "PROBE ABGEBROCHEN: kein wine neben dem wineserver"; exit 1; }
if ps -axo command= | grep -iF -e '\steamapps\common\' -e '\Epic Games\' -e '\GOG Games\' | grep -viF -e grep -e probe.sh >/dev/null; then
  say "PROBE ABGEBROCHEN: es läuft etwas aus einem Spielordner"; exit 1
fi
ps -axo command= | grep -iF '\steam\steam.exe' | grep -v grep >/dev/null || { say "PROBE ABGEBROCHEN: Windows-Steam läuft nicht"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -municode -static -o "$WORK/steam-keys.exe" "$HERE/steam-keys.c" \
  || { say "PROBE ABGEBROCHEN: steam-keys.exe ließ sich nicht bauen"; exit 1; }
export WINEPREFIX="$SUPPORT/Prefix" WINEDEBUG=-all

# A Wine program has to agree with the session's wineserver about msync; which way it runs isn't readable from
# outside, so the first `list` tries both (each within 20 s).
run() {  # run <seconds> args…: the helper's exit code, 124 when it didn't end in time
  local limit="$1"; shift
  "$WINE" "$WORK/steam-keys.exe" "$@" > "$WORK/out" 2>/dev/null &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null; do
    [ "$i" -ge $((limit * 10)) ] && { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; }
    sleep 0.1; i=$((i + 1))
  done
  wait "$pid"
}
for m in 1 0; do
  export WINEMSYNC="$m"
  run 20 list && break
  [ "$m" = 0 ] && { say "PROBE ABGEBROCHEN: das Hilfsprogramm kommt nicht in die Sitzung"; exit 1; }
done
say "Sitzung erreicht (WINEMSYNC=$WINEMSYNC)"
sed 's/^/  vorher: /' "$WORK/out" | tee -a "$LOG"
cut -d' ' -f1 "$WORK/out" > "$WORK/before"

say "Öffne Steams Installationsfenster für App $ID (steam://install, nichts wird bestätigt)"
"$WINE" 'C:\Program Files (x86)\Steam\steam.exe' "steam://install/$ID" >/dev/null 2>&1 &

# The new window of Steam's: not there before, at least 300 x 200.
DIALOG=""
for _ in $(seq 1 30); do
  sleep 1
  run 20 list || continue
  while read -r line; do
    hwnd="${line%% *}"; size="$(sed -n 's/.* size=\([0-9]*\)x\([0-9]*\) .*/\1 \2/p' <<<"$line")"
    grep -qxF "$hwnd" "$WORK/before" && continue
    set -- $size
    [ "${1:-0}" -ge 300 ] && [ "${2:-0}" -ge 200 ] && { DIALOG="${hwnd#hwnd=}"; echo "  neu: $line" | tee -a "$LOG"; break; }
  done < "$WORK/out"
  [ -n "$DIALOG" ] && break
done
[ -n "$DIALOG" ] || { say "ERGEBNIS: kein neues Steam-Fenster in 30 s (Demo schon installiert oder in der Bibliothek?)"; exit 2; }

say "Jetzt hinsehen: Wandert der Fokusrahmen in Steams Fenster bei jedem Tab?"
for n in 1 2; do
  sleep 2
  run 10 key tab "$DIALOG"; say "Tab $n per SendInput: exit $?"
done
sleep 2
run 10 key backtab "$DIALOG"; say "Umschalt-Tab per SendInput: exit $?"
sleep 2

closed=""
run 10 key esc "$DIALOG"; say "Esc per SendInput: exit $?"
if run 10 gone "$DIALOG" 3000; then closed="SendInput"; else
  run 10 post esc "$DIALOG"; say "Esc per PostMessage: exit $?"
  run 10 gone "$DIALOG" 3000 && closed="PostMessage"
fi
if [ -n "$closed" ]; then
  say "ERGEBNIS: Esc schließt Steams Dialog ($closed). Fenster ist zu."
  exit 0
fi
say "ERGEBNIS: Dialog noch offen. Bitte mit der Maus „Abbrechen“ drücken, nicht „Weiter“ oder „Installieren“."
exit 1
