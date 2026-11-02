"""Every text shown through L10n.t has a German entry, and the German table has no key twice
(a duplicate key crashes Nightforge at launch). A profile's "notYet" reason is shown through L10n.t
as well, so it needs its German entry too."""
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
sources = sorted(root.glob("Sources/Nightforge/*.swift"))
table_file = root / "Sources/Nightforge/Strings.swift"

# A Swift string literal: "…" with escapes, never across a line.
literal = r'"((?:[^"\\\n]|\\.)*)"'
used = {}
for path in sources:
    text = path.read_text()
    for match in re.finditer(r'L10n\.t\(\s*' + literal, text):
        used.setdefault(match.group(1), f"{path.name}:{text[:match.start()].count(chr(10)) + 1}")

table = table_file.read_text().split("private static let german: [String: String] = [", 1)[1]
keys = [m.group(1) for m in re.finditer(r'^\s*' + literal + r'\s*:', table, re.M)]
seen, duplicates = set(), []
for key in keys:
    if key in seen:
        duplicates.append(key)
    seen.add(key)

# Same in both languages: names and symbols that don't change.
same = {"OK", "Metascore", "GeForce Now", "Mac", "Windows", "HUD", "MetalFX", "Steam", "FPS", "Nightforge"}
missing = sorted((where, key) for key, where in used.items() if key not in seen and key not in same)

# Reasons in the profile lists (the key in Swift's escaping).
reasons = 0
for name in ("mac.json", "profiles.json"):
    for app_id, game in json.loads((root / "profiles" / name).read_text())["games"].items():
        reason = game.get("notYet")
        if not reason:
            continue
        reasons += 1
        key = reason.replace("\\", "\\\\").replace('"', '\\"')
        if key not in seen:
            missing.append((f"profiles/{name} {app_id}", key))

for key in duplicates:
    print(f"✗ twice in the German table: {key!r}")
for where, key in missing:
    print(f"✗ no German for {key!r} ({where})")
if duplicates or missing:
    print(f"{len(duplicates)} duplicate, {len(missing)} missing")
    sys.exit(1)
print(f"✓ Strings ({len(used)} texts and {reasons} profile reasons, all in German)")
