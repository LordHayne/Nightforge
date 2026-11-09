#!/usr/bin/env python3
"""Fetches what PCGamingWiki knows about every game: its IDs (Steam, GOG), engine, graphics interfaces,
32/64-bit programs, middleware (PhysX, audio, video, anti-cheat) and DRM. The whole of it goes to --facts
(build/pcgw-facts.json, not in the repository: data to look into); profiles/pcgw.json gets what Nightforge
uses, by Steam app ID, and fetch-agw.py carries that into profiles/agw.json, which isn't bundled with the
app: PCGamingWiki's content is CC BY-NC-SA 3.0.

PCGamingWiki's Cargo API has wanted a login since August 2026: an account's bot password with the right to
query Cargo, in PCGW_BOT_USER ("Name@botname") and PCGW_BOT_PASSWORD. Without them nothing is fetched and the
files stay as they are. The wiki allows 60 requests a minute and is a small community project: a run takes
a little over a hundred requests, one every 1.5 s.

Usage: fetch-pcgw.py [--out profiles/pcgw.json] [--facts build/pcgw-facts.json] [--minimum 10000]
"""

import argparse
import datetime
import http.cookiejar
import json
import os
import pathlib
import sys
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
API = "https://www.pcgamingwiki.com/w/api.php"
USER_AGENT = "NightforgeProfiles/1.0 (+https://github.com/LordHayne/Nightforge; nightly import of profiles/pcgw.json)"
DELAY = 1.5
PAGE = 500
MAX_PAGES = 400

TABLES = "Game,API,Middleware,Availability"
JOIN = "Game._pageID=API._pageID,Game._pageID=Middleware._pageID,Game._pageID=Availability._pageID"
# Alias → column. Lists come comma-separated.
FIELDS = {
    "page": "Game._pageName", "steam": "Game.Steam_AppID", "gog": "Game.GOGcom_ID", "engines": "Game.Engines",
    "d3d": "API.Direct3D_versions", "ddraw": "API.DirectDraw_versions", "opengl": "API.OpenGL_versions",
    "vulkan": "API.Vulkan_versions", "glide": "API.Glide_versions", "metal": "API.Metal_support",
    "win32": "API.Windows_32bit_executable", "win64": "API.Windows_64bit_executable",
    "macIntel": "API.macOS_Intel_64bit_app", "macARM": "API.macOS_ARM_app",
    "physics": "Middleware.Physics", "audio": "Middleware.Audio", "cutscenes": "Middleware.Cutscenes",
    "multiplayer": "Middleware.Multiplayer", "anticheat": "Middleware.Anticheat", "drm": "Availability.Uses_DRM",
    "drmSteam": "Availability.Steam_DRM", "drmEpic": "Availability.Epic_Games_Store_DRM", "drmGOG": "Availability.GOGcom_DRM",
}
LISTS = {"steam", "gog", "engines", "d3d", "ddraw", "opengl", "vulkan", "glide", "physics", "audio", "cutscenes",
         "multiplayer", "anticheat", "drm", "drmSteam", "drmEpic", "drmGOG"}
# DRM that's no news on a Steam game.
PLAIN_DRM = {"Steam", "DRM-free", "GOG.com"}


def version_key(version: str) -> tuple:
    digits = "".join(c for c in version if c.isdigit() or c == ".")
    try:
        return (float(digits.split(".")[0] + "." + "".join(digits.split(".")[1:]) if "." in digits else digits), version)
    except ValueError:
        return (0.0, version)


def facts(rows: list) -> dict:
    """Page name → what it lists, empty values left out."""
    pages = {}
    for row in rows:
        fields = row.get("title", row)
        page = (fields.get("page") or "").strip()
        if not page:
            continue
        entry = {}
        for alias in FIELDS:
            value = (fields.get(alias) or "").strip()
            if not value or alias == "page":
                continue
            if alias in LISTS:
                items = sorted({v.strip() for v in value.split(",") if v.strip()},
                               key=version_key if alias in ("d3d", "ddraw", "opengl", "vulkan", "glide") else str)
                if items:
                    entry[alias] = items
            else:
                entry[alias] = value
        pages[page] = entry
    return dict(sorted(pages.items()))


def derived(pages: dict) -> dict:
    """What Nightforge uses, by Steam app ID: DirectX versions where one is 12, PhysX, games with only a
    32-bit program, DRM and anti-cheat beyond Steam's own."""
    directx, physx, only32, drm, anticheat = {}, set(), set(), {}, {}
    for entry in pages.values():
        for app in entry.get("steam", []):
            if not app.isdigit():
                continue
            if "12" in entry.get("d3d", []):
                directx[app] = entry["d3d"]
            if any("physx" in p.lower() for p in entry.get("physics", [])):
                physx.add(app)
            if entry.get("win32") == "true" and entry.get("win64") != "true":
                only32.add(app)
            # The Steam version's own DRM where the page says it; what all versions use otherwise.
            other = [d for d in entry.get("drmSteam", entry.get("drm", [])) if d not in PLAIN_DRM]
            if other:
                drm[app] = other
            if entry.get("anticheat"):
                anticheat[app] = entry["anticheat"]
    number = lambda items: sorted(items, key=int)
    by_app = lambda mapping: {app: mapping[app] for app in number(mapping)}
    return {"directX": by_app(directx), "physX": number(physx), "only32bit": number(only32), "drm": by_app(drm),
            "anticheat": by_app(anticheat)}


