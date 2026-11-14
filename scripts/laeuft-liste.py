#!/usr/bin/env python3
"""Builds the list of games that start and run under Nightforge, with what was measured of them:
docs/laeuft/laeuft.json for tools (the landing page) and docs/laeuft/LAEUFT.md for people.
What the list claims, and what its numbers do and don't mean: docs/LAEUFT-LISTE.md.

Only Nightforge's own records go in – the start evidence (StartEvidence, start-evidence.jsonl) and the
game test's reports (GameTest, report.json, formats 1 and 2). Nothing from other sources, nothing guessed:
what no record holds is null in the JSON and "nicht gemessen" in the table. The inputs are only read.
The same inputs give the same files, byte for byte: nothing in them depends on when or where this ran.

With the stores' own lists of what is installed (Steam, Epic, GOG – read only, never changed) it also writes
the checklist, abhakliste.json and ABHAKLISTE.md: per installed game its size and whether a clean start and a
frame rate that counts are on record for the current build – what the player may uninstall, which only they do.

Usage: laeuft-liste.py [--evidence FILE]... [--names FILE] [--out DIR] [--since DATE] [--no-stock] [REPORT.json | FOLDER]...
Defaults: this Mac's evidence, game test runs and stores, docs/laeuft/namen.json, docs/laeuft.
"""

import argparse
import datetime
import getpass
import json
import pathlib
import re
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUPPORT = pathlib.Path.home() / "Library/Application Support/Nightforge"
FORMAT_VERSION = 1
REPORT_FORMATS = (1, 2)
LEVELS = ("laeuft", "startet", "anti-cheat", "kein-bild")
# A way's first word (LaunchAttempt.id), or "mac" for a Mac version.
LAYERS = ("wined3d", "dxvk", "dxmt", "d3dmetal", "mac")
# Ways that report no frame rates at all (GameTest.noFrames).
SILENT = ("d3dmetal", "wined3d", "mac")
# A frame limit and a number measured under it. An average from REACHED of the limit on reaches it (FramePacing's
# share); one above PAST of it ran past it: the limit didn't take hold, and the number is a free one.
REACHED, PAST = 0.95, 1.05
# Ways with nothing that holds a limit, whatever a run recorded as asked for: Apple's D3DMetal 3.0 (winecx 4.7.3)
# has no switch for the frame rate (docs/LAEUFT-LISTE.md, section 3). Goes once an engine part paces it.
LIMITLESS = ("d3dmetal",)
# The limit states that leave a number free.
FREE = ("none", "noneOnWay", "notApplied")
# A free number whose lowest ten seconds stay this close to its average hardly moved over the whole measuring:
# a film or a lock of the game's own sets that pace, not the Mac. Said from a minute of measuring on.
STEADY, STEADY_SECONDS = 0.95, 60
# Outcomes of a game test that say nothing about the game: nobody tried, or only the player could go on.
UNTRIED = ("skipped", "needsPlayer", "unknown")
UNKNOWN_MAC = "unbekannt"
# Skips of a game test that no run mends: someone has to look at the game by hand (GameTest.byHand).
BY_HAND = {"antiCheat": "Anti-Cheat sperrt es auf dem Mac", "vrOnly": "nur mit VR-Brille", "otherBottle": "liegt in einer CrossOver-Flasche",
           "versionSwitch": "erster Start der anderen Fassung (Spielstände würden übertragen)", "battleNet": "Battle.net-Spiele prüft der Spieletest nicht"}
# LaunchHealth.drawingWindow: this long with a picture counts as working.
WATCHED = 180
# Steam's tools, no games (Library.ignoredAppIDs).
NO_GAMES = {"228980", "1070560", "1391110", "1628350", "1493710", "2180100", "2805730"}
STORES = {"steam": "Steam", "epic": "Epic Games", "gog": "GOG", "battlenet": "Battle.net"}
OUTCOMES = {
    "hang": "hängt ohne Bild", "noWindow": "kein Fenster, beendet", "crash": "abgestürzt ohne Bild",
    "dialog": "wartet auf einen Klick in seinem eigenen Fenster", "startWindow": "braucht einen Klick im Startfenster",
    "noStart": "nicht gestartet",
}


# MARK: - Reading

def read_evidence(path):
    """The evidence's entries in the file's order; a line that isn't one is left out."""
    entries = []
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict) and entry.get("game") and entry.get("event") and entry.get("at"):
            entries.append(entry)
    return entries


def report_files(paths):
    """The reports under `paths`: a file as it is, a folder's report.json files (a run's folder, GameTests)
    and <date>.json files (docs/spieletest)."""
    files = []
    for path in map(pathlib.Path, paths):
        if path.is_dir():
            files += sorted(path.glob("**/*.json"))
        elif path.is_file():
            files.append(path)
    return files


