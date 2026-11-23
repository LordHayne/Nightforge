#!/bin/bash
# What can be checked before a release without a key – the steps release.yml and the signing scripts take first, and
# the release notes it publishes as they are:
#   scripts/release-check.sh 0.3.5             version, notes, keys, the lists' signatures, and a release build
#                                              (NIGHTFORGE_RELEASE=1, signed ad hoc) without a test switch
#   scripts/release-check.sh 0.3.5 --no-build  the same with the release build already in build/Nightforge.noindex
#   scripts/release-check.sh --notes FILE      only the notes' rules (tests/test_release_check.py)
# Signs nothing, asks for no key, pushes nothing. ✓ holds, ✗ has to be done before the tag, – is for information.
# The exit code is 1 when anything is ✗.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
red=0
ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; red=$((red + 1)); }
info() { echo "– $*"; }

# release.yml publishes docs/release-notes/v<version>.md word for word.
check_notes() {
  local file="$1" open
  if [ ! -f "$file" ]; then bad "no release notes at $file"; return; fi
  if grep -q '^## Deutsch' "$file" && grep -q '^## English' "$file"; then ok "notes: German and English"
  else bad "notes: a section is missing (## Deutsch, ## English)"; fi
  open=$(grep -o '\[offen' "$file" | wc -l | tr -d ' ')
  if [ "$open" = 0 ]; then ok "notes: nothing [offen]"; else bad "notes: $open places still [offen]"; fi
  if grep -q '<!--' "$file"; then bad "notes: a working comment (<!-- … -->) is still in"; else ok "notes: no working comment"; fi
  # The user's rule for texts (21.11.2026).
  if grep -q -i -E 'ehrlich|honest' "$file"; then bad "notes: \"ehrlich\" or \"honest\""; else ok "notes: no \"ehrlich\""; fi
}

if [ "${1:-}" = "--notes" ]; then
  check_notes "${2:?notes file}"
  exit $((red > 0))
fi

version="${1:?version, e.g. 0.3.5}"
build=1
[ "${2:-}" = "--no-build" ] && build=0

# The version the app says it is (release.yml sets it from the tag as well, the repository should agree).
plist=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null)
if [ "$plist" = "$version" ]; then ok "Info.plist: $version"; else bad "Info.plist says ${plist:-nothing}, not $version"; fi

check_notes "docs/release-notes/v$version.md"

# "Signing keys are in": a release without both public keys turns down every update after it.
tool_dir="$(mktemp -d)"
trap 'rm -rf "$tool_dir"' EXIT
if (. scripts/signing-lib.sh && build_signing_tool . "$tool_dir" > /dev/null 2>&1 && "$TOOL" keys > /dev/null); then
  ok "both keys in Sources/Nightforge/SigningKeys.swift"
else
  bad "the signing tool doesn't build or a key is missing (scripts/make-signing-keys.sh)"
fi

# The lists the app takes only signed.
if scripts/check-signatures.sh > /dev/null 2>&1; then ok "the lists' signatures hold (scripts/check-signatures.sh)"
else bad "a list's signature doesn't hold: scripts/sign-lists.sh after the merge"; fi
changed=$(git diff --name-only main -- components/manifest.json profiles/profiles.json profiles/agw.json 2>/dev/null)
if [ -n "$changed" ]; then info "lists changed against main ($(echo "$changed" | tr '\n' ' ')): sign them on main after the merge"
else info "lists as on main: no scripts/sign-lists.sh needed"; fi

app=build/Nightforge.noindex/Nightforge.app
if [ "$build" = 1 ]; then
  mkdir -p build
  if env -u SDKROOT NIGHTFORGE_RELEASE=1 NIGHTFORGE_AD_HOC=1 ./build.sh > build/release-check-build.log 2>&1; then
    ok "release build (NIGHTFORGE_RELEASE=1, ad hoc)"
  else
    bad "the release build failed: build/release-check-build.log"
  fi
fi
binary="$app/Contents/MacOS/Nightforge"
if [ -x "$binary" ]; then
  # The same keys release.yml looks for, read from it.
  keys=$(sed -n 's/.*for key in \([^;]*\); do.*/\1/p' .github/workflows/release.yml)
  if [ -z "$keys" ]; then bad "release.yml's list of test switches wasn't found"; fi
  found=$(strings -a "$binary")
  for key in $keys; do
    if grep -q -F "$key" <<< "$found"; then bad "the release build has the test switch $key"; else ok "no $key"; fi
  done
  # Without this the check would pass on any binary at all.
  if grep -q -F "console.modeAsked" <<< "$found"; then ok "the binary's text is readable (console.modeAsked found)"
  else bad "the binary's text isn't readable: the switch check proves nothing"; fi
  if codesign --verify --deep "$app" 2> /dev/null; then ok "codesign --verify --deep"; else bad "codesign --verify --deep fails"; fi
else
  bad "no release build at $app"
fi

echo
if [ "$red" = 0 ]; then echo "Nothing left that can be checked without a key."; else echo "$red to do before the tag."; fi
exit $((red > 0))
