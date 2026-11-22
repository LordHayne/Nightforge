#!/bin/bash
# Checks the script Nightforge leaves behind at quit (Engine.steamShutdownScript) against a stand-in ps, open, lsof, wine and wineserver in a folder of its own – nothing real is asked or ended:
# tests/QuitScriptTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/quitscript-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/QuitScriptTest/main.swift
"$OUT"
