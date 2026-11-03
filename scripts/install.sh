#!/bin/bash
# Installs or updates Nightforge from its newest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/LordHayne/Nightforge/main/scripts/install.sh | bash
#
# Downloaded this way the app carries no quarantine flag, so macOS opens it without the
# "can't be verified" detour (Nightforge is free and not registered with Apple).
# For testing: NIGHTFORGE_ZIP (a local zip), NIGHTFORGE_INSTALL_DIR, NIGHTFORGE_APPLICATIONS (in place of
# /Applications; HOME stands in for the home folder), NIGHTFORGE_NO_QUIT (leaves a running Nightforge alone),
# NIGHTFORGE_QUIT_WAIT (seconds to wait for it to quit, 15) and NIGHTFORGE_NO_OPEN.
set -euo pipefail

REPO="LordHayne/Nightforge"
APP="Nightforge.app"
APPLICATIONS="${NIGHTFORGE_APPLICATIONS:-/Applications}"

fail() { echo "✗ $*" >&2; exit 1; }

# Whether the app with bundle ID $1 runs. Asked by its ID, not by its path in some command line: a tail, grep
# or debugger with that path in its arguments isn't the app. Asking doesn't start it; an ID nothing has is "no".
app_running() {
  [ "$(osascript -e "application id \"$1\" is running" 2>/dev/null)" = "true" ]
}

# Quits an app only when it runs (AppleScript would start one it is told to quit), and waits until it has ended:
# its bundle is replaced right after. One that stays stops the install, with nothing replaced.
quit_running() {
  app_running "$1" || return 0
  osascript -e "tell application id \"$1\" to quit" >/dev/null 2>&1 || true
  local waited=0
  while app_running "$1"; do
    [ "$waited" -lt "${NIGHTFORGE_QUIT_WAIT:-15}" ] || fail "$2 didn't quit. Quit it yourself, then run this again."
    sleep 1
    waited=$((waited + 1))
  done
}

# An update replaces the copy that is there, in its folder: a second one elsewhere would leave the old
# version to whatever Spotlight or the Dock opens. With a copy in both folders the one opened last wins,
# by the date the Finder shows as "Last opened"; with neither date (never opened, Spotlight off) the one in
# /Applications, where a fresh Mac gets it. A copy in a folder this user can't write to can't be replaced.
install_target() {
  local dir name date best="" best_date=""
  for dir in "$APPLICATIONS" "$HOME/Applications"; do
    for name in "$APP" Nachtschicht.app; do
      [ -d "$dir/$name" ] && [ -w "$dir" ] || continue
      date="$(mdls -raw -name kMDItemLastUsedDate "$dir/$name" 2>/dev/null || true)"
      [ "$date" = "(null)" ] && date=""
      # The dates read "2026-11-02 21:15:04 +0000", so a later one sorts after an earlier one.
      if [ -z "$best" ] || [[ "$date" > "$best_date" ]]; then
        best="$dir"
        best_date="$date"
      fi
    done
  done
  if [ -n "$best" ]; then
    echo "$best"
  elif [ -w "$APPLICATIONS" ]; then
    echo "$APPLICATIONS"
  else
    echo "$HOME/Applications"
  fi
}

# Everything runs from here, called on the script's last line: a download cut short by `curl | bash`
# then runs nothing at all instead of half the steps.
main() {
  [ "$(uname -s)" = "Darwin" ] || fail "Nightforge runs on macOS only."
  [ "$(uname -m)" = "arm64" ] || fail "Nightforge needs a Mac with Apple silicon (M1 or newer)."
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 26 ] || fail "Nightforge needs macOS 26 Tahoe or newer."

  target="${NIGHTFORGE_INSTALL_DIR:-$(install_target)}"
  mkdir -p "$target"

  work="$(mktemp -d)"
  trap 'rm -rf -- "${work:?}"' EXIT

  if [ -n "${NIGHTFORGE_ZIP:-}" ]; then
    cp "$NIGHTFORGE_ZIP" "$work/Nightforge.zip"
  else
    echo "▸ Looking for the newest version …"
    # `|| true`: with pipefail, no match (offline, rate limit) would end the script without a word.
    url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | grep -o '"browser_download_url": *"[^"]*Nightforge-[^"]*\.zip"' | head -1 | cut -d'"' -f4 || true)"
    [ -n "$url" ] || fail "No release found. Check your internet connection and try again."
    echo "▸ Downloading ${url##*/} …"
    curl -fL --progress-bar -o "$work/Nightforge.zip" "$url"
  fi

  ditto -x -k "$work/Nightforge.zip" "$work/unpacked"
  [ -d "$work/unpacked/$APP" ] || fail "The download is incomplete. Please try again."

  # Quit a running copy so it can be replaced.
  if [ -z "${NIGHTFORGE_NO_QUIT:-}" ]; then
    quit_running io.github.lordhayne.nightforge Nightforge
    # Nightforge's earlier name: replaced by this install (its data moves over on first start).
    quit_running local.thomas.nachtschicht Nachtschicht
  fi

  rm -rf -- "${target:?}/$APP" "${target:?}/Nachtschicht.app"
  ditto "$work/unpacked/$APP" "$target/$APP"
  xattr -dr com.apple.quarantine "$target/$APP" 2>/dev/null || true

  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
  echo "✓ Nightforge $version installed in $target"
  for other in "$APPLICATIONS" "$HOME/Applications"; do
    if [ "$other" != "$target" ] && [ -d "$other/$APP" ]; then
      echo "  An older copy is still in $other. It stays as it was; you can move it to the Bin."
    fi
  done
  [ -n "${NIGHTFORGE_NO_OPEN:-}" ] || open "$target/$APP"
}

main "$@"