def read_reports(paths):
    """The game test reports of a format this knows, each run once (a copy in docs/spieletest is the same
    run), oldest first."""
    runs = {}
    for file in report_files(paths):
        try:
            report = json.loads(file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(report, dict) or report.get("formatVersion") not in REPORT_FORMATS:
            continue
        if not isinstance(report.get("games"), list) or not report.get("started"):
            continue
        runs.setdefault((report["started"], report.get("mac") or UNKNOWN_MAC), report)
    return [runs[key] for key in sorted(runs)]


def read_names(path):
    """Names for games no report names: {"steam.35140": "Batman: …"}."""
    try:
        names = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return {key: name for key, name in names.items() if isinstance(name, str) and name.strip()} if isinstance(names, dict) else {}


# MARK: - What the evidence says

def layer(way):
    return (way or "").split(" ")[0]


def seconds_between(earlier, later):
    def moment(stamp):
        return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    try:
        return (moment(later) - moment(earlier)).total_seconds()
    except ValueError:
        return float("inf")


def parts_of(start):
    """The engine's parts a start names, or None."""
    parts = start.get("parts")
    return [part for part in parts if isinstance(part, str)] if isinstance(parts, list) and parts else None


def launch_verdict(launch):
    """What one launch says about a clean start, and whether that settles it. Clean: one start, no failure, and
    working – `worked`, or a way already confirmed that kept its picture for `WATCHED` seconds."""
    if launch["starts"] > 1:
        return "severalWays", True
    if launch["failed"] or launch["gaveUp"]:
        return "failed", True
    ended = launch["ended"]
    if launch["worked"] or (launch["known"] and ended and ended["picture"] and (ended["seconds"] or 0) >= WATCHED):
        return "ok", True
    if ended is None:
        return "noOutcome", False
    return ("tooShort" if ended["picture"] else "endedEarly"), False


def stated(start):
    """The build a start names – Nightforge's version, when it was built, the engine's parts, as `build_of`
    gives a report's – or None for a line from before 14.11.2026, which says the engine only."""
    if not start.get("nightforge") or not start.get("parts"):
        return None
    return (start["nightforge"], start.get("built"), tuple(start["parts"]))


def from_evidence(entries):
    """Per game and Mac: its starts, the way that is confirmed and how it got there, what came after.
    `worked`, `failed`, `ended` and `gaveUp` carry no Mac or engine: they belong to the game's start before them.
    Confirmed is a way that `worked`, or that a start found confirmed already (`known`: from before the record
    began) – for as long as no later start of it was an unconfirmed one again (`withdrawn`)."""
    games = {}
    current = {}
    for entry in entries:
        key, event, way = entry["game"], entry["event"], entry.get("way")
        if event == "started":
            current[key] = entry
        start = current.get(key, {})
        mac = start.get("mac") or UNKNOWN_MAC
        game = games.setdefault((key, mac), {
            "starts": 0, "ways": [], "confirmed": {}, "currentWay": None, "failedSince": {}, "picture": None,
            "failed": 0, "gaveUp": False, "sawKnown": False, "last": None, "lastWay": None, "antiCheat": None,
            "kind": None, "profiled": {}, "withdrawn": {}, "launches": [], "name": None,
        })
        game["last"] = entry["at"]
        if way:
            game["lastWay"] = way

        def confirm(basis):
            if way not in game["confirmed"]:
                first = basis == "worked" and not game["sawKnown"]
                game["confirmed"][way] = {
                    "way": way, "at": entry["at"], "basis": basis,
                    "engine": start.get("engine") if start.get("way") == way else None,
                    "nightforge": start.get("nightforge") if start.get("way") == way else None,
                    "built": start.get("built") if start.get("way") == way else None,
                    "parts": parts_of(start) if start.get("way") == way else None,
                    # How many starts and ways it took – only for a game the record saw from its first start.
                    "starts": game["starts"] if first else None,
                    "ways": len(game["ways"]) if first else None,
                }
            game["currentWay"] = way
            game["failedSince"][way] = 0
            game["withdrawn"].pop(way, None)

        # One launch: a start, and each further way the ladder went on to right after a failure.
        launches = game["launches"]
        if event == "started":
            last = launches[-1] if launches else None
            if not (last and last["open"] and last["failedAt"] and seconds_between(last["failedAt"], entry["at"]) <= 15):
                launches.append({"at": entry["at"], "starts": 0, "ways": [], "failed": 0, "failedAt": None, "open": True, "worked": False,
                                 "gaveUp": False, "known": bool(entry.get("known")), "ended": None, "engine": entry.get("engine"),
                                 "nightforge": entry.get("nightforge"), "built": entry.get("built"), "parts": parts_of(entry),
                                 "mac": mac})
            launches[-1]["starts"] += 1
            launches[-1]["failedAt"] = None
            if way and way not in launches[-1]["ways"]:
                launches[-1]["ways"].append(way)
        elif launches and launches[-1]["open"]:
            if event == "failed":
                launches[-1]["failed"] += 1
                launches[-1]["failedAt"] = entry["at"]
            elif event == "worked":
                launches[-1]["worked"] = True
            elif event == "ended":
                launches[-1].update(ended={"picture": bool(entry.get("picture")), "seconds": entry.get("seconds")}, open=False)
            elif event == "gaveUp":
                launches[-1].update(gaveUp=True, open=False)

        if event == "started":
            game["starts"] += 1
            if way and way not in game["ways"]:
                game["ways"].append(way)
            if isinstance(entry.get("name"), str) and entry["name"].strip():
                game["name"] = entry["name"].strip()
            kind = entry.get("kind")
            if isinstance(kind, dict):
                game["kind"] = kind
                if "antiCheat" in kind:
                    game["antiCheat"] = bool(kind["antiCheat"])
            if entry.get("profiled") and way:
                game["profiled"][way] = True
            if entry.get("known"):
                game["sawKnown"] = True
                confirm("known")
            elif way in game["confirmed"]:
                # Started as unconfirmed again: Nightforge itself took the confirmation back (LaunchHealth.unconfirm,
                # a changed list of ways). It stands again with the next `worked`.
                game["withdrawn"].setdefault(way, entry["at"])
        elif event == "worked":
            confirm("worked")
        elif event == "failed":
            game["failed"] += 1
            if way in game["confirmed"]:
                game["failedSince"][way] = game["failedSince"].get(way, 0) + 1
        elif event == "ended":
            if entry.get("picture"):
                game["picture"] = {"way": way, "at": entry["at"]}
        elif event == "gaveUp":
            game["gaveUp"] = True
    return games


# MARK: - What the game tests say

def clean_ways(entry):
    """The ways a run took. Reports up to 11.11.2026 can hold a note of the start as one more way."""
    ways = [way.get("way") for way in entry.get("ways") or [] if isinstance(way, dict) and layer(way.get("way")) in LAYERS]
    if not ways and layer(entry.get("way")) in LAYERS:
        ways = [entry["way"]]
    return ways


def from_reports(reports):
    """Per game, version and Mac: its runs, oldest first, and the name the newest report has for it."""
    games, names = {}, {}
    for report in reports:
        mac = report.get("mac") or UNKNOWN_MAC
        for entry in report["games"]:
            if not isinstance(entry, dict) or not entry.get("store") or not entry.get("storeID"):
                continue
            key = f"{entry['store']}.{entry['storeID']}"
            if (entry.get("game") or "").strip():
                names[key] = entry["game"].strip()
            ways = clean_ways(entry)
            games.setdefault((key, entry.get("platform") or "windows", mac), []).append({
                "at": entry.get("startedAt") or report["started"], "format": report.get("formatVersion"),
                "nightforge": report.get("nightforge"), "engine": report.get("engine") or [], "built": report.get("built"),
                "check": entry.get("check"), "platform": entry.get("platform") or "windows",
                "runsOn": report.get("runsOn"), "playSeconds": report.get("playSeconds"), "frameLog": bool(report.get("frameLog")),
                "wineFps": bool(report.get("wineFps")),
                "onBattery": bool(report.get("onBattery")), "lowPower": bool(report.get("lowPower")),
                "outcome": entry.get("outcome"), "skip": entry.get("skip"), "ways": ways, "way": ways[-1] if ways else None,
                "secondsToPicture": entry.get("secondsToPicture"), "frames": entry.get("frames"),
                "measure": entry.get("measure") or {}, "loadLow": (entry.get("load") or {}).get("low"),
                "issues": entry.get("issues") or [], "notYet": bool(entry.get("notYet")),
            })
    return games, names


def build_of(run):
    """What tells one build from another: the version, the program's date (format 2), the engine's parts."""
    return (run.get("nightforge"), run.get("built"), tuple(run.get("engine") or []))


def no_frames(run):
    """Why a picture has no frame rate (GameTest.noFrames): the run's own word, else by its way."""
    # With Apple's Metal HUD logging the frames, D3DMetal reports; with Wine's fps channel on, Wine's own Direct3D.
    silent = [way for way in SILENT if not (way == "d3dmetal" and run["frameLog"]) and not (way == "wined3d" and run["wineFps"])]
    return run["measure"].get("noFrames") or ("wayReportsNone" if layer(run["way"]) in silent else "noneInLog")


def check_of(run):
    """A run's check of one game (GameTest.check), worked out the same way for reports from before it was written."""
    if isinstance(run["check"], dict) and run["check"].get("start") and run["check"].get("fps"):
        return run["check"]["start"], run["check"]["fps"]
    picture, frames = run["outcome"] == "picture", isinstance(run["frames"], dict)
    if run["outcome"] == "needsPlayer":
        start = "neededPlayer"
    elif not picture:
        start = "noPicture"
    elif len(run["ways"]) > 1:
        start = "severalWays"
    elif "crashed" in run["issues"]:
        start = "endedByItself"
    elif not frames and (run["playSeconds"] or 0) < WATCHED:
        start = "tooShort"
    else:
        start = "ok"
    if not picture:
        fps = "noPicture"
    elif not frames:
        fps = no_frames(run)
    elif run["onBattery"] or run["lowPower"] or run["measure"].get("throttled"):
        fps = "throttled"
    elif run["loadLow"] is False:
        fps = "loadHigh"
    else:
        fps = "ok"
    return start, fps


def public_gaps(run, fps):
    """Why a run's frame rate can't stand in a public list – empty when it can: every number needs its
    conditions on record, and none measured on battery, throttled or on a busy Mac belongs there."""
    measure, gaps = run["measure"], []
    if fps is None:
        return ["noFps"]
    if run["platform"] != "mac" and measure.get("frameLimit") is None:
        gaps.append("limitUnknown")
    if run["onBattery"]:
        gaps.append("onBattery")
    if run["lowPower"]:
        gaps.append("lowPower")
    if measure.get("throttled"):
        gaps.append("throttled")
    if run["loadLow"] is not True:
        gaps.append("loadHigh" if run["loadLow"] is False else "loadUnknown")
    if not run["nightforge"] or not run["engine"]:
        gaps.append("buildUnknown")
    if not (measure.get("swapchain") or measure.get("displayMode") or measure.get("window")):
        gaps.append("sizeUnknown")
    if not fps.get("seconds"):
        gaps.append("durationUnknown")
    return gaps


def limit_state(way, limit, fps):
    """What the frame limit did to a number: "held", "notReached", "notApplied" (the average ran past it),
    "noneOnWay" (the way has nothing that holds one), "none" (none was set). None without a number or a limit on record."""
    if limit is None or not fps:
        return None
    if limit <= 0:
        return "none"
    if layer(way) in LIMITLESS:
        return "noneOnWay"
    if fps["average"] > limit * PAST:
        return "notApplied"
    return "held" if fps["average"] >= limit * REACHED else "notReached"


def steady(state, fps):
    """A free number that hardly moved: no measure of what the Mac can do."""
    if state not in FREE or fps.get("low") is None or (fps.get("seconds") or 0) < STEADY_SECONDS:
        return False
    return fps["low"] >= fps["average"] * STEADY


def measured(run):
    """What one run with a picture measured, in one shape whatever the report's format: what it doesn't hold is null."""
    frames, measure = run["frames"], run["measure"]
    fps = None
    if isinstance(frames, dict) and frames.get("average") is not None:
        fps = {name: frames.get(name) for name in ("average", "low", "periods", "seconds", "slowestFrame", "slowestTypical", "source",
                                                   "onePercentLow", "gpuTime")}
    none = None
    if fps is None:
        none = no_frames(run)
    # Under a limit a number says what the limit did to it, not what the Mac could do; a free one that hardly
    # moved says neither.
    state = limit_state(run["way"], measure.get("frameLimit"), fps)
    still = steady(state, fps) if fps else False
    gaps = public_gaps(run, fps) + (["steady"] if still else [])
    return {
        "limitState": state, "steady": still, "public": not gaps, "notPublic": gaps, "throttled": measure.get("throttled"), "built": run["built"],
        "at": run["at"], "nightforge": run["nightforge"], "engine": run["engine"], "runsOn": run["runsOn"],
        "reportFormat": run["format"], "way": run["way"], "playSeconds": run["playSeconds"],
        "secondsToPicture": run["secondsToPicture"], "loadLow": run["loadLow"],
        "onBattery": run["onBattery"], "lowPower": run["lowPower"],
        "endedByItself": "crashed" in run["issues"], "fps": fps, "noFrames": none, "frameLog": run["frameLog"],
        "wineFps": run["wineFps"],
        "frameLimit": measure.get("frameLimit"), "refreshRate": measure.get("refreshRate"), "metalFX": measure.get("metalFX"),
        "window": measure.get("window"), "screen": measure.get("screen"), "swapchain": measure.get("swapchain"),
        "upscaledTo": measure.get("upscaledTo"), "displayMode": measure.get("displayMode"),
    }


# MARK: - What is installed

def parse_vdf(text):
    """Valve's key-value text ("key" "value", "key" { … }) as nested dicts."""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text)

    def block(index):
        out = {}
        while index < len(tokens):
            text_, brace = tokens[index]
            if brace == "}":
                return out, index + 1
            if brace == "{" or index + 1 >= len(tokens):
                index += 1
                continue
            key, index = text_.replace("\\\\", "\\"), index + 1
            if tokens[index][1] == "{":
                out[key], index = block(index + 1)
            else:
                out[key], index = tokens[index][0].replace("\\\\", "\\"), index + 1
        return out, index

    return block(0)[0]


