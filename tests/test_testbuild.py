"""scripts/testbuild/swiftc takes the short way only for exactly what it prepared, and a failure stays a failure.

Against a stand-in compiler that writes down every call, so no Swift is compiled here:
python3 -m unittest tests/test_testbuild.py
"""
from __future__ import annotations

import json
import os
import pathlib
import stat
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHIM = ROOT / "scripts" / "testbuild" / "swiftc"
AFFECTED = ROOT / "scripts" / "testbuild" / "affected.py"

COMPILER = textwrap.dedent("""\
    #!/bin/bash
    # Stands in for swiftc and swift-frontend: notes the call, makes what was asked for, ends as the test says.
    echo "$(basename "$0") $*" >> "$FAKE_LOG"
    case "$1" in
      --version) echo "fake swift 1"; exit 0 ;;
      -\\#\\#\\#) echo "$FAKE_FRONTEND -frontend -c -primary-file ${@: -1} -sdk /sdk -module-name main -parse-as-library -o main.o"; exit 0 ;;
    esac
    if [ "$1" = "-frontend" ]; then
      if [ -n "${FAKE_FRONTEND_FAILS:-}" ]; then echo "error: the test file is broken"; exit 1; fi
      previous=""
      for word in "$@"; do [ "$previous" = "-o" ] && : > "$word"; previous="$word"; done
      exit 0
    fi
    if [ "$1" = "-c" ]; then
      if [ -n "${FAKE_APP_BROKEN:-}" ]; then echo "x.swift:1:1: error: the app is broken"; exit 7; fi
      previous=""
      for word in "$@"; do [ "$previous" = "-output-file-map" ] && map="$word"; previous="$word"; done
      /usr/bin/python3 -I -c 'import json,sys
    for entry in json.load(open(sys.argv[1])).values(): open(entry["object"], "w").close()' "$map"
      exit 0
    fi
    if [ -n "${FAKE_REAL_EXIT:-}" ] && [[ "$*" == *.swift* ]]; then exit "$FAKE_REAL_EXIT"; fi
    if [ -n "${FAKE_LINK_FAILS:-}" ] && [[ "$*" != *.swift* ]]; then exit 1; fi
    previous=""
    for word in "$@"; do [ "$previous" = "-o" ] && : > "$word"; previous="$word"; done
    exit 0
    """)


class World(unittest.TestCase):
    def setUp(self) -> None:
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.home = pathlib.Path(holder.name).resolve()
        self.repo = self.home / "repo"
        for name in ("A", "B", "App"):
            self.write(f"Sources/Nightforge/{name}.swift", f"// {name}\n")
        self.write("tests/OneTest/main.swift", "// test\n")
        tools = self.home / "tools"
        tools.mkdir()
        self.real = tools / "swiftc"
        self.real.write_text(COMPILER)
        self.real.chmod(self.real.stat().st_mode | stat.S_IXUSR)
        self.frontend = tools / "swift-frontend"
        self.frontend.write_text(COMPILER)
        self.frontend.chmod(self.real.stat().st_mode)
        self.log = self.home / "log"
        self.log.touch()
        self.env = {**os.environ, "NIGHTFORGE_REAL_SWIFTC": str(self.real), "FAKE_LOG": str(self.log),
                    "FAKE_FRONTEND": str(self.frontend), "SDKROOT": "/sdk"}
        self.env.pop("NIGHTFORGE_TEST_OBJECTS", None)
        self.app = ["Sources/Nightforge/A.swift", "Sources/Nightforge/B.swift"]
        self.series = ["-parse-as-library", "-o", "out", *self.app, "tests/OneTest/main.swift"]

    def write(self, relative: str, text: str) -> None:
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def shim(self, *arguments: str, **extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(SHIM), *arguments], cwd=self.repo, env={**self.env, **extra}, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def prepare(self, *flags: str, **extra: str) -> subprocess.CompletedProcess[str]:
        answer = self.shim("--prepare", "build/objects", "2", *flags, **extra)
        if answer.stdout.strip():
            self.env["NIGHTFORGE_TEST_OBJECTS"] = answer.stdout.strip()
        return answer

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines()

    def forget_calls(self) -> None:
        self.log.write_text("")

    def full_compile(self, words: list[str] | None = None) -> str:
        """The line of the plain swiftc call that was handed these words, as if nothing stood in front of it."""
        wanted = "swiftc " + " ".join(words or self.series)
        self.assertIn(wanted, self.calls())
        return wanted


