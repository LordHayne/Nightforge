#!/bin/bash
# FAILS until save file names are compared the way the volume does and .DS_Store is no save (docs/TESTABDECKUNG.md, Befunde):
# tests/BugSaveNamesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/test-program"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/Shared/SaveWorld.swift tests/BugSaveNamesTest/main.swift
"$OUT"
