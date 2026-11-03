#!/bin/bash
# For a live test before KosmicKrisp has a release: puts a local build in place as if Nightforge
# had downloaded it, and adds it and upstream DXVK to the cached component list.
#
#   tests/kosmickrisp/stage-live-test.sh <nightforge-kosmickrisp-….tar.gz>
#   tests/kosmickrisp/stage-live-test.sh --undo
#
# Only for a test build whose Info.plist has NightforgeManifestURL set to "" – any other Nightforge
# fetches the online list at start and drops both entries again. The list as it was is kept as
# manifest.before-kosmickrisp.json; --undo puts it back (the next start then removes KosmicKrisp and
# upstream DXVK and gives the prefix DXVK-macOS's d3d9 again). Quit Nightforge first.
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
COMPONENTS="$HOME/Library/Application Support/Nightforge/Components"
MANIFEST="$COMPONENTS/manifest.json"
BACKUP="$COMPONENTS/manifest.before-kosmickrisp.json"

if [ "${1:-}" = "--undo" ]; then
  [ -f "$BACKUP" ] || { echo "no $BACKUP – nothing to undo" >&2; exit 1; }
  mv "$BACKUP" "$MANIFEST"
  echo "component list restored"
  exit 0
fi

ARCHIVE="$(cd "$(dirname "${1:?usage: $0 <archive> | --undo}")" && pwd -P)/$(basename "$1")"
NAME="$(basename "$ARCHIVE" .tar.gz)"
VERSION="${NAME#nightforge-kosmickrisp-}"
[ "$VERSION" != "$NAME" ] || { echo "not a nightforge-kosmickrisp archive: $ARCHIVE" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "no component list at $MANIFEST – start Nightforge once first" >&2; exit 1; }
SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
SIZE="$(stat -f %z "$ARCHIVE")"

# Unpacked the way ComponentStore.install leaves it: the archive's folder in <id>/<version>,
# and .sha256 (without a line break) saying which download it is.
TARGET="$COMPONENTS/kosmickrisp/$VERSION"
rm -rf "$TARGET"
mkdir -p "$TARGET"
tar -xzf "$ARCHIVE" -C "$TARGET"
printf '%s' "$SHA" > "$TARGET/.sha256"

[ -f "$BACKUP" ] || cp "$MANIFEST" "$BACKUP"
python3 -I - "$MANIFEST" "$here/../../components/manifest.json" "$VERSION" "$SHA" "$SIZE" "$NAME" <<'PY'
import json, sys
path, repo_manifest, version, sha, size, name = sys.argv[1:]
manifest = json.load(open(path))
dxvk = next(c for c in json.load(open(repo_manifest))["components"] if c["id"] == "dxvk")
kosmickrisp = {
    "id": "kosmickrisp", "kind": "graphics", "version": version,
    # Never fetched: the folder above is already there. The release it will come from.
    "url": f"https://github.com/LordHayne/Nightforge/releases/download/kosmickrisp-{version}/{name}.tar.gz",
    "sha256": sha, "size": int(size), "license": "MIT AND Apache-2.0", "source": "https://github.com/LordHayne/Nightforge",
}
components = [c for c in manifest["components"] if c["id"] not in ("kosmickrisp", "dxvk")]
manifest["components"] = components + [kosmickrisp, dxvk]
with open(path, "w") as out:
    json.dump(manifest, out, indent=2)
    out.write("\n")
PY
echo "KosmicKrisp $VERSION in $TARGET, list: kosmickrisp + dxvk $(python3 -I -c 'import json,sys; print(next(c["version"] for c in json.load(open(sys.argv[1]))["components"] if c["id"] == "dxvk"))' "$MANIFEST")"
