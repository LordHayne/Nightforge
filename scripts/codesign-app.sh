#!/bin/bash
# Signs a built Nightforge.app: scripts/codesign-app.sh <app> (build.sh calls it).
#
# Signed ad hoc, an app's designated requirement is its build's cdhash: to macOS every build is new code,
# and it asks again for what the player allowed (an external drive, Accessibility, Automation). With
# Nightforge's own code signing identity (docs/CODESIGNATUR.md), a self-signed
# certificate, every build has the same requirement – this identifier, signed with that certificate – and
# macOS keeps those answers across updates (Apple's TN3127). The certificate isn't Apple's: Gatekeeper
# treats the app as before.
# NIGHTFORGE_CODESIGN_IDENTITY (the certificate's SHA-1) and NIGHTFORGE_CODESIGN_KEYCHAIN come from
# release.yml; here the "Nightforge Code Signing" identity in your keychains, if there is one; else ad hoc.
set -euo pipefail
APP_PATH="${1:?usage: $0 <app>}"

IDENTITY="${NIGHTFORGE_CODESIGN_IDENTITY:-}"
KEYCHAIN=()
[ -z "${NIGHTFORGE_CODESIGN_KEYCHAIN:-}" ] || KEYCHAIN=(--keychain "$NIGHTFORGE_CODESIGN_KEYCHAIN")
if [ -z "$IDENTITY" ]; then
  # Without -v: the certificate is its own root, which macOS doesn't trust – codesign doesn't need it to.
  IDENTITY="$(security find-identity -p codesigning 2>/dev/null | awk '/"Nightforge Code Signing"/ { print $2; exit }' || true)"
fi
if [ -n "$IDENTITY" ]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
  REQUIREMENT="designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$IDENTITY\""
  # Nested code first with its own requirements, then the app with the one that names it.
  codesign --force --deep --timestamp=none --sign "$IDENTITY" ${KEYCHAIN[@]+"${KEYCHAIN[@]}"} "$APP_PATH" >/dev/null
  codesign --force --timestamp=none --sign "$IDENTITY" ${KEYCHAIN[@]+"${KEYCHAIN[@]}"} -r="$REQUIREMENT" "$APP_PATH" >/dev/null
  codesign --verify --deep --strict "$APP_PATH"
  codesign --display -r - "$APP_PATH" 2>/dev/null | grep -qiF "certificate leaf = H\"$IDENTITY\"" \
    || { echo "✗ The app's designated requirement doesn't name the certificate." >&2; exit 1; }
  echo "✓ Signed with Nightforge's code signing identity ($IDENTITY)"
else
  # Ad hoc, so macOS launches the app without any identity.
  codesign --force --deep --sign - "$APP_PATH" >/dev/null
fi