def read_text(path):
    try:
        return pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def read_json(path):
    try:
        return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def place(path):
    """Where a game lies, without the drive's name: that one is the player's."""
    return "extern" if str(path).startswith("/Volumes/") else "intern"


def steam_stock(steam, platform, prefix=None):
    """Steam's installed games from libraryfolders.vdf and each library's appmanifest files. Under Wine a
    library's path is a Windows one: C: is the prefix's drive_c, Z: the Mac's root."""
    folders = parse_vdf(read_text(pathlib.Path(steam) / "steamapps/libraryfolders.vdf") or "").get("libraryfolders", {})
    games = []
    for folder in folders.values():
        if not isinstance(folder, dict) or not folder.get("path"):
            continue
        path = folder["path"]
        if prefix is not None:
            drive, rest = path[:2].upper(), path[2:].replace("\\", "/")
            if drive == "C:":
                path = str(pathlib.Path(prefix) / "drive_c") + rest
            elif drive == "Z:":
                path = rest
            else:
                continue
        apps = folder.get("apps") if isinstance(folder.get("apps"), dict) else {}
        for app, listed in sorted(apps.items()):
            if app in NO_GAMES:
                continue
            manifest = parse_vdf(read_text(pathlib.Path(path) / f"steamapps/appmanifest_{app}.acf") or "").get("AppState", {})
            sizes = [int(value) for value in (manifest.get("SizeOnDisk"), listed) if str(value or "").isdigit() and int(value) > 0]
            if not sizes:
                continue  # listed, nothing on the disk yet
            games.append({"key": f"steam.{app}", "platform": platform, "name": (manifest.get("name") or "").strip() or None,
                          "sizeBytes": sizes[0], "location": place(path)})
    return games


def epic_stock(support):
    """Epic's installed games from legendary's installed.json; an add-on's size counts for the game it lies in."""
    installed = read_json(pathlib.Path(support) / "Epic/legendary/installed.json")
    games, extra = [], {}
    for item in (installed or {}).values() if isinstance(installed, dict) else []:
        if not isinstance(item, dict) or not item.get("app_name"):
            continue
        size = item.get("install_size") if isinstance(item.get("install_size"), int) else 0
        if item.get("is_dlc"):
            extra[item.get("install_path")] = extra.get(item.get("install_path"), 0) + size
            continue
        games.append({"key": f"epic.{item['app_name']}", "platform": "mac" if str(item.get("platform", "")).lower() == "mac" else "windows",
                      "name": (item.get("title") or "").strip() or None, "sizeBytes": size, "location": place(item.get("install_path") or ""),
                      "_path": item.get("install_path")})
    for game in games:
        game["sizeBytes"] += extra.get(game.pop("_path"), 0)
    return games


def gog_stock(support):
    """GOG's installed games from Nightforge's own installed.json, their names from its library.json."""
    installed = read_json(pathlib.Path(support) / "GOG/installed.json")
    library = read_json(pathlib.Path(support) / "GOG/library.json") or {}
    titles = {str(game.get("id")): game.get("title") for game in library.get("games", []) if isinstance(game, dict)} if isinstance(library, dict) else {}
    games = []
    for ident, item in (installed or {}).items() if isinstance(installed, dict) else []:
        if not isinstance(item, dict):
            continue
        path = urllib.parse.unquote(urllib.parse.urlparse(str(item.get("path") or "")).path)
        games.append({"key": f"gog.{ident}", "platform": "windows" if str(item.get("platform", "windows")).lower() == "windows" else "mac",
                      "name": (titles.get(str(ident)) or "").strip() or None,
                      "sizeBytes": item.get("size") if isinstance(item.get("size"), int) else 0, "location": place(path)})
    return games


def read_stock(support=SUPPORT, mac_steam=None):
    """Every installed game of Steam (Windows and Mac), Epic and GOG, by key and version. Only read."""
    support = pathlib.Path(support)
    mac_steam = pathlib.Path(mac_steam) if mac_steam else pathlib.Path.home() / "Library/Application Support/Steam"
    prefix = support / "Prefix"
    games = (steam_stock(prefix / "drive_c/Program Files (x86)/Steam", "windows", prefix) + steam_stock(mac_steam, "mac")
             + epic_stock(support) + gog_stock(support))
    unique = {}
    for game in games:
        unique.setdefault((game["key"], game["platform"]), game)
    return [unique[key] for key in sorted(unique)]


# MARK: - The list

