#!/usr/bin/env python3
"""Builds the list of games that start and run under Nightforge, with what was measured of them:
docs/laeuft/laeuft.json for tools (the landing page) and docs/laeuft/LAEUFT.md for people.
What the list claims, and what its numbers do and don't mean: docs/LAEUFT-LISTE.md.

Only Nightforge's own records go in – the start evidence (StartEvidence, start-evidence.jsonl) and the
game test's reports (GameTest, report.json, formats 1 and 2). Nothing from other sources, nothing guessed:
what no record holds is null in the JSON and "nicht gemessen" in the table. The inputs are only read.
The same inputs give the same files, byte for byte: nothing in them depends on when or where this ran.

Usage: laeuft-liste.py [--evidence FILE]... [--names FILE] [--out DIR] [REPORT.json | FOLDER]...
Defaults: this Mac's evidence and game test runs, docs/laeuft/namen.json, docs/laeuft.
"""

import argparse
import getpass
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUPPORT = pathlib.Path.home() / "Library/Application Support/Nightforge"
FORMAT_VERSION = 1
REPORT_FORMATS = (1, 2)
LEVELS = ("laeuft", "startet", "anti-cheat", "kein-bild")
# A way's first word (LaunchAttempt.id), or "mac" for a Mac version.
LAYERS = ("wined3d", "dxvk", "dxmt", "d3dmetal", "mac")
# Ways that report no frame rates at all (GameTest.noFrames).
SILENT = ("d3dmetal", "wined3d", "mac")
# Outcomes of a game test that say nothing about the game: nobody tried, or only the player could go on.
UNTRIED = ("skipped", "needsPlayer", "unknown")
UNKNOWN_MAC = "unbekannt"
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
            "kind": None, "profiled": {}, "withdrawn": {},
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
                    # How many starts and ways it took – only for a game the record saw from its first start.
                    "starts": game["starts"] if first else None,
                    "ways": len(game["ways"]) if first else None,
                }
            game["currentWay"] = way
            game["failedSince"][way] = 0
            game["withdrawn"].pop(way, None)

        if event == "started":
            game["starts"] += 1
            if way and way not in game["ways"]:
                game["ways"].append(way)
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
                "nightforge": report.get("nightforge"), "engine": report.get("engine") or [],
                "runsOn": report.get("runsOn"), "playSeconds": report.get("playSeconds"),
                "onBattery": bool(report.get("onBattery")), "lowPower": bool(report.get("lowPower")),
                "outcome": entry.get("outcome"), "skip": entry.get("skip"), "ways": ways, "way": ways[-1] if ways else None,
                "secondsToPicture": entry.get("secondsToPicture"), "frames": entry.get("frames"),
                "measure": entry.get("measure") or {}, "loadLow": (entry.get("load") or {}).get("low"),
                "issues": entry.get("issues") or [], "notYet": bool(entry.get("notYet")),
            })
    return games, names


def measured(run):
    """What one run with a picture measured, in one shape whatever the report's format: what it doesn't hold is null."""
    frames, measure = run["frames"], run["measure"]
    fps = None
    if isinstance(frames, dict) and frames.get("average") is not None:
        fps = {name: frames.get(name) for name in ("average", "low", "periods", "seconds", "slowestFrame", "slowestTypical", "source")}
    no_frames = None
    if fps is None:
        no_frames = measure.get("noFrames") or ("wayReportsNone" if layer(run["way"]) in SILENT else "noneInLog")
    return {
        "at": run["at"], "nightforge": run["nightforge"], "engine": run["engine"], "runsOn": run["runsOn"],
        "reportFormat": run["format"], "way": run["way"], "playSeconds": run["playSeconds"],
        "secondsToPicture": run["secondsToPicture"], "loadLow": run["loadLow"],
        "onBattery": run["onBattery"], "lowPower": run["lowPower"],
        "endedByItself": "crashed" in run["issues"], "fps": fps, "noFrames": no_frames,
        "frameLimit": measure.get("frameLimit"), "refreshRate": measure.get("refreshRate"), "metalFX": measure.get("metalFX"),
        "window": measure.get("window"), "screen": measure.get("screen"), "swapchain": measure.get("swapchain"),
        "upscaledTo": measure.get("upscaledTo"), "displayMode": measure.get("displayMode"),
    }


# MARK: - The list

