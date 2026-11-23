#!/bin/bash
# Checks Subprocess.run with its limit, withDeadline and DetachedProcess.waitUntilExit(timeout:) – on programs of its own (sleep, echo, sh), never on Nightforge's, Wine's or Steam's:
# tests/SubprocessTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/subprocess-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/SubprocessTest/main.swift
"$OUT"
