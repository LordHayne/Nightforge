"""Finds SwiftUI controls and what's chained to them in Nightforge's sources, for the rules in
tests/ControllerRulesTest and tests/AccessibilityRulesTest. A small scanner, not a Swift parser: it knows
comments, strings, and bracket pairs, which is enough to tell a control's body and modifiers."""
import pathlib
import re


def blank_comments(text):
    """The text with // comments blanked, every position staying where it was."""
    out, i, in_string = [], 0, False
    while i < len(text):
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            if c in '"\n':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if text.startswith("//", i):
            while i < len(text) and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def pair_end(text, i):
    """The position after the bracket that closes the one at `i`."""
    closes = {"(": ")", "{": "}", "[": "]"}[text[i]]
    depth, in_string = 0, False
    while i < len(text):
        c = text[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c in '"\n':
                in_string = False
        elif c == '"':
            in_string = True
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def _skip_space(text, i, newlines=True):
    while i < len(text) and text[i] in (" \t\n" if newlines else " \t"):
        i += 1
    return i


def _trailing(text, i):
    """Past the trailing closures (`{ … }`, `label: { … }`) after `i`."""
    while True:
        j = _skip_space(text, i)
        if j < len(text) and text[j] == "{":
            i = pair_end(text, j)
            continue
        named = re.match(r"(label|icon|content)\s*:\s*\{", text[j:])
        if named:
            i = pair_end(text, j + named.end() - 1)
            continue
        return i


def _chain(text, i):
    """Past the `.modifier(…)` chain after `i`."""
    while True:
        j = _skip_space(text, i)
        modifier = re.match(r"\.\w+", text[j:])
        if not modifier:
            return i
        k = j + modifier.end()
        if k < len(text) and text[k] == "(":
            k = pair_end(text, k)
        while True:
            l = _skip_space(text, k, newlines=False)
            if l < len(text) and text[l] == "{":
                k = pair_end(text, l)
            else:
                break
        i = k


class Control:
    def __init__(self, file, line, kind, body):
        self.file, self.line, self.kind, self.body = file, line, kind, body

    @property
    def where(self):
        return f"{self.file}:{self.line}"

    def __repr__(self):
        return f"{self.where} {' '.join(self.body.split())[:120]}"


def controls(root, kinds=("Button", "Toggle", "Picker", "Menu")):
    """Every control of `kinds`, with its body and modifier chain."""
    found = []
    pattern = re.compile(r"\b(" + "|".join(kinds) + r")\b(?=\s*[\(\{])")
    for path in sorted(pathlib.Path(root).glob("Sources/Nightforge/*.swift")):
        text = blank_comments(path.read_text())
        for match in pattern.finditer(text):
            k = _skip_space(text, match.end())
            end = _chain(text, _trailing(text, pair_end(text, k)))
            found.append(Control(path.name, text[: match.start()].count("\n") + 1, match.group(1), text[match.start():end]))
    return found


def is_view_call(text, match_start):
    return not text[max(0, match_start - 1)] in ".\"\\"
