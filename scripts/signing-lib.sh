# Shared by the signing scripts (make-signing-keys.sh, sign-release.sh, sign-lists.sh,
# check-signatures.sh); sourced, not run. A private key only ever travels through a pipe: never onto
# the screen, into a file of the repository or onto a command line, where `ps` would show it.

# The Keychain item of the main key (login Keychain, "Nightforge signing key").
SIGNING_SERVICE="nightforge-signing-key"
SIGNING_ACCOUNT="main"
SIGNING_REPO="${NIGHTFORGE_REPO:-LordHayne/Nightforge}"

# The online lists the app takes only with their signature (Components.swift, Profiles.swift,
# MacSources.swift), each with a .sig beside it.
SIGNED_LISTS=(components/manifest.json profiles/profiles.json profiles/agw.json)

# Builds scripts/signing-tool.swift from the tree in $1 (its Signature.swift and SigningKeys.swift,
# so the tool knows that tree's keys) into the folder $2, and sets TOOL. NIGHTFORGE_SIGNING_TOOL
# names one built already (the tests do).
build_signing_tool() {
  if [ -n "${NIGHTFORGE_SIGNING_TOOL:-}" ]; then
    TOOL="$NIGHTFORGE_SIGNING_TOOL"
    return
  fi
  local clt_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
  if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p 2>/dev/null)" = "/Library/Developer/CommandLineTools" ] && [ -d "$clt_sdk" ]; then
    export SDKROOT="$clt_sdk"
  fi
  TOOL="$2/signing-tool"
  swiftc -O -parse-as-library -o "$TOOL" "$1/scripts/signing-tool.swift" \
    "$1/Sources/Nightforge/Signature.swift" "$1/Sources/Nightforge/SigningKeys.swift" \
    || { echo "✗ The signing tool doesn't build (Command Line Tools or Xcode needed)." >&2; return 1; }
}

# Where the private key comes from: the Keychain (macOS asks for your password; click "Allow", not
# "Always Allow"), the clipboard with --spare (the spare key, copied from your password manager), or
# the file NIGHTFORGE_SIGNING_KEY_FILE names (tests, or a key kept on a USB stick).
SIGNING_KEY_SOURCE="keychain"

# Writes the private key to stdout, for a pipe into the tool.
read_private_key() {
  if [ -n "${NIGHTFORGE_SIGNING_KEY_FILE:-}" ]; then
    cat -- "$NIGHTFORGE_SIGNING_KEY_FILE"
  elif [ "$SIGNING_KEY_SOURCE" = "clipboard" ]; then
    pbpaste
  else
    security find-generic-password -s "$SIGNING_SERVICE" -a "$SIGNING_ACCOUNT" -w
  fi
}

# Empties the clipboard once the spare key has been read from it.
forget_clipboard() {
  if [ "$SIGNING_KEY_SOURCE" = "clipboard" ]; then pbcopy < /dev/null || true; fi
}
