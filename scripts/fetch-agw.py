#!/usr/bin/env python3
"""Builds profiles/agw.json: what AppleGamingWiki says about running each game on a Mac.

AppleGamingWiki (https://www.applegamingwiki.com) rates every way a game runs on a Mac in a table
on the game's page ({{Compatibility/macOS}}): native, Rosetta 2, CrossOver, Wine (with Apple's Game
Porting Toolkit and Whisky), Parallels. This reads that table for the four ways Nightforge cares about
and the Steam and GOG IDs in the page's infobox.

Its text is licensed CC BY-NC-SA 3.0, which doesn't go together with Nightforge's GPL code or the
permissive profiles.json: the result is a file of its own, under that licence, with attribution
(profiles/LICENSE-applegamingwiki). The app downloads it; it is never built into the app.

Per game and way it keeps the rating, the note shortened and without wiki markup, and what the note
and its {{Refdevice}} reports name: CrossOver or GPTK versions, graphics layers (D3DMetal, DXMT,
DXVK, WineD3D), DirectX versions, Apple chips and the newest report's date. Never the reporters'
user names.

"hint" is Nightforge's reading of it, only where it is clear: the one graphics layer the ways rated
perfect or playable name, when nothing names it in a bad light. Nightforge's own tested profiles
(profiles/mac.json) always win; a game with a layer there gets no hint. In the app a hint only orders
the ways LaunchHealth tries, it never blocks or changes anything else.

More than half of the pages are short ones without an infobox, so without IDs. Their titles are
PCGamingWiki's, and Wikidata (CC0) links PCGamingWiki titles to Steam app IDs: one SPARQL query fills
those in ("ids": "wikidata", or "name" when the title differs in case and punctuation only).

Fetching is polite: an identifying User-Agent, one request per second, maxlag, about 45 requests a
night (the pages that use the table, then their wikitext 50 at a time), and one Wikidata query. When
a source is down or its format changes, the script fails and the last agw.json stays.

Usage: fetch-agw.py [--out profiles/agw.json] [--mac profiles/mac.json]
                    [--pages saved.json | --save-pages saved.json]
                    [--wikidata saved.json | --save-wikidata saved.json]
"""

import argparse
import datetime
import gzip
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
FORMAT_VERSION = 1

API = "https://www.applegamingwiki.com/w/api.php"
WIKI = "https://www.applegamingwiki.com/wiki/"
WIKIDATA = "https://query.wikidata.org/sparql"
# PCGamingWiki ID (P6337) → Steam application ID (P1733).
WIKIDATA_QUERY = "SELECT ?pcgw ?steam WHERE { ?item wdt:P6337 ?pcgw ; wdt:P1733 ?steam . }"
USER_AGENT = "NightforgeProfiles/1.0 (+https://github.com/LordHayne/Nightforge; nightly import of profiles/agw.json)"
TEMPLATE = "Template:Compatibility/macOS"
# Seconds between two requests, and how often one is tried.
DELAY = 1.0
TRIES = 5
BATCH = 50

# The table's ways Nightforge has a use for, by their name in the template.
PATHS = {"native": "native", "rosetta 2": "rosetta", "crossover": "crossover", "wine": "wine"}
# Template:Rating's values; "na", "unknown" and free text say nothing.
RATINGS = ("perfect", "playable", "runs", "menu", "unplayable")
GOOD = {"perfect", "playable"}
# The ways a Windows game runs through; their notes are where graphics layers come up.
WINE_PATHS = ("crossover", "wine")

NOTE_LENGTH = 300
# Some pages have far more text in a note than a table cell takes; after this nothing new is read.
EVIDENCE_LENGTH = 4000

