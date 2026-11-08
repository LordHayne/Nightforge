#!/bin/bash
# Checks the home button's setup against what macOS offers: tests/HomeButtonSetupTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -framework GameController -o "$WORK/test" Sources/Nightforge/HomeButtonSetup.swift tests/HomeButtonSetupTest/main.swift
"$WORK/test"
