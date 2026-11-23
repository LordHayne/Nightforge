#!/bin/bash
# Checks what a failed start is read from: crash dumps, the table from failure to remedy, a game's sort and
# a start's recipe in its record: tests/StartDiagnosisTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/start-diagnosis-test"
mkdir -p "$WORK/home"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/StartDiagnosisTest/main.swift
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT"
