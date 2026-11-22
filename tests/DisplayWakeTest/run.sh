#!/bin/bash
# Checks when a press on the pad brings the picture back: tests/DisplayWakeTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/DisplayWake.swift tests/DisplayWakeTest/main.swift
"$WORK/test"
