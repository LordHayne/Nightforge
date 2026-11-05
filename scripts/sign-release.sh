#!/bin/bash
# Signs a release draft that .github/workflows/release.yml made:
#
#   scripts/sign-release.sh v0.3.1             sign; publish afterwards (the command is printed)
#   scripts/sign-release.sh v0.3.1 --publish   sign and publish in one go
#   --spare   sign with the spare key, copied from your password manager to the clipboard
#   --add     keep the signature that's there and add this key's (after a key change)
#
# Releases are immutable once published, so the signature goes onto the draft. The script downloads
# the draft's zip, checks that the app inside is the tag's version and knows both public keys (an app
# without them could never update again), signs the zip with the main key from your Keychain (macOS
# asks for your password: click "Allow") and uploads Nightforge-<version>.zip.sig beside it. Before it
# signs it shows what you sign and asks: the signature says you saw these bytes, not that they were
# built from the tag.
# First it gives the app Nightforge's code signing certificate (docs/CODESIGNATUR.md), which exists only
# on this Mac: CI builds ad hoc. The zip is packed again from that app, and that zip is the one signed and
# uploaded in place of the workflow's. The DMG is built again from that same app and goes up in place of the
# workflow's ad hoc one, its SHA-256 into the release notes (review A3).
# A tag with a suffix (v0.3.1-rc.1) is a test release: published as a prerelease, which neither the
# app nor scripts/install.sh offers (docs/SICHERHEIT-0.3.md › Test-Release).
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/signing-lib.sh

fail() { echo "✗ $*" >&2; exit 1; }
usage() { echo "usage: $0 <tag> [--publish] [--spare] [--add]" >&2; exit 2; }

tag=""
publish=0
add=()
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) publish=1 ;;
    --spare) SIGNING_KEY_SOURCE="clipboard" ;;
    --add) add=(--add) ;;
    -*) usage ;;
    *) [ -z "$tag" ] || usage; tag="$1" ;;
  esac
  shift
done
[[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$ ]] || usage
version="${tag#v}"
zip="Nightforge-$version.zip"

work="$(mktemp -d)"
trap 'forget_clipboard; rm -rf -- "${work:?}"' EXIT

echo "▸ Looking at the draft of $tag …"
release="$(gh release view "$tag" --repo "$SIGNING_REPO" --json isDraft,isPrerelease,assets)" \
  || fail "No release $tag. Is the release workflow for the tag done?"
[ "$(jq -r .isDraft <<< "$release")" = "true" ] \
  || fail "$tag is published already: nothing can be added to it any more. Make a new tag."
prerelease="$(jq -r .isPrerelease <<< "$release")"
jq -e --arg zip "$zip" '.assets | any(.name == $zip)' <<< "$release" > /dev/null || fail "The draft has no $zip."
[ "$prerelease" = "true" ] || [[ "$version" != *-* ]] || fail "$tag has a suffix but isn't a prerelease: the app would offer it to everyone."

