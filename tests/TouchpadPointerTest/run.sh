#!/bin/bash
# Checks the touchpad as a mouse, against a stand-in for the Mac: tests/TouchpadPointerTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/TouchpadPointer.swift tests/TouchpadPointerTest/main.swift
"$WORK/test"
