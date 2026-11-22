#!/bin/bash
# Checks what Nightforge reads from profiles/agw.json (AppleGamingWiki), the links on a game's page,
# the shared report, the problem report's link and clipboard, and the "How did it run?" answers:
# tests/MacSourcesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/mac-sources-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/MacSourcesTest/main.swift
"$OUT" profiles/agw.json "$WORK"
