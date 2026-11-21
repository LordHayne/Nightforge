#!/bin/bash
# The real LibraryModel on a made-up Mac: its pages, selection and marks under random use, with games coming and going:
# tests/ModelNavigationTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/model-navigation-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/Shared/ModelWorld.swift tests/ModelNavigationTest/main.swift
mkdir -p "$WORK/home"
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT"
