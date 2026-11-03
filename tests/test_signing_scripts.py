"""The signing scripts (scripts/make-signing-keys.sh, sign-release.sh, sign-lists.sh,
check-signatures.sh) against stand-ins for the Keychain (`security`), the clipboard and GitHub (`gh`),
in a copy of the repository: no real Keychain, no network. Above all: a private key never shows up
in the output, on a command line or in the repository."""
import base64
import hashlib
import json
import os
import pathlib
import plistlib
import pty
import re
import select
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = ["signing-lib.sh", "signing-tool.swift", "make-signing-keys.sh", "sign-release.sh", "sign-lists.sh",
           "check-signatures.sh"]
# The online lists the scripts sign, as scripts/signing-lib.sh names them.
LISTS = re.search(r"^SIGNED_LISTS=\((.*)\)$", (ROOT / "scripts/signing-lib.sh").read_text(), re.M).group(1).split()

# A Keychain of one item ($FAKE/keychain), as `security` and `security -i` handle it.
FAKE_SECURITY = r"""#!/bin/bash
printf '%s\n' "$*" >> "$FAKE/security.argv"
run() {
  local command="$1"; shift
  case "$command" in
    add-generic-password)
      [ ! -e "$FAKE/keychain" ] || { echo "The specified item already exists in the keychain." >&2; return 45; }
      while [ $# -gt 0 ]; do
        case "$1" in
          -w) printf '%s' "$2" > "$FAKE/keychain"; shift ;;
          -T) [ -n "$2" ] || touch "$FAKE/asks-every-time"; shift ;;
          -a|-s|-l|-j) shift ;;
        esac
        shift
      done ;;
    delete-generic-password) [ -e "$FAKE/keychain" ] || return 44; rm "$FAKE/keychain" ;;
    find-generic-password)
      [ -e "$FAKE/keychain" ] || { echo "could not be found" >&2; return 44; }
      case " $* " in *" -w "*) cat "$FAKE/keychain"; echo ;; esac ;;
    *) return 2 ;;
  esac
}
if [ "$1" = "-i" ]; then
  status=0
  while IFS= read -r line; do eval "set -- $line"; run "$@" || status=$?; done
  exit $status
fi
run "$@"
"""

FAKE_PBCOPY = r"""#!/bin/bash
cat > "$FAKE/clipboard"
[ ! -s "$FAKE/clipboard" ] || [ -e "$FAKE/first-copy" ] || cp "$FAKE/clipboard" "$FAKE/first-copy"
"""

FAKE_PBPASTE = r"""#!/bin/bash
cat "$FAKE/clipboard" 2>/dev/null || true
"""

# One release ($FAKE/release.json, its files in $FAKE/assets), as `gh release …` handles it; a
# published one takes no more files.
FAKE_GH = r"""
import json, os, pathlib, shutil, sys
fake = pathlib.Path(os.environ["FAKE"])
with open(fake / "gh.argv", "a") as log:
    log.write(" ".join(sys.argv[1:]) + "\n")
state = json.loads((fake / "release.json").read_text())
assets = fake / "assets"
args = sys.argv[1:]
def option(name):
    return args[args.index(name) + 1] if name in args else None
if args[:2] != ["release", args[1]] or args[2] != state["tag"]:
    sys.exit("release not found")
if args[1] == "view":
    fields = option("--json").split(",")
    answer = {"isDraft": state["isDraft"], "isPrerelease": state["isPrerelease"],
              "assets": [{"name": p.name} for p in sorted(assets.iterdir())]}
    print(json.dumps({k: v for k, v in answer.items() if k in fields}))
elif args[1] == "download":
    target = pathlib.Path(option("--dir"))
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy(assets / option("--pattern"), target)
elif args[1] == "upload":
    if not state["isDraft"]:
        sys.exit("Cannot upload assets to an immutable release")
    shutil.copy(args[3], assets)
elif args[1] == "edit":
    if "--draft=false" in args:
        state["isDraft"] = False
    (fake / "release.json").write_text(json.dumps(state))
else:
    sys.exit("unknown")
"""


