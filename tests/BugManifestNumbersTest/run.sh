#!/bin/bash
# FAILS until a number too long in a Steam manifest doesn't crash Nightforge (docs/TESTABDECKUNG.md, Befunde):
# tests/BugManifestNumbersTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/test-program"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES  tests/BugManifestNumbersTest/main.swift
"$OUT"
