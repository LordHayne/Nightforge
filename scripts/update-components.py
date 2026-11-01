#!/usr/bin/env python3
"""Rebuilds components/manifest.json from the releases listed in components/sources.json.

Runs nightly in CI. A source with a "tag" is pinned to that release; one without follows the newest
stable release (Nightforge's own builds). A pinned source marked "propose" is a third party's whose
newer releases Nightforge looks at: with --propose its pin moves to the newest stable release (in
sources.json, and so in the manifest), and the workflow opens a pull request for a person to read –
nothing a stranger publishes reaches the app unseen. Uses the sha256 digest GitHub publishes for
release assets; files without one (e.g. a script taken from a tag) are downloaded once and hashed.
Set GITHUB_TOKEN to avoid rate limits.

Usage: update-components.py [--propose]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "components" / "sources.json"
MANIFEST = ROOT / "components" / "manifest.json"
SCHEMA_VERSION = 1


def request(url: str) -> urllib.request.Request:
    headers = {"User-Agent": "nightforge-components", "Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def get_json(url: str):
    with urllib.request.urlopen(request(url), timeout=30) as response:
        return json.load(response)


def hash_url(url: str) -> tuple[str, int]:
    digest, size = hashlib.sha256(), 0
    with urllib.request.urlopen(request(url), timeout=120) as response:
        while chunk := response.read(1 << 20):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def latest_release(repo: str, tag_prefix: str = "") -> dict | None:
    releases = get_json(f"https://api.github.com/repos/{repo}/releases?per_page=30")
    # GitHub doesn't list releases newest first (a graphics package from the morning came before
    # the evening's), so order by when each was published.
    releases.sort(key=lambda release: release.get("published_at") or "", reverse=True)
    for release in releases:
        if not release["draft"] and not release["prerelease"] and release["tag_name"].startswith(tag_prefix):
            return release
    return None


def build(source: dict) -> dict | None:
    """The manifest entry for one source; None for an "optional" one whose release doesn't exist
    (yet): the entry stays out of the list, the app copes without it."""
    repo = source["repo"]
    try:
        if "tag" in source:
            release = get_json(f"https://api.github.com/repos/{repo}/releases/tags/{source['tag']}")
        else:
            release = latest_release(repo, source.get("tagPrefix", ""))
    except urllib.error.HTTPError as error:
        if source.get("optional") and error.code == 404:
            release = None
        else:
            raise
    if release is None:
        if source.get("optional"):
            return None
        sys.exit(f"{repo}: no stable release found")
    license_id = source.get("license") or (get_json(f"https://api.github.com/repos/{repo}").get("license") or {}).get("spdx_id") or "NOASSERTION"
    version = release["tag_name"].removeprefix(source.get("tagPrefix", "")).lstrip("v")

    if "file" in source:
        url = f"https://raw.githubusercontent.com/{repo}/{release['tag_name']}/{source['file']}"
        sha256, size = hash_url(url)
    else:
        pattern = re.compile(source["asset"])
        assets = [a for a in release["assets"] if pattern.search(a["name"])]
        if len(assets) != 1:
            sys.exit(f"{repo} {release['tag_name']}: expected one asset matching {source['asset']}, found {len(assets)}")
        asset = assets[0]
        url, size = asset["browser_download_url"], asset["size"]
        digest = asset.get("digest") or ""
        sha256 = digest.removeprefix("sha256:") if digest.startswith("sha256:") else hash_url(url)[0]

    return {
        "id": source["id"],
        "kind": source["kind"],
        "version": version,
        "url": url,
        "sha256": sha256,
        "size": size,
        "license": license_id,
        "source": f"https://github.com/{repo}",
    }


def propose_newer(sources: list[dict]) -> list[tuple[str, str, str]]:
    """Moves the pin of every source marked "propose" to the newest stable release of its repo, in
    place; returns (id, pinned tag, newest tag) for each that moved. Nothing is pinned by this alone:
    the result goes into a pull request."""
    moves = []
    for source in sources:
        if not source.get("propose") or "tag" not in source:
            continue
        newest = latest_release(source["repo"], source.get("tagPrefix", ""))
        if newest is not None and newest["tag_name"] != source["tag"]:
            moves.append((source["id"], source["tag"], newest["tag_name"]))
            source["tag"] = newest["tag_name"]
    return moves


def describe_changes(previous: list[dict], components: list[dict]) -> list[str]:
    """One line per component that is new, gone or at another version – the pull request's text. A
    file that changed under the same version is the one to look at hardest (a release replaced in place)."""
    before = {c["id"]: c["version"] for c in previous}
    after = {c["id"]: c["version"] for c in components}
    hashes = {c["id"]: c.get("sha256") for c in previous}
    lines = [f"{id}: {before[id]} -> {after[id]}" for id in after if id in before and before[id] != after[id]]
    lines += [f"{c['id']}: {c['version']} unchanged, but its file is a different one (sha256 changed) – a release replaced in place?"
              for c in components if c["id"] in before and before[c["id"]] == c["version"] and hashes[c["id"]] != c.get("sha256")]
    lines += [f"{id}: new, {after[id]}" for id in after if id not in before]
    lines += [f"{id}: gone (was {before[id]})" for id in before if id not in after]
    return lines


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--propose", action="store_true",
                        help="move the pin of sources marked \"propose\" to their newest stable release")
    options = parser.parse_args(argv)

    document = json.loads(SOURCES.read_text())
    sources = document["sources"]
    if options.propose:
        moves = propose_newer(sources)
        for id, old, new in moves:
            print(f"proposed: {id} {old} -> {new}")
        if moves:
            SOURCES.write_text(json.dumps(document, indent=2) + "\n")

    components = []
    for source in sources:
        component = build(source)
        if component is None:
            print(f"{source['id']}: no release yet, left out")
        else:
            components.append(component)

    previous = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    if previous.get("components") == components and previous.get("schemaVersion") == SCHEMA_VERSION:
        print("manifest unchanged")
        return

    manifest = {"schemaVersion": SCHEMA_VERSION, "generated": date.today().isoformat(), "components": components}
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    for line in describe_changes(previous.get("components", []), components):
        print(line)
    for c in components:
        print(f"{c['id']:<12} {c['version']:<28} {c['size'] / 1048576:7.1f} MB  {c['license']}")


if __name__ == "__main__":
    main()
