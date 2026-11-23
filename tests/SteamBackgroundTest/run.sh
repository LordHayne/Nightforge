#!/bin/bash
# Checks what the background Steam keeps from Nightforge: hide-steam-dock.dylib in the data folder
# (DockHider) and the Guide button's setting in localconfig.vdf (SteamGuideButton):
# tests/SteamBackgroundTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/steam-background-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/FakeProcesses.swift tests/SteamBackgroundTest/main.swift
"$OUT"

# Steam's tray icon: the library hides the menu bar item winemac makes of it, a game's stays (three
# Steam icons at once on 27.10.). x86_64 like Wine, so it needs Rosetta – and a menu bar.
if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "– Steam's tray icon: skipped, no Rosetta"
  exit 0
fi
PROBE="nightforge-tray-probe"
# The library as build.sh links it: no framework of its own (hide-steam-dock.m swaps AppKit's methods once it's there).
clang -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib -lobjc -Wall \
  -o "$WORK/hide-steam-dock.dylib" wrapper/hide-steam-dock.m wrapper/network-order.c wrapper/d3dmetal-pace.m wrapper/d3dmetal-pace-rules.c
clang -arch x86_64 -mmacosx-version-min=11.0 -fobjc-arc -framework AppKit -Wall \
  -o "$WORK/$PROBE" tests/SteamBackgroundTest/tray-probe.m
clang -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib -fobjc-arc -framework AppKit -Wall \
  -o "$WORK/late-driver.dylib" tests/SteamBackgroundTest/late-driver.m
clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall -o "$WORK/wine-like" tests/SteamBackgroundTest/wine-like.c
# The same from an app bundle, as Wine runs with Game Mode on: macOS makes it a Dock app from the start.
BUNDLE_ID="io.github.lordhayne.nightforge.test-wine-like"
mkdir -p "$WORK/Wine.app/Contents/MacOS"
cp "$WORK/wine-like" "$WORK/Wine.app/Contents/MacOS/wine-like"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict>' \
  '<key>CFBundleExecutable</key><string>wine-like</string>' "<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>" \
  '<key>CFBundlePackageType</key><string>APPL</string>' '</dict></plist>' > "$WORK/Wine.app/Contents/Info.plist"
# A hidden item's state goes into the program's own defaults, by its name or its bundle's.
trap 'rm -rf "$WORK"; defaults delete "$PROBE" >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/$PROBE.plist"
      defaults delete wine-like >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/wine-like.plist"
      defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"' EXIT
late() { (DYLD_INSERT_LIBRARIES="$WORK/hide-steam-dock.dylib" exec -a "$1" "$2" "$3" "$WORK/late-driver.dylib") 2>/dev/null; }
failed=0
# AppKit only where Wine brings it (23.11.2026): a process without a window – wineserver, services, winedevice –
# goes without it. Linked to AppKit, the library brought it into all of them.
appkit="$( (DYLD_INSERT_LIBRARIES="$WORK/hide-steam-dock.dylib" exec -a 'C:\windows\system32\winedevice.exe' "$WORK/wine-like" appkit) )"
[ "$appkit" = "0" ] || { echo "✗ a process without a window shouldn't get AppKit from the library: $appkit"; failed=1; }
[ "$appkit" = "0" ] && echo "✓ a Wine process without a window goes without AppKit"
as_program() { (DYLD_INSERT_LIBRARIES="$WORK/hide-steam-dock.dylib" exec -a "$1" "$WORK/$PROBE"); }
steam="$(as_program 'C:\Program Files (x86)\Steam\steam.exe')"
game="$(as_program 'C:\Games\Hades\Hades.exe')"
if [ "$steam" = "no item" ] || [ "$game" = "no item" ]; then
  echo "– Steam's tray icon: skipped, no menu bar here"
  exit $failed
fi
[ "$steam" = "hidden nightforge.steam-tray.0" ] || { echo "✗ Steam's tray icon should be hidden, under its own name: $steam"; failed=1; }
[ "$game" = "shown Item-0" ] || { echo "✗ a game's tray icon should stay as it is: $game"; failed=1; }
[ $failed = 0 ] && echo "✓ Steam's tray icon stays out of the menu bar, a game's stays"

# The Dock and tray rules hold when AppKit comes late, with Wine's Mac driver (late-driver.m).
steamexe='C:\Program Files (x86)\Steam\steam.exe'; gameexe='C:\Games\Hades\Hades.exe'
helperexe='C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper.exe'
answers="$(late "$steamexe" "$WORK/wine-like" window) $(late "$gameexe" "$WORK/wine-like" window) $(late "$helperexe" "$WORK/wine-like" window)"
[ "$answers" = "1 0 1" ] || { echo "✗ a window: Steam and its web helper stay accessory apps, a game gets the Dock (1 0 1): $answers"; failed=1; }
answers="$(late "$steamexe" "$WORK/Wine.app/Contents/MacOS/wine-like" launch) $(late "$gameexe" "$WORK/Wine.app/Contents/MacOS/wine-like" launch)"
[ "$answers" = "1 1" ] || { echo "✗ started from the bundle: an accessory app until Wine asks for the Dock (1 1): $answers"; failed=1; }
steam="$(late "$steamexe" "$WORK/wine-like" tray)"; game="$(late "$gameexe" "$WORK/wine-like" tray)"
[ "$steam" = "hidden nightforge.steam-tray.0" ] && [ "$game" = "shown Item-0" ] \
  || { echo "✗ with AppKit late, Steam's tray icon hidden, a game's shown: $steam / $game"; failed=1; }
[ $failed = 0 ] && echo "✓ with AppKit from Wine's Mac driver, the Dock and tray rules as before"
exit $failed