def build(evidence_lists, reports, names=None, stock=None):
    """The list's document: one entry per game, version and Mac that anything was recorded of."""
    names = names or {}
    stock_names = {game["key"]: game["name"] for game in stock or [] if game.get("name")}
    starts, evidence_names = {}, {}
    for entries in evidence_lists:
        for (key, mac), game in from_evidence(entries).items():
            starts[(key, "windows", mac)] = game  # the evidence records Windows versions only
            if game["name"]:
                evidence_names[key] = game["name"]
    tests, report_names = from_reports(reports)
    # Per Mac: the build that ran last there, and every time something named a build – for what an entry
    # says of the current state beside the values it keeps from the build they were measured on.
    launches = [launch for game in starts.values() for launch in game["launches"]]
    macs = sorted({mac for _, _, mac in set(starts) | set(tests)})
    marks = {mac: build_marks(reports, launches, mac) for mac in macs}
    currents = {mac: current_build(reports, launches, mac=mac) for mac in macs}
    entries = []
    for key, platform, mac in sorted(set(starts) | set(tests)):
        evidence, runs = starts.get((key, platform, mac)), tests.get((key, platform, mac), [])
        tried = [run for run in runs if run["outcome"] not in UNTRIED]
        pictures = [run for run in tried if run["outcome"] == "picture"]
        blocked = bool(runs) and runs[-1]["skip"] == "antiCheat"
        if not evidence and not tried and not blocked:
            continue  # only ever skipped for something else: nothing is known of it

        confirmed = withdrawn = None
        if evidence and evidence["currentWay"]:
            current = evidence["currentWay"]
            if current in evidence["withdrawn"]:
                withdrawn = {"way": current, "at": evidence["withdrawn"][current], "confirmedAt": evidence["confirmed"][current]["at"]}
            else:
                confirmed = evidence["confirmed"][current]
        # The newest picture: a game test's run, or a start the evidence saw end with one. A picture stays one –
        # a start without one after it is said beside it (`noPictureSince`) and takes nothing back, as a newer
        # build takes no value away.
        seen = []
        if pictures:
            seen.append((pictures[-1]["at"], pictures[-1]["way"], "gameTest"))
        if evidence and evidence["picture"]:
            seen.append((evidence["picture"]["at"], evidence["picture"]["way"], "evidence"))
        newest = max(seen, key=lambda one: one[0]) if seen else None

        if blocked:
            level, way = "anti-cheat", None
        elif confirmed:
            level, way = "laeuft", confirmed["way"]
        elif newest:
            level, way = "startet", newest[1]
        else:
            level = "kein-bild"
            way = (tried[-1]["way"] if tried else None) or (evidence["lastWay"] if evidence else None)
        since = None
        if level == "startet":
            after = [(run["at"], "gameTest") for run in tried if run["outcome"] != "picture" and run["at"] > newest[0]]
            after += [(launch["at"], "evidence") for launch in (evidence["launches"] if evidence else [])
                      if launch["at"] > newest[0] and (launch["failed"] or launch["gaveUp"]) and not launch["worked"]]
            if after:
                since = dict(zip(("at", "by"), max(after)), count=len(after))

        # A value doesn't go with a newer build or a newer run without one: the newest that can stand in public,
        # else the newest with a frame rate, else the newest picture – each with the build it was measured on.
        chosen = None
        if level in ("laeuft", "startet") and pictures:
            on_way = [measured(run) for run in pictures if run["way"] == way] or [measured(run) for run in pictures]
            chosen = next((m for m in reversed(on_way) if m["public"]), None) or next((m for m in reversed(on_way) if m["fps"]), on_way[-1])
        # What the current build has seen of it: its newest start there, with or without a picture.
        current, now = currents.get(mac), None
        if current:
            here = [(run["at"], run["outcome"] == "picture", "gameTest") for run in tried if build_of(run) == build_of(current)]
            here += [(launch["at"], bool(launch["worked"] or (launch["ended"] and launch["ended"]["picture"])), "evidence")
                     for launch in (evidence["launches"] if evidence else [])
                     if build_of_launch(launch, marks[mac]) == build_of(current)]
            if here:
                now = dict(zip(("at", "picture", "by"), max(here)))
        # True, false, or null where no record says.
        anti_cheat = True if blocked else evidence["antiCheat"] if evidence else None
        notes = []
        if anti_cheat and level in ("laeuft", "startet"):
            notes.append("antiCheatOnlineUnproven")
        if withdrawn:
            notes.append("confirmationWithdrawn")
        if since:
            notes.append("noPictureSince")
        if confirmed and evidence["profiled"].get(way):
            notes.append("profiled")
        if confirmed and evidence["failedSince"].get(way):
            notes.append("failedSince")
        if runs and runs[-1]["notYet"]:
            notes.append("profileSaysNotYet")
        if chosen and chosen["way"] != way:
            notes.append("measuredOnAnotherWay")
        if chosen and chosen["loadLow"] is False:
            notes.append("loadHigh")
        if chosen and (chosen["onBattery"] or chosen["lowPower"]):
            notes.append("batteryOrLowPower")
        if chosen and chosen["endedByItself"]:
            notes.append("endedByItself")

        kind = evidence["kind"] if evidence else None
        store, _, store_id = key.partition(".")
        said = evidence_names.get(key)
        name = report_names.get(key) or said or names.get(key) or stock_names.get(key)
        entries.append({
            "key": key, "store": store, "storeID": store_id, "platform": platform, "mac": mac,
            "name": name, "nameFrom": "report" if key in report_names else "evidence" if said else "names" if key in names
            else "stock" if name else None,
            "level": level, "way": way, "antiCheat": anti_cheat,
            "confirmed": dict(confirmed, failedSince=evidence["failedSince"].get(way, 0)) if confirmed else None,
            "withdrawn": withdrawn,
            "seen": {"at": newest[0], "by": newest[2]} if level == "startet" else None,
            "noPictureSince": since,
            "evidence": {
                "starts": evidence["starts"], "ways": evidence["ways"], "failed": evidence["failed"],
                "gaveUp": evidence["gaveUp"], "last": evidence["last"],
            } if evidence else None,
            "gameTest": {
                "runs": len(tried), "pictures": len(pictures), "last": tried[-1]["at"],
                "lastOutcome": tried[-1]["outcome"], "lastWays": tried[-1]["ways"],
            } if tried else None,
            "gameEngine": {"engine": kind.get("engine"), "version": kind.get("engineVersion")}
            if kind and kind.get("engine") not in (None, "other") else None,
            "measured": chosen, "onCurrentBuild": now, "notes": notes,
        })
    entries.sort(key=lambda e: (e["mac"], LEVELS.index(e["level"]), (e["name"] or e["key"]).casefold(), e["key"], e["platform"]))
    stamps = [entry["at"] for entries_ in evidence_lists for entry in entries_] + [report["started"] for report in reports]
    return {
        "formatVersion": FORMAT_VERSION,
        "dataUntil": max(stamps) if stamps else None,
        "sources": {"evidenceEntries": sum(len(e) for e in evidence_lists), "gameTestRuns": len(reports)},
        "currentBuilds": {mac: build for mac, build in currents.items() if build},
        "entries": entries,
    }


# MARK: - The checklist

def build_marks(reports, launches=(), mac=None):
    """Every time something named its build, oldest first: a game test's report, a start since 14.11.2026."""
    marks = [(report["started"], build_of(report), report.get("mac") or UNKNOWN_MAC, "firstRun") for report in reports]
    marks += [(launch["at"], stated(launch), launch["mac"], "firstStart") for launch in launches if stated(launch)]
    return sorted((mark for mark in marks if mac is None or mark[2] == mac), key=lambda one: (one[0], one[3]))


def current_build(reports, launches=(), since=None, mac=None):
    """The build that ran last: the one the newest game test or the newest start that names its build ran on,
    and since when it has been seen – or `since`, for a build nothing names yet."""
    marks = build_marks(reports, launches, mac)
    if not marks:
        return None
    newest = marks[-1]
    first = next(one for one in marks if one[1] == newest[1])
    nightforge, built, engine = newest[1]
    return {"nightforge": nightforge, "built": built, "engine": list(engine), "mac": newest[2],
            "since": since or first[0], "sinceFrom": "argument" if since else first[3]}


