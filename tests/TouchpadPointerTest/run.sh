#!/bin/bash
# Checks the touchpad as a mouse, against a stand-in for the Mac: tests/TouchpadPointerTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/TouchpadPointer.swift tests/TouchpadPointerTest/main.swift
"$WORK/test"
