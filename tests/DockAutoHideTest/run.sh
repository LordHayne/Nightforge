#!/bin/bash
# Checks the Dock's setting in console mode: tests/DockAutoHideTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/DockAutoHide.swift tests/DockAutoHideTest/main.swift
"$WORK/test"
