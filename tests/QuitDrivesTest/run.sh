#!/bin/bash
# Checks the quit script (Engine.steamShutdownScript) with games on external drives, folders with spaces
# and umlauts, and damaged manifests, against stand-ins – nothing real is asked or ended:
# tests/QuitDrivesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/quitdrives-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/QuitWorld.swift tests/QuitDrivesTest/main.swift
"$OUT"
