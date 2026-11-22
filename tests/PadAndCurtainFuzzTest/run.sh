#!/bin/bash
# The 0.3.3 rules under thousands of random inputs: the touchpad as a mouse, the pad keyboard, player numbers, a pad
# coming and going, the way out of a curtain and Steam only when it's needed: tests/PadAndCurtainFuzzTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/pad-curtain-fuzz-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/PadAndCurtainFuzzTest/main.swift
"$OUT"
