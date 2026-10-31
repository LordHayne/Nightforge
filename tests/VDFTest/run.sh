#!/bin/bash
# Checks VDF, the reader for Steam's manifests and library lists:
# tests/VDFTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
OUT="$(mktemp -d)/vdf-test"
# VDF.swift needs nothing else, so the test builds in seconds.
swiftc -parse-as-library -o "$OUT" Sources/Nightforge/VDF.swift tests/VDFTest/main.swift
"$OUT"
