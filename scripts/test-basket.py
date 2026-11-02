#!/usr/bin/env python3
"""Writes the test basket for the nightly game test: which games to test next so Nightforge learns the
most about Steam's 200 most played games, with the games the player already has and the free ones.

  1. owned      games in the player's library (Steam's caches through tests/CatalogProbe, Epic's and
                GOG's lists in Nightforge's support folder), with size and whether installed
  2. free       free-to-play games without an anti-cheat block (profiles/profiles.json), Steam demos of
                the top 200 and free benchmarks
  3. proxy      per engine and graphics API, the cheapest testable game of 1 or 2: a test of it covers
                the top-200 games of the same kind ("standsFor")
  4. untestable top-200 games without reliable Mac data none of that reaches: only the sources and
                players' reports help ("coveredBy" names a proxy of the same kind, if there is one)

Sorted by score = popularity (top-200 rank) × missing data (docs/recherche/mac-abdeckung.md's groups)
× download (installed counts as nothing to download). Engines come from Wikidata (P408, CC0), DirectX
versions, sizes, demos and free-to-play from Steam's store API (one request every 1.6 s, cached).

The basket lists the player's own library, so it is written outside the repository (--out). Nothing
is downloaded or started here; what gets tested is the player's choice.

Usage: test-basket.py --steam-owned owned.json --cache DIR --out testkorb.json [--md testkorb.md]
                      [--support ~/Library/Application Support/Nightforge] [--day 2026-11-01]
  owned.json: tests/CatalogProbe/run.sh "<Steam folder>" --json
"""

import argparse
import datetime
import importlib.util
import json
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("mac_coverage", ROOT / "scripts" / "mac-coverage.py")
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)

USER_AGENT = coverage.USER_AGENT
APPDETAILS = "https://store.steampowered.com/api/appdetails?appids={appid}&l=english"
WIKIDATA = "https://query.wikidata.org/sparql"

# Free benchmarks on Steam that run the engine of a top game; checked against the store's answer by name.
BENCHMARKS = {
    3132990: ("Black Myth: Wukong Benchmark Tool", [2358720]),
    3065170: ("Monster Hunter Wilds Benchmark", [2246340]),
}
# How much a game still needs a test, by what Nightforge knows (mac-coverage.py's groups).
MISSING = {"gap": 1.0, "agw-native": 0.9, "agw-bad": 0.8, "agw-good": 0.5, "tested": 0.05, "mac": 0.05, "anticheat": 0.0}
OUTSIDE_TOP = 0.15


