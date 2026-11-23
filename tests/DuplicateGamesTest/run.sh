#!/bin/bash
# Checks that a game from several stores is one card (matching, which store it starts through, marks, counts):
# tests/DuplicateGamesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/duplicate-games-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/DuplicateGamesTest/main.swift
"$OUT"
