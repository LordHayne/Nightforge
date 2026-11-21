#!/bin/bash
# Steam's licence at a game's first start, without Steam: tests/SteamLicenceTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
# SteamLicenceFiles needs the VDF reader: the rules are what's looked at here.
sed '/^\/\/\/ Steam.s own files, read only/,/^}$/d' Sources/Nightforge/SteamLicence.swift > "$WORK/SteamLicence.swift"
swiftc -parse-as-library -o "$WORK/test" "$WORK/SteamLicence.swift" tests/SteamLicenceTest/main.swift
"$WORK/test"
