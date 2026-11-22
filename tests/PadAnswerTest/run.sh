#!/bin/bash
# Checks when A and B answer a game's question, and that the Windows helper builds: tests/PadAnswerTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/PadAnswer.swift tests/PadAnswerTest/main.swift
"$WORK/test"
if command -v x86_64-w64-mingw32-gcc >/dev/null; then
  x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Werror -municode -mwindows -static -o "$WORK/pad-answer.exe" wrapper/pad-answer.c
  echo "✓ wrapper/pad-answer.c builds"
fi
