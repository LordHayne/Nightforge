#!/bin/bash
# Compiles ComponentStore with the smoke test and runs it from the repo root (no network needed).
set -euo pipefail
cd "$(dirname "$0")/../.."

# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk

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