def steam_details(appid: int, cache: pathlib.Path) -> dict:
    """Steam's store answer for an app (cached), {} when it has none."""
    path = cache / f"appdetails-full-{appid}.json"
    if not path.exists():
        time.sleep(1.6)
        request = urllib.request.Request(APPDETAILS.format(appid=appid), headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                path.write_bytes(response.read())
        except OSError:
            return {}
    answer = json.loads(path.read_text() or "{}").get(str(appid), {})
    return answer.get("data") or {} if answer.get("success") else {}


def requirements(details: dict) -> str:
    pc = details.get("pc_requirements") or {}
    if isinstance(pc, list):
        return ""
    return re.sub(r"<[^>]+>", " ", " ".join(str(pc.get(k, "")) for k in ("minimum", "recommended")))


def apis(details: dict) -> list:
    """["dx11", "dx12", "vulkan"] as the system requirements name them."""
    text = requirements(details)
    found = {"dx" + m for m in re.findall(r"(?i)DirectX\s*:?\s*(?:Version\s*)?(9|10|11|12)\b", text)}
    found |= {"dx" + m for m in re.findall(r"(?i)\bDX\s?(11|12)\b", text)}
    if re.search(r"(?i)\bvulkan\b", text):
        found.add("vulkan")
    return sorted(found, key=lambda a: (a == "vulkan", int(a[2:]) if a[2:].isdigit() else 0))


def storage_gb(details: dict):
    match = re.search(r"(?i)(?:Storage|Hard (?:Drive|Disk)(?: Space)?)\s*:\s*(\d+(?:[.,]\d+)?)\s*(GB|MB|TB)", requirements(details))
    if not match:
        return None
    value = float(match.group(1).replace(",", "."))
    return round(value / 1024 if match.group(2).upper() == "MB" else value * 1024 if match.group(2).upper() == "TB" else value, 1)


def engines(appids: list, cache: pathlib.Path) -> dict:
    """Steam app ID → engine names from Wikidata (P408), one query."""
    path = cache / "wikidata-engines.json"
    if not path.exists():
        values = " ".join(f'"{a}"' for a in sorted(set(appids)))
        query = ("SELECT ?steam ?engineLabel WHERE { VALUES ?steam { " + values + " } ?item wdt:P1733 ?steam ; wdt:P408 ?engine . "
                 "SERVICE wikibase:label { bd:serviceParam wikibase:language \"en\". } }")
        request = urllib.request.Request(WIKIDATA, data=urllib.parse.urlencode({"query": query}).encode(),
                                         headers={"User-Agent": USER_AGENT, "Accept": "application/sparql-results+json"})
        with urllib.request.urlopen(request, timeout=120) as response:
            path.write_bytes(response.read())
    found = {}
    for row in json.loads(path.read_text())["results"]["bindings"]:
        name = row["engineLabel"]["value"]
        if re.fullmatch(r"Q\d+", name):
            continue
        found.setdefault(int(row["steam"]["value"]), set()).add(name)
    return {appid: " / ".join(sorted(names)) for appid, names in found.items()}


def installed_steam(steam: pathlib.Path) -> dict:
    """Steam app ID → bytes on disk, from libraryfolders.vdf's "apps" blocks."""
    try:
        text = (steam / "steamapps" / "libraryfolders.vdf").read_text(errors="replace")
    except OSError:
        return {}
    found = {}
    for block in re.findall(r'"apps"\s*\{([^}]*)\}', text):
        for appid, size in re.findall(r'"(\d+)"\s+"(\d+)"', block):
            found[int(appid)] = int(size)
    return found


def read_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def library(owned_steam: list, support: pathlib.Path) -> list:
    """Every game in the player's library: {"key", "name", "store", "steam" (its Steam app ID or twin),
    "sizeGB", "installed", "mac"}."""
    steam_root = support / "Prefix" / "drive_c" / "Program Files (x86)" / "Steam"
    on_disk = installed_steam(steam_root)
    games = []
    for game in owned_steam:
        size = on_disk.get(game["appID"]) or game.get("size") or 0
        games.append({"key": f"steam.{game['appID']}", "name": game["name"], "store": "steam", "steam": game["appID"],
                      "sizeGB": round(size / 1e9, 1) if size else None, "installed": game["appID"] in on_disk,
                      "mac": bool(game.get("mac")), "vrOnly": bool(game.get("vrOnly"))})
    twins = read_json(support / "GameInfo" / "known.json", {}).get("twins", {})
    epic_sizes = read_json(support / "Epic" / "sizes.json", {})
    epic_installed = read_json(support / "Epic" / "legendary" / "installed.json", {})
    for game in read_json(support / "Epic" / "library.json", {}).get("games", []):
        app = game.get("appName")
        size = (epic_sizes.get(app) or {}).get("download")
        games.append({"key": f"epic.{app}", "name": game.get("title"), "store": "epic",
                      "steam": (twins.get(f"epic.{app}") or {}).get("appID"), "sizeGB": round(size / 1e9, 1) if size else None,
                      "installed": app in epic_installed, "mac": False, "vrOnly": False})
    gog_sizes = read_json(support / "GOG" / "sizes.json", {})
    gog_installed = read_json(support / "GOG" / "installed.json", {})
    for game in read_json(support / "GOG" / "library.json", {}).get("games", []):
        product = str(game.get("id"))
        size = (gog_sizes.get(f"{product}.windows") or {}).get("download")
        games.append({"key": f"gog.{product}", "name": game.get("title"), "store": "gog",
                      "steam": (twins.get(f"gog.{product}") or {}).get("appID"), "sizeGB": round(size / 1e9, 1) if size else None,
                      "installed": product in gog_installed, "mac": bool(game.get("mac")), "vrOnly": False})
    return games


def build(top: list, owned: list, profiles: dict, mac: dict, agw: dict, cache: pathlib.Path) -> list:
    rank = {g["appid"]: g for g in top}
    facts = {g["appid"]: coverage.classify(g, profiles, mac, agw) for g in top}
    details = {}
    wanted = set(rank) | {g["steam"] for g in owned if g["steam"]} | set(BENCHMARKS)
    for appid in sorted(wanted):
        details[appid] = steam_details(appid, cache)
    demos = {}
    for appid in rank:
        for demo in details.get(appid, {}).get("demos") or []:
            if str(demo.get("appid", "")).isdigit():
                demos[int(demo["appid"])] = appid
    for appid in demos:
        details[appid] = steam_details(appid, cache)
    engine = engines(list(wanted | set(demos)), cache)

    def describe(appid):
        d = details.get(appid) or {}
        return {"engine": engine.get(appid), "api": apis(d) or None}

    def data_of(appid, mac_flag=False):
        if appid in facts:
            return facts[appid]
        game = {"appid": appid, "name": "", "mac": mac_flag}
        return coverage.classify(game, profiles, mac, agw)

    def blocked(appid):
        profile = profiles.get("games", {}).get(str(appid), {})
        return bool(profile.get("antiCheat") or profile.get("antiCheatOnline") or profile.get("notYet"))

    def popularity(appid):
        return 1 - (rank[appid]["rank"] - 1) / 200 if appid in rank else OUTSIDE_TOP

    entries = {}

    def add(key, name, category, kind, steam, owned_flag, installed, size, stands=None):
        f = data_of(steam) if steam else {"group": "gap", "wine": {}, "hint": None, "mac": False}
        entry = {"key": key, "name": name, "category": category, "kind": kind, "owned": owned_flag, "installed": installed,
                 "sizeGB": size, "rank": rank[steam]["rank"] if steam in rank else None, "data": f["group"],
                 **(describe(steam) if steam else {"engine": None, "api": None}),
                 "agw": f["wine"] or None, "hint": f["hint"], "standsFor": stands or []}
        entries.setdefault(key, entry)
        return entries[key]

    # 1. The player's library: Windows games only (a Mac version needs no Wine test), no VR-only ones.
    for game in owned:
        if game["mac"] or game["vrOnly"] or game["steam"] in coverage.SOFTWARE or (game["steam"] and blocked(game["steam"])):
            continue
        add(game["key"], game["name"], "owned", "game", game["steam"], True, game["installed"], game["sizeGB"])
    # 2. Free: free-to-play top games without a block, demos of top games, benchmarks.
    for appid in rank:
        d = details.get(appid) or {}
        if d.get("is_free") and d.get("type") == "game" and not blocked(appid) and not rank[appid]["mac"] \
                and f"steam.{appid}" not in entries:
            add(f"steam.{appid}", rank[appid]["name"], "free", "f2p", appid, False, False, storage_gb(d))
    for appid, main in demos.items():
        d = details.get(appid) or {}
        if d.get("type") == "demo" and not blocked(main) and not rank[main]["mac"] and f"steam.{appid}" not in entries:
            entry = add(f"steam.{appid}", d.get("name") or f"{rank[main]['name']} Demo", "free", "demo", main, False, False,
                        storage_gb(d), stands=[f"steam.{main}"])
            entry.update({"demoOf": f"steam.{main}"})
    for appid, (name, covers) in BENCHMARKS.items():
        d = details.get(appid) or {}
        if not d or name.split(":")[0].lower() not in (d.get("name") or "").lower():
            continue
        main = covers[0]
        entry = add(f"steam.{appid}", d.get("name"), "free", "benchmark", main, f"steam.{appid}" in {g["key"] for g in owned},
                    False, storage_gb(d), stands=[f"steam.{c}" for c in covers])
        entry["installed"] = any(g["key"] == f"steam.{appid}" and g["installed"] for g in owned)
        if f"steam.{appid}" in rank:
            entry["rank"] = rank[appid]["rank"]

    # 3. Proxies: per engine and API, the testable game that's cheapest to test covers the top games of its kind.
    def kind_of(entry):
        return (entry["engine"], tuple(entry["api"] or ())) if entry["engine"] and entry["api"] else None

    needing = [g for g in top if facts[g["appid"]]["group"] in ("gap", "agw-bad", "agw-good", "agw-native")]
    testable = [e for e in entries.values() if e["category"] in ("owned", "free")]
    for game in needing:
        kind = kind_of({**describe(game["appid"])})
        if not kind:
            continue
        candidates = [e for e in testable if kind_of(e) == kind]
        if not candidates:
            continue
        best = min(candidates, key=lambda e: (not e["installed"], e["sizeGB"] if e["sizeGB"] is not None else 999))
        if f"steam.{game['appid']}" != best["key"] and f"steam.{game['appid']}" not in best["standsFor"]:
            best["standsFor"].append(f"steam.{game['appid']}")
        best["category"] = "proxy" if best["standsFor"] and best["key"] not in best["standsFor"] else best["category"]
        game["coveredBy"] = best["key"]

    # 4. Top games without reliable Mac data that nothing above reaches.
    for game in needing:
        key = f"steam.{game['appid']}"
        if key in entries or any(key in e["standsFor"] and e["kind"] in ("demo", "benchmark") for e in entries.values()):
            continue
        entry = add(key, game["name"], "untestable", "game", game["appid"], False, False, storage_gb(details.get(game["appid"]) or {}))
        if game.get("coveredBy"):
            entry["coveredBy"] = game["coveredBy"]

    # Scores and reasons.
    for entry in entries.values():
        own = int(entry["key"].split(".")[1]) if entry["key"].startswith("steam.") and entry["key"].split(".")[1].isdigit() else None
        steam = next((g["steam"] for g in owned if g["key"] == entry["key"]), own)
        covered = [int(k.split(".")[1]) for k in entry["standsFor"] if k.split(".")[1].isdigit()]
        pops = sorted([popularity(c) for c in covered] + ([popularity(steam)] if steam else []), reverse=True)
        pop = (pops[0] + 0.25 * sum(pops[1:4])) if pops else OUTSIDE_TOP
        missing = max([MISSING.get(data_of(c)["group"], 0.5) for c in covered] + [MISSING.get(entry["data"], 0.5)])
        size = entry["sizeGB"]
        download = 1.0 if entry["installed"] else 0.6 if size is None else 1 / (1 + size / 25)
        # Tested already (mac.json): its result counts for the games it stands for, no new test needed.
        known = 0.2 if entry["data"] in ("tested", "mac") else 1
        entry["score"] = round(min(pop, 2.0) * missing * download * known * (0.3 if entry["category"] == "untestable" else 1), 3)
        entry["why"] = reason(entry, len(covered))
    return sorted(entries.values(), key=lambda e: (-e["score"], e["name"] or ""))


GROUP_WORDS = {"gap": "keine Mac-Daten", "agw-bad": "AGW: Probleme", "agw-good": "AGW: läuft, nicht bestätigt",
               "agw-native": "AGW nur nativ", "tested": "schon getestet", "mac": "Mac-Version", "anticheat": "Anti-Cheat"}


def reason(entry: dict, covers: int) -> str:
    parts = [f"Top {entry['rank']}" if entry["rank"] else "außerhalb der Top 200", GROUP_WORDS.get(entry["data"], entry["data"])]
    if entry["installed"]:
        parts.append("schon installiert")
    elif entry["sizeGB"] is not None:
        parts.append(f"{entry['sizeGB']:g} GB Download")
    if entry["kind"] in ("demo", "benchmark", "f2p"):
        parts.append({"demo": "kostenlose Demo", "benchmark": "kostenloser Benchmark", "f2p": "kostenlos spielbar"}[entry["kind"]])
    if covers and entry["data"] == "tested":
        parts.append(f"sein Ergebnis gilt für {covers} Top-Spiel{'e' if covers > 1 else ''} gleicher Engine und API")
    elif covers:
        parts.append(f"deckt {covers} Top-Spiel{'e' if covers > 1 else ''} gleicher Engine und API ab")
    if entry["category"] == "untestable":
        parts.append("nicht im Besitz, keine Demo" + (f", Stellvertreter {entry['coveredBy']}" if entry.get("coveredBy") else ""))
    return ", ".join(parts)


def markdown(basket: list, generated: str) -> str:
    lines = ["# Testkorb für den nächtlichen Spieletest", "",
             f"Erzeugt {generated} von `scripts/test-basket.py` (lokal, nicht im Repo: enthält die eigene Bibliothek). "
             "Nichts wird heruntergeladen; was getestet wird, entscheidet der Nutzer.", ""]
    names = {"proxy": "Stellvertreter (deckt andere Spiele mit ab)", "owned": "Schon im Besitz", "free": "Kostenlos testbar",
             "untestable": "Nicht testbar (nur Quellen und Berichte)"}
    for category in ("proxy", "owned", "free", "untestable"):
        rows = [e for e in basket if e["category"] == category]
        if not rows:
            continue
        lines += [f"## {names[category]} ({len(rows)})", "", "| Score | Spiel | Key | Engine · API | Hinweis | Warum |", "|---|---|---|---|---|---|"]
        for e in rows[:60 if category != "untestable" else 40]:
            kind = " · ".join(p for p in [e["engine"], ", ".join(e["api"] or [])] if p) or "–"
            lines.append(f"| {e['score']:.2f} | {coverage.escape(e['name'])} | `{e['key']}` | {coverage.escape(kind)} | {e['hint'] or ''} | "
                         f"{coverage.escape(e['why'])} |")
        if len(rows) > 60:
            lines.append(f"| | … {len(rows) - 60} weitere in testkorb.json | | | | |")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--steam-owned", type=pathlib.Path, required=True)
    parser.add_argument("--support", type=pathlib.Path, default=pathlib.Path.home() / "Library" / "Application Support" / "Nightforge")
    parser.add_argument("--cache", type=pathlib.Path, required=True)
    parser.add_argument("--day", default=(datetime.date.today() - datetime.timedelta(days=1)).isoformat())
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--md", type=pathlib.Path)
    options = parser.parse_args()
    if ROOT in options.out.resolve().parents or (options.md and ROOT in options.md.resolve().parents):
        parser.error("the basket lists the player's own library: write it outside the repository")
    options.cache.mkdir(parents=True, exist_ok=True)

    top, _ = coverage.top200(options.day, options.cache)
    owned = library(json.loads(options.steam_owned.read_text()), options.support)
    profiles = json.loads((ROOT / "profiles" / "profiles.json").read_text())
    mac = json.loads((ROOT / "profiles" / "mac.json").read_text())
    agw = json.loads((ROOT / "profiles" / "agw.json").read_text())
    basket = build(top, owned, profiles, mac, agw, options.cache)
    generated = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    options.out.write_text(json.dumps({"formatVersion": 1, "generated": generated, "games": basket}, indent=1, ensure_ascii=False) + "\n")
    if options.md:
        options.md.write_text(markdown(basket, generated[:10]))
    counts = {}
    for entry in basket:
        counts[entry["category"]] = counts.get(entry["category"], 0) + 1
    print(f"{len(owned)} games in the library, {len(basket)} in the basket: {counts} → {options.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
