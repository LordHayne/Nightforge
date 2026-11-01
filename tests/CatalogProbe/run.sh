#!/bin/bash
# Compiles SteamCatalog with a tiny driver and prints what it reads from the given Steam folder.
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/catalog-probe"
swiftc -O -o "$OUT" Sources/Nightforge/SteamCatalog.swift tests/CatalogProbe/main.swift
"$OUT" "$@"
