#!/bin/bash
# Checks what each store shows in each state in both launcher menus (LauncherState), how a client's
# sign-in is read, and that the sign-in has no field of Nightforge's own: tests/LauncherMenuTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/launcher-menu-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/LauncherMenuTest/main.swift
"$OUT"
