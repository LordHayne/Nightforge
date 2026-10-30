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
OUT="$(mktemp -d)/steam-background-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/SteamBackgroundTest/main.swift
"$OUT"
