#!/bin/bash
# Checks VDF, the reader for Steam's manifests and library lists:
# tests/VDFTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/vdf-test"
# VDF.swift needs nothing else, so the test builds in seconds.
swiftc -parse-as-library -o "$OUT" Sources/Nightforge/VDF.swift tests/VDFTest/main.swift
"$OUT"
