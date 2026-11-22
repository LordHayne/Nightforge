#!/bin/bash
# Checks which Unity games get "Play!" pressed in Unity's configuration window, from their files:
# tests/UnityDialogTest/run.sh
# (The program that presses it, under Wine against a stand-in window: tests/UnityDialogTest/dialog.sh.)
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT  # the test program and its home go with it
OUT="$WORK/unity-dialog-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/UnityDialogTest/main.swift
mkdir -p "$WORK/home"
HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" TMPDIR="$WORK/" "$OUT"
