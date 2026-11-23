#!/bin/bash
# Everything that keeps a bad update off the Mac, before Nightforge swaps itself: a copy of the test program as a
# made-up Nightforge.app, a made-up GitHub, zips signed with a key of the test's own. No swap and no restart happen:
# tests/UpdaterInstallTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk
WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK"; rm -rf "$WORK"' EXIT
OUT="$WORK/updater-install-test"
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/Shared/TestDefaults.swift tests/UpdaterInstallTest/main.swift
mkdir -p "$WORK/home" "$WORK/tmp"

# A Nightforge.app around the test program, in `$1`.
make_app() {
  mkdir -p "$1/Nightforge.app/Contents/MacOS"
  cp "$OUT" "$1/Nightforge.app/Contents/MacOS/Nightforge"
  cat > "$1/Nightforge.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>test.nightforge.updater</string>
<key>CFBundleExecutable</key><string>Nightforge</string>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
</dict></plist>
PLIST
}
ROOT="$PWD"
run() { (cd "$ROOT" && env HOME="$WORK/home" CFFIXED_USER_HOME="$WORK/home" TMPDIR="$WORK/tmp/" "$1/Nightforge.app/Contents/MacOS/Nightforge" "$2"); }

make_app "$WORK/Apps"
run "$WORK/Apps" normal

make_app "$WORK/Locked"
chmod 555 "$WORK/Locked"
run "$WORK/Locked" locked
chmod 755 "$WORK/Locked"

make_app "$WORK/AppTranslocation/X/d"
run "$WORK/AppTranslocation/X/d" translocated