class ShortWay(World):
    def test_a_prepared_series_compiles_only_its_own_file_and_links(self) -> None:
        self.assertEqual(self.prepare().returncode, 0)
        self.forget_calls()
        self.assertEqual(self.shim(*self.series).returncode, 0)
        compile_call, link_call = self.calls()
        self.assertTrue(compile_call.startswith("swift-frontend -frontend -c "))
        self.assertIn("-primary-file tests/OneTest/main.swift", compile_call)
        self.assertNotIn("-primary-file Sources", compile_call)
        self.assertIn("A.o", link_call)
        self.assertNotIn(".swift", link_call)
        self.assertTrue((self.repo / "out").exists())

    def test_the_real_app_entry_is_not_part_of_the_objects(self) -> None:
        self.prepare()
        plan = json.loads((pathlib.Path(self.env["NIGHTFORGE_TEST_OBJECTS"]) / "plan.json").read_text())
        self.assertEqual(plan["sources"], self.app)

    def test_an_unchanged_app_is_not_compiled_again(self) -> None:
        self.prepare()
        first = self.env["NIGHTFORGE_TEST_OBJECTS"]
        self.forget_calls()
        self.prepare()
        self.assertEqual(self.env["NIGHTFORGE_TEST_OBJECTS"], first)
        self.assertFalse([call for call in self.calls() if call.startswith("swiftc -c")])


class NoOldObjects(World):
    def test_a_changed_file_gets_new_objects(self) -> None:
        self.prepare()
        first = self.env["NIGHTFORGE_TEST_OBJECTS"]
        self.write("Sources/Nightforge/A.swift", "// changed\n")
        self.forget_calls()
        self.prepare()
        self.assertNotEqual(self.env["NIGHTFORGE_TEST_OBJECTS"], first)
        self.assertTrue([call for call in self.calls() if call.startswith("swiftc -c")])
        self.assertFalse(pathlib.Path(first).exists())

    def test_other_flags_get_their_own_objects_and_leave_these(self) -> None:
        self.prepare()
        plain = self.env["NIGHTFORGE_TEST_OBJECTS"]
        self.prepare("-profile-generate")
        self.assertNotEqual(self.env["NIGHTFORGE_TEST_OBJECTS"], plain)
        self.assertTrue(pathlib.Path(plain).exists())

    def test_a_file_changed_after_preparing_goes_the_old_way(self) -> None:
        self.prepare()
        self.write("Sources/Nightforge/B.swift", "// changed during the run\n")
        self.forget_calls()
        self.assertEqual(self.shim(*self.series).returncode, 0)
        self.full_compile()
        self.assertFalse([call for call in self.calls() if "-frontend" in call])

    def test_a_new_app_file_goes_the_old_way(self) -> None:
        self.prepare()
        self.write("Sources/Nightforge/C.swift", "// new\n")
        words = ["-parse-as-library", "-o", "out", *self.app, "Sources/Nightforge/C.swift", "tests/OneTest/main.swift"]
        self.forget_calls()
        self.shim(*words)
        self.full_compile(words)


class OldWay(World):
    def assert_untouched(self, *words: str) -> None:
        self.forget_calls()
        self.assertEqual(self.shim(*words).returncode, 0)
        self.assertEqual(self.calls(), ["swiftc " + " ".join(words)])

    def test_anything_but_the_prepared_build_passes_straight_through(self) -> None:
        self.prepare()
        test = "tests/OneTest/main.swift"
        for words in (
            ["-parse-as-library", "-o", "out", self.app[0], test],  # part of the app
            ["-parse-as-library", "-o", "out", *self.app],  # no file of its own
            ["-o", "out", *self.app, test],  # without -parse-as-library
            ["-parse-as-library", "-DSOMETHING", "-o", "out", *self.app, test],
            ["-parse-as-library", "-D", "SOMETHING", "-o", "out", *self.app, test],
            ["-parse-as-library", "-framework", "GameController", "-o", "out", *self.app, test],
            ["-parse-as-library", "-O", "-o", "out", *self.app, test],
            ["-parse-as-library", "-o", "out", *self.app, test, "extra.o"],
            ["-parse-as-library", *self.app, test],  # nothing to make
            ["-parse-as-library", "-o", "out", *[str(self.repo / name) for name in self.app], test],
            ["--version"],
        ):
            with self.subTest(words=words):
                self.assert_untouched(*words)

    def test_without_prepared_objects_it_is_only_swiftc(self) -> None:
        self.assert_untouched(*self.series)

    def test_another_sdk_passes_through(self) -> None:
        self.prepare()
        self.forget_calls()
        self.shim(*self.series, SDKROOT="/other")
        self.full_compile()