LAYERS = [
    ("d3dmetal", re.compile(r"(?i)\b(?:d3d|3d3)\s?metal\b|\bgptk\b|\bgame\s?porting\s?toolkit\b")),
    ("dxmt", re.compile(r"(?i)\bdxmt\b")),
    ("dxvk", re.compile(r"(?i)\bdxvk\b")),
    ("wined3d", re.compile(r"(?i)\bwine\s?d3d\b")),
]
DIRECTX = re.compile(r"(?i)\b(?:dx|directx|direct3d|d3d)\s?-?\s?(9|10|11|12)\b")
CROSSOVER = re.compile(r"(?i)\bcross\s?over\s?v?(\d{1,2}(?:\.\d{1,2}){0,2})\b")
GPTK = re.compile(r"(?i)\b(?:gptk|game\s?porting\s?toolkit)(?:\s?v?(\d(?:\.\d{1,2})?)\b)?")
WHISKY = re.compile(r"(?i)\bwhisky\b")
CHIP = re.compile(r"\bM([1-9])(?:\s?(Pro|Max|Ultra))?\b")
# Words like these close to a layer's name (NEAR words before or after) mean it isn't recommended
# ("crashes with DXVK", "D3DMetal off", "D3DMetal renders blood incorrectly").
NEAR = 5
NEGATIVE = re.compile(r"(?i)\b(?:not|no|n't|crash\w*|fail\w*|broken|freez\w*|hang\w*|stuck|unplayable|disabl\w*|"
                      r"without|off|avoid|instead|black\s?screen|won't|cannot|can't|doesn't|didn't|error\w*|"
                      r"incorrect\w*|wrong\w*|glitch\w*|artifact\w*|missing|invisible|bug\w*|issue\w*|problem\w*|worse)\b")
# DXMT came with CrossOver 25. A report that picked DXVK before only says it beat Wine's own Direct3D
# and D3DMetal, not DXMT, which Nightforge tries first for DirectX 11: those don't hint DXVK.
DXMT_SINCE = 25


def find_template(text: str, name: str):
    """The body of the first {{name …}} in `text` (between the name and the closing braces), or None."""
    pattern = re.compile(r"\{\{\s*" + r"[\s_]+".join(map(re.escape, name.split())) + r"\s*(?=[|}\n])", re.IGNORECASE)
    match = pattern.search(text)
    if not match:
        return None
    depth, index = 2, match.end()
    while index < len(text):
        if text.startswith("{{", index):
            depth += 2
            index += 2
        elif text.startswith("}}", index):
            depth -= 2
            if depth == 0:
                return text[match.end():index]
            index += 2
        else:
            index += 1
    return None


def template_args(body: str) -> dict:
    """A template body's named arguments, split at the pipes that belong to it, not to a nested
    template, link or reference."""
    args, part, depth, index = {}, [], 0, 0
    parts = []
    while index < len(body):
        two = body[index:index + 2]
        if two in ("{{", "[["):
            depth += 1
            part.append(two)
            index += 2
            continue
        if two in ("}}", "]]"):
            depth -= 1
            part.append(two)
            index += 2
            continue
        if body[index:index + 4].lower() == "<ref":
            gt = body.find(">", index)
            end = body.lower().find("</ref>", gt) if gt != -1 else -1
            if gt != -1 and body[gt - 1] == "/":
                end_at = gt + 1  # <ref name="x"/>
            elif end != -1:
                end_at = end + len("</ref>")
            else:
                end_at = len(body)
            part.append(body[index:end_at])
            index = end_at
            continue
        if body[index] == "|" and depth == 0:
            parts.append("".join(part))
            part = []
        else:
            part.append(body[index])
        index += 1
    parts.append("".join(part))
    for item in parts:
        name, equals, value = item.partition("=")
        if equals:
            args[" ".join(name.split()).lower()] = value.strip()
    return args


def references(text: str) -> list:
    """The {{Refdevice}} arguments of every reference in `text`."""
    found = []
    for ref in re.findall(r"(?is)<ref[^>/]*>(.*?)</ref>", text):
        body = find_template(ref, "Refdevice")
        if body is not None:
            found.append(template_args(body))
    return found


