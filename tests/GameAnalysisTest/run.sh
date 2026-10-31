#!/bin/bash
# Checks GameAnalysis, what a game's files say before it runs:
# tests/GameAnalysisTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
OUT="$(mktemp -d)/game-analysis-test"
# GameAnalysis.swift needs nothing else, so the test builds in seconds.
swiftc -parse-as-library -o "$OUT" Sources/Nightforge/GameAnalysis.swift tests/GameAnalysisTest/main.swift
"$OUT"
