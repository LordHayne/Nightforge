#!/bin/bash
# Checks how Nightforge starts programs apart from itself (Detached.swift, wrapper/nightforge-helper.c):
# tests/DetachedProcessTest/run.sh [--dock]  (--dock also checks the Dock with a small test app)
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT  # the test program and its home go with it
OUT="$DIR/detached-process-test"
clang -arch arm64 -mmacosx-version-min=14.0 -O2 -Wall -o "$DIR/nightforge-helper" wrapper/nightforge-helper.c
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/FakeProcesses.swift tests/DetachedProcessTest/main.swift
"$OUT" "$DIR/nightforge-helper" "$@"
