"""Engine.swift names Wine's processor-dependent folders only through WineFolders, so an engine for another
processor is one change. Comments may still spell them out; what's on disk is checked by EngineLayoutTest."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def code_lines(path):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        code = re.split(r"\s//\s", line, maxsplit=1)[0]
        if not code.lstrip().startswith("//"):
            yield number, code


class WineFoldersTests(unittest.TestCase):
    def test_engine_swift_has_no_fixed_folder_left(self):
        found = [(n, c.strip()) for n, c in code_lines(ROOT / "Sources/Nightforge/Engine.swift")
                 if re.search(r"x86_64-(unix|windows)|i386-windows", c)]
        self.assertEqual(found, [])

    def test_the_names_stand_in_one_place(self):
        text = (ROOT / "Sources/Nightforge/WineFolders.swift").read_text()
        for name in ("x86_64-unix", "x86_64-windows", "i386-windows"):
            self.assertEqual(text.count(f'"{name}"'), 1, name)


if __name__ == "__main__":
    unittest.main()