class FailuresStay(World):
    def test_a_broken_test_file_ends_as_swiftc_ends(self) -> None:
        self.prepare()
        self.forget_calls()
        answer = self.shim(*self.series, FAKE_FRONTEND_FAILS="1", FAKE_REAL_EXIT="5")
        self.assertEqual(answer.returncode, 5)
        self.full_compile()

    def test_a_link_that_fails_ends_as_swiftc_ends(self) -> None:
        self.prepare()
        answer = self.shim(*self.series, FAKE_LINK_FAILS="1", FAKE_REAL_EXIT="6")
        self.assertEqual(answer.returncode, 6)

    def test_lost_objects_fall_back(self) -> None:
        self.prepare()
        (pathlib.Path(self.env["NIGHTFORGE_TEST_OBJECTS"]) / "plan.json").unlink()
        self.forget_calls()
        self.assertEqual(self.shim(*self.series).returncode, 0)
        self.full_compile()

    def test_an_app_that_does_not_compile_fails_each_series_with_its_errors(self) -> None:
        answer = self.prepare(FAKE_APP_BROKEN="1")
        self.assertEqual(answer.returncode, 1)
        self.forget_calls()
        series = self.shim(*self.series)
        self.assertEqual(series.returncode, 7)
        self.assertIn("the app is broken", series.stderr)
        self.assertEqual(self.calls(), [])

    def test_a_failed_app_build_is_tried_again_next_time(self) -> None:
        self.prepare(FAKE_APP_BROKEN="1")
        self.forget_calls()
        self.assertEqual(self.prepare().returncode, 0)
        self.assertTrue([call for call in self.calls() if call.startswith("swiftc -c")])
        self.assertEqual(self.shim(*self.series).returncode, 0)

    def test_preparing_says_when_it_can_not_be_used(self) -> None:
        self.assertEqual(self.shim("--prepare", "build/objects", "2", NIGHTFORGE_REAL_SWIFTC="/no/such/swiftc").returncode, 3)


class Affected(World):
    def setUp(self) -> None:
        super().setUp()
        del self.env["SDKROOT"]  # git asks the real SDK
        self.write("Sources/Nightforge/A.swift", "struct Alpha {}\nprivate struct Hidden {}\n")
        self.write("Sources/Nightforge/B.swift", "enum Beta {}\n")
        self.write("tests/OneTest/run.sh", "SOURCES=$(ls Sources/Nightforge/*.swift)\n")
        self.write("tests/OneTest/main.swift", "let a = Alpha()\n")
        self.write("tests/TwoTest/run.sh", "swiftc Sources/Nightforge/B.swift tests/TwoTest/main.swift\n")
        self.write("tests/TwoTest/main.swift", "let b = Beta.self\n")
        self.write("tests/ThreeTest/run.sh", "python3 tests/ThreeTest/check.py\n")
        self.write("tests/ThreeTest/check.py", 'import glob\nglob.glob("Sources/Nightforge/*.swift")\n')
        self.write("tests/FourTest/main.swift", "import Helper\nlet s = Hidden.self\n// uses tests/Shared/Helper.swift\n")
        self.write("tests/FourTest/run.sh", "swiftc tests/Shared/Helper.swift tests/FourTest/main.swift\n")
        self.write("tests/Shared/Helper.swift", "// helper\n")
        self.write("docs/x.md", "text\n")
        self.write("build.sh", "true\n")
        for words in (["init", "-q"], ["add", "-A"],
                      ["-c", "user.name=t", "-c", "user.email=t@e", "commit", "-qm", "base"], ["branch", "base"]):
            subprocess.run(["git", *words], cwd=self.repo, check=True, env={**self.env, "GIT_CONFIG_GLOBAL": "/dev/null"})

    def chosen(self) -> list[str]:
        answer = subprocess.run([str(AFFECTED), "base"], cwd=self.repo, env=self.env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, check=True)
        return [line.removeprefix("tests/") for line in answer.stdout.split()]

    def test_nothing_changed_means_nothing(self) -> None:
        self.assertEqual(self.chosen(), [])

    def test_documentation_touches_nothing(self) -> None:
        self.write("docs/x.md", "other\n")
        self.assertEqual(self.chosen(), [])

    def test_a_series_of_its_own(self) -> None:
        self.write("tests/TwoTest/main.swift", "// edited\n")
        self.assertEqual(self.chosen(), ["TwoTest"])

    def test_a_shared_file_reaches_who_uses_it(self) -> None:
        self.write("tests/Shared/Helper.swift", "// edited\n")
        self.assertEqual(self.chosen(), ["FourTest"])

    def test_an_app_file_reaches_who_names_it_and_who_reads_the_folder(self) -> None:
        self.write("Sources/Nightforge/A.swift", "struct Alpha { let x = 1 }\nprivate struct Hidden {}\n")
        self.assertEqual(self.chosen(), ["OneTest", "ThreeTest"])  # FourTest names only what's private to A.swift

    def test_a_series_that_lists_the_file(self) -> None:
        self.write("Sources/Nightforge/B.swift", "enum Beta { case one }\n")
        self.assertEqual(self.chosen(), ["ThreeTest", "TwoTest"])

    def test_anything_else_means_all(self) -> None:
        self.write("build.sh", "false\n")
        self.assertEqual(self.chosen(), ["FourTest", "OneTest", "ThreeTest", "TwoTest"])

    def test_an_unknown_base_means_all(self) -> None:
        answer = subprocess.run([str(AFFECTED), "no-such-ref"], cwd=self.repo, env=self.env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, check=True)
        self.assertEqual(len(answer.stdout.split()), 4)


if __name__ == "__main__":
    unittest.main()
