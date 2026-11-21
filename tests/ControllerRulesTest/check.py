"""Every Button, Toggle, Picker and Menu in Nightforge's views can be reached with a controller: it says
`.padFocus`, or it's listed below with the reason why it doesn't need to (mouse-only arrows, a control the pad
works through another way). A control added later fails here until it's one or the other. No two controls
may share a pad name either: the second one replaces the first (PadFocus.register), which then can't be
reached."""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / "tests/Shared"))
from swift_views import blank_comments, controls

# (file, a piece of the control's text): why the pad doesn't need it there.
NO_PAD_NEEDED = {
    ("App.swift", 'L10n.t("Rescan Library")'): "the Mac's menu bar, ⌘R",
    ("App.swift", 'L10n.t("Settings …")'): "the Mac's menu bar; the pad's menu opens Settings",
    ("App.swift", 'L10n.t("Restart Nightforge")'): "the Mac's menu bar; Settings has it with focus",
    ("App.swift", 'L10n.t("Quit Nightforge")'): "the Mac's menu bar; the pad's menu quits",
    ("App.swift", 'L10n.t("Full Screen")'): "the Mac's menu bar",
    ("GameMenuViews.swift", "action.title(game), role:"): "the right-click menu; the quick menu has the same entries (GameMenu.padID)",
    ("GameMenuViews.swift", 'Image(systemName: "ellipsis")'): "the mouse's way to the quick menu; the pad holds ☰",
    ("HomeStage.swift", "Button(action: action) {\n            Image(systemName: symbol)"): "the mouse's arrows; the pad moves the stage itself",
    ("LauncherViews.swift", "Text(state.actionLabel).displayFont(15)"): "inside the card, whose own .padFocus runs the same action",
    ("LibraryGrid.swift", "model.searchText = \"\""): "the mouse's × in the search field; Esc and B clear it",
    ("LibraryView.swift", "clock.arrow.circlepath"): "SaveChoice.option: both calls add .padFocus (checked below)",
    ("LibraryView.swift", "isRunning && !busy"): "the big button: its call adds .padFocus (checked below)",
    ("SignInStage.swift", "model.cancelSignIn()"): "the hint for the mouse; B cancels (InputRouter)",
    ("SignInStage.swift", 'L10n.t("Show Window Again")'): "the pad brings the window with A (InputRouter)",
    ("SignInStage.swift", 'L10n.t("Sign In Later")'): "A on Epic's stage presses it, it only shows with a controller (InputRouter, checked below)",
    ("SignInStage.swift", "Hint(.pad(model.padSymbols.details)"): "X changes between phone and keyboard (InputRouter, checked below)",
    ("SignInStage.swift", "Button(title) { model.switchSignInWay() }"): "only without a controller: with one, it's the hint that X presses",
    ("PadKeyboardView.swift", "Button(action: close)"): "the X for the mouse; B closes the keyboard (InputRouter)",
    ("PhoneSignInView.swift", 'L10n.t("New Code")'): "A asks for it once the old code has run out (InputRouter, checked below)",
}

# A pad name used by two controls that can't be on screen together (they're different pages or branches).
SHARED_NAMES = {
    "play": "the Home button and the game page's button: never on one page",
    "empty.rescan": "two branches of the empty library",
}

problems, seen_allowed = [], set()
found = controls(root)
for control in found:
    if ".padFocus" in control.body:
        continue
    allowed = [key for key in NO_PAD_NEEDED if key[0] == control.file and key[1] in control.body]
    if allowed:
        seen_allowed.update(allowed)
    else:
        problems.append(f"{control}\n    the controller can't reach it: add .padFocus, or list it in tests/ControllerRulesTest/check.py with why")
for key in NO_PAD_NEEDED:
    if key not in seen_allowed:
        problems.append(f"{key}: no control matches this exception any more; take it out of the list")

# On the sign-in stage the pad doesn't move a highlight (InputRouter.perform): A and X go to the stage itself.
router = blank_comments((root / "Sources/Nightforge/InputRouter.swift").read_text())
for call in ("model?.signInPrimary()", "model?.switchSignInWay()"):
    if call not in router:
        problems.append(f"InputRouter.swift doesn't call {call}: the stage's buttons above can't be pressed with the pad")

# The calls that add the focus for the two shared views above.
view = blank_comments((root / "Sources/Nightforge/LibraryView.swift").read_text())
options = [m.start() for m in re.finditer(r"(?<!func )\boption\(title:", view)]
for start in options:
    # up to the next blank-looking statement: the focus is on the same or the following few lines
    if ".padFocus" not in view[start:start + 420]:
        problems.append(f"LibraryView.swift:{view[:start].count(chr(10)) + 1}: SaveChoice.option() without .padFocus")
if len(options) != 2:
    problems.append(f"expected 2 calls of option(title:) in LibraryView.swift, found {len(options)}: check its .padFocus")

names = {}
for path in sorted((root / "Sources/Nightforge").glob("*.swift")):
    text = blank_comments(path.read_text())
    for match in re.finditer(r'\.padFocus\(\s*"([^"\\]+)"', text):
        names.setdefault(match.group(1), []).append(f"{path.name}:{text[:match.start()].count(chr(10)) + 1}")
for name, places in sorted(names.items()):
    if len(places) > 1 and name not in SHARED_NAMES:
        problems.append(f'pad name "{name}" is used by {", ".join(places)}: the later one replaces the other (PadFocus.register)')
for name in SHARED_NAMES:
    if len(names.get(name, [])) < 2:
        problems.append(f'"{name}" isn\'t shared any more: take it out of the list')

for problem in problems:
    print("✗ " + problem)
if problems:
    print(f"{len(problems)} problem(s)")
    sys.exit(1)
if len(found) < 100:
    print(f"✗ only {len(found)} controls found: did the scanner break?")
    sys.exit(1)
print(f"✓ Controller reach ({len(found)} controls, {len(names)} pad names)")
