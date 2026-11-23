#!/bin/bash
# Probe for docs/ENTWURF-STEAM-PAD.md, way B. Run by the coordinator, not by a worker; see README.md beside it.
#   probe.sh <demo app ID>        opens steam://install/<ID> itself (before 16:30)
#   probe.sh --warten [seconds]   sends nothing: waits (default 180 s) for a window of Steam's the player brings up
#                                 (the launch option of Drawful 2, Valheim's cloud question), then the keys
#   probe.sh --jetzt              sends nothing: takes the one visible window of Steam's at least 300 x 200 now
# Opens Steam's install dialog for a demo (steam://install/<ID>), sends it Tab twice and Esc, and checks that the
# dialog is closed again. Sends no Enter, no Space, no click (steam-keys.c knows only Esc and Tab). Prints window
# handles, classes and sizes, never titles, accounts or process arguments.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MODE=install; ID=""; WAIT=30
case "${1:-}" in
  --warten) MODE=wait; WAIT="${2:-180}"; [[ "$WAIT" =~ ^[0-9]+$ ]] || { echo "PROBE ABGEBROCHEN: Sekunden als Zahl"; exit 64; } ;;
  --jetzt) MODE=now ;;
  *) ID="${1:-}"; [[ "$ID" =~ ^[0-9]+$ ]] || { echo "PROBE ABGEBROCHEN: App-ID einer Demo, --warten oder --jetzt"; exit 64; } ;;
esac
LOG="${PROBE_LOG:-$PWD/steam-pad-probe-$(date +%Y%m%d-%H%M%S).log}"
say() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

# Guards: not from 16:30 on, a Nightforge Steam session running, no game running.
now=$((10#$(date +%H%M)))
# The modes that send nothing run with the player there, who brought the question up: also in the evening.
[ "$MODE" != install ] || [ "$now" -lt 1630 ] || { say "PROBE ABGEBROCHEN: ab 16:30 keine Proben, die selbst etwas öffnen"; exit 1; }
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

if [ "$(defaults read io.github.lordhayne.nightforge wineSandbox 2>/dev/null)" = 1 ]; then
  say "PROBE ABGEBROCHEN: Wines Sandbox ist an; ihr Profil baut nur Nightforge selbst (WineSandbox.profile)"; exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -municode -static -o "$WORK/steam-keys.exe" "$HERE/steam-keys.c" \
  || { say "PROBE ABGEBROCHEN: steam-keys.exe ließ sich nicht bauen"; exit 1; }
clang -O2 -Wall -o "$WORK/steam-env" "$HERE/steam-env.c" || { say "PROBE ABGEBROCHEN: steam-env ließ sich nicht bauen"; exit 1; }

# The environment the call to steam.exe gets: the running Steam's own (exact, read from its process as
# DockHider.startValue does), or else built as Engine.environment(wine:) and Engine.startSteam build it.
ENGINE="$(dirname "$(dirname "$SERVER")")"
STEAM_PID="$(ps -axo pid=,command= | grep -iF '\steam\steam.exe' | grep -v grep | awk '{print $1}' | sort -n | head -n 1)"
ENVV=()
if [ -n "$STEAM_PID" ] && "$WORK/steam-env" "$STEAM_PID" > "$WORK/env" 2>/dev/null; then
  while IFS= read -r -d '' entry; do ENVV+=("$entry"); done < "$WORK/env"
  ENV_FROM="vom laufenden Steam übernommen (${#ENVV[@]} Einträge)"
else
  LIB="$SUPPORT/hide-steam-dock.dylib"
  if [ -f "$LIB" ]; then FP="$(shasum -a 256 "$LIB" | cut -c1-32)"; else FP=none; fi
  ENVV=("HOME=$HOME" "USER=${USER:-}" "TMPDIR=${TMPDIR:-/tmp}" "PATH=$ENGINE/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        "WINEPREFIX=$SUPPORT/Prefix" "WINEDEBUG=-all" "NIGHTFORGE_LIBRARY=sha256:$FP"
        "WINEDLLOVERRIDES=bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d")
  [ -f "$LIB" ] && ENVV+=("DYLD_INSERT_LIBRARIES=$LIB")
  [ -f "$ENGINE/lib/external/libd3dshared.dylib" ] && ENVV+=("CX_APPLEGPTK_LIBD3DSHARED_PATH=$ENGINE/lib/external/libd3dshared.dylib")
  GAME_LOADER="$ENGINE/Nightforge Game.app/Contents/MacOS/wine"
  if [ "$(defaults read io.github.lordhayne.nightforge gameMode 2>/dev/null)" != 0 ] && [ -x "$GAME_LOADER" ]; then
    ENVV+=("WINELOADER=$GAME_LOADER")
  fi
  ENV_FROM="nachgebaut wie Engine.environment (die Umgebung des laufenden Steam war nicht lesbar)"
fi
# The program: the loader Steam was started with (WINELOADER), else the engine's wine.
LOADER="$WINE"
for entry in "${ENVV[@]}"; do case "$entry" in WINELOADER=*) [ -x "${entry#WINELOADER=}" ] && LOADER="${entry#WINELOADER=}" ;; esac; done
has_msync() { for entry in "${ENVV[@]}"; do case "$entry" in WINEMSYNC=*) return 0 ;; esac; done; return 1; }

