#!/usr/bin/env python3
"""Writes profiles/pcgw-directx.json: the DirectX versions PCGamingWiki lists for the games it knows a
DirectX 12 for, by Steam app ID. fetch-agw.py carries them into profiles/agw.json, which isn't bundled with
the app: PCGamingWiki's content is CC BY-NC-SA 3.0.

PCGamingWiki's Cargo API has wanted a login since August 2026: an account's bot password, in PCGW_BOT_USER
("Name@botname") and PCGW_BOT_PASSWORD. Without them nothing is fetched and the file stays as it is. The
wiki allows 60 requests a minute and is a small community project: a run takes a few dozen requests.

Usage: fetch-pcgw.py [--out profiles/pcgw-directx.json] [--minimum 200]
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
USER_AGENT = "NightforgeProfiles/1.0 (+https://github.com/LordHayne/Nightforge; nightly import of profiles/pcgw-directx.json)"
DELAY = 1.5
PAGE = 500
MAX_PAGES = 200


def version_key(version: str) -> tuple:
    digits = "".join(c for c in version if c.isdigit() or c == ".")
    try:
        return (float(digits), version)
    except ValueError:
        return (0.0, version)


def directx_by_app(rows: list) -> dict:
    """Steam app ID → DirectX versions, from the API's rows. A page can name several app IDs."""
    games = {}
    for row in rows:
        fields = row.get("title", row)
        versions = sorted({v.strip() for v in (fields.get("d3d") or "").split(",") if v.strip()}, key=version_key)
        for app in (fields.get("steam") or "").split(","):
            app = app.strip()
            if app.isdigit() and versions:
                games[app] = versions
    return dict(sorted(games.items(), key=lambda item: int(item[0])))


def document(games: dict, previous: dict = None, now: datetime.datetime = None) -> dict:
    doc = {
        "about": "The DirectX versions PCGamingWiki lists for games it knows a DirectX 12 for, by Steam app ID. "
                 "Built by scripts/fetch-pcgw.py.",
        "license": "CC BY-NC-SA 3.0",
        "licenseURL": "https://creativecommons.org/licenses/by-nc-sa/3.0/",
        "attribution": "PCGamingWiki contributors, https://www.pcgamingwiki.com",
        "games": games,
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
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, params: dict, post: bool = False) -> dict:
        wait = self.last + self.delay - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        self.last = time.monotonic()
        body = urllib.parse.urlencode(params | {"format": "json"})
        url, data = (API, body.encode()) if post else (API + "?" + body, None)
        request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
        with self.opener.open(request, timeout=60) as response:
            return json.loads(response.read())

    def login(self, user: str, password: str):
        token = self.call({"action": "query", "meta": "tokens", "type": "login"})["query"]["tokens"]["logintoken"]
        answer = self.call({"action": "login", "lgname": user, "lgpassword": password, "lgtoken": token}, post=True)
        result = answer.get("login", {}).get("result")
        if result != "Success":
            raise RuntimeError(f"login failed: {result}")

    def rows(self) -> list:
        rows, offset = [], 0
        for _ in range(MAX_PAGES):
            answer = self.call({
                "action": "cargoquery", "tables": "Game,API", "join_on": "Game._pageID=API._pageID",
                "fields": "Game.Steam_AppID=steam,API.Direct3D_versions=d3d",
                "where": 'API.Direct3D_versions HOLDS "12" AND Game.Steam_AppID IS NOT NULL',
                "order_by": "Game._pageID", "limit": str(PAGE), "offset": str(offset),
            })
            if "error" in answer:
                raise RuntimeError(f"{answer['error'].get('code')}: {answer['error'].get('info')}")
            page = answer.get("cargoquery", [])
            rows += page
            if len(page) < PAGE:
                return rows
            offset += PAGE
        raise RuntimeError("more pages than expected")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "profiles" / "pcgw-directx.json")
    parser.add_argument("--minimum", type=int, default=200, help="fewer games than this fails the run")
    options = parser.parse_args()
    user, password = os.environ.get("PCGW_BOT_USER"), os.environ.get("PCGW_BOT_PASSWORD")
    if not user or not password:
        print("No PCGW_BOT_USER and PCGW_BOT_PASSWORD: nothing fetched, the list stays as it is.")
        return 0
    wiki = Wiki()
    wiki.login(user, password)
    rows = wiki.rows()
    games = directx_by_app(rows)
    if len(games) < options.minimum:
        print(f"only {len(games)} games, expected at least {options.minimum}: keeping the old file", file=sys.stderr)
        return 1
    previous = json.loads(options.out.read_text(encoding="utf-8")) if options.out.exists() else None
    options.out.write_text(json.dumps(document(games, previous), indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    only12 = sum(1 for versions in games.values() if versions == ["12"])
    print(f"{len(rows)} rows → {len(games)} games with DirectX 12, {only12} with nothing else → {options.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
