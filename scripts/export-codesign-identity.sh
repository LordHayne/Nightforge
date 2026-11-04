#!/bin/bash
# Exports only Nightforge's code signing identity (the certificate in scripts/codesign-certificate.sha1
# and its private key) as a .p12, for the backup on the USB stick (docs/CODESIGNATUR.md › 2):
#
#   scripts/export-codesign-identity.sh /Volumes/<Stick>/Nightforge-Code-Signing.p12
#
# `security export -t identities` would take every identity in the keychain; Keychain Access shows
# only Passwords on macOS 27. macOS asks for the .p12's password in a dialog of its own and whether
# the key may be exported (Allow). Run it yourself in Terminal; it changes nothing in the keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "✗ $*" >&2; exit 1; }
[ $# -eq 1 ] || { echo "usage: $0 /Volumes/<Stick>/Nightforge-Code-Signing.p12" >&2; exit 2; }
out="$1"
[ -t 0 ] || fail "Run this yourself in Terminal: macOS asks you things on the way."
[ ! -e "$out" ] || fail "$out is there already."
folder="$(cd "$(dirname "$out")" 2>/dev/null && pwd -P)" || fail "The folder for $out isn't there."
case "$folder/" in "$(pwd -P)"/*) fail "Not into the repository: the key mustn't end up on GitHub." ;; esac
pinned="$(grep -v '^#' scripts/codesign-certificate.sha1 2>/dev/null | tr -d '[:space:]' || true)"
[ -n "$pinned" ] || fail "scripts/codesign-certificate.sha1 names no certificate yet."

work="$(mktemp -d)"
trap 'rm -rf -- "${work:?}"' EXIT
clt_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p 2>/dev/null)" = "/Library/Developer/CommandLineTools" ] && [ -d "$clt_sdk" ]; then
  export SDKROOT="$clt_sdk"
fi
swiftc -O -parse-as-library -o "$work/export" scripts/export-codesign-identity.swift \
  || fail "The export tool doesn't build (Command Line Tools or Xcode needed)."
"$work/export" "$pinned" "$out"