gh release download "$tag" --repo "$SIGNING_REPO" --pattern "$zip" --dir "$work"
if [ ${#add[@]} -gt 0 ] && jq -e --arg sig "$zip.sig" '.assets | any(.name == $sig)' <<< "$release" > /dev/null; then
  gh release download "$tag" --repo "$SIGNING_REPO" --pattern "$zip.sig" --dir "$work"
fi

echo "▸ Checking the app in $zip …"
build_signing_tool . "$work"
ditto -x -k "$work/$zip" "$work/unpacked"
app="$work/unpacked/Nightforge.app"
[ -d "$app" ] || fail "$zip holds no Nightforge.app."
inside="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[ "$inside" = "$version" ] || fail "The app in $zip is $inside, not $version."
keys="$("$TOOL" keys)" || fail "SigningKeys.swift here has no keys: scripts/make-signing-keys.sh first."
while read -r role key; do
  grep -qaF "$key" "$app/Contents/MacOS/Nightforge" \
    || fail "The app in $zip doesn't know the $role key of this checkout. Its players couldn't update again: build the release from a commit with these keys."
done <<< "$keys"
echo "✓ Nightforge $version, knows both keys."

# The code signature macOS recognises the app by across updates, from the certificate pinned in
# scripts/codesign-certificate.sha1 and kept in this Mac's keychain only. An app that has it already
# (a second run, --add) stays as it is, so the signature on the draft still holds for its zip.
pinned="$(grep -v '^#' scripts/codesign-certificate.sha1 2>/dev/null | tr -d '[:space:]' | tr 'a-f' 'A-F' || true)"
final="$work/$zip"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
has_certificate() { codesign --display -r - "$app" 2>/dev/null | grep -qiF "certificate leaf = H\"$pinned\""; }
# Both, whether it was signed now or in an earlier run.
names_us() {
  has_certificate && codesign --display -r - "$app" 2>/dev/null | grep -qF "identifier \"$bundle_id\"" \
    || fail "The app's designated requirement doesn't name $bundle_id and the certificate $pinned."
}
if [ -z "$pinned" ]; then
  code_note="ad hoc (scripts/codesign-certificate.sha1 names no certificate)"
elif has_certificate; then
  names_us
  code_note="Nightforge Code Signing $pinned, from an earlier run"
else
  # Signing it changes the zip's bytes, so a signature already on the draft wouldn't hold any more and
  # --add would end with this key's alone.
  [ ${#add[@]} -eq 0 ] || [ ! -e "$work/$zip.sig" ] \
    || fail "The draft's $zip isn't code-signed yet, and signing it changes its bytes: the signature on the draft wouldn't hold. Sign it once without --add first, then add the other key."
  security find-identity -p codesigning 2>/dev/null | grep -qiF "$pinned" \
    || fail "The code signing certificate $pinned isn't in this Mac's keychain (docs/CODESIGNATUR.md)."
  echo "▸ Signing the app with Nightforge's certificate (macOS may ask whether codesign may use its key) …"
  NIGHTFORGE_CODESIGN_IDENTITY="$pinned" NIGHTFORGE_CODESIGN_KEYCHAIN="" scripts/codesign-app.sh "$app"
  names_us
  mkdir "$work/signed"
  final="$work/signed/$zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$final"
  code_note="Nightforge Code Signing $pinned, signed now"
fi

# The DMG, for whoever installs by hand, from that same app (review A3): the workflow's is ad hoc, and nothing
# checked it. dmgbuild comes pinned by its hashes (scripts/dmgbuild-requirements.txt, as in release.yml) into a
# venv of its own; Homebrew's Python 3.13 when there is one, as its ds-store needs a newer Python than macOS's.
# NIGHTFORGE_DMGBUILD: a stand-in for the tests.
dmg="Nightforge-$version.dmg"
build_dmg() {
  if [ -n "${NIGHTFORGE_DMGBUILD:-}" ]; then "$NIGHTFORGE_DMGBUILD" "$1" "$2"; return; fi
  local python
  python="$(brew --prefix python@3.13 2>/dev/null)/bin/python3.13"
  [ -x "$python" ] || python=python3
  "$python" -m venv "$work/dmgbuild"
  "$work/dmgbuild/bin/python3" -m pip install -q --require-hashes -r scripts/dmgbuild-requirements.txt
  "$work/dmgbuild/bin/python3" -m dmgbuild -s scripts/dmg-settings.py -D app="$1" Nightforge "$2" > /dev/null
}
echo "▸ Building $dmg from that app …"
build_dmg "$app" "$work/$dmg" || fail "$dmg couldn't be built from the app."
hdiutil verify "$work/$dmg" > /dev/null 2>&1 || fail "$dmg doesn't verify."
dmg_sha="$(shasum -a 256 "$work/$dmg" | cut -d' ' -f1)"

# What you sign (review M5): the zip as it came down (and as GitHub lists it), the commit the tag
# points at on GitHub, and the steamwebhelper wrapper in the app beside the repository's at that commit.
zip_sha="$(shasum -a 256 "$work/$zip" | cut -d' ' -f1)"
listed="$(jq -r --arg zip "$zip" '.assets[] | select(.name == $zip) | .digest // empty' <<< "$release")"
# An older gh, or an asset from before GitHub kept digests: then there's nothing to compare, but said so.
[ -n "$listed" ] || echo "⚠ GitHub names no SHA-256 for the draft's $zip (gh too old?): not compared with the download." >&2
[ -z "$listed" ] || [ "$listed" = "sha256:$zip_sha" ] || fail "$zip came down other than GitHub lists it ($listed)."
commit="$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}" 2>/dev/null | tail -1 | cut -f1 || true)"
built_from="${commit:-unknown (no tag $tag on origin)}"
[ -z "$commit" ] || built_from="$(git log -1 --format='%h %s (%an, %ad)' --date=short "$commit" 2>/dev/null \
  || echo "$commit (not in this checkout: git fetch)")"
wrapper="$(shasum -a 256 "$app/Contents/Resources/steamwebhelper.exe" 2>/dev/null | cut -d' ' -f1 || true)"
if [ -z "$wrapper" ]; then
  wrapper_note="✗ none in the app"
elif [ -n "$commit" ] && git show "$commit:wrapper/steamwebhelper.exe" > "$work/wrapper.exe" 2>/dev/null; then
  ours="$(shasum -a 256 "$work/wrapper.exe" | cut -d' ' -f1)"
  if [ "$ours" = "$wrapper" ]; then wrapper_note="the same as wrapper/steamwebhelper.exe at $tag"
  else wrapper_note="✗ not the one at $tag ($ours): look before you sign"; fi
else
  wrapper_note="nothing here to compare it with"
fi
echo "▸ You're about to sign:"
echo "    $zip  sha256 $zip_sha  (as the release workflow built it)"
[ "$final" = "$work/$zip" ] || echo "    $zip  sha256 $(shasum -a 256 "$final" | cut -d' ' -f1)  (code-signed here: this one goes on the release)"
echo "    code signature  $code_note"
echo "    $dmg  sha256 $dmg_sha  (built here from that app: this one goes on the release, its SHA-256 into the notes)"
echo "    built from  $built_from"
echo "    steamwebhelper.exe  sha256 ${wrapper:--}  ($wrapper_note)"
read -r -p "Sign it? Type yes: " answer || answer=""
[ "$answer" = "yes" ] || fail "Nothing signed."

echo "▸ Signing (macOS asks for your password: click Allow) …"
read_private_key | "$TOOL" sign ${add[@]+"${add[@]}"} "$final"
forget_clipboard
"$TOOL" verify "$final" > /dev/null

uploads=("$final.sig" "$work/$dmg")
[ "$final" = "$work/$zip" ] || uploads=("$final" "$final.sig" "$work/$dmg")
gh release upload "$tag" "${uploads[@]}" --repo "$SIGNING_REPO" --clobber
assets="$(gh release view "$tag" --repo "$SIGNING_REPO" --json assets)"
jq -e --arg sig "$zip.sig" '.assets | any(.name == $sig)' <<< "$assets" > /dev/null \
  || fail "GitHub doesn't list $zip.sig on the draft."
listed="$(jq -r --arg zip "$zip" '.assets[] | select(.name == $zip) | .digest // empty' <<< "$assets")"
[ -n "$listed" ] || echo "⚠ GitHub names no SHA-256 for $zip on the draft: not compared with the one signed." >&2
[ -z "$listed" ] || [ "$listed" = "sha256:$(shasum -a 256 "$final" | cut -d' ' -f1)" ] \
  || fail "GitHub lists another $zip on the draft than the one signed ($listed)."
echo "✓ $zip.sig is on the draft$([ "$final" = "$work/$zip" ] || echo ", beside the code-signed $zip")."
listed="$(jq -r --arg dmg "$dmg" '.assets[] | select(.name == $dmg) | .digest // empty' <<< "$assets")"
[ -z "$listed" ] || [ "$listed" = "sha256:$dmg_sha" ] || fail "GitHub lists another $dmg on the draft than the one built here ($listed)."
# Its SHA-256 into the notes, in place of the line of an earlier run: whoever downloads it by hand can compare.
body="$(gh release view "$tag" --repo "$SIGNING_REPO" --json body | jq -r '.body // ""')"
{ printf '%s\n' "$body" | grep -v "^SHA-256 of $dmg: " || true; printf '\nSHA-256 of %s: `%s`\n' "$dmg" "$dmg_sha"; } > "$work/notes.md"
gh release edit "$tag" --repo "$SIGNING_REPO" --notes-file "$work/notes.md" > /dev/null
echo "✓ $dmg is on the draft, built from the same app, its SHA-256 in the notes."

if [ "$prerelease" = "true" ]; then edit=(--draft=false --prerelease); else edit=(--draft=false --latest); fi
if [ "$publish" = 1 ]; then
  gh release edit "$tag" --repo "$SIGNING_REPO" "${edit[@]}" > /dev/null
  echo "✓ $tag is published$([ "$prerelease" = "true" ] && echo " as a prerelease")."
else
  echo "To publish: gh release edit $tag --repo $SIGNING_REPO ${edit[*]}"
  echo "         or: scripts/sign-release.sh $tag --publish"
fi
