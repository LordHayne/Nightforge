"""The helper app exists in two places: the one build.sh assembles inside Nightforge (signed by codesign-app.sh,
copied out by Detached.swift) and the one Detached.swift makes itself on a Mac where that copy is missing. What
they say of themselves has to match, or the fallback's helper differs in identity, in a permission text
or in its name; and the three files have to agree on where it lies. Info.plist's version needs its release notes
in docs/release-notes/ (release.yml publishes only those)."""
import pathlib
import plistlib
import re
import sys

root = pathlib.Path(sys.argv[1])
build = (root / "build.sh").read_text()
sign = (root / "scripts/codesign-app.sh").read_text()
detached = (root / "Sources/Nightforge/Detached.swift").read_text()
problems = []

plist_text = re.search(r'cat > "\$HELPER_APP/Contents/Info.plist" <<\'PLIST\'\n(.*?)\nPLIST', build, re.S)
if not plist_text:
    problems.append("build.sh no longer writes the helper's Info.plist the way this test reads it")
else:
    built = plistlib.loads(plist_text.group(1).encode())
    made = {}
    for match in re.finditer(r'"(\w+)":\s*("([^"]*)"|true|false)', detached):
        key, value = match.group(1), match.group(2)
        if key.startswith(("CFBundle", "LS", "NS")):
            made[key] = match.group(3) if value.startswith('"') else value == "true"
    if built != made:
        different = sorted(k for k in set(built) | set(made) if built.get(k) != made.get(k))
        problems.append(f"the helper build.sh makes and the one Detached.swift makes differ in {different}: {built} vs {made}")
    if built.get("CFBundleExecutable") != "nightforge-helper":
        problems.append(f"the helper's program: {built.get('CFBundleExecutable')}")

helper = "Contents/Helpers/Nightforge Helper.app"
for name, text in (("build.sh", build), ("codesign-app.sh", sign)):
    if helper not in text:
        problems.append(f"{name} doesn't say {helper}: the helper wouldn't be signed or found")
if '"Nightforge Helper.app"' not in detached or 'Contents/Helpers/\\(helperName)' not in detached:
    problems.append("Detached.swift doesn't look for the helper at Contents/Helpers/Nightforge Helper.app any more")

info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
version = info.get("CFBundleShortVersionString", "")
notes = root / f"docs/release-notes/v{version}.md"
if not version or not notes.exists():
    problems.append(f"Info.plist says {version!r} and there's no {notes.relative_to(root)}: release.yml wouldn't publish notes")

for problem in problems:
    print("✗ " + problem)
if problems:
    print(f"{len(problems)} problem(s)")
    sys.exit(1)
print(f"✓ Build layout (helper app, release notes of {version})")
