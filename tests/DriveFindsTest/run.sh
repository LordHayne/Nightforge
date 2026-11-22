#!/bin/bash
# Checks what Nightforge finds on a drive that already holds games ("Nightforge Games" from an earlier
# install or another Mac), from a folder tree built in a temporary directory – no real drive is read:
# tests/DriveFindsTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/drive-finds-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/DriveFindsTest/main.swift
"$OUT"