def build_of_launch(launch, marks, current=None, since=None):
    """The build a start ran on: the one it names; else – a line from before 14.11.2026 – the build last
    named before it, or the current one from `since` on. None where nothing says, or the line's engine is
    another."""
    named = stated(launch)
    if named:
        return named
    build = None
    if current and since and launch["at"] >= since:
        build = current
    else:
        for at, marked, _, _ in marks:
            if at > launch["at"]:
                break
            build = marked
    if build is None:
        return None
    winecx = next((part for part in build[2] if part.startswith("winecx@")), None)
    if (winecx and launch["engine"] not in (None, winecx)) or launch["nightforge"] not in (None, build[0]):
        return None
    return build


def start_on(starts):
    """One build's answer on the start: its newest clean one – a clean start stays one, whatever came after
    it – else what its newest start says."""
    starts = sorted(starts, key=lambda one: one["at"])
    clean = [one for one in starts if one["why"] == "ok"]
    newest = clean[-1] if clean else starts[-1] if starts else None
    return {"ok": bool(clean), "why": newest["why"] if newest else "never", "at": newest["at"] if newest else None,
            "by": newest["by"] if newest else None, "way": newest["way"] if newest else None}


def fps_on(pictures):
    """One build's answer on the frame rate: its newest run with one that counts, else why its newest has none."""
    fps = {"ok": False, "why": "never", "at": None, "way": None, "average": None, "frameLimit": None, "limitState": None, "steady": False,
           "public": False}
    for run in sorted(pictures, key=lambda run: run["at"], reverse=True):
        m, code = measured(run), check_of(run)[1]
        if code == "ok" and "limitUnknown" in m["notPublic"]:
            code = "limitUnknown"  # a number without its limit isn't one with its conditions
        elif code == "ok" and m["steady"]:
            code = "steady"  # a film's or a lock's pace is no number for a list of what runs how well
        found = {"ok": code == "ok", "why": code, "at": run["at"], "way": run["way"], "average": m["fps"]["average"] if m["fps"] else None,
                 "frameLimit": m["frameLimit"], "limitState": m["limitState"], "steady": m["steady"], "public": m["public"]}
        if found["ok"] or fps["why"] == "never":
            fps = found
        if found["ok"]:
            break
    return fps


def checklist(stock, evidence_lists, reports, names=None, since=None):
    """Per installed game: its size, and whether a clean start and a frame rate that counts were once on
    record for the same build. That is "fertig", and stays it when a newer build runs: a game that has been
    uninstalled can't be measured again. The build is named with the entry, and a start that went wrong
    later is a note beside it. "von-hand" is what no game test will ever start."""
    names = names or {}
    stamps = [entry["at"] for entries in evidence_lists for entry in entries] + [report["started"] for report in reports]
    starts = {}
    for entries in evidence_lists:
        starts.update(from_evidence(entries))
    launches = [launch for game in starts.values() for launch in game["launches"]]
    build = current_build(reports, launches, since)
    tests, report_names = from_reports(reports)
    mac = build["mac"] if build else next((key[1] for key in reversed(list(starts))), UNKNOWN_MAC)
    marks = build_marks(reports, launches, mac)
    current = build_of(build) if build else None
    first_seen = {}
    for at, marked, _, _ in marks:
        first_seen.setdefault(marked, at)
    games, used = [], set()
    for item in stock:
        key, platform = item["key"], item["platform"]
        evidence = starts.get((key, mac)) if platform == "windows" else None
        runs = tests.get((key, platform, mac), [])
        # Per build: every start seen on it, and its runs with a picture.
        seen = {}
        for run in runs:
            if run["outcome"] == "skipped":
                continue
            on = seen.setdefault(build_of(run), {"starts": [], "pictures": []})
            code = check_of(run)[0]
            on["starts"].append({"at": run["at"], "why": code, "settles": code not in ("tooShort", "neededPlayer"), "by": "gameTest", "way": run["way"]})
            if run["outcome"] == "picture":
                on["pictures"].append(run)
        for launch in evidence["launches"] if evidence else []:
            ran_on = build_of_launch(launch, marks, current, since)
            if ran_on is None:
                continue
            code, settles = launch_verdict(launch)
            seen.setdefault(ran_on, {"starts": [], "pictures": []})["starts"].append(
                {"at": launch["at"], "why": code, "settles": settles, "by": "evidence", "way": launch["ways"][-1] if launch["ways"] else None})
        answers = []
        for ran_on, on in seen.items():
            start, fps = start_on(on["starts"]), fps_on(on["pictures"])
            answers.append((start["ok"] and fps["ok"], max(one["at"] for one in on["starts"]), ran_on, start, fps))
        # Done once is done: the newest build that had both. Else the build that got furthest – a clean start or a
        # frame rate stays what it is – and among those the newest with a record of it.
        chosen = max(answers, key=lambda one: (one[0], one[3]["ok"] + one[4]["ok"], one[1])) if answers else None
        done = bool(chosen and chosen[0])
        start, fps = (chosen[3], chosen[4]) if chosen else (start_on([]), fps_on([]))
        # A start that went wrong after the clean one, on whichever build: said, and takes nothing back.
        later = None
        if start["ok"]:
            after = sorted((one for on in seen.values() for one in on["starts"]
                            if one["settles"] and one["why"] != "ok" and one["at"] > start["at"]), key=lambda one: one["at"])
            if after:
                later = {"count": len(after), "at": after[-1]["at"], "why": after[-1]["why"], "by": after[-1]["by"]}
        ran_on = None
        if chosen:
            used.add(chosen[2])
            ran_on = {"nightforge": chosen[2][0], "built": chosen[2][1], "engine": list(chosen[2][2]), "since": first_seen.get(chosen[2]),
                      "current": chosen[2] == current}

        # What the newest game test left it out for – unless it has been started since: the other version's
        # first start is over once the player has made it.
        skipped = runs[-1]["skip"] if runs and runs[-1]["outcome"] == "skipped" else None
        if skipped and evidence and evidence["launches"] and evidence["launches"][-1]["at"] > runs[-1]["at"]:
            skipped = None
        by_hand = skipped if skipped in BY_HAND else "antiCheat" if evidence and evidence["antiCheat"] else None
        status = "fertig" if done and by_hand != "antiCheat" else "von-hand" if by_hand else "offen"
        store, _, store_id = key.partition(".")
        games.append({
            "key": key, "store": store, "storeID": store_id, "platform": platform,
            "name": report_names.get(key) or (evidence["name"] if evidence else None) or item.get("name") or names.get(key),
            "sizeBytes": item["sizeBytes"], "location": item["location"], "status": status,
            "missing": [] if status == "fertig" else [what for what, have in (("start", start["ok"]), ("fps", fps["ok"])) if not have],
            "byHand": by_hand if status == "von-hand" else None, "skipped": skipped, "start": start, "fps": fps, "build": ran_on, "later": later,
        })
    order = ("fertig", "offen", "von-hand")
    games.sort(key=lambda game: (order.index(game["status"]), -game["sizeBytes"], (game["name"] or game["key"]).casefold(), game["key"], game["platform"]))
    totals = {status: {"games": sum(1 for game in games if game["status"] == status),
                       "bytes": sum(game["sizeBytes"] for game in games if game["status"] == status)} for status in order}
    # The builds the entries name, newest first.
    builds = [{"nightforge": one[0], "built": one[1], "engine": list(one[2]), "since": first_seen.get(one), "current": one == current}
              for one in sorted(used, key=lambda one: (first_seen.get(one) or "", one[0] or "", one[1] or "", one[2]), reverse=True)]
    return {"formatVersion": FORMAT_VERSION, "dataUntil": max(stamps) if stamps else None, "mac": mac, "build": build,
            "builds": builds, "totals": totals, "games": games}


# MARK: - The German table

def date(stamp):
    """An ISO 8601 UTC stamp as "14.11.2026" (its UTC day: the same on every Mac)."""
    match = re.match(r"(\d{4})-(\d{2})-(\d{2})", stamp or "")
    return f"{int(match[3])}.{int(match[2])}.{match[1]}" if match else "–"


