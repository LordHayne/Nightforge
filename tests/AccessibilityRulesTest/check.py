"""A button that shows only a symbol has no words of its own for VoiceOver, so it says
`.accessibilityLabel`. A tooltip (`.help`) isn't one: VoiceOver treats it as a hint, and every other such button in
Nightforge has both. Toggles and pickers with hidden labels are the same case."""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / "tests/Shared"))
from swift_views import controls

WORDS = re.compile(r'\bText\(|\bLabel\(|\bSectionTitle\(|\bHint\(|Button\(\s*("|L10n|\w+\.\w+\(|\w+\s*[,)])')
problems = []
found = controls(root)
for control in found:
    body = control.body
    if ".accessibilityLabel" in body:
        continue
    if control.kind == "Button" and "Image(" in body and not WORDS.search(body):
        problems.append(f"{control}\n    a button with only a symbol: give it .accessibilityLabel")
    if control.kind in ("Toggle", "Picker") and ".labelsHidden" in body and not re.search(r'(Toggle|Picker)\(\s*(L10n|"[^"]|\w+[,)])', body):
        problems.append(f"{control}\n    hidden label and no name: give it .accessibilityLabel")

for problem in problems:
    print("✗ " + problem)
if problems:
    print(f"{len(problems)} problem(s)")
    sys.exit(1)
print(f"✓ Accessibility rules ({len(found)} controls)")