run() {  # run <seconds> args…: the helper's exit code, 124 when it didn't end in time
  local limit="$1"; shift
  env -i "${ENVV[@]}" "$LOADER" "$WORK/steam-keys.exe" "$@" > "$WORK/out" 2>/dev/null &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null; do
    [ "$i" -ge $((limit * 10)) ] && { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; }
    sleep 0.1; i=$((i + 1))
  done
  wait "$pid"
}
# A Wine program has to agree with the session's wineserver about msync. Taken from Steam when its environment was
# read; otherwise both ways are tried (each within 20 s).
if has_msync; then
  run 20 list || { say "PROBE ABGEBROCHEN: das Hilfsprogramm kommt nicht in die Sitzung"; exit 1; }
else
  base=("${ENVV[@]}")
  for m in 1 0; do
    ENVV=("${base[@]}" "WINEMSYNC=$m")
    run 20 list && break
    [ "$m" = 0 ] && { say "PROBE ABGEBROCHEN: das Hilfsprogramm kommt nicht in die Sitzung"; exit 1; }
  done
fi
say "Sitzung erreicht; Umgebung $ENV_FROM; Programm: $( [ "$LOADER" = "$WINE" ] && echo "wine der Engine" || echo "Nightforge Game.app (Spielmodus)")"
sed 's/^/  vorher: /' "$WORK/out" | tee -a "$LOG"
cut -d' ' -f1 "$WORK/out" > "$WORK/before"
grep "visible=0" "$WORK/out" | cut -d' ' -f1 > "$WORK/hidden-before"

# Steam's console_log: whether the call reached the running Steam (ExecCommandLine), as -shutdown does.
CONSOLE="$SUPPORT/Prefix/drive_c/Program Files (x86)/Steam/logs/console_log.txt"
SEEN_BEFORE="$( [ -f "$CONSOLE" ] && wc -l < "$CONSOLE" | tr -d ' ' || echo 0)"
exec_lines() {  # new ExecCommandLine lines since the start, said without their arguments
  [ -f "$CONSOLE" ] || return
  tail -n +"$((SEEN_BEFORE + 1))" "$CONSOLE" | grep -E "ExecCommandLine|ExecuteSteamURL" | while IFS= read -r line; do
    when="$(sed -n 's/^\[\([^]]*\)\].*/\1/p' <<<"$line")"
    kind="$(grep -oE "ExecCommandLine|ExecuteSteamURL" <<<"$line" | head -n 1)"
    if grep -qF "steam://install/$ID" <<<"$line"; then what="mit steam://install/$ID"; else what="ohne diesen Link"; fi
    echo "  console_log ${when:-?}: $kind $what"
  done
}

if [ "$MODE" = install ]; then
# As Engine.startSteam: steam.exe, its start arguments (Engine.steamArguments, the client being installed), the command.
say "Öffne Steams Installationsfenster für App $ID (steam://install, nichts wird bestätigt)"
env -i "${ENVV[@]}" "$LOADER" 'C:\Program Files (x86)\Steam\steam.exe' -no-cef-sandbox -cef-single-process -noverifyfiles \
  -cef-disable-gpu -cef-disable-gpu-compositing -nofriendsui -nochatui "steam://install/$ID" >/dev/null 2>&1 &
CALL=$!
called=$(date +%s)
for _ in $(seq 1 200); do kill -0 "$CALL" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$CALL" 2>/dev/null; then
  say "Der zweite steam.exe läuft nach 20 s noch (gibt er den Befehl nicht ab?)"
else
  wait "$CALL"; rc=$?; say "Der zweite steam.exe endete nach $(( $(date +%s) - called )) s mit exit $rc"
fi
exec_lines | tee -a "$LOG"
fi

