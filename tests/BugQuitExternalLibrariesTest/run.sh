#!/bin/bash
# FAILS until the quit script looks at every Steam library: games and downloads in a library on an external drive
# aren't seen. See docs/TESTABDECKUNG.md (Befunde):
# tests/BugQuitExternalLibrariesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/bugquit-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/QuitWorld.swift tests/BugQuitExternalLibrariesTest/main.swift
"$OUT"
