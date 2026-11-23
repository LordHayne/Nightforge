#!/bin/bash
# Builds Nightforge.app. With --install it is copied to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

# The Command Line Tools ship without SwiftUI's macro plugins, so @State fails against the
# macOS 27 SDK. Without Xcode, fall back to the 26.5 SDK they still include.
# shellcheck source=scripts/sdk-lib.sh
. scripts/sdk-lib.sh && nightforge_pick_sdk

APP="Nightforge"
# In a folder Spotlight leaves out (".noindex"): a test build in a worktree never shows up in Spotlight or Launchpad
# beside the installed Nightforge, and `open -b` doesn't pick it (22.11.2026: three Nightforges to choose from).
# Only ~/Applications/Nightforge.app (--install) and the release are apps to the Mac.
OUT="build/Nightforge.noindex/$APP.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "▸ Compiling (release, Apple Silicon) …"
# NIGHTFORGE_RELEASE=1 builds what goes out: without the test switches that record play (GameTest.measuresPlay).
swift build -c release --arch arm64 ${NIGHTFORGE_RELEASE:+-Xswiftc -DNIGHTFORGE_RELEASE}
BIN_DIR="$(swift build -c release --arch arm64 ${NIGHTFORGE_RELEASE:+-Xswiftc -DNIGHTFORGE_RELEASE} --show-bin-path)"

echo "▸ Building app bundle …"
rm -rf "$OUT"
# The two languages Nightforge speaks: empty .lproj folders let macOS show its own menus, panels
# and text-field menus in German on a German Mac (the app's own text comes from Strings.swift).
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/en.lproj" "$OUT/Contents/Resources/de.lproj"
cp "$BIN_DIR/$APP" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
# Offline fallback for the component list; the app prefers the online copy once it's published.
cp components/manifest.json "$OUT/Contents/Resources/manifest.json"
# Same for the per-game fixes (scripts/build-profiles.py).
cp profiles/profiles.json "$OUT/Contents/Resources/profiles.json"
# Licences travel with the app: Nightforge's own (GPL-3.0) and the ones for the fixes data.
cp LICENSE "$OUT/Contents/Resources/LICENSE"
cp profiles/LICENSE-umu-protonfixes "$OUT/Contents/Resources/LICENSE-umu-protonfixes"
cp profiles/LICENSE-areweanticheatyet "$OUT/Contents/Resources/LICENSE-areweanticheatyet"
# Apple's licence for D3DMetal, which the dialog shows before anything of Apple's is set up.
cp Resources/Apple-GPTK-License.rtf "$OUT/Contents/Resources/Apple-GPTK-License.rtf"
# What else is inside the app (Vulkan headers in the layer, the mingw runtime in the wrapper) and
# what Nightforge downloads, with their licences.
cp Resources/THIRD_PARTY_NOTICES.txt "$OUT/Contents/Resources/THIRD_PARTY_NOTICES.txt"
mkdir -p "$OUT/Contents/Resources/licenses"
cp wrapper/vulkan-headers/LICENSE.md "$OUT/Contents/Resources/licenses/Vulkan-Headers-LICENSE.md"
cp wrapper/vulkan-headers/Apache-2.0.txt wrapper/vulkan-headers/MIT.txt "$OUT/Contents/Resources/licenses/"

# Steam's browser needs this wrapper under Wine (see wrapper/steamwebhelper-wrapper.c).
# Rebuilt when mingw-w64 is installed, otherwise the checked-in build is used.
# (Built into the app bundle only; the checked-in binary is the one the GitHub workflow produces.)
MINGW="$(command -v x86_64-w64-mingw32-gcc || true)"
if [ -n "$MINGW" ]; then
  "$MINGW" -O2 -Wall -Wextra -municode -mwindows -static \
    -o "$OUT/Contents/Resources/steamwebhelper.exe" wrapper/steamwebhelper-wrapper.c
