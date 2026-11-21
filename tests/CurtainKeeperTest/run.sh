#!/bin/bash
# Checks that a curtain never stays with nobody to take it away (Tomb Raider, 8.11.): tests/CurtainKeeperTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/curtain-keeper-test"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/CurtainKeeperTest/main.swift
"$OUT"
