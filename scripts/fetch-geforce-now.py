#!/usr/bin/env python3
"""Fetches the GeForce Now game catalog for build-profiles.py --geforcenow.

GeForce Now's deep links (https://github.com/NVIDIAGameWorks/GeForceNOW-SDK, doc/GfnSdk-Deep-Linking.md)
need a game's id, a UUID. NVIDIA's public game list only has numeric ids, so this reads the catalog
GeForce Now's own web app uses, which has both the UUID and the Steam app ID of every game.

The catalog is one source among several. When it can't be had (since 20.11.2026 it answers plain
requests with 403 "FORBIDDEN" on `apps`), this says so, writes nothing and still exits 0:
build-profiles.py then keeps the GeForce Now ids of the last list instead of the night failing.

Usage: fetch-geforce-now.py <out.json> [--region NP-AMS-08]
"""

import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

URL = "https://games.geforce.com/graphql"
QUERY = """query($vpcId: String!, $after: String) {
  apps(vpcId: $vpcId, first: 1000, after: $after) {
    pageInfo { hasNextPage endCursor }
    items { id title variants { appStore storeId } }
  }
}"""
# Fewer games than this is a broken answer, not the catalog (it had about 2,000 in November 2026).
MINIMUM_GAMES = 100


class Unavailable(Exception):
    """The catalog couldn't be had this time."""


def fetch(region, urlopen=urllib.request.urlopen):
    games, after = [], None
    while True:
        body = json.dumps({"query": QUERY, "variables": {"vpcId": region, "after": after}}).encode()
        request = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
        try:
            with urlopen(request, timeout=60) as response:
                result = json.load(response)
        except urllib.error.HTTPError as error:
            raise Unavailable(f"HTTP {error.code} {error.reason}") from error
        except (OSError, ValueError) as error:  # URLError and timeouts are OSErrors, bad JSON a ValueError
            raise Unavailable(str(error) or type(error).__name__) from error
        if not isinstance(result, dict):
            raise Unavailable("unexpected answer, not an object")
        if result.get("errors"):
            raise Unavailable(f"the catalog answered with errors: {result['errors']}"[:300])
        try:
            page = result["data"]["apps"]
            items, more = page["items"], page["pageInfo"]["hasNextPage"]
        except (KeyError, TypeError) as error:
            raise Unavailable(f"unexpected answer, no {error}") from error
        if not isinstance(items, list):
            raise Unavailable("unexpected answer, items isn't a list")
        games += items
        if not more:
            if len(games) < MINIMUM_GAMES:
                raise Unavailable(f"only {len(games)} games")
            return games
        after = page["pageInfo"]["endCursor"]


def warn(message):
    """On stderr, and as an annotation on the run's page when it runs in GitHub Actions."""
    print(f"::warning title=GeForce Now catalog::{message}" if os.environ.get("GITHUB_ACTIONS") else message,
          file=sys.stderr)


def main(argv=None, urlopen=urllib.request.urlopen) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", type=pathlib.Path)
    # A European data centre; the catalog differs little between regions.
    parser.add_argument("--region", default="NP-AMS-08")
    options = parser.parse_args(argv)
    try:
        games = fetch(options.region, urlopen)
    except Unavailable as error:
        warn(f"Not fetched ({error}); the profiles keep the GeForce Now ids of the last list.")
        return 0
    options.out.write_text(json.dumps(games, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(games)} GeForce Now games → {options.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
