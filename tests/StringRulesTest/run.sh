#!/bin/bash
# Checks every translated text as a format: placeholders and their arguments, German against English:
# tests/StringRulesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -I tests/StringRulesTest/check.py .
