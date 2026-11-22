#!/bin/bash
# Checks what changes on a TV (margins, text, highlight): tests/TVRulesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/TVRules.swift tests/TVRulesTest/main.swift
"$WORK/test"
