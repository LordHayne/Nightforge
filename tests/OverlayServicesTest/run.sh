#!/bin/bash
# Checks the overlay's services without touching the Mac: the volume on a stand-in for Core Audio, the screenshot on one for ScreenCaptureKit:
# tests/OverlayServicesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/overlay-services-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/OverlayServicesTest/main.swift
"$OUT"
