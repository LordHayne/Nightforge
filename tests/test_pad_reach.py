"""Controller-only (the user's decision 1 for 0.4, 22.11.2026): what Nightforge shows itself can be reached and
left with the pad. Read from the sources, so a field or a sheet added later is held to it too (docs/ENTWURF-PAD-ONLY.md).

- Every text field takes the pad's highlight (`.padFocus`), so A puts the cursor in it. The library's search is the
  one exception: Y opens the pad's own keyboard there (InputRouter.openKeyboard).
- Every sheet closes with B: B sends Esc to it (InputRouter.press), and only a control with `.cancelAction` takes
  Esc in a SwiftUI sheet. GlassDialog and GlassQuestion bring their × with it (GlassCloseButton), Settings its header.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = sorted((ROOT / "Sources/Nightforge").glob("*.swift"))
CLOSES = ("GlassDialog(", "GlassQuestion(", "GlassDialogHeader(", ".keyboardShortcut(.cancelAction)")
# The search field: Y opens the pad keyboard over it, B leaves it (onExitCommand).
TEXT_FIELD_EXCEPTIONS = {("LibraryGrid.swift", "$model.searchText")}


def code(line):
    return line.split("//", 1)[0]


def chain(lines, start):
    """The lines of the expression starting at `start`: its body and the modifiers after it, up to the next
    statement at the same indent or one further out."""
    indent = len(lines[start]) - len(lines[start].lstrip())
    taken = [lines[start]]
    for line in lines[start + 1:start + 40]:
        text = line.strip()
        if not text or text.startswith("//"):
            continue
        here = len(line) - len(line.lstrip())
        if here < indent or (here == indent and not text.startswith((".", "}", ")"))):
            break
        taken.append(line)
    return "\n".join(taken)


def struct_body(name):
    """The source of `struct <name>` up to the next top-level declaration."""
    for source in SOURCES:
        text = source.read_text()
        found = re.search(r"^(?:private |fileprivate )?struct " + re.escape(name) + r"\b", text, re.M)
        if not found:
            continue
        rest = text[found.end():]
        end = re.search(r"^(?:private |fileprivate )?(?:struct|enum|final class|class|extension) ", rest, re.M)
        return rest[:end.start()] if end else rest
    return None


class PadReachTests(unittest.TestCase):
    def test_every_text_field_takes_the_highlight(self):
        missing = []
        for source in SOURCES:
            lines = source.read_text().split("\n")
            for number, line in enumerate(lines):
                # GlassTextField brings its own highlight; its TextField inside is checked where it stands.
                if not re.search(r"(?<![A-Za-z])TextField\(", code(line)):
                    continue
                if any(source.name == name and binding in line for name, binding in TEXT_FIELD_EXCEPTIONS):
                    continue
                if ".padFocus(" not in chain(lines, number):
                    missing.append(f"{source.name}:{number + 1}")
        self.assertEqual(missing, [], "text fields the pad can't reach")

    def test_every_sheet_closes_with_b(self):
        sheets = 0
        for source in SOURCES:
            lines = source.read_text().split("\n")
            for number, line in enumerate(lines):
                if ".sheet(" not in code(line):
                    continue
                sheets += 1
                body = chain(lines, number)
                if any(mark in body for mark in CLOSES):
                    continue
                views = [name for name in re.findall(r"\b([A-Z][A-Za-z]+)\(", body)
                         if name not in {"Binding", "DialogMessage"} and struct_body(name) is not None]
                self.assertTrue(views, f"{source.name}:{number + 1}: no view found in the sheet")
                self.assertTrue(any(mark in struct_body(views[0]) for mark in CLOSES),
                                f"{source.name}:{number + 1}: {views[0]} has nothing that takes Esc, so B doesn't close it")
        self.assertGreater(sheets, 15, "the sheets were found")

    def test_the_exception_is_still_the_search(self):
        grid = (ROOT / "Sources/Nightforge/LibraryGrid.swift").read_text()
        self.assertIn("$model.searchText", grid)
        self.assertIn(".onExitCommand", grid)


if __name__ == "__main__":
    unittest.main()