def moment(stamp):
    """An ISO 8601 UTC stamp as "14.11.2026 14:40 UTC": two builds of one day are told apart by the minute."""
    match = re.match(r"(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})", stamp or "")
    if not match:
        return date(stamp)
    year, month, day, hour, minute = match.groups()
    return f"{int(day)}.{int(month)}.{year} {hour}:{minute} UTC"


def number(value, digits=0):
    return f"{value:.{digits}f}".replace(".", ",")


def cell(text):
    return str(text).replace("|", "\\|")


def title(entry):
    return cell(entry["name"]) if entry["name"] else f"`{entry['key']}`"


def proof_text(entry):
    confirmed = entry["confirmed"]
    if confirmed:
        if confirmed["basis"] == "known":
            text = f"bestätigt vor dem {date(confirmed['at'])} (vor der Aufzeichnung)"
        else:
            text = f"bestätigt {date(confirmed['at'])}"
            if confirmed["starts"]:
                text += f", {confirmed['starts']}. Start"
                if confirmed["ways"] and confirmed["ways"] > 1:
                    text += f", {confirmed['ways']} Wege"
        version = f"Nightforge {confirmed['nightforge']}" + (f" (gebaut {moment(confirmed['built'])})" if confirmed.get("built") else "") \
            if confirmed.get("nightforge") else None
        return " · ".join(filter(None, [text, version, confirmed["engine"]]))
    seen = entry["seen"]
    if seen:
        return f"Bild im Spieletest {date(seen['at'])}" if seen["by"] == "gameTest" else f"Bild beim Start {date(seen['at'])} (Evidenz)"
    return "–"


LIMIT_LEADS = {"held": "hält das Limit: ", "notReached": "erreicht das Limit nicht: ", "notApplied": "Limit greift nicht: ",
               "noneOnWay": "frei (kein Limit auf diesem Weg): ", "none": "frei: "}


def frames_text(m):
    """Under a limit: what the limit did to the number. Without one: a free number. Never the one for the other."""
    if not m:
        return "nicht gemessen"
    if m["fps"]:
        fps = m["fps"]
        text = f"Ø {number(fps['average'])}, tiefste Periode {number(fps['low'])}"
        if fps.get("source") == "wine-fps":
            text += " (Wines fps-Kanal)"
        if fps.get("onePercentLow") is not None:
            text += f", 1-%-Tief {number(fps['onePercentLow'])}"
        if fps.get("seconds"):
            text += f", über {number(fps['seconds'])} s"
        if m["steady"]:
            return "starr, kein Leistungswert: " + text
        return LIMIT_LEADS[m["limitState"]] + text if m["limitState"] else text + " (Limit nicht aufgezeichnet)"
    silent = {"d3dmetal": "D3DMetal meldet keine", "wined3d": "WineD3D meldet keine ohne Wines fps-Kanal", "mac": "Mac-Fassung meldet keine"}
    # With the HUD's frame log a way through Metal had its chance: then the log held none.
    return f"nicht gemessen ({'keine im Log' if m['noFrames'] == 'noneInLog' else silent.get(layer(m['way']), 'keine im Log')})"


def slowest_text(m):
    if m and m["fps"] and m["fps"].get("source") == "wine-fps":
        return "gibt Wines fps-Kanal nicht her"  # a rate every 1.5 s, no single frames
    if not m or not m["fps"] or m["fps"].get("slowestFrame") is None:
        return "nicht gemessen"
    usual = m["fps"].get("slowestTypical")
    return (f"üblich {number(usual)} ms, " if usual is not None else "") + f"schlimmster {number(m['fps']['slowestFrame'])} ms"


def size_text(m):
    if not m:
        return "nicht gemessen"
    if m["swapchain"]:
        return f"{m['swapchain']} px" + (f", MetalFX auf {m['upscaledTo']}" if m["upscaledTo"] else "")
    if m["displayMode"]:
        return f"{m['displayMode']} (Modus des Spiels)"
    if m["window"]:
        return f"Fenster {m['window']} Punkte"
    return "nicht gemessen"


def limit_text(m):
    if not m or m["frameLimit"] is None:
        return "nicht gemessen"
    if m["frameLimit"] <= 0:
        return "keins"
    if layer(m["way"]) in LIMITLESS:
        return f"keins möglich (verlangt: {m['frameLimit']} FPS)"
    return f"{m['frameLimit']} FPS" + (", greift nicht" if m["limitState"] == "notApplied" else "")


def run_text(m):
    """The conditions of the measurement: when, on which Nightforge and engine, for how long."""
    if not m:
        return "–"
    # A Mac version runs on no engine; D3DMetal's own part only where it drew.
    wanted = [] if layer(m["way"]) == "mac" else ["winecx", "graphics"] + (["d3dmetal"] if layer(m["way"]) == "d3dmetal" else [])
    parts = [part for part in m["engine"] if part.split("@")[0] in wanted]
    seconds = f"{number(m['playSeconds'])} s" if m["playSeconds"] else None
    version = f"Nightforge {m['nightforge']}" + (f" (gebaut {moment(m['built'])})" if m["built"] else "") if m["nightforge"] else None
    return " · ".join(filter(None, [date(m["at"]), version] + parts + [seconds]))


NOTES = {
    "antiCheatOnlineUnproven": "Anti-Cheat: nur der Start ist belegt, der Online-Teil nicht",
    "profiled": "mit Profil",
    "profileSaysNotYet": "Profil sagt „noch nicht“",
    "measuredOnAnotherWay": "Messung auf anderem Weg",
    "loadHigh": "Last beim Messen hoch",
    "batteryOrLowPower": "auf Akku oder im Stromsparmodus gemessen",
    "endedByItself": "endete im Spielfenster von selbst",
}
GAPS = {
    "limitUnknown": "Limit nicht aufgezeichnet", "onBattery": "auf Akku", "lowPower": "Stromsparmodus", "throttled": "Limit gedrosselt",
    "loadHigh": "Last hoch", "loadUnknown": "Last nicht aufgezeichnet", "buildUnknown": "Build nicht aufgezeichnet",
    "sizeUnknown": "Größe nicht aufgezeichnet", "durationUnknown": "Messdauer nicht aufgezeichnet",
    "steady": "starrer Wert (Film oder Sperre des Spiels)",
}


def notes_text(entry):
    notes = [NOTES[note] for note in entry["notes"] if note in NOTES]
    if "failedSince" in entry["notes"]:
        count = entry["confirmed"]["failedSince"]
        notes.append(f"danach {count} Fehlstart" + ("s" if count > 1 else ""))
    if "confirmationWithdrawn" in entry["notes"]:
        gone = entry["withdrawn"]
        notes.append(f"{gone['way']} war bestätigt, seit {date(gone['at'])} nicht mehr")
    if "noPictureSince" in entry["notes"]:
        gone = entry["noPictureSince"]
        times = f"{gone['count']} Starts" if gone["count"] > 1 else "ein Start"
        notes.append(f"danach {times} ohne Bild, zuletzt {date(gone['at'])} ({'Spieletest' if gone['by'] == 'gameTest' else 'Evidenz'})")
    m = entry["measured"]
    if m and m["fps"] and not m["public"]:
        notes.append("FPS nicht für die öffentliche Liste: " + ", ".join(GAPS.get(gap, gap) for gap in m["notPublic"]))
    if m and m["way"] and "measuredOnAnotherWay" in entry["notes"]:
        notes[notes.index(NOTES["measuredOnAnotherWay"])] = f"Messung auf {m['way']}"
    return "; ".join(notes) or "–"


