#!/bin/bash
# Checks GOG without GOG Galaxy: what Nightforge reads from GOG's API and from gogdl (library,
# sizes, builds, download progress, the games' own info files, cloud-save folders), the sign-in
# code, GameID, merging with other stores, Mac first, and the store with a library from last time
# when GOG can't be reached – in an empty home of its own:
# tests/GOGTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
DIR="$(mktemp -d)"
OUT="$DIR/gog-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/GOGTest/main.swift
mkdir -p "$DIR/home"
HOME="$DIR/home" CFFIXED_USER_HOME="$DIR/home" "$OUT"
