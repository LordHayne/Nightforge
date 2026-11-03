#!/bin/bash
# Checks what the background Steam keeps from Nightforge: hide-steam-dock.dylib in the data folder
# (DockHider) and the Guide button's setting in localconfig.vdf (SteamGuideButton):
# tests/SteamBackgroundTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/steam-background-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/SteamBackgroundTest/main.swift
"$OUT"

# Steam's tray icon: the library hides the menu bar item winemac makes of it, a game's stays (three
# Steam icons at once on 27.10.). x86_64 like Wine, so it needs Rosetta – and a menu bar.
if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "– Steam's tray icon: skipped, no Rosetta"
  exit 0
fi
PROBE="nightforge-tray-probe"
# The hidden item's state goes into the probe's own defaults, by the probe's name.
trap 'rm -rf "$WORK"; defaults delete "$PROBE" >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/$PROBE.plist"' EXIT
clang -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib -framework AppKit -Wall \
  -o "$WORK/hide-steam-dock.dylib" wrapper/hide-steam-dock.m
clang -arch x86_64 -mmacosx-version-min=11.0 -fobjc-arc -framework AppKit -Wall \
  -o "$WORK/$PROBE" tests/SteamBackgroundTest/tray-probe.m
as_program() { (DYLD_INSERT_LIBRARIES="$WORK/hide-steam-dock.dylib" exec -a "$1" "$WORK/$PROBE"); }
steam="$(as_program 'C:\Program Files (x86)\Steam\steam.exe')"
game="$(as_program 'C:\Games\Hades\Hades.exe')"
if [ "$steam" = "no item" ] || [ "$game" = "no item" ]; then
  echo "– Steam's tray icon: skipped, no menu bar here"
  exit 0
fi
failed=0
[ "$steam" = "hidden nightforge.steam-tray.0" ] || { echo "✗ Steam's tray icon should be hidden, under its own name: $steam"; failed=1; }
[ "$game" = "shown Item-0" ] || { echo "✗ a game's tray icon should stay as it is: $game"; failed=1; }
[ $failed = 0 ] && echo "✓ Steam's tray icon stays out of the menu bar, a game's stays"
exit $failed
