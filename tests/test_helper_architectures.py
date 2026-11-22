"""Nightforge's own Mac helpers still build for arm64, so an engine without Rosetta doesn't start with a porting job.

Only the Vulkan layer ships universal. It's loaded by the Vulkan loader in the x86_64 game bundle and nowhere else.
The Dock hider and the sandbox helper stay x86_64: DYLD_INSERT_LIBRARIES is handed to everything Steam starts, and
today an arm64 program skips the x86_64 library. With an arm64 part it would load it, and AppKit with it. The sandbox
helper as universal would run as arm64 when Nightforge starts it, and is x86_64 on purpose (wrapper/nightforge-sandbox.c)."""
import os
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SDK = pathlib.Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
HELPERS = {
    "hide-steam-dock": (["-dynamiclib", "-framework", "AppKit"], ["wrapper/hide-steam-dock.m", "wrapper/network-order.c"]),
    "nightforge-sandbox": ([], ["wrapper/nightforge-sandbox.c"]),
    "nightforge-vulkan-layer": (["-dynamiclib", "-fvisibility=hidden", "-fobjc-arc", "-I", "wrapper/vulkan-headers", "-I", "wrapper",
                                 "-framework", "Metal", "-framework", "QuartzCore", "-framework", "CoreGraphics", "-weak_framework", "MetalFX"],
                                ["wrapper/nightforge-vulkan-layer.c", "wrapper/nightforge-vulkan-metalfx.m"]),
}


def build_line(output):
    """The clang line in build.sh that makes `output`, its continuation lines joined."""
    text = (ROOT / "build.sh").read_text().replace("\\\n", " ")
    lines = [line for line in text.splitlines() if line.startswith("clang ") and re.search(rf"/{re.escape(output)}\b", line)]
    assert len(lines) == 1, (output, lines)
    return lines[0]


class HelperArchitectureTests(unittest.TestCase):
    def test_each_helper_compiles_and_links_for_arm64(self):
        env = dict(os.environ)
        if "SDKROOT" not in env and SDK.is_dir():
            env["SDKROOT"] = str(SDK)
        with tempfile.TemporaryDirectory() as folder:
            for name, (flags, sources) in HELPERS.items():
                output = pathlib.Path(folder) / name
                command = ["clang", "-arch", "arm64", "-mmacosx-version-min=11.0", "-O2", "-Wall", *flags, "-o", str(output), *sources]
                done = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
                self.assertEqual(done.returncode, 0, f"{name}: {done.stderr}")
                archs = subprocess.run(["lipo", "-archs", str(output)], capture_output=True, text=True).stdout.split()
                self.assertEqual(archs, ["arm64"], name)

    def test_only_the_vulkan_layer_ships_universal(self):
        self.assertIn("-arch x86_64 -arch arm64", build_line("nightforge-vulkan-layer.dylib"))
        for output in ("hide-steam-dock.dylib", "nightforge-sandbox"):
            line = build_line(output)
            self.assertIn("-arch x86_64", line)
            self.assertNotIn("arm64", line, output)


if __name__ == "__main__":
    unittest.main()
