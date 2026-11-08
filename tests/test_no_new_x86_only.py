"""Nothing new depends on x86_64 without saying so (docs/ENTWURF-ARM64.md, Rosetta ends with macOS 27): a new source
in components/sources.json names its "arch", and a new x86_64-only clang line has to be added here, with its reason."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Everything Wine loads or starts, as of 8.11.2026.
KNOWN_X86_ONLY_LINES = {
    "build.sh": 2,  # hide-steam-dock, nightforge-sandbox: see tests/test_helper_architectures.py
    "scripts/build-enginefix.sh": 1,  # patches winecx's own ntdll.so
    ".github/workflows/gamepad.yml": 1,  # winebus.so for winecx
    ".github/workflows/graphics.yml": 2,  # winemac.so and DXMT's Unix side for Wine
}
# The sources that existed before the rule; kosmickrisp is held back from the list since 9a6157e.
KNOWN_SOURCES_WITHOUT_ARCH = {"cabextract", "d3dmetal", "dxmt", "dxvk", "dxvk-macos", "enginefix", "gamepad", "gogdl", "graphics",
                              "kosmickrisp", "legendary", "moltenvk", "wine", "winecx", "winetricks"}
ARCHES = {"x86_64", "arm64", "universal"}


def x86_only_lines(text):
    return sum("-arch x86_64" in line and "-arch arm64" not in line for line in text.splitlines())


class NoNewX86OnlyTests(unittest.TestCase):
    def test_no_new_x86_only_clang_line(self):
        found = {}
        paths = [ROOT / "build.sh", *(ROOT / "scripts").glob("*"), *(ROOT / ".github/workflows").glob("*.yml")]
        for path in paths:
            if path.is_file() and (count := x86_only_lines(path.read_text(errors="replace"))):
                found[str(path.relative_to(ROOT))] = count
        self.assertEqual(found, KNOWN_X86_ONLY_LINES)

    def test_a_new_source_names_its_processor(self):
        sources = json.loads((ROOT / "components/sources.json").read_text())["sources"]
        for source in sources:
            if source["id"] not in KNOWN_SOURCES_WITHOUT_ARCH:
                self.assertIn(source.get("arch"), ARCHES, f'{source["id"]} needs "arch" in components/sources.json')
            if "arch" in source:
                self.assertIn(source["arch"], ARCHES, source["id"])


if __name__ == "__main__":
    unittest.main()
