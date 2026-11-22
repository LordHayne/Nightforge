#!/bin/bash
# Checks the players' tips: setup tips, Settings › Controller › Every button, the loading screen's tip: tests/PadGuideTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$WORK/test" $SOURCES tests/PadGuideTest/main.swift
"$WORK/test"
