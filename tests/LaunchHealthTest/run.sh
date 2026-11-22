#!/bin/bash
# Checks game analysis, the self-healing launch ladder and the log parsing:
# tests/LaunchHealthTest/run.sh [Steam folder]  (with a Steam folder it also analyses installed games)
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/launch-health-test"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/LaunchHealthTest/main.swift
"$OUT" "$@"
