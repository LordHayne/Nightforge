#!/bin/bash
# Checks the root certificates Nightforge adds to the prefix: each is what its fingerprints say, and the
# registry text holds it as Wine reads it: tests/WindowsRootsTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/windows-roots-test"
mkdir -p "$WORK/home"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/WindowsRootsTest/main.swift
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT"
