#!/bin/bash
# Checks that the online lists carry a signature that holds, with the keys in
# Sources/Nightforge/SigningKeys.swift – the same check the app makes before it takes a list
# (.github/workflows/signatures.yml). A list that fails here doesn't reach players: sign it with
# scripts/sign-lists.sh <branch>.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/signing-lib.sh

work="$(mktemp -d)"
trap 'rm -rf -- "${work:?}"' EXIT
build_signing_tool . "$work"
"$TOOL" verify components/manifest.json profiles/profiles.json \
  || { echo "Sign them before merging: scripts/sign-lists.sh <branch> (docs/SICHERHEIT-0.3.md › Signierte Releases)"; exit 1; }
