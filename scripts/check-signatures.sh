#!/bin/bash
# Checks that the online lists carry a signature that holds, with the keys in
# Sources/Nightforge/SigningKeys.swift – the same check the app makes before it takes a list
# (.github/workflows/signatures.yml). A list that fails here doesn't reach players: sign it with
# scripts/sign-lists.sh <branch>.
#
#   scripts/check-signatures.sh          this checkout's lists
#   scripts/check-signatures.sh <tree>   another checkout's lists (a pull request's), checked with this
#                                        checkout's tool and keys; red when it changes either
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/signing-lib.sh

tree="${1:-.}"
[ -d "$tree" ] || { echo "✗ $tree isn't a folder."; exit 2; }
if [ "$tree" != . ]; then
  # What it's checked with mustn't come from what is checked (review D).
  changed=0
  for source in "${SIGNING_SOURCES[@]}" .github/workflows/signatures.yml; do
    { [ ! -e "$source" ] && [ ! -e "$tree/$source" ]; } || cmp -s "$source" "$tree/$source" || { echo "✗ It changes $source: this check can't vouch for that. Read it by hand."; changed=1; }
  done
  [ "$changed" = 0 ] || exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf -- "${work:?}"' EXIT
build_signing_tool . "$work"
lists=()
for list in "${SIGNED_LISTS[@]}"; do lists+=("$tree/$list"); done
"$TOOL" verify "${lists[@]}" \
  || { echo "Sign them before merging: scripts/sign-lists.sh <branch> (docs/SICHERHEIT-0.3.md › Signierte Releases)"; exit 1; }
