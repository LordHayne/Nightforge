"""What StringsTest doesn't look at: every text is a format as well. A wrong placeholder crashes Nightforge
(`%@` given a number reads it as a pointer) or shows "%@" to the player. So:
- each L10n.t("…", args) has as many arguments as placeholders, and of the right kind where that shows,
- L10n.t("…") without arguments has no placeholder and no "%%": it isn't formatted at all,
- the German text has the same placeholders as the English key (a bare "%" there is a placeholder too:
  "% f" is a float), in the same order or numbered,
- nothing the player reads is a bare English string in the views or toasts, which would stay English in German."""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
LITERAL = r'"((?:[^"\\\n]|\\.)*)"'
SPEC = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(ll|l|h|q|z|t)?([@dDiuUxXoOfeEgGcCsSp%])")
STRINGS = re.compile(r'(\.label|\.name|\.title|\.path|\.lastPathComponent|\.joined\(.*\)|Format\.\w+\(.*\)|^".*")$')
NUMBERS = re.compile(r"(\.count|^\d+|^Int\(.*\))$")
SOURCES = sorted((root / "Sources/Nightforge").glob("*.swift"))


def specs(text):
    return [(m.group(1), (m.group(2) or "") + m.group(3)) for m in SPEC.finditer(text) if m.group(3) != "%"]


def arguments(text, i):
    """The top-level arguments of the call whose first argument starts at `i`."""
    depth, args, current, in_string = 0, [], [], False
    while i < len(text):
        c = text[i]
        if in_string:
            current.append(c)
            if c == "\\":
                current.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                args.append("".join(current))
                return args
            depth -= 1
        elif c == "," and depth == 0:
            args.append("".join(current))
            current = []
            i += 1
            continue
        current.append(c)
        i += 1
    return args


problems, calls = [], 0
for path in SOURCES:
    text = path.read_text()
    for match in re.finditer(r"L10n\.t\(", text):
        where = f"{path.name}:{text[:match.start()].count(chr(10)) + 1}"
        args = arguments(text, match.end())
        literal = re.fullmatch(LITERAL, args[0].strip())
        if not literal:
            continue  # a text from a list; StringsTest covers those it can
        calls += 1
        key, rest = literal.group(1), args[1:]
        wanted = specs(key)
        if len(wanted) != len(rest):
            problems.append(f'{where}: "{key[:70]}" has {len(wanted)} placeholder(s) and {len(rest)} argument(s)')
        if not rest and "%" in key:
            problems.append(f'{where}: "{key[:70]}" isn\'t formatted without arguments, so the player sees the %')
        for (_, kind), arg in zip(wanted, rest):
            arg = arg.strip()
            if kind.endswith("@") and NUMBERS.search(arg):
                problems.append(f'{where}: "{key[:60]}" gives a number ({arg}) to %@: a crash')
            if not kind.endswith("@") and STRINGS.search(arg):
                problems.append(f'{where}: "{key[:60]}" gives text ({arg}) to %{kind}')

table = (root / "Sources/Nightforge/Strings.swift").read_text().split("private static let german: [String: String] = [", 1)[1]
entries = 0
for match in re.finditer(r"^\s*" + LITERAL + r"\s*:\s*" + LITERAL, table, re.M):
    key, german = match.group(1), match.group(2)
    entries += 1
    if not german.strip():
        problems.append(f'empty German for "{key[:70]}"')
    english, deutsch = specs(key), specs(german)
    numbered = any(position for position, _ in deutsch)
    if numbered:
        order = sorted(deutsch, key=lambda spec: int(spec[0] or 0))
        same = [kind for _, kind in order] == [kind for _, kind in english]
    else:
        same = deutsch == english
    if not same:
        problems.append(f'"{key[:60]}" → "{german[:60]}": other placeholders ({english} / {deutsch})')
    if key.count("%%") != german.count("%%"):
        problems.append(f'"{key[:60]}" → "{german[:60]}": a different number of "%%"')

def without_interpolations(text):
    r"""The text without its \( … ) parts, whatever's nested in them (the literal may be cut off inside one)."""
    out, i = [], 0
    while i < len(text):
        if text.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(text) and depth:
                depth += {"(": 1, ")": -1}.get(text[i], 0)
                i += 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


# Shown as it stands, whatever the language: words here belong in L10n.t. Interpolations, single tokens
# and these names are no text to translate.
NAMES = {"DEMO", "MAC", "esc", "Nightforge", "OK"}
VIEW = re.compile(r'\b(Text|Button|Label|Toggle|Section|Menu|Picker)\(\s*' + LITERAL
                  + r'|\.(help|accessibilityLabel|accessibilityHint|navigationTitle)\(\s*' + LITERAL
                  + r'|\bToasts\.shared\.show\(\s*' + LITERAL
                  + r'|\b(messageText|informativeText)\s*=\s*' + LITERAL)
raw = 0
for path in SOURCES:
    if path.name == "Strings.swift":
        continue
    for number, line in enumerate(path.read_text().split("\n"), 1):
        code = line.split("//", 1)[0]
        for match in VIEW.finditer(code):
            text = next(group for group in match.groups()[1:] if group is not None and group not in ("help", "accessibilityLabel", "accessibilityHint", "navigationTitle", "messageText", "informativeText"))
            if re.search(r"[A-Za-zÄÖÜäöü]{2,}", without_interpolations(text)) and text not in NAMES:
                raw += 1
                problems.append(f'{path.name}:{number}: "{text[:70]}" stays English in German: L10n.t, or add it to the names here')

for problem in problems:
    print("✗ " + problem)
if problems:
    print(f"{len(problems)} problem(s)")
    sys.exit(1)
if calls < 1000 or entries < 1000:
    print(f"✗ only {calls} calls and {entries} German texts found: did the scanner break?")
    sys.exit(1)
print(f"✓ String rules ({calls} calls, {entries} German texts)")