def rows(entries):
    lines = ["| Spiel | Laden | Fassung | Weg | Beleg | Spieletest | Bild nach | Frame-Limit | FPS | Langsamster Frame | Größe | Messung | "
             "Aktueller Build | Hinweis |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for entry in entries:
        m, test = entry["measured"], entry["gameTest"]
        cells = [
            title(entry), STORES.get(entry["store"], entry["store"]), "Mac" if entry["platform"] == "mac" else "Windows",
            entry["way"] or "–", proof_text(entry),
            f"Bild in {test['pictures']} von {test['runs']}" if test else "–",
            f"{number(m['secondsToPicture'])} s" if m and m["secondsToPicture"] is not None else "nicht gemessen",
            limit_text(m), frames_text(m), slowest_text(m), size_text(m), run_text(m), now_text(entry.get("onCurrentBuild")), notes_text(entry),
        ]
        lines.append("| " + " | ".join(cells) + " |")
    return lines


def now_text(now):
    """What the current build has seen of a game: its newest start there."""
    if not now:
        return "noch nichts"
    source = "Spieletest" if now["by"] == "gameTest" else "Evidenz"
    return ("Bild" if now["picture"] else "kein Bild") + f" {date(now['at'])} ({source})"


def tried_text(entry):
    test, evidence = entry["gameTest"], entry["evidence"]
    parts = []
    if test:
        parts.append(f"Spieletest {date(test['last'])}: {OUTCOMES.get(test['lastOutcome'], test['lastOutcome'])}"
                     + (f" (Bild in {test['pictures']} von {test['runs']} Läufen)" if test["pictures"] else ""))
    if evidence:
        text = f"{evidence['starts']} Start" + ("s" if evidence["starts"] != 1 else "") + " aufgezeichnet, kein Bild bestätigt"
        parts.append(text + (", aufgegeben" if evidence["gaveUp"] else ""))
    return "; ".join(parts)


def markdown(document):
    entries = document["entries"]
    lines = [
        "# Läuft unter Nightforge", "",
        "Erzeugt von `scripts/laeuft-liste.py` aus Nightforges eigenen Aufzeichnungen (Start-Evidenz und Spieletest) – nicht von Hand ändern. "
        "Was die Stufen bedeuten, unter welchen Bedingungen gemessen wird und was die Zahlen nicht aussagen: "
        "[LAEUFT-LISTE.md](../LAEUFT-LISTE.md). Maschinenlesbar: [laeuft.json](laeuft.json).", "",
        f"Stand der Daten: {date(document['dataUntil'])} (Tage in UTC). Quellen: {document['sources']['evidenceEntries']} Einträge der Start-Evidenz, "
        f"{document['sources']['gameTestRuns']} Spieletest-Läufe.", "",
    ]
    if not entries:
        lines += ["Noch nichts aufgezeichnet.", ""]
    for mac in sorted({entry["mac"] for entry in entries}):
        here = [entry for entry in entries if entry["mac"] == mac]
        by = {level: [entry for entry in here if entry["level"] == level] for level in LEVELS}
        lines += [f"## {mac}", ""]
        current = (document.get("currentBuilds") or {}).get(mac)
        if current:
            lines += [f"Aktueller Build: {build_text(current)}, gesehen seit dem {date(current['since'])}. Messwerte stehen mit dem Build, "
                      "auf dem sie gemessen sind, und bleiben, wenn ein neuerer läuft; die Spalte „Aktueller Build“ sagt, was der "
                      "jüngste von dem Spiel gesehen hat.", ""]
        if by["laeuft"]:
            lines += [f"### Läuft ({len(by['laeuft'])})", "",
                      "Der Weg ist bestätigt: Das Spiel hat gemessene Frames gezeichnet oder lief 180 s mit Bild.", ""]
            lines += rows(by["laeuft"]) + [""]
        if by["startet"]:
            lines += [f"### Startet ({len(by['startet'])})", "",
                      "Ein Bild kam, der Weg ist aber nicht (oder nicht mehr) bestätigt. Für Mac-Fassungen zeichnet Nightforge keine "
                      "Bestätigung auf: Sie stehen höchstens hier.", ""]
            lines += rows(by["startet"]) + [""]
        if by["anti-cheat"]:
            lines += [f"### Anti-Cheat ({len(by['anti-cheat'])})", "",
                      "Nightforge startet diese Spiele nicht und prüft sie nicht: Ihr Anti-Cheat sperrt sie auf dem Mac.", ""]
            lines += [f"- {title(entry)} ({STORES.get(entry['store'], entry['store'])})" for entry in by["anti-cheat"]] + [""]
        if by["kein-bild"]:
            lines += [f"### Versucht, bisher ohne Bild ({len(by['kein-bild'])})", "",
                      "Gehört nicht zur Liste, steht hier der Ehrlichkeit halber: gestartet, aber kein Bild aufgezeichnet.", "",
                      "| Spiel | Laden | Fassung | Letzter Weg | Stand |", "|---|---|---|---|---|"]
            lines += ["| " + " | ".join([title(entry), STORES.get(entry["store"], entry["store"]),
                                         "Mac" if entry["platform"] == "mac" else "Windows", entry["way"] or "–", tried_text(entry)]) + " |"
                      for entry in by["kein-bild"]]
            lines.append("")
    unnamed = sorted({entry["key"] for entry in entries if not entry["name"]})
    if unnamed:
        lines += ["Ohne Namen (kein Spieletest hat sie gespielt, ihre Starts nennen keinen, und `namen.json` kennt sie nicht): "
                  + ", ".join(f"`{key}`" for key in unnamed), ""]
    return "\n".join(lines)


START = {
    "severalWays": "brauchte mehrere Wege", "failed": "Fehlstart", "endedByItself": "endete von selbst", "noPicture": "kein Bild",
    "tooShort": "Bild, aber unter 180 s beobachtet", "neededPlayer": "brauchte den Spieler", "noOutcome": "Ausgang nicht aufgezeichnet",
    "endedEarly": "vor dem Bild beendet", "never": "kein Start aufgezeichnet",
}
NO_FPS = {
    "noPicture": "kein Bild", "noneInLog": "keine im Log", "throttled": "auf Akku oder gedrosselt gemessen", "loadHigh": "Last war hoch",
    "limitUnknown": "Wert ohne aufgezeichnetes Limit", "never": "auf diesem Build nicht gemessen", "nowhere": "nie gemessen",
    "steady": "starrer Wert, kein Leistungswert (Film oder Sperre des Spiels)",
}
HELD = {"held": "hält {} FPS", "notReached": "erreicht {} FPS nicht", "notApplied": "Limit {} FPS greift nicht",
        "noneOnWay": "frei gemessen (kein Limit auf diesem Weg)", "none": "frei gemessen"}
SKIPS = dict(BY_HAND, signIn="bräuchte eine Anmeldung", update="ein Update stünde an", runtimes="bräuchte erst Laufzeiten",
             d3dMetal="braucht D3DMetal, das nicht eingerichtet ist", macSteamSetup="Steam für Mac ist nicht eingerichtet",
             steamAsks="Steam fragte etwas", macOSAsks="macOS fragt um Erlaubnis", stopped="Test vorher angehalten", gone="nicht mehr installiert")


def size_gb(count):
    return number(count / 1_000_000_000, 1) + " GB"


def start_text(start, later=None):
    source = "Spieletest" if start["by"] == "gameTest" else "Evidenz"
    where = f" ({source} {date(start['at'])}" + (f", {start['way']}" if start["way"] else "") + ")" if start["at"] else ""
    text = ("ja" if start["ok"] else "fehlt: " + START.get(start["why"], start["why"])) + where
    if later:
        # Said, not counted: a clean start stays one.
        again = "Spieletest" if later["by"] == "gameTest" else "Evidenz"
        count = f"{later['count']} Starts gingen" if later["count"] > 1 else "ein Start ging"
        text += f"; danach {count} schief, zuletzt {date(later['at'])}: {START.get(later['why'], later['why'])} ({again})"
    return text


def fps_text(fps, nowhere=False):
    value = f"Ø {number(fps['average'])}" if fps["average"] is not None else None
    where = f"{date(fps['at'])}" + (f", {fps['way']}" if fps["way"] else "") if fps["at"] else None
    if fps["ok"]:
        held = HELD[fps["limitState"]].format(fps["frameLimit"]) if fps["limitState"] else None
        return "ja: " + ", ".join(filter(None, [held, value, where]))
    silent = {"d3dmetal": "D3DMetal meldet keine", "wined3d": "WineD3D meldet keine ohne Wines fps-Kanal", "mac": "Mac-Fassung meldet keine"}
    why = silent.get(layer(fps["way"]), "der Weg meldet keine") if fps["why"] == "wayReportsNone" else NO_FPS.get(fps["why"], fps["why"])
    if fps["why"] == "never" and not fps["at"] and nowhere:
        why = NO_FPS["nowhere"]
    return "fehlt: " + why + (" (" + ", ".join(filter(None, [value, where])) + ")" if where else "")


def build_text(build):
    """A build in words: the version, when it was built, the engine's parts."""
    return " · ".join([f"Nightforge {build['nightforge']}" + (f" (gebaut {moment(build['built'])})" if build["built"] else "")] + build["engine"])


def checklist_markdown(document):
    build, totals, builds = document["build"], document["totals"], document.get("builds") or []
    lines = [
        "# Abhakliste: Was darf weg?", "",
        "Erzeugt von `scripts/laeuft-liste.py` aus dem Bestand der Läden (Steam, Epic, GOG – nur gelesen), der Start-Evidenz und den "
        "Spieletests – nicht von Hand ändern. Die Regeln stehen in [LAEUFT-LISTE.md](../LAEUFT-LISTE.md). "
        "**Deinstalliert wird von hier aus nie etwas: Das macht der Nutzer selbst.**", "",
        f"Mac: {document['mac']}. Stand der Daten: {date(document['dataUntil'])} (Tage in UTC).",
    ]
    if build:
        since = {"argument": "so angegeben", "firstStart": "erster aufgezeichneter Start auf diesem Build"}.get(
            build["sinceFrom"], "erster Spieletest auf diesem Build")
        lines.append(f"Aktueller Build: {build_text(build)}. Gesehen seit dem {date(build['since'])} ({since}).")
    else:
        lines.append("Kein Spieletest-Bericht und kein Start, der seinen Build nennt: Der Build ist unbekannt, FPS-Werte gibt es keine.")
    lines += ["",
              "**Fertig** ist ein Spiel, sobald beides einmal auf demselben Build aufgezeichnet war: ein sauberer Start (Bild auf dem "
              "ersten und einzigen Weg, kein Fehlversuch, nicht von selbst beendet, als laufend bestätigt) und ein FPS-Wert mit seinen "
              "Bedingungen (Limit aufgezeichnet, am Netz, Last niedrig). Es bleibt fertig, auch wenn seither ein neuerer Build läuft: Der "
              "Build, auf dem beides vorlag, steht am Eintrag. Geht ein späterer Start schief, steht das dabei und nimmt nichts zurück.", "",
              "**" + " ".join(f"{label}: {totals[status]['games']} {'Spiel' if totals[status]['games'] == 1 else 'Spiele'}, "
                              f"{size_gb(totals[status]['bytes'])}." for label, status in
                              (("Fertig", "fertig"), ("Offen", "offen"), ("Von Hand zu prüfen", "von-hand"))) + "**", ""]
    labels = {}
    if builds:
        lines.append("Builds, auf denen die Einträge stehen (neuester zuerst):")
        lines.append("")
        for number_, one in enumerate(builds, 1):
            labels[build_of(one)] = f"B{number_}"
            seen = f", gesehen seit {date(one['since'])}" if one["since"] else ""
            lines.append(f"- **B{number_}**{' (aktuell)' if one['current'] else ''}: {build_text(one)}{seen}")
        lines.append("")
    lines += ["| Spiel | Laden | Fassung | Größe | Start (100 %) | FPS | Build | Status |", "|---|---|---|---|---|---|---|---|"]
    for game in document["games"]:
        if game["status"] == "fertig":
            status = "**fertig – darf weg**"
        elif game["status"] == "von-hand":
            status = "von Hand zu prüfen: " + BY_HAND.get(game["byHand"], game["byHand"])
        else:
            status = "offen" + (f" (Spieletest ließ es aus: {SKIPS.get(game['skipped'], game['skipped'])})" if game["skipped"] else "")
        name = cell(game["name"]) if game["name"] else f"`{game['key']}`"
        on = game.get("build")
        where = labels.get(build_of(on), "–") + (" (aktuell)" if on["current"] else "") if on else "–"
        lines.append("| " + " | ".join([name, STORES.get(game["store"], game["store"]), "Mac" if game["platform"] == "mac" else "Windows",
                                         size_gb(game["sizeBytes"]), start_text(game["start"], game.get("later")),
                                         fps_text(game["fps"], nowhere=on is None), where, status]) + " |")
    lines.append("")
    return "\n".join(lines)


# MARK: - Writing

def leaks(text, home=None, user=None):
    """Whether `text` names a home folder, an account or a drive: nothing of that belongs in the list."""
    home = home if home is not None else str(pathlib.Path.home())
    user = user if user is not None else getpass.getuser()
    if home and len(home) > 1 and home in text:
        return True
    if user and re.search(r"[/\\]users[/\\]+" + re.escape(user) + r"\b", text, re.IGNORECASE):
        return True
    return bool(re.search(r"/Users/|/Volumes/|[A-Za-z]:\\+users\\", text, re.IGNORECASE))


def write(document, out, home=None, user=None, check=None):
    """laeuft.json and LAEUFT.md into `out`, with a checklist abhakliste.json and ABHAKLISTE.md too – or
    nothing at all when any of them would give the player away."""
    files = {"laeuft.json": json.dumps(document, indent=1, ensure_ascii=False, sort_keys=True) + "\n", "LAEUFT.md": markdown(document)}
    if check is not None:
        files["abhakliste.json"] = json.dumps(check, indent=1, ensure_ascii=False, sort_keys=True) + "\n"
        files["ABHAKLISTE.md"] = checklist_markdown(check)
    if any(leaks(text, home, user) for text in files.values()):
        raise SystemExit("✗ the list would name a home folder, an account or a drive – nothing written")
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (out / name).write_text(text, encoding="utf-8")
    return out / "laeuft.json", out / "LAEUFT.md"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("reports", nargs="*", help="game test reports, or folders of them (default: this Mac's GameTests)")
    parser.add_argument("--evidence", action="append", help="a start-evidence.jsonl; may be given more than once (default: this Mac's)")
    parser.add_argument("--names", default=str(ROOT / "docs/laeuft/namen.json"), help="names for games no report names")
    parser.add_argument("--out", default=str(ROOT / "docs/laeuft"), help="where laeuft.json and LAEUFT.md go")
    parser.add_argument("--since", help="the checklist counts what was recorded from this UTC moment on (2026-11-11T20:00:00Z): "
                                        "for a build no game test has run on yet (default: its first game test)")
    parser.add_argument("--stock", default=str(SUPPORT), help="Nightforge's folder with the stores' lists of installed games")
    parser.add_argument("--mac-steam", help="Steam for Mac's folder (default: the one in Application Support)")
    parser.add_argument("--no-stock", action="store_true", help="don't read what is installed: no checklist")
    options = parser.parse_args(argv)
    evidence = options.evidence if options.evidence is not None else [str(SUPPORT / "start-evidence.jsonl")]
    reports = options.reports or [str(SUPPORT / "GameTests")]
    lists = [read_evidence(path) for path in evidence if pathlib.Path(path).is_file()]
    runs, names = read_reports(reports), read_names(options.names)
    stock = [] if options.no_stock else read_stock(options.stock, options.mac_steam)
    document = build(lists, runs, names, stock)
    check = checklist(stock, lists, runs, names, options.since) if stock else None
    data, table = write(document, options.out, check=check)
    counts = {level: sum(1 for entry in document["entries"] if entry["level"] == level) for level in LEVELS}
    print(f"✓ {data} and {table.name}: " + ", ".join(f"{count} {level}" for level, count in counts.items()))
    if check:
        print("✓ abhakliste.json and ABHAKLISTE.md: " + ", ".join(f"{check['totals'][status]['games']} {status}" for status in check["totals"]))
    unnamed = sorted({entry["key"] for entry in document["entries"] if not entry["name"]})
    if unnamed:
        print("! no name for: " + ", ".join(unnamed) + f" – add them to {options.names}", file=sys.stderr)


if __name__ == "__main__":
    main()
