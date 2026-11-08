#!/bin/bash
# Signs a built Nightforge.app: scripts/codesign-app.sh <app> (build.sh calls it).
#
# Signed ad hoc, an app's designated requirement is its build's cdhash: to macOS every build is new code,
# and it asks again for what the player allowed (an external drive, Accessibility, Automation). With
# Nightforge's own code signing identity (docs/CODESIGNATUR.md), a self-signed
# certificate, every build has the same requirement – this identifier, signed with that certificate – and
# macOS keeps those answers across updates (Apple's TN3127). The certificate isn't Apple's: Gatekeeper
# treats the app as before.
# NIGHTFORGE_CODESIGN_IDENTITY (the certificate's SHA-1) is what scripts/sign-release.sh hands in, the one
# pinned in scripts/codesign-certificate.sha1; NIGHTFORGE_CODESIGN_KEYCHAIN a keychain file to take it from.
# Without them the "Nightforge Code Signing" identity in your keychains, if there is one; else ad hoc
# (the release workflow: the certificate is only on the maintainer's Mac). NIGHTFORGE_AD_HOC=1 signs ad hoc
# whatever the keychain holds: a build no one watches (a session, a test run) mustn't wait on macOS asking
# whether codesign may use the key.
set -euo pipefail
APP_PATH="${1:?usage: $0 <app>}"

IDENTITY="${NIGHTFORGE_CODESIGN_IDENTITY:-}"
KEYCHAIN=()
[ -z "${NIGHTFORGE_CODESIGN_KEYCHAIN:-}" ] || KEYCHAIN=(--keychain "$NIGHTFORGE_CODESIGN_KEYCHAIN")
if [ -n "${NIGHTFORGE_AD_HOC:-}" ]; then
  IDENTITY=""
elif [ -z "$IDENTITY" ]; then
  # Without -v: the certificate is its own root, which macOS doesn't trust – codesign doesn't need it to.
  # Only the certificate pinned in codesign-certificate.sha1 when there is one: another one of that name
  # would give the app another requirement, and macOS would ask again.
  pinned="$(grep -v '^#' "$(dirname "$0")/codesign-certificate.sha1" 2>/dev/null | tr -d '[:space:]' | tr 'a-f' 'A-F' || true)"
  named="$(security find-identity -p codesigning 2>/dev/null | awk '/"Nightforge Code Signing"/ { print toupper($2) }' || true)"
  if [ -z "$pinned" ]; then
    IDENTITY="$(head -1 <<< "$named")"
  elif grep -qxF "$pinned" <<< "$named"; then
    IDENTITY="$pinned"
  elif [ -n "$named" ]; then
    echo "⚠ The \"Nightforge Code Signing\" certificate here isn't the pinned one ($pinned): signing ad hoc." >&2
  fi
fi
if [ -n "$IDENTITY" ]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
  REQUIREMENT="designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$IDENTITY\""
  # Nested code first with its own requirements, then the app with the one that names it. The helper app
  # by name: --deep doesn't count Contents/Helpers as nested code, and with its own requirement on the
  # certificate macOS keeps its permissions across builds (Detached.swift).
  HELPER="$APP_PATH/Contents/Helpers/Nightforge Helper.app"
  if [ -d "$HELPER" ]; then
    HELPER_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HELPER/Contents/Info.plist")"
    codesign --force --timestamp=none --sign "$IDENTITY" ${KEYCHAIN[@]+"${KEYCHAIN[@]}"} \
      -r="designated => identifier \"$HELPER_ID\" and certificate leaf = H\"$IDENTITY\"" "$HELPER" >/dev/null
  fi
  codesign --force --deep --timestamp=none --sign "$IDENTITY" ${KEYCHAIN[@]+"${KEYCHAIN[@]}"} "$APP_PATH" >/dev/null
  codesign --force --timestamp=none --sign "$IDENTITY" ${KEYCHAIN[@]+"${KEYCHAIN[@]}"} -r="$REQUIREMENT" "$APP_PATH" >/dev/null
  codesign --verify --deep --strict "$APP_PATH"
  [ ! -d "$HELPER" ] || codesign --verify --strict "$HELPER"
  codesign --display -r - "$APP_PATH" 2>/dev/null | grep -qiF "certificate leaf = H\"$IDENTITY\"" \
    || { echo "✗ The app's designated requirement doesn't name the certificate." >&2; exit 1; }
  echo "✓ Signed with Nightforge's code signing identity ($IDENTITY)"
else
  # Ad hoc, so macOS launches the app without any identity; the helper app by name first, as above.
  [ ! -d "$APP_PATH/Contents/Helpers/Nightforge Helper.app" ] \
    || codesign --force --sign - "$APP_PATH/Contents/Helpers/Nightforge Helper.app" >/dev/null
  codesign --force --deep --sign - "$APP_PATH" >/dev/null
fi
