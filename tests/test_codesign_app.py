"""scripts/codesign-app.sh signs with Nightforge's own code signing identity when there is one, with a
designated requirement that names the identifier and the certificate, and ad hoc otherwise. Against
stand-ins for `security` and `codesign`: no keychain is read, nothing is signed for real."""
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "codesign-app.sh"
CERT = "0123456789ABCDEF0123456789ABCDEF01234567"

FAKE_SECURITY = """#!/bin/bash
[ "$1 $2 $3" = "find-identity -p codesigning" ] && cat "$FAKE/identities" 2>/dev/null
exit 0
"""
# Remembers every call; `--display -r -` shows the requirement of the last signature that set one.
FAKE_CODESIGN = """#!/bin/bash
printf '%s\\n' "$*" >> "$FAKE/codesign.argv"
for arg; do case "$arg" in -r=*) printf '%s' "${arg#-r=}" > "$FAKE/requirement" ;; esac; done
if [ "$1 $2 $3" = "--display -r -" ]; then
  [ -n "${FAKE_REQUIREMENT:-}" ] && echo "$FAKE_REQUIREMENT" || cat "$FAKE/requirement" 2>/dev/null
fi
exit 0
"""


class CodesignApp(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = pathlib.Path(self.temp.name)
        self.fake = root / "fake"
        self.fake.mkdir()
        bin_dir = root / "bin"
        bin_dir.mkdir()
        for name, text in (("security", FAKE_SECURITY), ("codesign", FAKE_CODESIGN)):
            (bin_dir / name).write_text(text)
            (bin_dir / name).chmod(0o755)
        self.app = root / "Nightforge.app"
        (self.app / "Contents").mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "io.github.lordhayne.nightforge"}))
        self.env = {"PATH": f"{bin_dir}:/usr/bin:/bin:/usr/sbin:/sbin", "FAKE": str(self.fake), "HOME": str(root)}

    def sign(self, **extra):
        result = subprocess.run(["bash", str(SCRIPT), str(self.app)], env={**self.env, **extra}, capture_output=True, text=True)
        calls = (self.fake / "codesign.argv").read_text().splitlines() if (self.fake / "codesign.argv").exists() else []
        return result, calls

    def test_without_an_identity_ad_hoc(self):
        result, calls = self.sign()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [f"--force --deep --sign - {self.app}"])

    def test_the_identity_from_the_keychain(self):
        (self.fake / "identities").write_text(
            f'  1) {CERT} "Nightforge Code Signing" (CSSMERR_TP_NOT_TRUSTED)\n     1 identities found\n')
        result, calls = self.sign()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"--force --deep --timestamp=none --sign {CERT} {self.app}", calls)
        requirement = f'designated => identifier "io.github.lordhayne.nightforge" and certificate leaf = H"{CERT}"'
        self.assertIn(f"--force --timestamp=none --sign {CERT} -r={requirement} {self.app}", calls)
        self.assertLess(calls.index(f"--force --deep --timestamp=none --sign {CERT} {self.app}"),
                        calls.index(f"--force --timestamp=none --sign {CERT} -r={requirement} {self.app}"),
                        "nested code first, then the app with its requirement")
        self.assertIn(f"--verify --deep --strict {self.app}", calls)
        self.assertIn(CERT, result.stdout)

    def test_ad_hoc_on_request_whatever_the_keychain_holds(self):
        """A build no one watches mustn't wait on macOS asking whether codesign may use the key."""
        (self.fake / "identities").write_text(f'  1) {CERT} "Nightforge Code Signing" (CSSMERR_TP_NOT_TRUSTED)\n')
        result, calls = self.sign(NIGHTFORGE_AD_HOC="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [f"--force --deep --sign - {self.app}"])

    def test_another_identity_in_the_keychain_doesnt_count(self):
        (self.fake / "identities").write_text(f'  1) {CERT} "Someone Else" (CSSMERR_TP_NOT_TRUSTED)\n')
        result, calls = self.sign()
        self.assertEqual(calls, [f"--force --deep --sign - {self.app}"])

    def test_the_identity_and_a_keychain_handed_in(self):
        result, calls = self.sign(NIGHTFORGE_CODESIGN_IDENTITY=CERT, NIGHTFORGE_CODESIGN_KEYCHAIN="/tmp/ci keychain.keychain-db")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all("--keychain /tmp/ci keychain.keychain-db" in call for call in calls if "--sign" in call), calls)

    def test_a_requirement_without_the_certificate_fails_the_build(self):
        result, _ = self.sign(NIGHTFORGE_CODESIGN_IDENTITY=CERT, FAKE_REQUIREMENT='designated => cdhash H"ff"')
        self.assertEqual(result.returncode, 1)
        self.assertIn("doesn't name the certificate", result.stderr)

    def test_the_certificate_never_goes_to_github(self):
        """The user chose: the certificate stays on the Mac, sign-release.sh signs with the pinned one."""
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertNotIn("NIGHTFORGE_CODESIGN", workflow)
        self.assertNotIn("secrets.", workflow)
        self.assertIn("scripts/codesign-certificate.sha1", (ROOT / "scripts/sign-release.sh").read_text())
        pin = [line for line in (ROOT / "scripts/codesign-certificate.sha1").read_text().splitlines() if not line.startswith("#")]
        self.assertTrue(all(len(line.strip()) == 40 for line in pin if line.strip()), "a SHA-1, or nothing yet")


class ExportCodesignIdentity(unittest.TestCase):
    def test_it_runs_only_in_a_terminal(self):
        """The backup tool asks the user things (macOS's dialogs): never from a script or a session."""
        result = subprocess.run(["bash", str(ROOT / "scripts/export-codesign-identity.sh"), "/tmp/nf-test.p12"],
                                stdin=subprocess.DEVNULL, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Run this yourself in Terminal", result.stderr)
        self.assertFalse(pathlib.Path("/tmp/nf-test.p12").exists())


if __name__ == "__main__":
    unittest.main()
