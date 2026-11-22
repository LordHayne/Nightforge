#!/bin/bash
# Checks what's said when a controller comes, goes or runs low: tests/ControllerNoticesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/ControllerNotices.swift tests/ControllerNoticesTest/main.swift
"$WORK/test"
