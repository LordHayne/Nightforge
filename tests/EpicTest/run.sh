#!/bin/bash
# Checks Epic Games without Epic: what Nightforge reads from legendary (library, installs, download
# progress, launch parameters), unpacking legendary once, Epic's sign-in code, and the store with a
# library from last time when Epic can't be reached – in an empty home of its own:
# tests/EpicTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT  # the test program and its home go with it
OUT="$DIR/epic-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/FakeProcesses.swift tests/EpicTest/main.swift
# A legendary that hangs, for removing a download (Legendary.end).
clang -O2 -Wall -o "$DIR/stand-in" tests/EpicTest/stand-in.c
mkdir -p "$DIR/home"
HOME="$DIR/home" CFFIXED_USER_HOME="$DIR/home" STAND_IN="$DIR/stand-in" "$OUT"
