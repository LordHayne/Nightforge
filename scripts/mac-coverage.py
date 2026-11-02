#!/usr/bin/env python3
"""Writes docs/recherche/mac-abdeckung.md: which of Steam's 200 most played games Nightforge has Mac
knowledge for, and which it has none for – so testing goes to the gaps.

The list is built like docs/recherche/top200.md's: places 1–100 from Steam's GetMostPlayedGames as the
GitHub repo JigSawFr/Atlas mirrors it (branch data), places 101–200 by the day's peak of Steam's hourly
player counts for 500 games in Fegue3/Steam-Analytics (branch data), with its names and Mac flags.
Software (Wallpaper Engine, OBS, …) is left out. Names and Mac flags the mirrors lack come from Steam's
store API, one request every 1.5 seconds.

Per game: Steam's Mac version, an anti-cheat block (profiles/profiles.json), Nightforge's own test
(profiles/mac.json) and what AppleGamingWiki says (profiles/agw.json). The report is German, like the
other research documents.

Usage: mac-coverage.py [--day 2026-11-01] [--cache DIR] [--out docs/recherche/mac-abdeckung.md]
"""

import argparse
import datetime
import json
import pathlib
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
USER_AGENT = "NightforgeProfiles/1.0 (+https://github.com/LordHayne/Nightforge; Mac coverage report)"
ATLAS = "https://raw.githubusercontent.com/JigSawFr/Atlas/data/sources/steam-store/most-played.json"
ANALYTICS = "https://raw.githubusercontent.com/Fegue3/Steam-Analytics/data/raw/{kind}/{day}.jsonl"
APPDETAILS = "https://store.steampowered.com/api/appdetails?appids={appid}&filters=basic,platforms&l=english"

# Not games: what the research left out as well, and tools that show up in Steam's charts.
SOFTWARE = {
    431960: "Wallpaper Engine", 1905180: "OBS Studio", 1366800: "Crosshair X", 993090: "Lossless Scaling",
    250820: "SteamVR", 629520: "Soundpad", 480: "Spacewar", 404790: "Godot Engine", 1070560: "Steam Linux Runtime",
}

AGW_RATINGS = {"perfect": "perfekt", "playable": "spielbar", "runs": "läuft mit Fehlern", "menu": "nur Menü", "unplayable": "unspielbar"}
GOOD = {"perfect", "playable"}


def fetch(url: str, cache: pathlib.Path) -> bytes:
    """The file at `url`, downloaded once into `cache`."""
    path = cache / url.split("//", 1)[1].replace("/", "_")
    if path.exists():
        return path.read_bytes()
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    path.write_bytes(data)
    return data


def steam_details(appid: int, cache: pathlib.Path) -> dict:
    """{"name", "type", "mac"} from Steam's store API; {} when it doesn't say."""
    path = cache / f"appdetails-{appid}.json"
    if not path.exists():
        time.sleep(1.5)
        request = urllib.request.Request(APPDETAILS.format(appid=appid), headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=60) as response:
            path.write_bytes(response.read())
    answer = json.loads(path.read_text()).get(str(appid), {})
    data = answer.get("data") or {}
    if not answer.get("success") or not data:
        return {}
    return {"name": data.get("name"), "type": data.get("type"), "mac": (data.get("platforms") or {}).get("mac")}


def top200(day: str, cache: pathlib.Path) -> list:
    """[{"rank", "appid", "name", "mac"}] for the 200 most played games."""
    atlas = json.loads(fetch(ATLAS, cache))
    players = [json.loads(line) for line in fetch(ANALYTICS.format(kind="players", day=day), cache).decode().splitlines() if line.strip()]
    metadata = [json.loads(line) for line in fetch(ANALYTICS.format(kind="metadata", day=day), cache).decode().splitlines() if line.strip()]
    known = {g["appid"]: g for run in metadata for g in run.get("games", []) if g.get("status") == "ok"}
    peak = {}
    for run in players:
        for game in run.get("games", []):
            if game.get("status") == "ok":
                peak[game["appid"]] = max(peak.get(game["appid"], 0), game.get("players") or 0)

    def details(appid):
        """(name, mac), or None for something that isn't a game."""
        meta = known.get(appid)
        name, mac = (meta.get("name"), meta.get("mac")) if meta else (None, None)
        if name is None or mac is None:
            store = steam_details(appid, cache)
            if store.get("type") not in (None, "game"):
                return None
            name, mac = name or store.get("name"), mac if mac is not None else store.get("mac")
        return name or "?", mac

    charts = [int(appid) for appid, _ in sorted(atlas["items"].items(), key=lambda item: item[1])]
    by_peak = [appid for appid, _ in sorted(peak.items(), key=lambda item: -item[1])]
    result, seen = [], set()
    # The charts' first 100 games, then the next by the day's peak.
    for candidates, limit in ((charts, 100), (by_peak, 200)):
        for appid in candidates:
            if len(result) >= limit:
                break
            if appid in seen or appid in SOFTWARE:
                continue
            seen.add(appid)
            found = details(appid)
            if found:
                result.append({"appid": appid, "name": found[0], "mac": found[1], "players": peak.get(appid)})
    for rank, game in enumerate(result, 1):
        game["rank"] = rank
    return result, atlas.get("generated")


