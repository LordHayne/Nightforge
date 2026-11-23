#!/bin/bash
# Checks how the games on a drive are taken over without a download: Steam's list of libraries, legendary's
# import (a stand-in legendary that answers as 0.21.1 does) and Nightforge's own record for GOG – in an empty
# home of its own, over a drive built in a temporary directory. No real drive, no real store:
# tests/DriveTakeoverTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT  # the test program and its home go with it
OUT="$DIR/drive-takeover-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDrives.swift tests/Shared/FakeProcesses.swift tests/Shared/TestDefaults.swift tests/DriveTakeoverTest/main.swift
mkdir -p "$DIR/home"
HOME="$DIR/home" CFFIXED_USER_HOME="$DIR/home" "$OUT"