else
  # It stands in for Steam's own helper for every player, and a binary diff can't be read in a review:
  # only the build whose SHA-256 the workflow wrote beside it (a line that can) goes into the app.
  if ! (cd wrapper && shasum -a 256 -c -s steamwebhelper.exe.sha256); then
    echo "✗ wrapper/steamwebhelper.exe doesn't match wrapper/steamwebhelper.exe.sha256." >&2
    echo "  Install mingw-w64 (brew install mingw-w64) to build it from wrapper/steamwebhelper-wrapper.c." >&2
    exit 1
  fi
  cp wrapper/steamwebhelper.exe "$OUT/Contents/Resources/steamwebhelper.exe"
fi

# Presses "Play!" in Unity's configuration window for the games that show one (wrapper/unity-play.c,
# UnityDialog.swift). Built the same way; the checked-in build is the one unity-play.yml produces, and
# it runs in every player's Wine session while a binary diff can't be read in a review: only the build
# whose SHA-256 the workflow wrote beside it (a line that can) goes into the app.
if [ -n "$MINGW" ]; then
  "$MINGW" -O2 -Wall -Wextra -municode -mwindows -static \
    -o "$OUT/Contents/Resources/unity-play.exe" wrapper/unity-play.c
else
  if ! (cd wrapper && shasum -a 256 -c -s unity-play.exe.sha256); then
    echo "✗ wrapper/unity-play.exe doesn't match wrapper/unity-play.exe.sha256." >&2
    echo "  Install mingw-w64 (brew install mingw-w64) to build it from wrapper/unity-play.c." >&2
    exit 1
  fi
  cp wrapper/unity-play.exe "$OUT/Contents/Resources/unity-play.exe"
fi

# Presses the button a Windows game's question means, for A and B on the pad (wrapper/pad-answer.c,
# PadAnswerRun.swift). The same rule as above: only a build whose SHA-256 lies beside it. Until
# pad-answer.yml has produced one, a Mac without mingw-w64 makes an app without it, and the pad's A and
# B simply leave such a question to the touchpad.
if [ -n "$MINGW" ]; then
  "$MINGW" -O2 -Wall -Wextra -municode -mwindows -static \
    -o "$OUT/Contents/Resources/pad-answer.exe" wrapper/pad-answer.c
elif [ -f wrapper/pad-answer.exe ] && (cd wrapper && shasum -a 256 -c -s pad-answer.exe.sha256); then
  cp wrapper/pad-answer.exe "$OUT/Contents/Resources/pad-answer.exe"
else
  echo "▸ No pad-answer.exe yet: A and B won't answer a game's questions in this build."
fi

# Keeps the background Steam out of the Dock, gives Wine the network interfaces in an order Steam's
# sign-in finds the connected one in (wrapper/network-order.c), and holds the frame limit on D3DMetal
# (wrapper/d3dmetal-pace.m). x86_64, loaded into Wine processes.
# No framework linked: d3dmetal-pace.m opens Metal and QuartzCore in a process that has D3DMetal, and hide-steam-dock.m
# swaps AppKit's methods once Wine's Mac driver brought it – the processes without a window go without AppKit.
clang -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib -lobjc -Wall \
  -o "$OUT/Contents/Resources/hide-steam-dock.dylib" wrapper/hide-steam-dock.m wrapper/network-order.c \
  wrapper/d3dmetal-pace.m wrapper/d3dmetal-pace-rules.c

# Starts Wine inside a macOS sandbox when that's switched on (wrapper/nightforge-sandbox.c; x86_64
# like Wine, for hide-steam-dock.dylib, which reaches it through DYLD_INSERT_LIBRARIES).
clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall \
  -o "$OUT/Contents/Resources/nightforge-sandbox" wrapper/nightforge-sandbox.c

# Starts Steam, Wine, games and downloads apart from Nightforge, so a quit Nightforge leaves the Dock
# (wrapper/nightforge-helper.c; below also as a signed app that Nightforge copies out, see Detached.swift).
clang -arch arm64 -mmacosx-version-min=14.0 -O2 -Wall \
  -o "$OUT/Contents/Resources/nightforge-helper" wrapper/nightforge-helper.c
