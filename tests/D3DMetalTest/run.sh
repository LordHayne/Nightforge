#!/bin/bash
# Checks where Apple's D3DMetal comes from: the answer kept on file, a copy from before the question,
# the import from Apple's toolkit (a folder, a disk image, one nested in another), the wait for the
# download – no network, no real signature, in an empty home of its own:
# tests/D3DMetalTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT  # the test program and its home go with it
OUT="$DIR/d3dmetal-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/D3DMetalTest/main.swift
mkdir -p "$DIR/home"
HOME="$DIR/home" CFFIXED_USER_HOME="$DIR/home" "$OUT"
