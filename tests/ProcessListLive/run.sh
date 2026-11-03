#!/bin/bash
# The one check that asks the real `ps -ax` – everything else hands ProcessList a list of its own
# (tests/Shared/FakeProcesses.swift), so a ps that hangs doesn't stop a series. Not a *Test folder:
# scripts/run-tests.sh doesn't run it. The CI does (.github/workflows/ci.yml); on a Mac, only when asked:
# tests/ProcessListLive/run.sh   (a ps that hangs shows as a failed check after 4 s, and leaves one more ps behind)
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
OUT="$WORK/process-list-live"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/ProcessListLive/main.swift
"$OUT"