def stamped(text, generated):
    """A list's text with another "generated" stamp."""
    return re.sub(r'"generated": "[^"]*"', f'"generated": "{generated}"', text, count=1)


def write_executable(path, text):
    path.write_text(text)
    path.chmod(0o755)


def run_in_terminal(args, env, cwd, answers=(), timeout=120):
    """Runs `args` with a terminal for its input and output, as in Terminal. `answers`: pairs of a
    text to wait for and a function giving what to type then."""
    master, slave = pty.openpty()
    process = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, env=env, cwd=cwd, close_fds=True)
    os.close(slave)
    output, seen, pending = b"", 0, list(answers)
    deadline = time.time() + timeout
    try:
        while True:
            ready, _, _ = select.select([master], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    chunk = b""
                if not chunk:
                    break
                output += chunk
            while pending and pending[0][0].encode() in output[seen:]:
                seen = output.index(pending[0][0].encode(), seen) + len(pending[0][0])
                os.write(master, pending.pop(0)[1]())
            if not ready and process.poll() is not None:
                break
            if time.time() > deadline:
                process.kill()
                raise AssertionError("timed out; so far:\n" + output.decode(errors="replace"))
    finally:
        os.close(master)
    process.wait()
    return process.returncode, output.decode(errors="replace")


class SigningScripts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = pathlib.Path(tempfile.mkdtemp(prefix="nightforge-signing-"))
        tools = cls.tmp / "tools"
        tools.mkdir()
        # The tool as the repository has it (no keys yet), for making keys.
        cls.plain_tool = tools / "plain"
        cls.compile(cls.plain_tool, ROOT / "Sources/Nightforge/SigningKeys.swift")
        cls.main, cls.spare, cls.stranger = (cls.tool(cls.plain_tool, "generate").strip() for _ in range(3))
        cls.main_public = cls.tool(cls.plain_tool, "public", stdin=cls.main).strip()
        cls.spare_public = cls.tool(cls.plain_tool, "public", stdin=cls.spare).strip()
        # SigningKeys.swift with the test's keys, and the tool built from it.
        cls.keys_file = tools / "SigningKeys.swift"
        cls.keys_file.write_text(cls.with_keys((ROOT / "Sources/Nightforge/SigningKeys.swift").read_text(),
                                               cls.main_public, cls.spare_public))
        cls.keyed_tool = tools / "keyed"
        cls.compile(cls.keyed_tool, cls.keys_file)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @staticmethod
    def compile(output, keys_file):
        env = dict(os.environ)
        sdk = "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
        if "SDKROOT" not in env and os.path.isdir(sdk) and subprocess.run(
                ["xcode-select", "-p"], capture_output=True, text=True).stdout.strip() == "/Library/Developer/CommandLineTools":
            env["SDKROOT"] = sdk
        subprocess.run(["swiftc", "-parse-as-library", "-o", str(output), str(ROOT / "scripts/signing-tool.swift"),
                        str(ROOT / "Sources/Nightforge/Signature.swift"), str(keys_file)], check=True, env=env,
                       capture_output=True)

    @staticmethod
    def tool(tool, *args, stdin=""):
        return subprocess.run([str(tool), *args], input=stdin, capture_output=True, text=True, check=True).stdout

    @staticmethod
    def with_keys(text, main, spare):
        return text.replace('static let main = ""', f'static let main = "{main}"').replace(
            'static let spare = ""', f'static let spare = "{spare}"')

    def setUp(self):
        self.work = pathlib.Path(tempfile.mkdtemp(dir=self.tmp))
        self.fake = self.work / "fake"
        self.fake.mkdir()
        bin_dir = self.work / "bin"
        bin_dir.mkdir()
        write_executable(bin_dir / "security", FAKE_SECURITY)
        write_executable(bin_dir / "pbcopy", FAKE_PBCOPY)
        write_executable(bin_dir / "pbpaste", FAKE_PBPASTE)
        write_executable(bin_dir / "gh", f"#!{sys.executable} -I\n" + FAKE_GH)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("NIGHTFORGE_")}
        self.env.update(PATH=f"{bin_dir}:{os.environ['PATH']}", FAKE=str(self.fake),
                        NIGHTFORGE_SIGNING_TOOL=str(self.keyed_tool),
                        GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.repo = self.work / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "Sources/Nightforge").mkdir(parents=True)
        for name in SCRIPTS:
            shutil.copy2(ROOT / "scripts" / name, self.repo / "scripts" / name)
        shutil.copy(ROOT / "Sources/Nightforge/Signature.swift", self.repo / "Sources/Nightforge")
        shutil.copy(ROOT / "Sources/Nightforge/SigningKeys.swift", self.repo / "Sources/Nightforge")

    def key_file(self, secret):
        path = self.work / f"key-{len(list(self.work.glob('key-*')))}"
        path.write_text(secret + "\n")
        return str(path)

    def assertNoSecret(self, *texts):
        for text in texts:
            for secret in (self.main, self.spare, self.stranger):
                self.assertNotIn(secret, text)

    def logs(self):
        return [(self.fake / name).read_text() for name in ("security.argv", "gh.argv") if (self.fake / name).exists()]

    # MARK: make-signing-keys.sh

    def keygen(self, *args, answers=()):
        env = dict(self.env, NIGHTFORGE_SIGNING_TOOL=str(self.plain_tool))
        return run_in_terminal(["bash", "scripts/make-signing-keys.sh", *args], env, self.repo, answers)

    def keys_in_repo(self):
        text = (self.repo / "Sources/Nightforge/SigningKeys.swift").read_text()
        return [line.split('"')[1] for line in text.splitlines() if line.startswith("    static let main =")
                or line.startswith("    static let spare =")]

    def public(self, secret):
        return self.tool(self.plain_tool, "public", stdin=secret).strip()

    def test_keys_need_a_terminal(self):
        env = dict(self.env, NIGHTFORGE_SIGNING_TOOL=str(self.plain_tool))
        result = subprocess.run(["bash", "scripts/make-signing-keys.sh"], cwd=self.repo, env=env, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Run this yourself in Terminal", result.stderr)
        self.assertEqual(self.keys_in_repo(), ["", ""])

    def test_keys_with_the_spare_in_a_file(self):
        spare_file = self.work / "stick" / "nightforge-spare.txt"
        spare_file.parent.mkdir()
        status, output = self.keygen("--spare-file", str(spare_file))
        self.assertEqual(status, 0, output)
        main, spare = self.keys_in_repo()
        self.assertEqual(len(main), 44)
        self.assertEqual(len(spare), 44)
        keychain = (self.fake / "keychain").read_text()
        self.assertEqual(self.public(keychain), main, "the Keychain holds the main key")
        self.assertTrue((self.fake / "asks-every-time").exists(), 'added with -T "": no program reads it unasked')
        self.assertEqual(self.public(spare_file.read_text()), spare, "the file holds the spare key")
        self.assertEqual(stat.S_IMODE(spare_file.stat().st_mode), 0o600)
        for secret in (keychain.strip(), spare_file.read_text().strip()):
            self.assertNotIn(secret, output)
            for log in self.logs():
                self.assertNotIn(secret, log, "never on a command line")
            for path in self.repo.rglob("*"):
                if path.is_file():
                    self.assertNotIn(secret, path.read_text(errors="replace"), path)
        self.assertIn("git add Sources/Nightforge/SigningKeys.swift", output)

        status, output = self.keygen("--spare-file", str(self.work / "stick" / "again.txt"))
        self.assertEqual(status, 1)
        self.assertIn("has keys already", output)

    def test_the_spare_goes_through_the_clipboard_and_is_checked(self):
        def wrong():
            (self.fake / "clipboard").write_text("not the key")
            return b"\n"

        def right():
            shutil.copy(self.fake / "first-copy", self.fake / "clipboard")
            return b"\n"

        status, output = self.keygen(answers=[
            ("Press Return once it's saved", lambda: b"\n"),
            ("Press Return when it's on the clipboard", wrong),
            ("That isn't the spare key", lambda: b""),
            ("Press Return when it's on the clipboard", right),
        ])
        self.assertEqual(status, 0, output)
        self.assertIn("Your password manager has the spare key", output)
        spare_secret = (self.fake / "first-copy").read_text()
        self.assertEqual(self.public(spare_secret), self.keys_in_repo()[1])
        self.assertEqual((self.fake / "clipboard").read_text(), "", "the clipboard is empty afterwards")
        self.assertNoSecret(output)
        self.assertNotIn(spare_secret, output)
        self.assertNotIn(spare_secret, (self.fake / "keychain").read_text(), "the spare never goes into the Keychain")

    def test_replacing_the_main_key(self):
        status, output = self.keygen("--spare-file", str(self.work / "spare.txt"))
        self.assertEqual(status, 0, output)
        main, spare = self.keys_in_repo()
        status, output = self.keygen("--replace", "main", answers=[("Type replace to go on", lambda: b"no\n")])
        self.assertEqual(status, 1)
        self.assertEqual(self.keys_in_repo(), [main, spare], "nothing changed without the word")
        status, output = self.keygen("--replace", "main", answers=[("Type replace to go on", lambda: b"replace\n")])
        self.assertEqual(status, 0, output)
        new_main, same_spare = self.keys_in_repo()
        self.assertNotEqual(new_main, main)
        self.assertEqual(same_spare, spare)
        self.assertEqual(self.public((self.fake / "keychain").read_text()), new_main)
        self.assertIn("--spare --add", output)

    def test_the_spare_file_may_not_go_into_the_repository(self):
        status, output = self.keygen("--spare-file", str(self.repo / "spare.txt"))
        self.assertEqual(status, 1)
        self.assertIn("Not into the repository", output)
        self.assertFalse((self.repo / "spare.txt").exists())

    # MARK: sign-release.sh

    def draft(self, tag="v0.3.1", draft=True, prerelease=False, version=None, keys=None):
        """A release as release.yml drafts it, its app knowing `keys`."""
        version = version or tag[1:]
        app = self.work / "build" / "Nightforge.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        with open(app / "Contents/Info.plist", "wb") as plist:
            plistlib.dump({"CFBundleShortVersionString": version, "CFBundleIdentifier": "io.github.lordhayne.nightforge"}, plist)
        known = keys if keys is not None else [self.main_public, self.spare_public]
        (app / "Contents/MacOS/Nightforge").write_bytes(b"\xcf\xfa\xed\xfe" + b"\0".join(k.encode() for k in known) + b"\0rest")
        assets = self.fake / "assets"
        assets.mkdir()
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(assets / f"Nightforge-{tag[1:]}.zip")], check=True)
        (assets / f"Nightforge-{tag[1:]}.dmg").write_bytes(b"dmg")
        (self.fake / "release.json").write_text(json.dumps({"tag": tag, "isDraft": draft, "isPrerelease": prerelease}))
        return assets / f"Nightforge-{tag[1:]}.zip"

    def sign_release(self, *args, key=None, env=None):
        env = dict(env or self.env)
        if key:
            env["NIGHTFORGE_SIGNING_KEY_FILE"] = self.key_file(key)
        return subprocess.run(["bash", "scripts/sign-release.sh", *args], cwd=self.repo, env=env, capture_output=True, text=True)

    def verify(self, file):
        return subprocess.run([str(self.keyed_tool), "verify", str(file)], capture_output=True, text=True)

    def release_state(self):
        return json.loads((self.fake / "release.json").read_text())

    def test_a_draft_is_signed_with_the_keychain_key(self):
        zip_file = self.draft()
        (self.fake / "keychain").write_text(self.main)
        result = self.sign_release("v0.3.1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(pathlib.Path(str(zip_file) + ".sig").exists(), "the .sig is on the draft")
        check = self.verify(zip_file)
        self.assertEqual(check.returncode, 0, check.stdout)
        self.assertIn("main key", check.stdout)
        self.assertTrue(self.release_state()["isDraft"], "not published without --publish")
        self.assertIn("gh release edit v0.3.1", result.stdout)
        self.assertNoSecret(result.stdout, result.stderr, *self.logs())

    def test_publish_makes_it_the_newest_release(self):
        self.draft()
        result = self.sign_release("v0.3.1", "--publish", key=self.main)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.release_state()["isDraft"])
        self.assertIn("--latest", (self.fake / "gh.argv").read_text())

    def test_a_test_release_stays_a_prerelease(self):
        self.draft("v0.3.1-rc.1", prerelease=True)
        result = self.sign_release("v0.3.1-rc.1", "--publish", key=self.main)
        self.assertEqual(result.returncode, 0, result.stderr)
        edit = [line for line in (self.fake / "gh.argv").read_text().splitlines() if line.startswith("release edit")]
        self.assertIn("--prerelease", edit[0])
        self.assertNotIn("--latest", edit[0])

    def test_a_test_tag_that_isnt_a_prerelease_is_refused(self):
        self.draft("v0.3.1-rc.1", prerelease=False)
        result = self.sign_release("v0.3.1-rc.1", key=self.main)
        self.assertEqual(result.returncode, 1)
        self.assertIn("isn't a prerelease", result.stderr)

    def test_a_published_release_cant_be_signed(self):
        zip_file = self.draft(draft=False)
        result = self.sign_release("v0.3.1", key=self.main)
        self.assertEqual(result.returncode, 1)
        self.assertIn("published already", result.stderr)
        self.assertFalse(pathlib.Path(str(zip_file) + ".sig").exists())

    def test_an_app_without_the_keys_isnt_signed(self):
        zip_file = self.draft(keys=[self.main_public])
        result = self.sign_release("v0.3.1", key=self.main)
        self.assertEqual(result.returncode, 1)
        self.assertIn("doesn't know the spare key", result.stderr)
        self.assertFalse(pathlib.Path(str(zip_file) + ".sig").exists())

    def test_an_app_of_another_version_isnt_signed(self):
        zip_file = self.draft(version="0.3.0")
        result = self.sign_release("v0.3.1", key=self.main)
        self.assertEqual(result.returncode, 1)
        self.assertIn("is 0.3.0, not 0.3.1", result.stderr)
        self.assertFalse(pathlib.Path(str(zip_file) + ".sig").exists())

    def test_a_key_the_app_doesnt_know_is_refused(self):
        zip_file = self.draft()
        result = self.sign_release("v0.3.1", key=self.stranger)
        self.assertEqual(result.returncode, 1)
        self.assertIn("isn't the main or the spare key", result.stderr)
        self.assertFalse(pathlib.Path(str(zip_file) + ".sig").exists())
        self.assertNoSecret(result.stdout, result.stderr)

    def test_no_key_from_the_keychain_stops_it(self):
        zip_file = self.draft()
        result = self.sign_release("v0.3.1")  # the Keychain has none (or you clicked Deny)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(pathlib.Path(str(zip_file) + ".sig").exists())

    def test_the_spare_from_the_clipboard_then_added_to_the_main(self):
        zip_file = self.draft()
        self.assertEqual(self.sign_release("v0.3.1", key=self.main).returncode, 0)
        (self.fake / "clipboard").write_text(self.spare)
        result = self.sign_release("v0.3.1", "--spare", "--add")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.fake / "clipboard").read_text(), "", "the clipboard is emptied")
        lines = pathlib.Path(str(zip_file) + ".sig").read_text().split()
        self.assertEqual(len(lines), 2, "both signatures")
        for line in lines:
            only = self.work / "only" / zip_file.name
            only.parent.mkdir(exist_ok=True)
            shutil.copy(zip_file, only)
            pathlib.Path(str(only) + ".sig").write_text(line + "\n")
            self.assertEqual(self.verify(only).returncode, 0, "each holds on its own")
        self.assertNoSecret(result.stdout, result.stderr, *self.logs())

    # MARK: sign-lists.sh and check-signatures.sh

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, check=True, capture_output=True, text=True,
                              env=self.env).stdout

    def lists_repo(self):
        """The repository copy with a remote of its own: main has the lists, bot/profiles a changed one."""
        (self.repo / "Sources/Nightforge/SigningKeys.swift").write_text(self.keys_file.read_text())
        for name in LISTS:
            (self.repo / name).parent.mkdir(exist_ok=True)
            shutil.copy(ROOT / name, self.repo / name)
        origin = self.work / "origin.git"
        subprocess.run(["git", "init", "--quiet", "--bare", "-b", "main", str(origin)], check=True)
        self.git("init", "--quiet", "-b", "main")
        self.git("remote", "add", "origin", str(origin))
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "lists")
        self.git("push", "--quiet", "origin", "main")
        self.git("checkout", "--quiet", "-b", "bot/profiles")
        profiles = self.repo / "profiles/profiles.json"
        profiles.write_text(stamped(profiles.read_text().replace('"formatVersion": 1', '"formatVersion": 1, "note": "tonight"', 1),
                                    "2099-01-01T00:00:00Z"))
        self.git("commit", "--quiet", "-am", "Update game profiles")
        self.git("push", "--quiet", "origin", "bot/profiles")
        self.git("checkout", "--quiet", "main")
        return origin

    def sign_lists(self, *args, key=None):
        env = dict(self.env, NIGHTFORGE_SIGNING_KEY_FILE=self.key_file(key or self.main))
        return subprocess.run(["bash", "scripts/sign-lists.sh", *args], cwd=self.repo, env=env, capture_output=True, text=True)

    def checkout(self, origin, branch):
        clone = self.work / f"clone-{branch.replace('/', '-')}-{len(list(self.work.glob('clone-*')))}"
        subprocess.run(["git", "clone", "--quiet", "-b", branch, str(origin), str(clone)], check=True)
        for name in SCRIPTS:
            shutil.copy2(ROOT / "scripts" / name, clone / "scripts" / name)
        return clone

    def check_signatures(self, tree):
        return subprocess.run(["bash", "scripts/check-signatures.sh"], cwd=tree, env=self.env, capture_output=True, text=True)

    def test_the_lists_of_a_pull_request_are_signed_and_pushed(self):
        origin = self.lists_repo()
        before = self.check_signatures(self.checkout(origin, "bot/profiles"))
        self.assertEqual(before.returncode, 1, "unsigned lists fail the check")
        self.assertIn("scripts/sign-lists.sh", before.stdout)

        result = self.sign_lists("bot/profiles")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("--match-head-commit", result.stdout)
        tree = self.checkout(origin, "bot/profiles")
        self.assertEqual(self.check_signatures(tree).returncode, 0, "the pushed branch passes the check")
        self.assertEqual(self.git("log", "-1", "--format=%s", cwd=tree).strip(), "Sign the online lists")
        self.assertEqual(self.git("status", "--porcelain"), "", "your working copy isn't touched")
        self.assertEqual(self.git("branch", "--show-current").strip(), "main")
        self.assertEqual(len(self.git("worktree", "list").splitlines()), 1, "the folder it signed in is gone")
        self.assertNoSecret(result.stdout, result.stderr)

        again = self.sign_lists("bot/profiles")
        self.assertEqual(again.returncode, 0)
        self.assertIn("Nothing to sign", again.stdout)

        # The next night's list replaces tonight's: only that one needs signing again.
        self.git("fetch", "--quiet", "origin")
        self.git("checkout", "--quiet", "-B", "bot/profiles", "origin/bot/profiles")
        profiles = self.repo / "profiles/profiles.json"
        profiles.write_text(stamped(profiles.read_text().replace('"note": "tonight"', '"note": "tomorrow"'), "2099-01-02T00:00:00Z"))
        self.git("commit", "--quiet", "-am", "Update game profiles")
        self.git("push", "--quiet", "origin", "bot/profiles")
        self.git("checkout", "--quiet", "main")
        self.assertEqual(self.check_signatures(self.checkout(origin, "bot/profiles")).returncode, 1, "a changed list fails again")
        result = self.sign_lists("bot/profiles")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("components/manifest.json is signed already", result.stdout)
        self.assertIn("profiles/agw.json is signed already", result.stdout)
        self.assertEqual(self.check_signatures(self.checkout(origin, "bot/profiles")).returncode, 0)

    def test_a_changed_list_needs_a_newer_stamp_than_mains(self):
        """The app takes no list older than the one it has (review M1): signing one that would be, fails."""
        origin = self.lists_repo()
        self.git("checkout", "--quiet", "bot/profiles")
        profiles = self.repo / "profiles/profiles.json"
        main_stamp = json.loads(self.git("show", "main:profiles/profiles.json"))["generated"]
        profiles.write_text(stamped(profiles.read_text().replace('"note": "tonight"', '"note": "again"'), main_stamp))
        self.git("commit", "--quiet", "-am", "Update game profiles")
        self.git("push", "--quiet", "--force", "origin", "bot/profiles")
        self.git("checkout", "--quiet", "main")
        result = self.sign_lists("bot/profiles")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("isn't newer than main's", result.stderr)
        self.assertEqual(self.check_signatures(self.checkout(origin, "bot/profiles")).returncode, 1, "nothing was pushed")

    def test_a_changed_list_fails_the_check(self):
        origin = self.lists_repo()
        result = self.sign_lists("main")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        tree = self.checkout(origin, "main")
        self.assertEqual(self.check_signatures(tree).returncode, 0)
        manifest = tree / "components/manifest.json"
        manifest.write_text(manifest.read_text().replace("https://", "http://", 1))
        result = self.check_signatures(tree)
        self.assertEqual(result.returncode, 1)
        self.assertIn("doesn't hold", result.stdout)

    def test_a_stranger_cant_sign_the_lists(self):
        origin = self.lists_repo()
        result = self.sign_lists("bot/profiles", key=self.stranger)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.check_signatures(self.checkout(origin, "bot/profiles")).returncode, 1, "nothing was pushed")

    # MARK: scripts/install.sh

    def release(self, name, signer=None):
        """A release on disk as GitHub's API lists it, its zip signed by `signer` (a private key)."""
        folder = self.work / name
        contents = folder / "Nightforge.app/Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "9.9"}))
        zip_file = folder / "Nightforge-9.9.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(folder / "Nightforge.app"), str(zip_file)], check=True)
        if signer:
            self.tool(self.keyed_tool, "sign", str(zip_file), stdin=signer)
        api = folder / "latest.json"
        api.write_text(json.dumps({"assets": [{"browser_download_url": zip_file.as_uri() + suffix}
                                              for suffix in (".sig", "")]}, indent=2))
        return zip_file, api

    def install(self, api, keys=None, script=ROOT / "scripts/install.sh"):
        """install.sh with that release and those public keys. As far as it can tell no Nightforge runs,
        and nothing is quit or opened."""
        shims = self.work / "shims"
        shims.mkdir(exist_ok=True)
        for name, body in (("pgrep", "exit 1"), ("osascript", "exit 0"), ("open", "exit 0")):
            write_executable(shims / name, f"#!/bin/bash\n{body}\n")
        target = self.work / f"Applications-{api.parent.name}"
        env = dict(self.env, PATH=f"{shims}:/usr/bin:/bin:/usr/sbin:/sbin", NIGHTFORGE_INSTALL_DIR=str(target),
                   NIGHTFORGE_NO_OPEN="1", NIGHTFORGE_NO_QUIT="1", NIGHTFORGE_RELEASE=api.as_uri(),
                   NIGHTFORGE_SIGNING_KEYS=(keys or self.keys_file).as_uri())
        result = subprocess.run(["bash", str(script)], env=env, capture_output=True, text=True, timeout=120)
        return result, target / "Nightforge.app"

    def test_the_installer_takes_a_release_signed_with_either_key(self):
        for signer in (self.main, self.spare):
            with self.subTest(main=signer == self.main):
                zip_file, api = self.release(f"release-{signer == self.main}", signer)
                signature = pathlib.Path(f"{zip_file}.sig")
                signature.write_text("not a signature\n" + signature.read_text())
                result, app = self.install(api)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Nightforge 9.9 installed", result.stdout)
                self.assertTrue((app / "Contents/Info.plist").exists())

    def test_the_installer_refuses_what_the_maintainer_didnt_sign(self):
        only_main = self.work / "only-main.swift"
        only_main.write_text(self.with_keys((ROOT / "Sources/Nightforge/SigningKeys.swift").read_text(), self.main_public, ""))
        for case in ("unsigned", "changed after signing", "a key main doesn't list", "no keys on main yet"):
            with self.subTest(case):
                zip_file, api = self.release(case.replace(" ", "-"), None if case == "unsigned" else
                                             self.spare if case == "a key main doesn't list" else self.main)
                keys = {"a key main doesn't list": only_main,
                        "no keys on main yet": ROOT / "Sources/Nightforge/SigningKeys.swift"}.get(case)
                if case == "changed after signing":
                    with zip_file.open("ab") as file:
                        file.write(b"\0")
                result, app = self.install(api, keys)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("isn't signed by its maintainer", result.stderr)
                self.assertFalse(app.exists(), "nothing installed")

    def test_the_0_3_0_zip_counts_by_its_checksum(self):
        """0.3.0 came out before the signatures: its zip by its SHA-256, here a stand-in's."""
        zip_file, api = self.release("old")
        text = (ROOT / "scripts/install.sh").read_text()
        self.assertRegex(text, r'UNSIGNED_030="[0-9a-f]{64}"')
        script = self.work / "install.sh"
        script.write_text(re.sub(r'UNSIGNED_030="[0-9a-f]{64}"',
                                 f'UNSIGNED_030="{hashlib.sha256(zip_file.read_bytes()).hexdigest()}"', text))
        result, app = self.install(api, script=script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(app.exists())

    def test_the_installers_ed25519_against_rfc_8032(self):
        """install.sh's own Ed25519 check (Perl, no developer tools) with RFC 8032's test vectors."""
        text = (ROOT / "scripts/install.sh").read_text()
        function = re.search(r"^ed25519_verify\(\) \{\n.*?^PERL\n\}\n", text, re.M | re.S).group(0)
        vectors = [
            ("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
             "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
            ("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
             "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
            ("fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
             "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
        ]
        order = 2 ** 252 + 27742317777372353535851937790883648493

        def holds(key, message, signature):
            (self.work / "message").write_bytes(message)
            (self.work / "message.sig").write_text(base64.b64encode(signature).decode() + "\n")
            return subprocess.run(["bash", "-c", function + 'ed25519_verify "$@"', "-", str(self.work / "message"),
                                   str(self.work / "message.sig"), base64.b64encode(key).decode()]).returncode == 0

        for key, message, signature in vectors:
            key, message, signature = bytes.fromhex(key), bytes.fromhex(message), bytes.fromhex(signature)
            with self.subTest(message=message.hex()):
                self.assertTrue(holds(key, message, signature))
                self.assertFalse(holds(key, message + b"!", signature), "another message")
                self.assertFalse(holds(key, message, signature[:5] + bytes([signature[5] ^ 1]) + signature[6:]), "R changed")
                # S + L signs the same, but RFC 8032 (and CryptoKit) take only S below L.
                s = int.from_bytes(signature[32:], "little") + order
                self.assertFalse(holds(key, message, signature[:32] + s.to_bytes(32, "little")), "S + L")
        self.assertFalse(holds(bytes.fromhex(vectors[0][0]), b"", bytes.fromhex(vectors[1][2])), "another key's signature")


class InstallScript(unittest.TestCase):
    def test_the_installer_takes_the_zip_not_its_signature(self):
        """scripts/install.sh (from main, also for 0.3.0 players) picks the zip of a signed release."""
        script = (ROOT / "scripts/install.sh").read_text()
        pattern = script.split("grep -o '", 1)[1].split("'", 1)[0]
        base = "https://github.com/LordHayne/Nightforge/releases/download/v0.3.1/Nightforge-0.3.1"
        for order in ([".dmg", ".zip", ".zip.sig"], [".zip.sig", ".dmg", ".zip"]):
            answer = json.dumps({"assets": [{"browser_download_url": base + suffix} for suffix in order]}, indent=2)
            picked = subprocess.run(f"grep -o '{pattern}' | head -1 | cut -d'\"' -f4", shell=True, input=answer,
                                    capture_output=True, text=True).stdout.strip()
            self.assertEqual(picked, base + ".zip", order)


if __name__ == "__main__":
    unittest.main()
