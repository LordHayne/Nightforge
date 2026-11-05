#!/bin/bash
# Signs the online lists (components/manifest.json, profiles/profiles.json, profiles/agw.json) on a
# branch and pushes the signatures there:
#
#   scripts/sign-lists.sh bot/profiles   the nightly pull request, before you merge it
#   scripts/sign-lists.sh main           main itself (the first time, or after an unsigned merge)
#   --spare, --add                       as in scripts/sign-release.sh
#
# The app takes an online list only with its signature beside it (Sources/Nightforge/Signature.swift),
# and the nightly runs can't sign: so a list change reaches players once you've read the pull
# request, signed it here and merged it. A list whose signature still holds is left alone.
# The branch is checked out into a folder of its own; your working copy isn't touched. Nothing of the
# branch runs: the signing tool is built from this checkout (the private key goes into it), the
# branch may change only the lists, their signatures and components/sources.json, and git runs no
# hooks in its folder.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/signing-lib.sh

fail() { echo "✗ $*" >&2; exit 1; }
usage() { echo "usage: $0 <branch> [--spare] [--add]" >&2; exit 2; }

branch=""
add=()
while [ $# -gt 0 ]; do
  case "$1" in
    --spare) SIGNING_KEY_SOURCE="clipboard" ;;
    --add) add=(--add) ;;
    -*) usage ;;
    *) [ -z "$branch" ] || usage; branch="$1" ;;
  esac
  shift
done
[ -n "$branch" ] || usage
git check-ref-format --branch "$branch" > /dev/null 2>&1 || fail "$branch isn't a branch name."

work="$(mktemp -d)"
tree="$work/tree"
cleanup() {
  forget_clipboard
  git worktree remove --force "$tree" > /dev/null 2>&1 || true
  rm -rf -- "${work:?}"
}
trap cleanup EXIT

echo "▸ Fetching $branch …"
git fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/$branch" || fail "origin has no branch $branch."
[ "$branch" = main ] || git fetch --quiet origin "refs/heads/main:refs/remotes/origin/main" || fail "origin has no main."
# A branch that changed the signing tool could have it write the key out: anything besides the lists
# (and the source list the components bot writes beside its manifest) is refused before anything is built.
allowed=(components/sources.json)
for list in "${SIGNED_LISTS[@]}"; do allowed+=("$list" "$list.sig"); done
while IFS= read -r changed; do
  [ -n "$changed" ] || continue
  case " ${allowed[*]} " in *" $changed "*) ;; *)
    fail "$branch changes $changed, not only the lists: it isn't signed here. Look at it as a pull request of its own." ;;
  esac
done <<< "$(git diff --name-only "origin/main...origin/$branch")"
git -c core.hooksPath=/dev/null worktree add --quiet --detach "$tree" "origin/$branch"
for source in "${SIGNING_SOURCES[@]}"; do
  cmp -s "$source" "$tree/$source" \
    || fail "$source on $branch isn't the one in this checkout: update it (git pull) and look at what changed."
done
build_signing_tool . "$work"

todo=()
for list in "${SIGNED_LISTS[@]}"; do
  if [ ${#add[@]} -eq 0 ] && "$TOOL" verify "$tree/$list" > /dev/null 2>&1; then
    echo "✓ $list is signed already."
  else
    todo+=("$list")
  fi
done
[ ${#todo[@]} -gt 0 ] || { echo "Nothing to sign."; exit 0; }

# The app takes no list older than the one it has, by its "generated" stamp: a list that changed
# needs a newer one than main's, or every Nightforge would turn it away. And none from the future: once
# taken, it would turn away the right lists after it (review N5).
# Both by the app's own rules, through the tool built from its Signature.swift: as dates, an offset
# or a day alone included, so the script never signs what every Nightforge would turn away.
stamp() { plutil -extract generated raw -o - "$1" 2>/dev/null || true; }
for list in "${todo[@]}"; do
  status=0
  "$TOOL" ahead "$tree/$list" || status=$?
  case "$status" in
    0) fail "$list has \"generated\" $(stamp "$tree/$list"), more than a day ahead: fix the clock or the stamp first." ;;
    2) fail "$list has no \"generated\" date Nightforge can read ($(stamp "$tree/$list"))." ;;
  esac
done
for list in "${todo[@]}"; do
  if [ "$branch" = main ]; then
    # On main itself: the list as it was when it was last signed, the commit that last changed its .sig
    # (review E). Never signed yet: nothing to compare with.
    ref="$(git -C "$tree" log -1 --format=%H -- "$list.sig")" before="the last signed one"
    [ -n "$ref" ] || continue
  else
    ref=origin/main before="main's"
  fi
  git -C "$tree" cat-file -e "$ref:$list" 2>/dev/null || continue
  git -C "$tree" diff --quiet "$ref" HEAD -- "$list" && continue
  git -C "$tree" show "$ref:$list" > "$work/before-list"
  "$TOOL" newer "$tree/$list" "$work/before-list" \
    || fail "$list changed, but its \"generated\" ($(stamp "$tree/$list")) isn't newer than $before ($(stamp "$work/before-list")): Nightforge would turn it away."
done

echo "▸ Signing what $branch holds now:"
git -C "$tree" log -1 --format='  %h %s (%an, %ar)'
for list in "${todo[@]}"; do
  echo "  $list  sha256 $(shasum -a 256 "$tree/$list" | cut -c1-16)…  $(git -C "$tree" diff --shortstat origin/main -- "$list" 2>/dev/null | sed 's/^ *//')"
done
echo "▸ macOS asks for your password now: click Allow."
paths=()
for list in "${todo[@]}"; do paths+=("$tree/$list"); done
read_private_key | "$TOOL" sign ${add[@]+"${add[@]}"} "${paths[@]}"
forget_clipboard
"$TOOL" verify "${paths[@]}" > /dev/null

for list in "${todo[@]}"; do git -C "$tree" add "$list.sig"; done
git -C "$tree" -c core.hooksPath=/dev/null commit --quiet -m "Sign the online lists" -m "$(cd "$tree" && shasum -a 256 "${todo[@]}")"
# A plain push: when the branch moved on meanwhile (a nightly run), this signature is for an old
# list and GitHub turns it away.
git -C "$tree" -c core.hooksPath=/dev/null push --quiet origin "HEAD:refs/heads/$branch" \
  || fail "$branch changed meanwhile (the nightly run?). Read the new state and run this again."
echo "✓ Signed and pushed to $branch: $(git -C "$tree" rev-parse --short HEAD)."
if [ "$branch" != main ]; then
  echo "  Merge the pull request once its \"Signatures\" check is green; merge exactly this commit:"
  echo "    gh pr merge $branch --merge --match-head-commit $(git -C "$tree" rev-parse HEAD)"
fi
