#!/bin/bash
# Checks which program starts a Steam game (SteamProgram): Steam's own launch options by type
# (Rocket League without anti-cheat), another program through the LaunchOptions in localconfig.vdf,
# and that only Nightforge's own LaunchOptions change. Steam's files are made up in a temporary
# folder: tests/SteamProgramTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/steam-program-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/SteamProgramTest/main.swift
"$OUT"
