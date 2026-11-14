#!/bin/bash
# Checks the closer look at a start nothing explains: what Wine's debug channels print, read for the game's
# own processes (fixtures/: Metal Gear Solid V's signature check of 11.11.2026), and when a start gets them:
# tests/CloserLookTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/closer-look-test"
mkdir -p "$WORK/home"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/CloserLookTest/main.swift
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT"
