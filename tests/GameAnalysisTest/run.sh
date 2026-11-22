#!/bin/bash
# Checks GameAnalysis, what a game's files say before it runs:
# tests/GameAnalysisTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/game-analysis-test"
# GameAnalysis.swift needs only GameKind.swift beside it, so the test builds in seconds.
swiftc -parse-as-library -o "$OUT" Sources/Nightforge/GameAnalysis.swift Sources/Nightforge/GameKind.swift tests/GameAnalysisTest/main.swift
"$OUT"
