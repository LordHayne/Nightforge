#!/bin/bash
# Checks the switch for opening at login, against a stand-in for macOS: tests/LoginItemTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/LoginItem.swift tests/LoginItemTest/main.swift
"$WORK/test"
