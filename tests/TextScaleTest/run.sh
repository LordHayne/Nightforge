#!/bin/bash
# Checks that every font size goes through "Larger text" (Accessibility.swift):
# tests/TextScaleTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -I tests/TextScaleTest/check.py .