def agw_entry(agw: dict, appid: int):
    key = str(appid)
    games, aliases = agw.get("games", {}), agw.get("aliases", {}).get("steam", {})
    return games.get(key) or games.get(aliases.get(key, ""))


def classify(game: dict, profiles: dict, mac: dict, agw: dict) -> dict:
    appid = str(game["appid"])
    profile = profiles.get("games", {}).get(appid, {})
    entry = agw_entry(agw, game["appid"])
    wine = {way: report["rating"] for way, report in (entry or {}).get("paths", {}).items() if way in ("crossover", "wine")}
    native = {way: report["rating"] for way, report in (entry or {}).get("paths", {}).items() if way in ("native", "rosetta")}
    facts = {
        "mac": game["mac"] is True,
        "antiCheat": bool(profile.get("antiCheat")),
        "online": bool(profile.get("antiCheatOnline")) and not profile.get("antiCheat"),
        "tested": appid in mac.get("games", {}),
        "notYet": bool(profile.get("notYet")),
        "wine": wine,
        "native": native,
        "hint": (entry or {}).get("hint", {}).get("graphics"),
        "page": (entry or {}).get("page"),
        "byName": (entry or {}).get("ids") == "name",
    }
    if facts["antiCheat"] or facts["online"]:
        group = "anticheat"
    elif facts["tested"]:
        group = "tested"
    elif facts["mac"]:
        group = "mac"
    elif any(r in GOOD for r in wine.values()):
        group = "agw-good"
    elif wine:
        group = "agw-bad"
    elif native:
        group = "agw-native"
    else:
        group = "gap"
    facts["group"] = group
    return facts


GROUPS = [
    ("anticheat", "Anti-Cheat sperrt, ganz oder online (profiles.json)", "entschieden: GeForce Now oder nur offline"),
    ("tested", "Von Nightforge getestet (mac.json)", "entschieden"),
    ("mac", "Mac-Version bei Steam", "Nightforge nimmt sie von selbst"),
    ("agw-good", "AGW: läuft über CrossOver/Wine", "Hinweis da, Test bestätigt ihn"),
    ("agw-bad", "AGW: nur mit Problemen über CrossOver/Wine", "testen, mit Vorsicht"),
    ("agw-native", "AGW kennt nur einen Mac-Weg (nativ/Rosetta)", "Lücke für Wine"),
    ("gap", "Keine Mac-Daten", "Lücke: hier zuerst testen"),
]


