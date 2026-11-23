#!/bin/bash
# Checks the pad keyboard's input (its keys, a pointer per half, what types): tests/PadKeyboardTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/TouchpadPointer.swift Sources/Nightforge/PadKeyboard.swift tests/PadKeyboardTest/main.swift
"$WORK/test"
