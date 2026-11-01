#!/bin/bash
# Checks the controller overlay: the hold, its steps, a game's processes, a stand-in game ended:
# tests/GameOverlayTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
OUT="$(mktemp -d)/game-overlay-test"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/GameOverlayTest/main.swift
"$OUT" tests/GameOverlayTest
