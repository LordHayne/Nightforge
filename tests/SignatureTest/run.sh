#!/bin/bash
# Checks the Ed25519 signatures on updates and online lists:
# tests/SignatureTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/signature-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/SignatureTest/main.swift
# A home of its own: the lists it fetches are kept in Application Support.
mkdir -p "$WORK/home"
env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" "$OUT"