def markdown(games: list, generated: str, day: str, agw: dict) -> str:
    counts = {key: {50: 0, 100: 0, 200: 0} for key, _, _ in GROUPS}
    for game in games:
        for limit in (50, 100, 200):
            if game["rank"] <= limit:
                counts[game["facts"]["group"]][limit] += 1
    hints = sum(1 for g in games if g["facts"]["hint"])
    with_agw = sum(1 for g in games if g["facts"]["page"])
    wine_rated = sum(1 for g in games if g["facts"]["wine"])
    lines = [
        "<!-- Erzeugt von scripts/mac-coverage.py; neu erzeugen statt von Hand ändern. -->",
        "",
        "## Mac-Daten für die 200 meistgespielten Steam-Spiele",
        "",
        f"Stand: Steam-Charts vom {generated} (Plätze 1–100), Spielerspitzen vom {day} (Plätze 101–200), "
        f"`profiles/agw.json` vom {agw.get('generated', '?')[:10]}. Software wie Wallpaper Engine und OBS ist herausgenommen.",
        "",
        "### Kurzfassung",
        "",
        "| Gruppe | Top 50 | Top 100 | Top 200 | Was das heißt |",
        "|---|---|---|---|---|",
    ]
    for key, label, meaning in GROUPS:
        c = counts[key]
        lines.append(f"| {label} | {c[50]} | {c[100]} | {c[200]} | {meaning} |")
    lines += [
        "",
        f"- AppleGamingWiki kennt {with_agw} der 200 Spiele, {wine_rated} davon mit einer Bewertung für CrossOver oder Wine. "
        f"Für {hints} gibt es einen klaren Grafikweg (`hint`), den LaunchHealth zuerst nimmt, wo er passt.",
        "- Die Gruppen schließen sich aus, in der Reihenfolge der Tabelle: Ein Spiel mit Anti-Cheat-Sperre zählt nur dort, "
        "auch wenn es eine Mac-Version hat.",
        "- AGW-Bewertungen stammen meist von CrossOver 22–25, nicht von Nightforges winecx/DXMT/D3DMetal. "
        "„Läuft laut AGW“ heißt: ein guter Kandidat, kein Beweis.",
        "",
        "### Wo zuerst getestet werden sollte",
        "",
        "Spiele ohne Mac-Version, ohne Sperre und ohne eigenen Test, nach Rang. „Keine Mac-Daten“ zuerst, dann die mit Problemen.",
        "",
        "| Rang | Spiel | App-ID | AGW (CrossOver/Wine) |",
        "|---|---|---|---|",
    ]
    for game in games:
        if game["facts"]["group"] in ("gap", "agw-bad", "agw-native"):
            lines.append(f"| {game['rank']} | {escape(game['name'])} | {game['appid']} | {agw_text(game['facts']) or 'nichts'} |")
    lines += [
        "",
        "### Alle 200",
        "",
        "Spalten: Mac = Steam hat eine Mac-Version; AC = Anti-Cheat sperrt (online = nur online); NF = Profil in `mac.json`; "
        "AGW = AppleGamingWiki für CrossOver/Wine (Hinweis in Klammern), „nativ“ wenn das Wiki nur einen Mac-Weg kennt; "
        "* = über den Namen gefunden.",
        "",
        "| Rang | Spiel | App-ID | Mac | AC | NF | AGW |",
        "|---|---|---|---|---|---|---|",
    ]
    for game in games:
        f = game["facts"]
        ac = "ja" if f["antiCheat"] else "online" if f["online"] else ""
        nf = "noch nicht" if f["notYet"] else "ja" if f["tested"] else ""
        lines.append(f"| {game['rank']} | {escape(game['name'])} | {game['appid']} | {'ja' if f['mac'] else ''} | {ac} | {nf} | {agw_text(f)} |")
    lines += [
        "",
        "### Quellen",
        "",
        "- Steam `ISteamChartsService/GetMostPlayedGames`, gespiegelt in https://github.com/JigSawFr/Atlas (Branch `data`).",
        "- Steam `GetNumberOfCurrentPlayers` und `IStoreBrowseService/GetItems`, gespiegelt in https://github.com/Fegue3/Steam-Analytics (Branch `data`).",
        "- AppleGamingWiki über `profiles/agw.json` (CC BY-NC-SA 3.0, https://www.applegamingwiki.com).",
        "",
    ]
    return "\n".join(lines)


def agw_text(f: dict) -> str:
    parts = [f"{way}: {AGW_RATINGS[r]}" for way, r in sorted(f["wine"].items())]
    if not parts and f["native"]:
        parts = ["nativ: " + ", ".join(AGW_RATINGS[r] for r in f["native"].values())]
    text = ", ".join(parts)
    if f["hint"]:
        text += f" ({f['hint']})"
    if text and f["byName"]:
        text += " *"
    return text


def escape(text: str) -> str:
    return str(text).replace("|", "\\|")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--day", default=(datetime.date.today() - datetime.timedelta(days=1)).isoformat(),
                        help="the day of Steam-Analytics' player counts (a whole day: yesterday by default)")
    parser.add_argument("--cache", type=pathlib.Path, required=True, help="a folder for the downloads")
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "docs" / "recherche" / "mac-abdeckung.md")
    options = parser.parse_args()
    options.cache.mkdir(parents=True, exist_ok=True)

    games, generated = top200(options.day, options.cache)
    profiles = json.loads((ROOT / "profiles" / "profiles.json").read_text())
    mac = json.loads((ROOT / "profiles" / "mac.json").read_text())
    agw = json.loads((ROOT / "profiles" / "agw.json").read_text())
    for game in games:
        game["facts"] = classify(game, profiles, mac, agw)
    options.out.write_text(markdown(games, generated, options.day, agw), encoding="utf-8")
    groups = {}
    for game in games:
        groups[game["facts"]["group"]] = groups.get(game["facts"]["group"], 0) + 1
    print(f"{len(games)} games: {groups} → {options.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