# The same helper as a finished app inside Nightforge, so codesign-app.sh signs it with Nightforge's
# certificate: macOS then knows it by that, and asks for a permission (removable volumes) only once
# instead of again after every build (8.11.). Nightforge copies it out at runtime (Detached.swift).
HELPER_APP="$OUT/Contents/Helpers/Nightforge Helper.app"
mkdir -p "$HELPER_APP/Contents/MacOS" "$HELPER_APP/Contents/Resources"
cp "$OUT/Contents/Resources/nightforge-helper" "$HELPER_APP/Contents/MacOS/nightforge-helper"
cat > "$HELPER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>nightforge-helper</string>
	<key>CFBundleIdentifier</key><string>io.github.lordhayne.nightforge.helper</string>
	<key>CFBundleName</key><string>Nightforge Helper</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>LSUIElement</key><true/>
	<key>NSMicrophoneUsageDescription</key><string>Voice chat in your games uses the microphone.</string>
</dict>
</plist>
PLIST

# Lets Windows games that render with Vulkan start on MoltenVK, and upscales them with MetalFX. Only Wine's
# Vulkan loader in the game bundle loads it, so x86_64 is the part that runs; the arm64 part is for later.
# Its MetalFX upscaling is Objective-C (wrapper/nightforge-vulkan-metalfx.m); MetalFX is weak-linked for older Macs.
clang -arch x86_64 -arch arm64 -mmacosx-version-min=11.0 -dynamiclib -fvisibility=hidden -fobjc-arc -O2 -Wall \
  -I wrapper/vulkan-headers -I wrapper -framework Metal -framework QuartzCore -framework CoreGraphics -weak_framework MetalFX \
  -o "$OUT/Contents/Resources/nightforge-vulkan-layer.dylib" wrapper/nightforge-vulkan-layer.c wrapper/nightforge-vulkan-metalfx.m

if [ -f Resources/AppIcon.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi
# The helper app shows Nightforge's icon too (assembled above, before the icon existed).
[ -f "$OUT/Contents/Resources/AppIcon.icns" ] && cp "$OUT/Contents/Resources/AppIcon.icns" "$HELPER_APP/Contents/Resources/"

# Nightforge's own code signing identity when there is one, else ad hoc (scripts/codesign-app.sh).
scripts/codesign-app.sh "$OUT"
# Known to LaunchServices once anything opened it: forgotten again – this one, and one left where builds went
# before (build/$APP.app; only forgotten, it stays where it is).
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$PWD/$OUT" >/dev/null 2>&1 || true
  [ -d "build/$APP.app" ] && { "$LSREGISTER" -u "$PWD/build/$APP.app" >/dev/null 2>&1 || true; }
fi
echo "✓ Done: $OUT"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  # `open` would only bring an already running copy to the front, so quit it first. Only when it
  # runs: AppleScript starts an app it is told to quit.
  if pgrep -qf "Applications/$APP.app/Contents/MacOS/$APP"; then
    osascript -e "tell application id \"io.github.lordhayne.nightforge\" to quit" >/dev/null 2>&1 || true
  fi
  pkill -f "$HOME/Applications/$APP.app/Contents/MacOS/$APP" 2>/dev/null || true
  rm -rf "$HOME/Applications/$APP.app"
  # Nightforge's earlier name: quit and replace it (its data moves over on first start).
  if pgrep -qf "Nachtschicht.app/Contents/MacOS/Nachtschicht"; then
    osascript -e 'tell application id "local.thomas.nachtschicht" to quit' >/dev/null 2>&1 || true
  fi
  pkill -f "$HOME/Applications/Nachtschicht.app/Contents/MacOS/Nachtschicht" 2>/dev/null || true
  rm -rf "$HOME/Applications/Nachtschicht.app"
  cp -R "$OUT" "$HOME/Applications/"
  echo "✓ Installed: ~/Applications/$APP.app"
  open "$HOME/Applications/$APP.app"
fi
