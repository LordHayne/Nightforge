#!/bin/bash
# Checks the engine layouts for D3DMetal (winecx) and Gcenx Wine:
# tests/EngineLayoutTest/run.sh [D3DMetal payload folder]  (with one it also installs real Apple files)
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/engine-layout-test"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/EngineLayoutTest/main.swift
# A home of its own: GameLog's wine.log lies in Application Support, never the player's.
mkdir -p "$WORK/home"
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT" "$@"
