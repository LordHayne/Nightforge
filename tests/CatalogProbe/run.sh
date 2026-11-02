#!/bin/bash
# Compiles the app with a tiny driver and prints what SteamCatalog reads from the given Steam folder.
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/catalog-probe"
# The whole app except its entry point: SteamCatalog's types reach into GameInfo and beyond.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -o "$OUT" $SOURCES tests/CatalogProbe/main.swift
"$OUT" "$@"
