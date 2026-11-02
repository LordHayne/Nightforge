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
# The branch is checked out into a folder of its own; your working copy isn't touched.
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
git fetch --quiet origin "refs/heads/$branch:refs/remotes/origin/$branch" || fail "origin has no branch $branch."
git worktree add --quiet --detach "$tree" "origin/$branch"
build_signing_tool "$tree" "$work"

todo=()
for list in "${SIGNED_LISTS[@]}"; do
  if [ ${#add[@]} -eq 0 ] && "$TOOL" verify "$tree/$list" > /dev/null 2>&1; then
    echo "✓ $list is signed already."
  else
    todo+=("$list")
  fi
done
[ ${#todo[@]} -gt 0 ] || { echo "Nothing to sign."; exit 0; }

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
git -C "$tree" commit --quiet -m "Sign the online lists" -m "$(cd "$tree" && shasum -a 256 "${todo[@]}")"
# A plain push: when the branch moved on meanwhile (a nightly run), this signature is for an old
# list and GitHub turns it away.
git -C "$tree" push --quiet origin "HEAD:refs/heads/$branch" \
  || fail "$branch changed meanwhile (the nightly run?). Read the new state and run this again."
echo "✓ Signed and pushed to $branch: $(git -C "$tree" rev-parse --short HEAD)."
if [ "$branch" != main ]; then
  echo "  Merge the pull request once its \"Signatures\" check is green; merge exactly this commit:"
  echo "    gh pr merge $branch --merge --match-head-commit $(git -C "$tree" rev-parse HEAD)"
fi
