#!/bin/bash
# Checks when full screen is offered: tests/FullScreenOfferTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program goes with it
swiftc -parse-as-library -o "$WORK/test" Sources/Nightforge/FullScreenOffer.swift tests/FullScreenOfferTest/main.swift
"$WORK/test"