def build(evidence_lists, reports, names=None):
    """The list's document: one entry per game, version and Mac that anything was recorded of."""
    names = names or {}
    starts = {}
    for entries in evidence_lists:
        for (key, mac), game in from_evidence(entries).items():
            starts[(key, "windows", mac)] = game  # the evidence records Windows versions only
    tests, report_names = from_reports(reports)
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
        # The newest of: the last tried run, a start the evidence saw end with a picture.
        seen = []
        if tried:
            seen.append((tried[-1]["at"], tried[-1]["outcome"] == "picture", tried[-1]["way"], "gameTest"))
        if evidence and evidence["picture"]:
            seen.append((evidence["picture"]["at"], True, evidence["picture"]["way"], "evidence"))
        newest = max(seen) if seen else None

        if blocked:
            level, way = "anti-cheat", None
        elif confirmed:
            level, way = "laeuft", confirmed["way"]
        elif newest and newest[1]:
            level, way = "startet", newest[2]
        else:
            level = "kein-bild"
            way = (newest[2] if newest else None) or (evidence["lastWay"] if evidence else None)

        chosen = None
        if level in ("laeuft", "startet") and pictures:
            on_way = [run for run in pictures if run["way"] == way]
            chosen = measured((on_way or pictures)[-1])
        # True, false, or null where no record says.
        anti_cheat = True if blocked else evidence["antiCheat"] if evidence else None
        notes = []
        if anti_cheat and level in ("laeuft", "startet"):
            notes.append("antiCheatOnlineUnproven")
        if withdrawn:
            notes.append("confirmationWithdrawn")
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
        name = report_names.get(key) or names.get(key)
        entries.append({
            "key": key, "store": store, "storeID": store_id, "platform": platform, "mac": mac,
            "name": name, "nameFrom": "report" if key in report_names else "names" if name else None,
            "level": level, "way": way, "antiCheat": anti_cheat,
            "confirmed": dict(confirmed, failedSince=evidence["failedSince"].get(way, 0)) if confirmed else None,
            "withdrawn": withdrawn,
            "seen": {"at": newest[0], "by": newest[3]} if level == "startet" else None,
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
            "measured": chosen, "notes": notes,
        })
    entries.sort(key=lambda e: (e["mac"], LEVELS.index(e["level"]), (e["name"] or e["key"]).casefold(), e["key"], e["platform"]))
    stamps = [entry["at"] for entries_ in evidence_lists for entry in entries_] + [report["started"] for report in reports]
    return {
        "formatVersion": FORMAT_VERSION,
        "dataUntil": max(stamps) if stamps else None,
        "sources": {"evidenceEntries": sum(len(e) for e in evidence_lists), "gameTestRuns": len(reports)},
        "entries": entries,
    }


# MARK: - The German table

def date(stamp):
    """An ISO 8601 UTC stamp as "14.11.2026" (its UTC day: the same on every Mac)."""
    match = re.match(r"(\d{4})-(\d{2})-(\d{2})", stamp or "")
    return f"{int(match[3])}.{int(match[2])}.{match[1]}" if match else "–"


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
        return text + (f" · {confirmed['engine']}" if confirmed["engine"] else "")
    seen = entry["seen"]
    if seen:
        return f"Bild im Spieletest {date(seen['at'])}" if seen["by"] == "gameTest" else f"Bild beim Start {date(seen['at'])} (Evidenz)"
    return "–"


def frames_text(m):
    if not m:
        return "nicht gemessen"
    if m["fps"]:
        text = f"{number(m['fps']['average'])} / {number(m['fps']['low'])}"
        return text + (f" über {number(m['fps']['seconds'])} s" if m["fps"].get("seconds") else "")
    silent = {"d3dmetal": "D3DMetal meldet keine", "wined3d": "WineD3D meldet keine", "mac": "Mac-Fassung meldet keine"}
    return f"nicht gemessen ({silent.get(layer(m['way']), 'keine im Log')})"


def slowest_text(m):
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
    return f"{m['frameLimit']} FPS" if m["frameLimit"] > 0 else "keins"


def run_text(m):
    """The conditions of the measurement: when, on which Nightforge and engine, for how long."""
    if not m:
        return "–"
    # A Mac version runs on no engine; D3DMetal's own part only where it drew.
    wanted = [] if layer(m["way"]) == "mac" else ["winecx", "graphics"] + (["d3dmetal"] if layer(m["way"]) == "d3dmetal" else [])
    parts = [part for part in m["engine"] if part.split("@")[0] in wanted]
    seconds = f"{number(m['playSeconds'])} s" if m["playSeconds"] else None
    return " · ".join(filter(None, [date(m["at"]), f"Nightforge {m['nightforge']}" if m["nightforge"] else None] + parts + [seconds]))


