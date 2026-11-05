#!/bin/bash
# Makes Nightforge's two signing keys. Run it yourself, in Terminal:
#
#   scripts/make-signing-keys.sh                    both keys, once
#   scripts/make-signing-keys.sh --replace main     a new main key, when the old one is lost
#   scripts/make-signing-keys.sh --replace spare    a new spare key, when the old one may be exposed
#   --spare-file PATH                               the spare key into a file (say on a USB stick)
#                                                   instead of the clipboard
#
# The main key goes into your login Keychain as "Nightforge signing key". Whenever a script signs with
# it, macOS asks for your password: click "Allow", not "Always Allow". The spare key never stays on
# this Mac: it goes to the clipboard for your password manager (or into the file you name), you copy
# it back once so the script can check it arrived whole, and the clipboard is emptied. Neither private
# key is shown, written into the repository or put on a command line. The public halves go into
# Sources/Nightforge/SigningKeys.swift, which you commit (nothing secret in it).
# docs/SICHERHEIT-0.3.md › Signierte Releases tells the whole story.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/signing-lib.sh

KEYS_FILE="Sources/Nightforge/SigningKeys.swift"

fail() { echo "✗ $*" >&2; exit 1; }
usage() { echo "usage: $0 [--replace main|spare] [--spare-file PATH]" >&2; exit 2; }

replace=""
spare_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --replace) [ $# -ge 2 ] || usage; replace="$2"; shift 2 ;;
    --spare-file) [ $# -ge 2 ] || usage; spare_file="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# It asks you things and shows nothing worth logging: not for scripts or other sessions.
[ -t 0 ] || fail "Run this yourself in Terminal: it asks you a few things on the way."

current() { sed -nE "s/^    static let $1 = \"([^\"]*)\"$/\1/p" "$KEYS_FILE"; }
have_main="$(current main)"
have_spare="$(current spare)"
case "$replace" in
  "")
    [ -z "$have_main$have_spare" ] || fail "$KEYS_FILE has keys already. To swap one: --replace main or --replace spare."
    make_main=1 make_spare=1 ;;
  main)
    [ -n "$have_spare" ] || fail "There's no spare key yet: run the script without --replace first."
    make_main=1 make_spare=0 ;;
  spare)
    [ -n "$have_main" ] || fail "There's no main key yet: run the script without --replace first."
    make_main=0 make_spare=1 ;;
  *) usage ;;
esac

