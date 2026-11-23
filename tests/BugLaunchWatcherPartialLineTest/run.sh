#!/bin/bash
# FAILS until a Steam log line that arrives in two writes is read whole (docs/TESTABDECKUNG.md, Befunde):
# tests/BugLaunchWatcherPartialLineTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/test-program"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES  tests/BugLaunchWatcherPartialLineTest/main.swift
mkdir -p "$WORK/home"
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT"
