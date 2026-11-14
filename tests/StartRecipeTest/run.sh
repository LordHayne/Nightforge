#!/bin/bash
# Checks step E's own logic, before the start loop goes by it: a remedy changing a recipe, what comes after a
# failed start (the same way changed, another way, no start), proofs that hold for a recipe, and what tells a
# game's error box from a question of its own: tests/StartRecipeTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/start-recipe-test"
mkdir -p "$WORK/home"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/StartRecipeTest/main.swift
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT"