def clean(text: str) -> str:
    """Wiki markup to plain text: references, templates, comments and tags go, links keep their words."""
    text = re.sub(r"(?s)<!--.*?-->", "", text)
    text = re.sub(r"(?is)<ref[^>]*/>", "", text)
    text = re.sub(r"(?is)<ref[^>]*>.*?</ref>", "", text)
    while True:
        stripped = re.sub(r"\{\{[^{}]*\}\}", "", text)
        if stripped == text:
            break
        text = stripped
    text = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"\[https?://[^\s\]]+\s+([^\]]*)\]", r"\1", text)
    text = re.sub(r"\[https?://[^\]]+\]", "", text)
    text = re.sub(r"(?i)<br\s*/?>", " ", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("'''", "").replace("''", "")
    return " ".join(text.split())


def shorten(text: str, length: int = NOTE_LENGTH) -> str:
    if len(text) <= length:
        return text
    cut = text[:length].rsplit(" ", 1)[0].rstrip(",;:-")
    return cut + " …"


def parse_date(value: str):
    """A report's date in any of the ways wiki editors write it, as YYYY-MM-DD; None when unclear."""
    value = (value or "").strip()
    for pattern, order in ((r"(\d{4})-(\d{1,2})-(\d{1,2})", "ymd"), (r"(\d{1,2})[-./](\d{1,2})[-./](\d{4})", "dmy"),
                           (r"(\d{4})/(\d{1,2})/(\d{1,2})", "ymd")):
        match = re.search(pattern, value)
        if not match:
            continue
        parts = dict(zip(order, map(int, match.groups())))
        try:
            return datetime.date(parts["y"], parts["m"], parts["d"]).isoformat()
        except ValueError:
            if order == "dmy":  # 10-13-2023: month first
                try:
                    return datetime.date(parts["y"], parts["d"], parts["m"]).isoformat()
                except ValueError:
                    return None
            return None
    for fmt in ("%B %Y", "%b %Y", "%d %B %Y", "%B %d, %Y"):
        try:
            return datetime.datetime.strptime(value, fmt).date().isoformat()
        except ValueError:
            pass
    return None


def sentences(text: str) -> list:
    return [s for s in re.split(r"(?<=[.!?;])\s+|\n+", text) if s.strip()]


def evidence(note: str) -> dict:
    """What one way's note and its reports name: {"text", "dates", "chips"} – the text to look for
    versions and layers in, newest dates first, chips in order."""
    reports = references(note)
    pieces = [clean(note)]
    dates, chips = [], []
    for report in reports:
        for field in ("method", "comment", "settings", "version", "os"):
            if report.get(field):
                pieces.append(clean(report[field]))
        date = parse_date(report.get("date", ""))
        if date:
            dates.append(date)
        device = clean(report.get("device") or report.get("devide") or "")
        for match in CHIP.finditer(device):
            chip = "M" + match.group(1) + (" " + match.group(2) if match.group(2) else "")
            if chip not in chips:
                chips.append(chip)
    text = ". ".join(p for p in pieces if p)[:EVIDENCE_LENGTH]
    for match in CHIP.finditer(pieces[0]):
        chip = "M" + match.group(1) + (" " + match.group(2) if match.group(2) else "")
        if chip not in chips:
            chips.append(chip)
    return {"text": text, "dates": sorted(set(dates), reverse=True), "chips": chips}


def versions(text: str) -> list:
    found = []
    for match in CROSSOVER.finditer(text):
        found.append("CrossOver " + match.group(1))
    for match in GPTK.finditer(text):
        found.append("GPTK " + match.group(1) if match.group(1) else "GPTK")
    if WHISKY.search(text):
        found.append("Whisky")
    unique = []
    for version in found:
        if version not in unique and not (version == "GPTK" and any(v.startswith("GPTK ") for v in found)):
            unique.append(version)
    return unique


def near(sentence: str, start: int, end: int, words: int = NEAR) -> str:
    """The words around sentence[start:end]: `words` before and after it."""
    before = sentence[:start].split()[-words:]
    after = sentence[end:].split()[:words]
    return " ".join(before + [sentence[start:end]] + after)


def layer_mentions(text: str) -> dict:
    """layer → {"good": mentions naming it plainly, "bad": mentions in a bad light}, counted. Bad is a
    negative word close by ("crashes with DXVK", "D3DMetal off") – a "missing folder" twenty words on
    says nothing about the layer."""
    mentions = {}
    for sentence in sentences(text):
        found = [(layer, match) for layer, pattern in LAYERS for match in pattern.finditer(sentence)]
        named = {layer for layer, _ in found}
        for layer, match in found:
            entry = mentions.setdefault(layer, {"good": 0, "bad": 0})
            # Two layers in one sentence is a comparison ("DXVK crashes, D3DMetal works"): neither is clear.
            negative = NEGATIVE.search(near(sentence, match.start(), match.end()))
            entry["bad" if negative or len(named) > 1 else "good"] += 1
    return mentions


def had_dxmt(found: list) -> bool:
    """A CrossOver version named is one that had DXMT (DXMT_SINCE)."""
    return any(int(v.split()[1].split(".")[0]) >= DXMT_SINCE for v in found if v.startswith("CrossOver "))


def parse_page(title: str, wikitext: str, edited: str = None):
    """One page as {"page", "edited", "steam": [ids], "gog": [ids], "codeweavers", "paths": {way: report}},
    or None when it has no ratings Nightforge uses."""
    table = find_template(wikitext, "Compatibility/macOS")
    if table is None:
        return None
    args = template_args(table)
    paths = {}
    mentions = {}
    for name, key in PATHS.items():
        rating = clean(args.get(name, "")).lower()
        if rating not in RATINGS:
            continue
        raw = args.get(name + " notes", "")
        found = evidence(raw)
        report = {"rating": rating}
        note = shorten(clean(raw))
        if note:
            report["note"] = note
        named = versions(found["text"])
        if named:
            report["versions"] = named
        layer = layer_mentions(found["text"])
        if layer:
            report["graphics"] = [graphics for graphics, _ in LAYERS if graphics in layer]
        directx = sorted({m.group(1) for m in DIRECTX.finditer(found["text"])}, key=int)
        if directx:
            report["directX"] = directx
        if found["chips"]:
            report["chips"] = found["chips"]
        if found["dates"]:
            report["date"] = found["dates"][0]
        paths[key] = report
        mentions[key] = layer
    if not paths:
        return None
    infobox = template_args(find_template(wikitext, "Infobox game") or "")

    def ids(*fields):
        found = []
        for field in fields:
            for value in re.split(r"[,\s]+", clean(infobox.get(field, ""))):
                if value.isdigit() and value not in found:
                    found.append(value)
        return found

    # Not the "… side" fields: many pages keep the sample article's "steam appid side = 10" (Counter-Strike).
    page = {"page": title, "steam": ids("steam appid"), "gog": ids("gogcom id")}
    if edited:
        page["edited"] = edited[:10]
    codeweavers = clean(infobox.get("codeweavers", ""))
    if re.fullmatch(r"[\w .:'&+-]{1,100}", codeweavers):
        page["codeweavers"] = codeweavers
    page["paths"] = paths
    page["_mentions"] = mentions
    return page


def title_key(title: str) -> str:
    """A wiki title for comparing: PCGamingWiki's IDs on Wikidata write spaces as underscores."""
    return " ".join(str(title).replace("_", " ").split())


def wikidata_ids(bindings: list) -> dict:
    """`title_key` of a PCGamingWiki page → its Steam app IDs, from the SPARQL result's bindings."""
    ids = {}
    for row in bindings:
        title, steam = row.get("pcgw", {}).get("value"), row.get("steam", {}).get("value", "")
        if title and steam.isdigit():
            found = ids.setdefault(title_key(title), [])
            if steam not in found:
                found.append(steam)
    return {title: sorted(found, key=int) for title, found in ids.items()}


def loose_key(title: str) -> str:
    """A title without case, punctuation, ™ and ®: AppleGamingWiki's short pages often write
    "Cruelty squad" for PCGamingWiki's "Cruelty Squad"."""
    title = re.sub(r"[™®©]", "", title_key(title))
    return " ".join(re.sub(r"[\W_]+", " ", title.casefold()).split())


def fill_ids(pages: list, ids: dict):
    """Gives the pages without a Steam or GOG ID the Steam app IDs Wikidata has for their title, in
    place: "ids": "wikidata" for the same title, "name" for one that differs only in case and
    punctuation, and only when no other title reads the same."""
    loose = {}
    for title, steam in ids.items():
        loose.setdefault(loose_key(title), []).append(steam)
    for page in pages:
        if page["steam"] or page["gog"]:
            continue
        if ids.get(title_key(page["page"])):
            page["steam"] = ids[title_key(page["page"])]
            page["ids"] = "wikidata"
        elif len(loose.get(loose_key(page["page"]), [])) == 1:
            page["steam"] = loose[loose_key(page["page"])][0]
            page["ids"] = "name"


def derive_hint(page: dict, own_graphics: str = None):
    """{"graphics", "directX", "from", "source"} when the page clearly names one graphics layer for the
    ways that run well, else None. `own_graphics`: the layer Nightforge's own profile tested; then
    there's nothing to hint."""
    if own_graphics:
        return None
    # `named`: every layer a way that runs well recommends; `good`: those of them that can be a hint.
    named, good, bad, supports, directx = set(), set(), set(), {}, set()
    for way in WINE_PATHS:
        report = page["paths"].get(way)
        if not report:
            continue
        for layer, counts in page["_mentions"].get(way, {}).items():
            if report["rating"] in GOOD and counts["good"] > 0:
                named.add(layer)
                # Picked over Wine's Direct3D or D3DMetal, not over DXMT: no reason to leave DXMT for it.
                if not (layer == "dxvk" and not had_dxmt(report.get("versions", []))):
                    good.add(layer)
                    supports.setdefault(layer, []).append(way)
                    directx.update(report.get("directX", []))
            if counts["bad"] or report["rating"] not in GOOD:
                bad.add(layer)
    if len(named) != 1 or len(good) != 1 or good & bad:
        return None
    layer = good.pop()
    hint = {"graphics": layer}
    if layer == "d3dmetal" and len(directx) == 1:
        hint["directX"] = directx.pop()
    hint["from"] = supports[layer]
    hint["source"] = "agw"
    return hint


def own_graphics(mac: dict) -> dict:
    """Store key ("870780", "gog.<id>") → the graphics layer Nightforge's own profile names."""
    layers = {}
    for key, profile in (mac.get("games") or {}).items():
        if profile.get("graphics"):
            layers[key] = profile["graphics"]
            for product in profile.get("gog") or []:
                layers["gog." + str(product)] = profile["graphics"]
    return layers


def build(pages: list, mac: dict) -> tuple:
    """The document's "games" and "aliases" from parsed pages, plus counts for the summary."""
    layers = own_graphics(mac)
    games, aliases = {}, {"steam": {}, "gog": {}}
    stats = {"pages": len(pages), "hints": 0, "overruled": 0, "gogOnly": 0, "noID": 0}
    # A Steam ID on two pages (a game and its remaster share one): a page's own infobox beats Wikidata,
    # then the first page by title keeps it.
    for page in sorted(pages, key=lambda p: ("ids" in p, p["page"])):
        if page["steam"]:
            key = page["steam"][0]
        elif page["gog"]:
            key = "gog." + page["gog"][0]
            stats["gogOnly"] += 1
        else:
            stats["noID"] += 1
            continue
        if key in games:
            continue
        own = next((layers[k] for k in [key] + ["gog." + g for g in page["gog"]] + page["steam"] if k in layers), None)
        hint = derive_hint(page, own)
        if own and derive_hint(page) is not None:
            stats["overruled"] += 1
        entry = {k: v for k, v in page.items() if k in ("page", "ids", "edited", "codeweavers", "paths")}
        if hint:
            entry["hint"] = hint
            stats["hints"] += 1
        games[key] = entry
        for other in page["steam"][1:]:
            if other not in games:
                aliases["steam"].setdefault(other, key)
        for product in page["gog"]:
            if "gog." + product != key:
                aliases["gog"].setdefault(product, key)
    # Aliases of IDs that have a page of their own point nowhere.
    aliases["steam"] = {k: v for k, v in aliases["steam"].items() if k not in games}
    aliases["gog"] = {k: v for k, v in aliases["gog"].items() if "gog." + k not in games}
    return games, aliases, stats


def order(games: dict) -> dict:
    """Steam app IDs by number, then "gog.<id>"."""
    return dict(sorted(games.items(), key=lambda item: (0, int(item[0]), "") if item[0].isdigit() else (1, 0, item[0])))


def document(games: dict, aliases: dict, previous: dict = None, now: datetime.datetime = None) -> dict:
    doc = {
        "formatVersion": FORMAT_VERSION,
        "about": "What AppleGamingWiki says about running each game on a Mac. Per way (native, rosetta, crossover, "
                 "wine): its rating (perfect, playable, runs, menu, unplayable), the note shortened, and what the note "
                 "and its reports name (versions, graphics layers, DirectX versions, Apple chips, the newest report's "
                 "date). \"hint\" is Nightforge's reading of it: the one graphics layer the ways rated perfect or "
                 "playable name. Keys are Steam app IDs, \"gog.<id>\" for games without one; \"aliases\" leads a "
                 "page's other IDs to its key; \"ids\" marks pages whose IDs come from Wikidata (CC0) by their "
                 "title, not from the page: \"wikidata\" the same title, \"name\" one that differs only in case and "
                 "punctuation. Built by scripts/fetch-agw.py.",
        "license": "CC BY-NC-SA 3.0",
        "licenseURL": "https://creativecommons.org/licenses/by-nc-sa/3.0/",
        "attribution": "AppleGamingWiki contributors, https://www.applegamingwiki.com (each game's page: "
                       + WIKI + "<page>). Changed by Nightforge: the macOS compatibility table only, wiki markup and "
                       "references removed, notes shortened, hints derived.",
        "source": {"url": "https://www.applegamingwiki.com", "template": TEMPLATE,
                   "ids": "https://www.wikidata.org (CC0): PCGamingWiki ID (P6337) → Steam application ID (P1733)"},
        "aliases": {k: dict(sorted(v.items(), key=lambda item: int(item[0]))) for k, v in aliases.items()},
        "games": order(games),
    }
    unchanged = previous and {k: v for k, v in previous.items() if k != "generated"} == doc
    doc["generated"] = previous["generated"] if unchanged else \
        (now or datetime.datetime.now(datetime.timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return doc


def validate(doc: dict, minimum: int):
    """Raises when the result looks like AppleGamingWiki changed its format rather than its content."""
    games = doc["games"]
    if len(games) < minimum:
        raise ValueError(f"only {len(games)} games – expected at least {minimum}; keeping the old file")
    for key, entry in games.items():
        if not (key.isdigit() or re.fullmatch(r"gog\.\d{1,20}", key)):
            raise ValueError(f"odd key {key!r}")
        if not entry.get("paths"):
            raise ValueError(f"{key}: no ratings")
        for way, report in entry["paths"].items():
            if way not in PATHS.values() or report.get("rating") not in RATINGS:
                raise ValueError(f"{key}: {way} {report.get('rating')!r}")
        hint = entry.get("hint")
        if hint and hint.get("graphics") not in ("d3dmetal", "dxmt", "dxvk", "wined3d"):
            raise ValueError(f"{key}: hint {hint!r}")
    rated = sum(1 for e in games.values() if any(w in e["paths"] for w in WINE_PATHS))
    if rated < minimum // 3:
        raise ValueError(f"only {rated} games with a CrossOver or Wine rating; keeping the old file")


class Wiki:
    """The MediaWiki API, one request per DELAY seconds."""

    def __init__(self, delay: float = DELAY):
        self.delay = delay
        self.last = 0.0
        self.requests = 0

    def get(self, params: dict) -> dict:
        query = urllib.parse.urlencode(params | {"format": "json", "formatversion": "2", "maxlag": "5"})
        for attempt in range(TRIES):
            wait = self.last + self.delay - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            self.last = time.monotonic()
            self.requests += 1
            request = urllib.request.Request(API + "?" + query, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "gzip"})
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    body = response.read()
                    if response.headers.get("Content-Encoding") == "gzip":
                        body = gzip.decompress(body)
                    result = json.loads(body)
            except urllib.error.HTTPError as error:
                if error.code not in (429, 500, 502, 503, 504) or attempt == TRIES - 1:
                    raise
                time.sleep(int(error.headers.get("Retry-After") or 0) or 5 * 2 ** attempt)
                continue
            except (urllib.error.URLError, TimeoutError):
                if attempt == TRIES - 1:
                    raise
                time.sleep(5 * 2 ** attempt)
                continue
            if result.get("error", {}).get("code") == "maxlag":
                time.sleep(5 * 2 ** attempt)
                continue
            if "error" in result:
                raise RuntimeError(result["error"])
            return result
        raise RuntimeError("AppleGamingWiki didn't answer")

    def pages(self) -> list:
        """[{"title", "wikitext", "edited"}] for every article that uses the macOS table."""
        listed, params = [], {"action": "query", "list": "embeddedin", "eititle": TEMPLATE, "einamespace": "0", "eilimit": "500"}
        while True:
            result = self.get(params)
            listed += [page["pageid"] for page in result["query"]["embeddedin"]]
            if "continue" not in result:
                break
            params = params | result["continue"]
        pages = []
        for start in range(0, len(listed), BATCH):
            ids = "|".join(str(i) for i in listed[start:start + BATCH])
            result = self.get({"action": "query", "prop": "revisions", "rvprop": "content|timestamp", "rvslots": "main", "pageids": ids})
            for page in result["query"]["pages"]:
                revision = (page.get("revisions") or [{}])[0]
                content = revision.get("slots", {}).get("main", {}).get("content")
                if content is not None:
                    pages.append({"title": page["title"], "wikitext": content, "edited": revision.get("timestamp")})
        return pages


def fetch_wikidata() -> list:
    """The SPARQL result's bindings for WIKIDATA_QUERY: one query, a few MB."""
    query = urllib.parse.urlencode({"query": WIKIDATA_QUERY})
    request = urllib.request.Request(WIKIDATA + "?" + query, headers={
        "User-Agent": USER_AGENT, "Accept": "application/sparql-results+json", "Accept-Encoding": "gzip"})
    for attempt in range(TRIES):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read()
                if response.headers.get("Content-Encoding") == "gzip":
                    body = gzip.decompress(body)
                return json.loads(body)["results"]["bindings"]
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or attempt == TRIES - 1:
                raise
            time.sleep(int(error.headers.get("Retry-After") or 0) or 10 * 2 ** attempt)
        except (urllib.error.URLError, TimeoutError):
            if attempt == TRIES - 1:
                raise
            time.sleep(10 * 2 ** attempt)
    raise RuntimeError("Wikidata didn't answer")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "profiles" / "agw.json")
    parser.add_argument("--mac", type=pathlib.Path, default=ROOT / "profiles" / "mac.json")
    parser.add_argument("--pages", type=pathlib.Path, help="read the pages from a file --save-pages wrote, offline")
    parser.add_argument("--save-pages", type=pathlib.Path, help="also keep the fetched pages, for --pages")
    parser.add_argument("--wikidata", type=pathlib.Path, help="read Wikidata's answer from a file --save-wikidata wrote")
    parser.add_argument("--save-wikidata", type=pathlib.Path, help="also keep Wikidata's answer, for --wikidata")
    parser.add_argument("--minimum", type=int, default=1000, help="fewer games than this fails the run")
    options = parser.parse_args()

    wiki = Wiki()
    raw = json.loads(options.pages.read_text(encoding="utf-8")) if options.pages else wiki.pages()
    if options.save_pages:
        options.save_pages.write_text(json.dumps(raw, ensure_ascii=False), encoding="utf-8")
    bindings = json.loads(options.wikidata.read_text(encoding="utf-8")) if options.wikidata else fetch_wikidata()
    if options.save_wikidata:
        options.save_wikidata.write_text(json.dumps(bindings, ensure_ascii=False), encoding="utf-8")
    pages = [p for p in (parse_page(r["title"], r["wikitext"], r.get("edited")) for r in raw) if p]
    fill_ids(pages, wikidata_ids(bindings))
    mac = json.loads(options.mac.read_text(encoding="utf-8"))
    games, aliases, stats = build(pages, mac)
    previous = json.loads(options.out.read_text(encoding="utf-8")) if options.out.exists() else None
    doc = document(games, aliases, previous)
    validate(doc, options.minimum)
    options.out.parent.mkdir(parents=True, exist_ok=True)
    options.out.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(raw)} pages, {len(pages)} with ratings → {len(games)} games ({stats['gogOnly']} GOG only, "
          f"{sum(1 for g in games.values() if g.get('ids'))} by Wikidata, "
          f"{sum(1 for g in games.values() if g.get('ids') == 'name')} of them by a looser title, "
          f"{stats['noID']} pages without an ID left out), {stats['hints']} graphics hints "
          f"({stats['overruled']} left out for mac.json), {wiki.requests} requests → {options.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