def document(data: dict, previous: dict = None, now: datetime.datetime = None) -> dict:
    doc = {
        "about": "What PCGamingWiki lists about games, by Steam app ID, as far as Nightforge uses it (scripts/fetch-pcgw.py): "
                 "DirectX versions where one is 12, PhysX, only a 32-bit program, DRM and anti-cheat other than Steam's. "
                 "The full facts stay with the run that fetched them.",
        "license": "CC BY-NC-SA 3.0",
        "licenseURL": "https://creativecommons.org/licenses/by-nc-sa/3.0/",
        "attribution": "PCGamingWiki contributors, https://www.pcgamingwiki.com",
        **data,
    }
    unchanged = previous and {k: v for k, v in previous.items() if k != "generated"} == doc
    doc["generated"] = previous["generated"] if unchanged else \
        (now or datetime.datetime.now(datetime.timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return doc


class Wiki:
    """The MediaWiki API with a login's cookies, one request per DELAY seconds."""

    def __init__(self, delay: float = DELAY):
        self.delay = delay
        self.last = 0.0
        self.requests = 0
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, params: dict, post: bool = False) -> dict:
        wait = self.last + self.delay - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        self.last = time.monotonic()
        self.requests += 1
        body = urllib.parse.urlencode(params | {"format": "json"})
        url, data = (API, body.encode()) if post else (API + "?" + body, None)
        request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
        with self.opener.open(request, timeout=90) as response:
            return json.loads(response.read())

    def login(self, user: str, password: str):
        token = self.call({"action": "query", "meta": "tokens", "type": "login"})["query"]["tokens"]["logintoken"]
        answer = self.call({"action": "login", "lgname": user, "lgpassword": password, "lgtoken": token}, post=True)
        result = answer.get("login", {}).get("result")
        if result != "Success":
            raise RuntimeError(f"login failed: {result}")

    def rows(self) -> list:
        rows, offset = [], 0
        fields = ",".join(f"{column}={alias}" for alias, column in FIELDS.items())
        for _ in range(MAX_PAGES):
            answer = self.call({"action": "cargoquery", "tables": TABLES, "join_on": JOIN, "fields": fields,
                                "order_by": "Game._pageID", "limit": str(PAGE), "offset": str(offset)})
            if "error" in answer:
                raise RuntimeError(f"{answer['error'].get('code')}: {answer['error'].get('info')}")
            page = answer.get("cargoquery", [])
            rows += page
            if len(page) < PAGE:
                return rows
            offset += PAGE
            if offset % 5000 == 0:
                print(f"  {offset} rows …", flush=True)
        raise RuntimeError("more pages than expected")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "profiles" / "pcgw.json")
    parser.add_argument("--facts", type=pathlib.Path, default=ROOT / "build" / "pcgw-facts.json")
    parser.add_argument("--minimum", type=int, default=10000, help="fewer games than this fails the run")
    options = parser.parse_args()
    user, password = os.environ.get("PCGW_BOT_USER"), os.environ.get("PCGW_BOT_PASSWORD")
    if not user or not password:
        print("No PCGW_BOT_USER and PCGW_BOT_PASSWORD: nothing fetched, the lists stay as they are.")
        return 0
    wiki = Wiki()
    wiki.login(user, password)
    rows = wiki.rows()
    pages = facts(rows)
    if len(pages) < options.minimum:
        print(f"only {len(pages)} games, expected at least {options.minimum}: keeping the old files", file=sys.stderr)
        return 1
    options.facts.parent.mkdir(parents=True, exist_ok=True)
    options.facts.write_text(json.dumps({"license": "CC BY-NC-SA 3.0", "attribution": "PCGamingWiki contributors, "
                                         "https://www.pcgamingwiki.com", "games": pages}, ensure_ascii=False) + "\n",
                             encoding="utf-8")
    data = derived(pages)
    previous = json.loads(options.out.read_text(encoding="utf-8")) if options.out.exists() else None
    options.out.write_text(json.dumps(document(data, previous), indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{wiki.requests} requests, {len(rows)} rows → {len(pages)} games; {len(data['directX'])} with DirectX 12, "
          f"{len(data['physX'])} with PhysX, {len(data['only32bit'])} only 32-bit, {len(data['drm'])} with more DRM than "
          f"Steam's, {len(data['anticheat'])} with anti-cheat → {options.out}, {options.facts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
