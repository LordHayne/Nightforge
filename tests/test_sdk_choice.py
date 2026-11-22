"""Tests for scripts/sdk-lib.sh: which macOS SDK Swift builds against. Run: python3 -m pytest tests/test_sdk_choice.py

Nothing is built: the Command Line Tools and Xcode are folders made up for each test."""

import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / "scripts" / "sdk-lib.sh"
INTERFACE = "System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
STATE_MACRO = 'public macro State() = #externalMacro(\n    module: "SwiftUIMacros", type: "StateMacro"\n)\n'


class SDKChoiceTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        base = pathlib.Path(self.folder.name).resolve()
        self.clt = base / "CommandLineTools"
        self.sdks = self.clt / "SDKs"
        self.sdk("MacOSX26.5.sdk", macros=False)
        self.sdk("MacOSX27.2.sdk", macros=True)
        for link, target in (("MacOSX.sdk", "MacOSX27.2.sdk"), ("MacOSX27.sdk", "MacOSX27.2.sdk"), ("MacOSX26.sdk", "MacOSX26.5.sdk")):
            (self.sdks / link).symlink_to(target)
        (self.clt / "usr/lib/swift/host/plugins").mkdir(parents=True)
        (self.clt / "usr/lib/swift/host/plugins/libObservationMacros.dylib").touch()
        self.xcode = base / "Xcode.app/Contents/Developer"
        self.xcode.mkdir(parents=True)
        self.fallback = str(self.sdks / "MacOSX26.5.sdk")
        # xcode-select, should the library ask it: here it says the Command Line Tools.
        self.bin = base / "bin"
        self.bin.mkdir()
        (self.bin / "xcode-select").write_text(f"#!/bin/sh\necho {self.clt}\n")
        (self.bin / "xcode-select").chmod(0o755)

    def tearDown(self):
        self.folder.cleanup()

    def sdk(self, name, macros):
        interface = self.sdks / name / INTERFACE
        interface.parent.mkdir(parents=True)
        interface.write_text("public struct State {}\n" + (STATE_MACRO if macros else ""))
        return self.sdks / name

    def pick(self, sdkroot=None, developer=None):
        """SDKROOT after nightforge_pick_sdk under `set -euo pipefail`, as build.sh runs it, and what it said."""
        env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": os.environ.get("HOME", "/tmp"), "NIGHTFORGE_CLT_ROOT": str(self.clt)}
        if sdkroot is not None:
            env["SDKROOT"] = str(sdkroot)
        if developer is not None:
            env["DEVELOPER_DIR"] = str(developer)
        result = subprocess.run(["/bin/bash", "-c", f'set -euo pipefail; . "{LIB}"; nightforge_pick_sdk; printf %s "${{SDKROOT:-}}"'],
                                env=env, capture_output=True, text=True, check=True)
        return result.stdout, result.stderr

    def test_without_sdkroot_the_tools_fall_back_quietly(self):
        self.assertEqual(self.pick(), (self.fallback, ""))

    def test_a_tools_sdk_that_needs_the_macros_is_replaced_with_a_line(self):
        for name in ("MacOSX.sdk", "MacOSX27.sdk", "MacOSX27.2.sdk"):
            with self.subTest(name=name):
                chosen, said = self.pick(self.sdks / name)
                self.assertEqual(chosen, self.fallback)
                self.assertIn(f"SDKROOT names {name}", said)
                self.assertIn("building against MacOSX26.5.sdk", said)
                self.assertEqual(said.count("\n"), 1)

    def test_the_fallback_itself_stays_by_any_name(self):
        for name in ("MacOSX26.5.sdk", "MacOSX26.sdk"):
            with self.subTest(name=name):
                self.assertEqual(self.pick(self.sdks / name), (str(self.sdks / name), ""))

    def test_a_tools_sdk_without_the_macros_stays(self):
        older = self.sdk("MacOSX15.5.sdk", macros=False)
        self.assertEqual(self.pick(older), (str(older), ""))

    def test_an_sdk_chosen_elsewhere_stays(self):
        elsewhere = pathlib.Path(self.folder.name).resolve() / "Elsewhere/MacOSX27.2.sdk"
        (elsewhere / INTERFACE).parent.mkdir(parents=True)
        (elsewhere / INTERFACE).write_text(STATE_MACRO)
        self.assertEqual(self.pick(elsewhere), (str(elsewhere), ""))

    def test_xcode_keeps_any_sdk(self):
        # Xcode has the plugin: by DEVELOPER_DIR, even with SDKROOT on a tools SDK, and without SDKROOT.
        self.assertEqual(self.pick(self.sdks / "MacOSX.sdk", developer=self.xcode), (str(self.sdks / "MacOSX.sdk"), ""))
        self.assertEqual(self.pick(developer=self.xcode), ("", ""))
        (self.bin / "xcode-select").write_text(f"#!/bin/sh\necho {self.xcode}\n")
        self.assertEqual(self.pick(self.sdks / "MacOSX.sdk"), (str(self.sdks / "MacOSX.sdk"), ""))

    def test_developer_dir_on_the_tools_counts_as_the_tools(self):
        self.assertEqual(self.pick(self.sdks / "MacOSX.sdk", developer=self.clt)[0], self.fallback)

    def test_tools_that_bring_the_plugin_keep_their_sdk(self):
        (self.clt / "usr/lib/swift/host/plugins/libSwiftUIMacros.dylib").touch()
        self.assertEqual(self.pick(self.sdks / "MacOSX.sdk"), (str(self.sdks / "MacOSX.sdk"), ""))
        self.assertEqual(self.pick(), ("", ""))

    def test_without_the_fallback_nothing_changes(self):
        (self.sdks / "MacOSX26.sdk").unlink()
        os.rename(self.fallback, self.sdks / "gone")
        self.assertEqual(self.pick(self.sdks / "MacOSX.sdk"), (str(self.sdks / "MacOSX.sdk"), ""))
        self.assertEqual(self.pick(), ("", ""))

    def test_an_sdkroot_that_isnt_there_is_left_for_swift_to_report(self):
        missing = self.sdks / "MacOSX99.sdk"
        self.assertEqual(self.pick(missing), (str(missing), ""))

    def test_an_sdk_without_a_swiftui_interface(self):
        # Can't be told: a chosen one stays; Swift's own default falls back, as before the library.
        bare = self.sdks / "Bare.sdk"
        bare.mkdir()
        self.assertEqual(self.pick(bare), (str(bare), ""))
        (self.sdks / "MacOSX.sdk").unlink()
        (self.sdks / "MacOSX.sdk").symlink_to("Bare.sdk")
        self.assertEqual(self.pick(), (self.fallback, ""))
        (self.sdks / "MacOSX.sdk").unlink()
        self.assertEqual(self.pick(), (self.fallback, ""))

    def test_every_build_script_asks_the_library(self):
        # One rule: no script keeps its own copy of the fallback (C-only builds like winebus excepted).
        users = subprocess.run(["git", "grep", "-l", "nightforge_pick_sdk", "--", "build.sh", "scripts", "tests"],
                               cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
        for script in ("build.sh", "scripts/signing-lib.sh", "scripts/export-codesign-identity.sh", "scripts/coverage.sh",
                       "scripts/testbuild/compile-once.sh", "tests/SearchTest/run.sh"):
            self.assertIn(script, users)
        copies = subprocess.run(["git", "grep", "-l", 'export SDKROOT="$CLT_SDK"\\|export SDKROOT="$clt_sdk"', "--", ":!tests/test_sdk_choice.py"],
                                cwd=ROOT, capture_output=True, text=True).stdout.split()
        self.assertEqual(copies, [])


if __name__ == "__main__":
    unittest.main()
