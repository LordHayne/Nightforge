#!/bin/bash
# Checks that VoiceOver has a name for every button that shows only a symbol:
# tests/AccessibilityRulesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -I tests/AccessibilityRulesTest/check.py .
