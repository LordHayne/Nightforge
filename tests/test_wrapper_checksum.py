"""The steamwebhelper wrapper stands in for Steam's own helper for every player, and its binary can't be read in a
review. So it goes into the app only as the build whose SHA-256 lies beside it: build.sh checks that when it can't
build the wrapper itself, and the workflow that builds it writes and commits both."""
import hashlib
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
WRAPPER = ROOT / "wrapper"


def build_check():
    """The command build.sh runs before it takes the checked-in binary."""
    match = re.search(r"if ! \((cd wrapper && shasum [^)]*)\); then", (ROOT / "build.sh").read_text())
    return match.group(1) if match else None


class WrapperChecksumTests(unittest.TestCase):
    def test_the_checked_in_binary_matches_its_checksum(self):
        digest, name = (WRAPPER / "steamwebhelper.exe.sha256").read_text().split()
        self.assertEqual(name, "steamwebhelper.exe")
        self.assertEqual(hashlib.sha256((WRAPPER / "steamwebhelper.exe").read_bytes()).hexdigest(), digest)

    def test_build_sh_checks_before_it_copies(self):
        build = (ROOT / "build.sh").read_text()
        self.assertIsNotNone(build_check())
        self.assertLess(build.index(build_check()), build.index("cp wrapper/steamwebhelper.exe"))
        self.assertIn("exit 1", build[build.index(build_check()):build.index("cp wrapper/steamwebhelper.exe")])

    def test_the_check_takes_the_build_and_nothing_else(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = pathlib.Path(temp) / "wrapper"
            folder.mkdir()
            for name in ("steamwebhelper.exe", "steamwebhelper.exe.sha256"):
                shutil.copy(WRAPPER / name, folder / name)

            def check():
                return subprocess.run(["bash", "-c", build_check()], cwd=temp, capture_output=True).returncode

            self.assertEqual(check(), 0, "the build the checksum names")
            with open(folder / "steamwebhelper.exe", "ab") as binary:
                binary.write(b"\0")
            self.assertNotEqual(check(), 0, "one byte more")
            (folder / "steamwebhelper.exe.sha256").unlink()
            self.assertNotEqual(check(), 0, "no checksum")

    def test_the_workflow_writes_and_commits_the_checksum(self):
        workflow = (ROOT / ".github/workflows/wrapper.yml").read_text()
        self.assertIn("sha256sum steamwebhelper.exe | tee steamwebhelper.exe.sha256", workflow)
        self.assertIn("git add wrapper/steamwebhelper.exe wrapper/steamwebhelper.exe.sha256", workflow)
        self.assertIn("git diff --quiet wrapper/steamwebhelper.exe wrapper/steamwebhelper.exe.sha256", workflow)


if __name__ == "__main__":
    unittest.main()
