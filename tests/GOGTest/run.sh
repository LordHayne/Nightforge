#!/bin/bash
# Checks GOG without GOG Galaxy: what Nightforge reads from GOG's API and from gogdl (library,
# sizes, builds, download progress, the games' own info files, cloud-save folders), the sign-in
# code, GameID, merging with other stores, Mac first, and the store with a library from last time
# when GOG can't be reached, and the real gogdl when it's installed – in an empty home of its own:
# tests/GOGTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT  # the test program and its home go with it
OUT="$DIR/gog-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/FakeProcesses.swift tests/GOGTest/main.swift
mkdir -p "$DIR/home"
# The real gogdl, when it's installed on this Mac (or GOGDL_COMPONENT_DIR names its version folder):
# a copy goes into the test's home, and the test starts it the way Nightforge does.
REAL="$HOME/Library/Application Support/Nightforge/Components/gogdl"
SOURCE="${GOGDL_COMPONENT_DIR:-$(ls -td "$REAL"/*/ 2>/dev/null | head -1 || true)}"
if [ -n "$SOURCE" ] && [ -f "${SOURCE%/}/.sha256" ]; then
  mkdir -p "$DIR/home/Library/Application Support/Nightforge/Components/gogdl"
  cp -R "${SOURCE%/}" "$DIR/home/Library/Application Support/Nightforge/Components/gogdl/"
fi
HOME="$DIR/home" CFFIXED_USER_HOME="$DIR/home" "$OUT"
