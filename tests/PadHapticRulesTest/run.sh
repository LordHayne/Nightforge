#!/bin/bash
# Checks which moments the pad answers with its motors: tests/PadHapticRulesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/PadHapticRules.swift tests/PadHapticRulesTest/main.swift
"$WORK/test"
