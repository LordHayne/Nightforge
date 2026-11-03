#!/bin/bash
# Checks which of the two Steams runs (SteamSwitch), their sign-in as they log it, Steam for Mac in
# the first start and its test home: tests/SteamSwitchTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program and its home go with it
OUT="$WORK/steam-switch-test"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/SteamSwitchTest/main.swift
"$OUT"
# Again in a home of its own, the way a first-start test runs: Steam for Mac must stay inside it.
mkdir -p "$WORK/fh"
# The stand-in's update takes a second there instead of ~50.
env HOME="$WORK/fh" CFFIXED_USER_HOME="$WORK/fh" NIGHTFORGE_TEST_STEAM_SECONDS=1 "$OUT" --test-home "$WORK/fh"
rm -rf "$WORK"
