#!/bin/bash
# Checks that a test program with the Mac's real home finds and reaches none of the player's Wine session (TestGuard).
# On purpose WITHOUT a home of its own: that is the case it guards. It only reads, and builds a Wine process without
# starting it: tests/TestGuardTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/test-guard-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/TestGuardTest/main.swift
"$OUT"
