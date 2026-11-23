#!/bin/bash
# The pad's silence while the overlay is up: Nightforge's side against winebus's real code, taken
# straight out of the patch and run as its own program (x86_64 where Rosetta is there, as Wine is):
# tests/PadSilenceTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PATCH=engine/patches/winebus-winecx-pad-silence.patch

# The patch's own header, the code that decides.
sed -n '/^+++ b\/dlls\/winebus.sys\/pad_silence.h/,/^diff --git/p' "$PATCH" | grep '^+' | grep -v '^+++' | sed 's/^+//' > "$WORK/pad_silence.h"
grep -q pad_silence_poll "$WORK/pad_silence.h"

if arch -x86_64 /usr/bin/true 2>/dev/null; then ARCH=(-arch x86_64); RUN=(arch -x86_64); else ARCH=(); RUN=(); fi
clang "${ARCH[@]}" -mmacosx-version-min=11.0 -Wall -Wno-unused-function -I"$WORK" -o "$WORK/stand-in" tests/PadSilenceTest/standin.c
"${RUN[@]}" "$WORK/stand-in" --rules

SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$WORK/pad-silence-test" $SOURCES tests/PadSilenceTest/main.swift
"$WORK/pad-silence-test" "$WORK/stand-in" "$PATCH" "${RUN[*]:-}"