NOTES = {
    "antiCheatOnlineUnproven": "Anti-Cheat: nur der Start ist belegt, der Online-Teil nicht",
    "profiled": "mit Profil",
    "profileSaysNotYet": "Profil sagt „noch nicht“",
    "measuredOnAnotherWay": "Messung auf anderem Weg",
    "loadHigh": "Last beim Messen hoch",
    "batteryOrLowPower": "auf Akku oder im Stromsparmodus gemessen",
    "endedByItself": "endete im Spielfenster von selbst",
}


def notes_text(entry):
    notes = [NOTES[note] for note in entry["notes"] if note in NOTES]
    if "failedSince" in entry["notes"]:
        count = entry["confirmed"]["failedSince"]
        notes.append(f"danach {count} Fehlstart" + ("s" if count > 1 else ""))
    if "confirmationWithdrawn" in entry["notes"]:
        gone = entry["withdrawn"]
        notes.append(f"{gone['way']} war bestätigt, seit {date(gone['at'])} nicht mehr")
    m = entry["measured"]
    if m and m["way"] and "measuredOnAnotherWay" in entry["notes"]:
        notes[notes.index(NOTES["measuredOnAnotherWay"])] = f"Messung auf {m['way']}"
    return "; ".join(notes) or "–"


def rows(entries):
    lines = ["| Spiel | Laden | Fassung | Weg | Beleg | Spieletest | Bild nach | Frame-Limit | FPS Ø / tiefste Periode | Langsamster Frame | Größe | Messung | Hinweis |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for entry in entries:
        m, test = entry["measured"], entry["gameTest"]
        cells = [
            title(entry), STORES.get(entry["store"], entry["store"]), "Mac" if entry["platform"] == "mac" else "Windows",
            entry["way"] or "–", proof_text(entry),
            f"Bild in {test['pictures']} von {test['runs']}" if test else "–",
            f"{number(m['secondsToPicture'])} s" if m and m["secondsToPicture"] is not None else "nicht gemessen",
            limit_text(m), frames_text(m), slowest_text(m), size_text(m), run_text(m), notes_text(entry),
        ]
        lines.append("| " + " | ".join(cells) + " |")
    return lines


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
        lines += ["Ohne Namen (kein Spieletest hat sie gespielt, und `namen.json` kennt sie nicht): " + ", ".join(f"`{key}`" for key in unnamed), ""]
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


def write(document, out, home=None, user=None):
    """laeuft.json and LAEUFT.md into `out` – or nothing at all when either would give the player away."""
    data = json.dumps(document, indent=1, ensure_ascii=False, sort_keys=True) + "\n"
    table = markdown(document)
    if leaks(data, home, user) or leaks(table, home, user):
        raise SystemExit("✗ the list would name a home folder, an account or a drive – nothing written")
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "laeuft.json").write_text(data, encoding="utf-8")
    (out / "LAEUFT.md").write_text(table, encoding="utf-8")
    return out / "laeuft.json", out / "LAEUFT.md"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("reports", nargs="*", help="game test reports, or folders of them (default: this Mac's GameTests)")
    parser.add_argument("--evidence", action="append", help="a start-evidence.jsonl; may be given more than once (default: this Mac's)")
    parser.add_argument("--names", default=str(ROOT / "docs/laeuft/namen.json"), help="names for games no report names")
    parser.add_argument("--out", default=str(ROOT / "docs/laeuft"), help="where laeuft.json and LAEUFT.md go")
    options = parser.parse_args(argv)
    evidence = options.evidence if options.evidence is not None else [str(SUPPORT / "start-evidence.jsonl")]
    reports = options.reports or [str(SUPPORT / "GameTests")]
    lists = [read_evidence(path) for path in evidence if pathlib.Path(path).is_file()]
    document = build(lists, read_reports(reports), read_names(options.names))
    data, table = write(document, options.out)
    counts = {level: sum(1 for entry in document["entries"] if entry["level"] == level) for level in LEVELS}
    print(f"✓ {data} and {table.name}: " + ", ".join(f"{count} {level}" for level, count in counts.items()))
    unnamed = sorted({entry["key"] for entry in document["entries"] if not entry["name"]})
    if unnamed:
        print("! no name for: " + ", ".join(unnamed) + f" – add them to {options.names}", file=sys.stderr)


if __name__ == "__main__":
    main()
