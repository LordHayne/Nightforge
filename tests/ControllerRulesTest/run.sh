#!/bin/bash
# Checks that the controller reaches every control (.padFocus) and that no two controls share a pad name:
# tests/ControllerRulesTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -I tests/ControllerRulesTest/check.py .
