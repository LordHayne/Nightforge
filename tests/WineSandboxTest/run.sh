#!/bin/bash
# Checks Wine's sandbox: the profile, the switch, and the real helper on a home of its own:
# tests/WineSandboxTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/wine-sandbox-test"
# The helper as build.sh makes it, and a program that shows what of its environment arrived (x86_64,
# like Wine, so DYLD_* would reach it).
clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall -o "$WORK/nightforge-sandbox" wrapper/nightforge-sandbox.c
printf '#include <stdio.h>\n#include <stdlib.h>\nint main(void) { const char *v = getenv("DYLD_FALLBACK_LIBRARY_PATH"); puts(v ? v : "(none)"); return 0; }\n' > "$WORK/showenv.c"
clang -arch x86_64 -O2 -o "$WORK/showenv" "$WORK/showenv.c"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/WineSandboxTest/main.swift
"$OUT" "$WORK/nightforge-sandbox" "$WORK/showenv"