DIALOG=""
MAIN=""
if [ "$MODE" = now ]; then
  # The one visible window of Steam's of a dialog's size; with none or several, nothing is sent.
  grep "visible=1" "$WORK/out" | while read -r line; do
    size="$(sed -n 's/.* size=\([0-9]*\)x\([0-9]*\) .*/\1 \2/p' <<<"$line")"; set -- $size
    [ "${1:-0}" -ge 300 ] && [ "${2:-0}" -ge 200 ] && echo "$line"
  done > "$WORK/candidates"
  count="$(wc -l < "$WORK/candidates" | tr -d ' ')"
  if [ "$count" != 1 ]; then
    sed 's/^/  sichtbar: /' "$WORK/candidates" | tee -a "$LOG"
    say "ERGEBNIS: $count sichtbare Steam-Fenster ab 300×200, nichts geschickt (genau eines nötig; sonst --warten nehmen)"; exit 2
  fi
  line="$(cat "$WORK/candidates")"; DIALOG="$(cut -d' ' -f1 <<<"$line")"; DIALOG="${DIALOG#hwnd=}"; MAIN=maybe
  echo "  gewählt: $line" | tee -a "$LOG"
fi
[ "$MODE" = wait ] && say "Warte bis zu $WAIT s auf ein Fenster von Steam: jetzt die Frage auslösen (Spielen drücken)"

# The new window of Steam's: not there before, at least 300 x 200 – or one that was there hidden and shows now.
for _ in $( [ -z "$DIALOG" ] && seq 1 "$WAIT" ); do
  sleep 1
  run 20 list || continue
  while read -r line; do
    hwnd="${line%% *}"; size="$(sed -n 's/.* size=\([0-9]*\)x\([0-9]*\) .*/\1 \2/p' <<<"$line")"
    if grep -qxF "$hwnd" "$WORK/before"; then
      # Steam may show the question in its main window, which it keeps hidden with -silent: a window that was there
      # hidden and now shows counts too.
      if grep -qxF "$hwnd" "$WORK/hidden-before" && grep -q "visible=1" <<<"$line"; then
        DIALOG="${hwnd#hwnd=}"; MAIN=1; echo "  sichtbar geworden: $line" | tee -a "$LOG"; break
      fi
      continue
    fi
    set -- $size
    [ "${1:-0}" -ge 300 ] && [ "${2:-0}" -ge 200 ] && { DIALOG="${hwnd#hwnd=}"; echo "  neu: $line" | tee -a "$LOG"; break; }
    # Smaller new ones are noted once, so a dialog of another size isn't missed unseen.
    grep -qxF "$hwnd" "$WORK/noted" 2>/dev/null || { echo "$hwnd" >> "$WORK/noted"; echo "  neu, klein: $line" | tee -a "$LOG"; }
  done < "$WORK/out"
  [ -n "$DIALOG" ] && break
done
if [ -z "$DIALOG" ]; then
  exec_lines | tee -a "$LOG"
  if [ "$MODE" = install ]; then
    [ -n "$(exec_lines)" ] || say "Steams console_log hat keine ExecCommandLine-Zeile seit dem Aufruf: der Befehl kam nicht bei Steam an"
    [ -n "${CALL:-}" ] && kill -0 "$CALL" 2>/dev/null && kill "$CALL" 2>/dev/null
  fi
  say "ERGEBNIS: kein neues Steam-Fenster in $WAIT s"; exit 2
fi

# Hidden on the Mac (Nightforge hides Steam's helper apps under its own surface): the first key brings it forward,
# as Nightforge's SteamWindow.reveal would before a question of Steam's.
grep -q "visible=0" <<<"$(grep -F "hwnd=$DIALOG " "$WORK/out" 2>/dev/null)" && say "Das Fenster ist in Wine noch unsichtbar; der erste Tab holt es nach vorn"
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
if [ "$MAIN" = 1 ]; then
  # A question inside Steam's main window closes without the window going: only the eye can tell.
  say "ERGEBNIS (nur per Auge): Steam zeigte die Frage in seinem Hauptfenster. Ist sie nach Esc weg? Wenn nicht: mit der Maus „Abbrechen“."
  exit 3
fi
if run 10 gone "$DIALOG" 3000; then closed="SendInput"; else
  run 10 post esc "$DIALOG"; say "Esc per PostMessage: exit $?"
  run 10 gone "$DIALOG" 3000 && closed="PostMessage"
fi
if [ -n "$closed" ]; then
  say "ERGEBNIS: Esc schließt Steams Dialog ($closed). Fenster ist zu."
  exit 0
fi
if [ "$MAIN" = maybe ]; then
  say "ERGEBNIS (nur per Auge): Das Fenster ist noch da. Ist die Frage darin weg? Wenn nicht: mit der Maus „Abbrechen“."
  exit 3
fi
say "ERGEBNIS: Dialog noch offen. Bitte mit der Maus „Abbrechen“ drücken, nicht „Weiter“, „Installieren“ oder „Spielen“."
exit 1
