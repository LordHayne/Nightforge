#!/bin/bash
# Checks that build.sh, scripts/codesign-app.sh and Detached.swift agree on the helper app, and that the
# version in Info.plist has its release notes: tests/BuildLayoutTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -I tests/BuildLayoutTest/check.py .
