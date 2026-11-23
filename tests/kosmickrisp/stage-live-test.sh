#!/bin/bash
# For a live test of KosmicKrisp while the component list doesn't name it (held back since 9a6157e): puts
# a build in place as if Nightforge had downloaded it, and names it in a test build's own list.
#
#   tests/kosmickrisp/stage-live-test.sh <nightforge-kosmickrisp-….tar.gz> [app]
#   tests/kosmickrisp/stage-live-test.sh --undo [app]
#
# app: a test build, build/Nightforge.noindex/Nightforge.app unless named; an installed Nightforge is refused.
# The component lists are signed: an edited Components/manifest.json no longer counts, and the online list
# wins over the app's own. So the test build's own list names KosmicKrisp and carries today's stamp (the
# newer of the kept list and the app's own goes first, ComponentStore.newerFirst), and the build doesn't
# ask online (NightforgeManifestURL ""). A list that isn't signed removes no component.
# --undo removes KosmicKrisp and restores the test build. Quit Nightforge first.
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
repo="$(cd -- "$here/../.." && pwd -P)"
COMPONENTS="$HOME/Library/Application Support/Nightforge/Components"

undo=false
if [ "${1:-}" = "--undo" ]; then
  undo=true
  shift
else
  ARCHIVE="$(cd "$(dirname "${1:?usage: $0 <archive> [app] | --undo [app]}")" && pwd -P)/$(basename "$1")"
  shift
fi
APP="${1:-$repo/build/Nightforge.noindex/Nightforge.app}"
BACKUP="$APP.before-kosmickrisp"
LIST="$APP/Contents/Resources/manifest.json"
INFO="$APP/Contents/Info.plist"

if $undo; then
  rm -rf "$COMPONENTS/kosmickrisp"
  if [ -f "$BACKUP/manifest.json" ] && [ -f "$LIST" ]; then
    cp "$BACKUP/manifest.json" "$LIST"
    plutil -replace NightforgeManifestURL -string "$(cat "$BACKUP/manifest-url.txt")" "$INFO"
    "$repo/scripts/codesign-app.sh" "$APP"
  fi
  rm -rf "$BACKUP"
  echo "KosmicKrisp removed, test build restored"
  exit 0
fi

[ -f "$LIST" ] || { echo "no test build at $APP – run ./build.sh first" >&2; exit 1; }
[ "$(basename "$(dirname "$(cd "$APP" && pwd -P)")")" != "Applications" ] \
  || { echo "$APP is an installed Nightforge: this is for a test build" >&2; exit 1; }
NAME="$(basename "$ARCHIVE" .tar.gz)"
VERSION="${NAME#nightforge-kosmickrisp-}"
[ "$VERSION" != "$NAME" ] || { echo "not a nightforge-kosmickrisp archive: $ARCHIVE" >&2; exit 1; }
[ -d "$COMPONENTS" ] || { echo "no $COMPONENTS – start Nightforge once first" >&2; exit 1; }
SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
SIZE="$(stat -f %z "$ARCHIVE")"

# Unpacked the way ComponentStore.install leaves it: the archive's folder in <id>/<version>,
# and .sha256 (without a line break) saying which download it is.
TARGET="$COMPONENTS/kosmickrisp/$VERSION"
rm -rf "$TARGET"
mkdir -p "$TARGET"
tar -xzf "$ARCHIVE" -C "$TARGET"
printf '%s' "$SHA" > "$TARGET/.sha256"

if [ ! -d "$BACKUP" ]; then
  mkdir -p "$BACKUP"
  cp "$LIST" "$BACKUP/manifest.json"
  /usr/libexec/PlistBuddy -c 'Print :NightforgeManifestURL' "$INFO" > "$BACKUP/manifest-url.txt"
fi
python3 -I - "$LIST" "$repo/components/manifest.json" "$VERSION" "$SHA" "$SIZE" "$NAME" <<'PY'
import json, sys, time
path, repo_manifest, version, sha, size, name = sys.argv[1:]
manifest = json.load(open(path))
kosmickrisp = {
    "id": "kosmickrisp", "kind": "graphics", "version": version,
    # Never fetched: the folder above is already there. The release it comes from.
    "url": f"https://github.com/LordHayne/Nightforge/releases/download/kosmickrisp-{version}/{name}.tar.gz",
    "sha256": sha, "size": int(size), "license": "MIT AND Apache-2.0", "source": "https://github.com/LordHayne/Nightforge",
}
components = [c for c in manifest["components"] if c["id"] != "kosmickrisp"] + [kosmickrisp]
if not any(c["id"] == "dxvk" for c in components):
    components.append(next(c for c in json.load(open(repo_manifest))["components"] if c["id"] == "dxvk"))
manifest["components"] = components
manifest["generated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
with open(path, "w") as out:
    json.dump(manifest, out, indent=2)
    out.write("\n")
PY
plutil -replace NightforgeManifestURL -string "" "$INFO"
"$repo/scripts/codesign-app.sh" "$APP"
echo "KosmicKrisp $VERSION in $TARGET, named in $LIST"
