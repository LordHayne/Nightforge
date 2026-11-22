#!/bin/bash
# Checks the home button's setup against what macOS offers: tests/HomeButtonSetupTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -framework GameController -o "$WORK/test" Sources/Nightforge/HomeButtonSetup.swift tests/HomeButtonSetupTest/main.swift
"$WORK/test"
