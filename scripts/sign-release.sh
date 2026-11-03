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

# What you sign (review M5): the zip as it came down (and as GitHub lists it), the commit the tag
# points at on GitHub, and the steamwebhelper wrapper in the app beside the repository's at that commit.
zip_sha="$(shasum -a 256 "$work/$zip" | cut -d' ' -f1)"
listed="$(jq -r --arg zip "$zip" '.assets[] | select(.name == $zip) | .digest // empty' <<< "$release")"
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
echo "    $zip  sha256 $zip_sha"
echo "    built from  $built_from"
echo "    steamwebhelper.exe  sha256 ${wrapper:--}  ($wrapper_note)"
read -r -p "Sign it? Type yes: " answer || answer=""
[ "$answer" = "yes" ] || fail "Nothing signed."

echo "▸ Signing (macOS asks for your password: click Allow) …"
read_private_key | "$TOOL" sign ${add[@]+"${add[@]}"} "$work/$zip"
forget_clipboard
"$TOOL" verify "$work/$zip" > /dev/null

gh release upload "$tag" "$work/$zip.sig" --repo "$SIGNING_REPO" --clobber
jq -e --arg sig "$zip.sig" '.assets | any(.name == $sig)' \
  <<< "$(gh release view "$tag" --repo "$SIGNING_REPO" --json assets)" > /dev/null \
  || fail "GitHub doesn't list $zip.sig on the draft."
echo "✓ $zip.sig is on the draft."

if [ "$prerelease" = "true" ]; then edit=(--draft=false --prerelease); else edit=(--draft=false --latest); fi
if [ "$publish" = 1 ]; then
  gh release edit "$tag" --repo "$SIGNING_REPO" "${edit[@]}" > /dev/null
  echo "✓ $tag is published$([ "$prerelease" = "true" ] && echo " as a prerelease")."
else
  echo "To publish: gh release edit $tag --repo $SIGNING_REPO ${edit[*]}"
  echo "         or: scripts/sign-release.sh $tag --publish"
fi
