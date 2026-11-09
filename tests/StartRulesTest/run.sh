#!/bin/bash
# Checks how a start is chosen and what it learns: what the files decide, reports, what a game says when
# it crashes, and the record of first starts: tests/StartRulesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/start-rules-test"
mkdir -p "$WORK/home"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/StartRulesTest/main.swift
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT"
