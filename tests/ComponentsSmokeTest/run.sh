#!/bin/bash
# Compiles ComponentStore with the smoke test and runs it from the repo root (no network needed).
set -euo pipefail
cd "$(dirname "$0")/../.."

CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/components-smoke"
swiftc -o "$OUT" \
  Sources/Nightforge/Components.swift \
  Sources/Nightforge/Signature.swift \
  Sources/Nightforge/SigningKeys.swift \
  Sources/Nightforge/Strings.swift \
  tests/ComponentsSmokeTest/main.swift
"$OUT"
