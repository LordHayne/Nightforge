"""Every font size in Nightforge's views goes through `.font(size:)` or `.displayFont(_:)`, so
"Larger text" reaches it. A fixed `.system(size:)`, `Theme.display(n)` or a text style (`.caption`,
`.body`, … are fixed sizes on macOS too) outside Accessibility.swift fails."""
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
helper = "Accessibility.swift"
# Theme.swift defines the display face that `.displayFont(_:)` scales.
allowed = {helper: None, "Theme.swift": "static func display("}

fixed = [
    (re.compile(r'\.system\(\s*size:'), ".font(size:)"),
    (re.compile(r'\bFont\.system\('), ".font(size:)"),
    (re.compile(r'Theme\.display\('), ".displayFont(_:)"),
    (re.compile(r'\.font\(\s*\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)\b'),
     ".font(size:)"),
    (re.compile(r'NSFont\.(systemFont|boldSystemFont|monospacedDigitSystemFont)\(ofSize:'), ".font(size:)"),
]

problems = []
uses = 0
for path in sorted(root.glob("Sources/Nightforge/*.swift")):
    if path.name == helper:
        continue
    for number, line in enumerate(path.read_text().split("\n"), 1):
        code = line.split("//", 1)[0]
        uses += len(re.findall(r'\.font\(size:|\.displayFont\(', code))
        if allowed.get(path.name) and allowed[path.name] in code:
            continue
        for pattern, instead in fixed:
            if pattern.search(code):
                problems.append(f"{path.name}:{number}: {line.strip()}\n    a fixed size – use {instead} ({helper}), "
                                "so “Larger text” makes it larger (`scales: false` for a symbol that belongs to a drawing)")
                break

for problem in problems:
    print("✗ " + problem)
if problems:
    print(f"{len(problems)} fixed font size(s)")
    sys.exit(1)
if uses < 100:
    print(f"✗ only {uses} uses of .font(size:)/.displayFont – did the helper move?")
    sys.exit(1)
print(f"✓ Text scale ({uses} font sizes, all through “Larger text”)")
