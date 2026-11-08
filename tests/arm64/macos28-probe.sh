#!/bin/bash
# What x86_64 Wine does on a macOS 28 beta (docs/ENTWURF-ARM64.md, section 6, point 8). Only looks, changes nothing.
#
#   tests/arm64/macos28-probe.sh [path to Wine's bin/wine]
#
# On a test volume that isn't used for playing: Apple's `game-test-tool enable` switches Rosetta off, and an upgrade
# doesn't bring it back. This script never runs that tool. By hand, on that volume:
#   1. run this script;  2. sudo game-test-tool enable, restart if asked;  3. run this script again.
# Wine only prints its version: no prefix, no game. It stops on anything older than macOS 28.
set -uo pipefail

version="$(sw_vers -productVersion)"
major="${version%%.*}"
if [ "$major" -lt 28 ]; then
  echo "macOS $version: this is for a macOS 28 beta" >&2
  exit 2
fi
echo "macOS: $version ($(sw_vers -buildVersion))"

if arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
  echo "arch -x86_64 /usr/bin/true: runs"
else
  echo "arch -x86_64 /usr/bin/true: does not run"
fi
# RosettaSupport goes by the line above: if /usr/bin/true has no x86_64 part any more, it says nothing about Rosetta.
echo "/usr/bin/true is built for: $(lipo -archs /usr/bin/true 2>&1)"

if command -v game-test-tool >/dev/null 2>&1; then
  echo "game-test-tool: $(command -v game-test-tool)"
else
  echo "game-test-tool: not there"
fi

wine="${1:-}"
if [ -n "$wine" ]; then
  # An empty prefix of its own, so that nothing can reach a real one.
  prefix="$(mktemp -d)"
  if output="$(WINEPREFIX="$prefix" arch -x86_64 "$wine" --version 2>&1)"; then
    echo "wine: $output"
  else
    echo "wine: does not start: $output"
  fi
  rm -rf "$prefix"
fi