if [ -n "$spare_file" ]; then
  [ "$make_spare" = 1 ] || fail "--spare-file is for a new spare key."
  [ ! -e "$spare_file" ] || fail "$spare_file is there already."
  folder="$(cd "$(dirname "$spare_file")" 2>/dev/null && pwd -P)" || fail "The folder for $spare_file isn't there."
  case "$folder/" in "$(pwd -P)"/*) fail "Not into the repository: the spare key mustn't end up on GitHub." ;; esac
fi

if [ -n "$replace" ]; then
  if [ "$replace" = main ]; then
    echo "A new main key replaces the one in your Keychain. Installed copies of Nightforge only know the"
    echo "old one and the spare, so the next releases and lists need the spare's signature as well."
  else
    echo "A new spare key replaces the old one. Copies of Nightforge older than the next release keep"
    echo "trusting the old spare: delete it from your password manager only after that release is out."
  fi
  read -r -p "Type replace to go on: " answer
  [ "$answer" = "replace" ] || fail "Nothing changed."
fi

work="$(mktemp -d)"
trap 'rm -rf -- "${work:?}"' EXIT
echo "▸ Building the signing tool …"
build_signing_tool . "$work"

if [ "$make_main" = 1 ]; then
  main_secret="$("$TOOL" generate)"
  main_public="$(printf '%s' "$main_secret" | "$TOOL" public)"
  # The new key goes in beside the old one first, under a name of its own, and is read back; only then does the
  # old one (the lost key's, or an earlier attempt's) give way to it (review A7). A Keychain that refuses halfway
  # leaves the old key or the new one, never neither.
  staged="$SIGNING_SERVICE.new"
  printf 'delete-generic-password -a %s -s %s\n' "$SIGNING_ACCOUNT" "$staged" | security -i > /dev/null 2>&1 || true
  # `security -i` reads its command from the pipe, so the key never stands on a command line.
  # -T "": no program may read it without asking you first.
  printf 'add-generic-password -a %s -s %s -l "Nightforge signing key (new)" -T "" -w %s\n' \
    "$SIGNING_ACCOUNT" "$staged" "$main_secret" | security -i > /dev/null 2>&1 \
    || fail "The Keychain didn't take the main key. Nothing changed, in the Keychain or in $KEYS_FILE."
  echo "▸ Reading it back to check: macOS asks for your password now. Click Allow (not Always Allow)."
  [ "$(security find-generic-password -s "$staged" -a "$SIGNING_ACCOUNT" -w 2>/dev/null | "$TOOL" public)" = "$main_public" ] \
    || fail "The Keychain didn't give the new key back. The old key is as it was, nothing changed in $KEYS_FILE; run the script again."
  printf 'delete-generic-password -a %s -s %s\n' "$SIGNING_ACCOUNT" "$SIGNING_SERVICE" | security -i > /dev/null 2>&1 || true
  printf 'add-generic-password -a %s -s %s -l "Nightforge signing key" -T "" -w %s\n' \
    "$SIGNING_ACCOUNT" "$SIGNING_SERVICE" "$main_secret" | security -i > /dev/null 2>&1 \
    || fail "The Keychain didn't take the main key under its own name. It's safe as \"$staged\" in Keychain Access; nothing changed in $KEYS_FILE."
  unset main_secret
  echo "▸ Reading it back once more, under its own name: macOS asks again. Click Allow (not Always Allow)."
  [ "$(read_private_key | "$TOOL" public)" = "$main_public" ] \
    || fail "The Keychain didn't give the new key back. It's safe as \"$staged\" in Keychain Access; nothing changed in $KEYS_FILE."
  printf 'delete-generic-password -a %s -s %s\n' "$SIGNING_ACCOUNT" "$staged" | security -i > /dev/null 2>&1 || true
  echo "✓ The main key is in your Keychain (Keychain Access › login › \"Nightforge signing key\")."
fi

if [ "$make_spare" = 1 ]; then
  spare_secret="$("$TOOL" generate)"
  spare_public="$(printf '%s' "$spare_secret" | "$TOOL" public)"
  if [ -n "$spare_file" ]; then
    (umask 077 && printf '%s\n' "$spare_secret" > "$spare_file")
    [ "$("$TOOL" public < "$spare_file")" = "$spare_public" ] || fail "$spare_file didn't keep the key."
    echo "✓ The spare key is in $spare_file. Keep it away from this Mac: a USB stick in a drawer, or print it and delete the file."
  else
    printf '%s' "$spare_secret" | pbcopy
    echo "▸ The spare key is on the clipboard now (it isn't shown anywhere)."
    echo "  Paste it into a new entry of your password manager, name it \"Nightforge spare key\" and save it."
    read -r -p "  Press Return once it's saved. " _
    pbcopy < /dev/null
    while :; do
      echo "▸ To check it arrived whole: copy it from your password manager once more."
      read -r -p "  Press Return when it's on the clipboard (Ctrl-C stops; nothing is changed yet). " _
      if [ "$(pbpaste | "$TOOL" public 2>/dev/null)" = "$spare_public" ]; then
        pbcopy < /dev/null
        echo "✓ Your password manager has the spare key. The clipboard is empty again."
        break
      fi
      pbcopy < /dev/null
      echo "✗ That isn't the spare key. See whether the entry has all 44 characters, then try again."
    done
  fi
  unset spare_secret
fi

[ "$make_main" = 0 ] || sed -i '' -E "s|^(    static let main = )\"[^\"]*\"$|\1\"$main_public\"|" "$KEYS_FILE"
[ "$make_spare" = 0 ] || sed -i '' -E "s|^(    static let spare = )\"[^\"]*\"$|\1\"$spare_public\"|" "$KEYS_FILE"
{ [ "$make_main" = 0 ] || [ "$(current main)" = "$main_public" ]; } && { [ "$make_spare" = 0 ] || [ "$(current spare)" = "$spare_public" ]; } \
  || fail "$KEYS_FILE didn't take the public keys."

echo "✓ $KEYS_FILE has the public keys. Commit it – it holds nothing secret:"
echo "    git add $KEYS_FILE && git commit -m \"Signing keys\""
if [ "$replace" = main ]; then
  echo "  Sign the next releases and lists with both keys: first as usual, then once more with"
  echo "  --spare --add (scripts/sign-release.sh, scripts/sign-lists.sh)."
fi
