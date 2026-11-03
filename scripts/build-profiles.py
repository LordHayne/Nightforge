#!/usr/bin/env python3
"""Builds profiles/profiles.json: per-game fixes Nightforge applies when it starts a game.

Sources, merged per Steam app ID:
  * umu-protonfixes (BSD-2-Clause, https://github.com/Open-Wine-Components/umu-protonfixes):
    the game fixes behind Proton-GE and umu. They're small Python scripts; this reads them as
    syntax trees and never runs them. Only plain, unconditional calls with literal arguments
    are translated; anything else is left out and the game is marked "partial".
  * AreWeAntiCheatYet (MIT, https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet), optional:
    games whose anti-cheat stops them even under Proton. On a Mac they don't start at all, so
    Nightforge says so before a download ("antiCheat"). Games it runs under Proton only through
    the anti-cheat's own Linux build (Easy Anti-Cheat, BattlEye) lose their online play on a Mac
    ("antiCheatOnline"); the app blocks those that have nothing else (no single player on Steam).
    Entries without a Steam app ID get one by their exact name from the GeForce Now catalog, or
    from STEAM_IDS_BY_SLUG.
  * The GeForce Now catalog (scripts/fetch-geforce-now.py), optional: which blocked games can be
    streamed instead ("geforceNow", the game id its deep links take), and Steam app IDs by name.
  * profiles/mac.json: Nightforge's own profiles, tested on Macs. They win over upstream, and
    reach the GOG versions they name ("gog"). "notYet" is the reason a game doesn't start on a Mac
    yet (Nightforge is working on it): it gets a GeForce Now id like the anti-cheat games.

Usage: build-profiles.py <umu-protonfixes checkout> [--anticheat games.json] [--geforcenow catalog.json]
                         [--out profiles/profiles.json]
"""

import argparse
import ast
import datetime
import json
import pathlib
import re
import subprocess
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
FORMAT_VERSION = 1

# Override orders in protonfixes' util.OverrideOrder, as Wine writes them in DllOverrides.
OVERRIDE_ORDERS = {
    "DISABLED": "",
    "NATIVE": "native",
    "BUILTIN": "builtin",
    "NATIVE_BUILTIN": "native,builtin",
    "BUILTIN_NATIVE": "builtin,native",
}

# winetricks verbs that set the Windows version. Nightforge runs every game in one prefix, so
# these become a per-program setting instead of changing it for Steam and all other games.
WINDOWS_VERSIONS = {"win2k", "winxp", "win2k3", "vista", "win7", "win8", "win81", "win10", "win11"}

# Calls that only matter on Linux / Proton (sync primitives, Steam Deck, CPU pinning, …).
IGNORED_CALLS = {
    "disable_esync", "disable_fsync", "disable_ntsync", "set_cpu_topology_limit",
    "set_cpu_topology_nosmt", "get_game_install_path", "protonprefix", "protondir",
    "get_resolution", "get_steam_account_id",
}

# Arguments that switch on anti-cheat runtimes Proton ships and macOS can't run.
IGNORED_ARGUMENTS = {"-battleye", "-eac_launcher"}

# AreWeAntiCheatYet statuses for games that don't run even under Proton ("Planned": the developer
# means to allow it, but hasn't yet).
BLOCKING_STATUSES = {"Broken", "Denied", "Planned"}
# "Supported" (the developer allows Proton) and "Running" (it works anyway). With Easy Anti-Cheat
# and BattlEye both only work because Proton loads the anti-cheat's Linux module in its place
# (Steam's "Proton EasyAntiCheat Runtime" and "Proton BattlEye Runtime"; ARC Raiders' players even
# force it with PROTON_USE_EAC_LINUX=1). A Mac has no such module, so online play is gone, single
# player often still works. Every other anti-cheat (Warden, PunkBuster, Treyarch Anti-Cheat,
# nProtect GameGuard, XIGNCODE3, …) runs inside Wine itself, on a Mac as under Proton: no block.
# FairFight only checks on the server and never blocks anything.
ONLINE_BLOCKING_STATUSES = {"Supported", "Running"}
LINUX_MODULE_ANTICHEATS = {"Easy Anti-Cheat", "BattlEye"}
# Arguments that start a game without its anti-cheat (Darktide's untrusted mode, Bandai Namco's
# -eac-nop-loaded). A game whose profile passes one starts on a Mac as under Proton: one that runs
# there loses nothing, one whose anti-cheat doesn't at most its online play.
ANTICHEAT_OFF_ARGUMENTS = {"-eac-untrusted", "-eac-nop-loaded", "-noeac", "-nobattleye", "-noanticheat", "-no-anticheat"}

# AreWeAntiCheatYet games without a Steam app ID that the GeForce Now catalog doesn't name either,
# by slug. Each checked against Steam's store page of that app: the same name, and for Delta Force,
# which AreWeAntiCheatYet still lists by its test name "Delta Force: Hawk Ops", the same website
# (playdeltaforce.com). Escape from Tarkov's Steam version is also the one umu-protonfixes installs
# the BattlEye runtime for.
STEAM_IDS_BY_SLUG = {
    "delta-force-hawk-ops": "2507950",  # Delta Force
    "ea-sports-fc26": "3405690",  # EA SPORTS FC™ 26
    "escape-from-tarkov": "3932890",  # Escape from Tarkov
    "formula1-25": "3059520",  # F1® 25
    "skate.": "3354750",  # skate.
}

# Anti-cheat that runs fine under Wine; it doesn't block a game.
HARMLESS_ANTICHEATS = {"VAC"}
# Anti-cheat that only a multiplayer server asks for (PunkBuster) or that only checks on the server
# (FairFight): it never stops a game from starting. Where it's all a game has, a "Broken" or
# "Denied" costs at most online play (Crysis, F.E.A.R. and their single player are fine).
SERVER_ANTICHEATS = {"PunkBuster", "FairFight"}

# Registry keys for Wine's Linux controller driver; under one shared prefix they'd change
# controllers for every game.
IGNORED_REGISTRY_PREFIXES = ("hklm\\system\\currentcontrolset\\services\\winebus",)

# Where a profile may write at all: a game's own settings under Software, and drive letters. Never
# autostart entries, file associations, policies or Wine's own settings (Engine.isAllowedRegistryKey).
# Wine's and CrossOver's own switches a profile's "environment" may set, with plain short values: the
# same list as GameEnvironment.allowed in the app (Sources/Nightforge/GameEnvironment.swift), which
# drops anything else. Never DYLD_* or paths: an environment variable can load code into a program.
ENVIRONMENT_NAMES = {"WINE_SIMULATE_WRITECOPY", "CX_HACK_FILESYSTEM_TYPE", "CX_ACTIVE_GRAPHICS_BACKEND",
                     "CX_GRAPHICS_BACKEND", "WINE_LARGE_ADDRESS_AWARE"}
ENVIRONMENT_VALUE = re.compile(r"[A-Za-z0-9._-]{1,32}")


def environment_allowed(environment) -> bool:
    return isinstance(environment, dict) and all(
        name in ENVIRONMENT_NAMES and isinstance(value, str) and ENVIRONMENT_VALUE.fullmatch(value)
        for name, value in environment.items())


REGISTRY_ROOTS = {"hkcu": "hkey_current_user", "hklm": "hkey_local_machine"}
REGISTRY_BLOCKED_VENDORS = {"microsoft", "classes", "policies", "wine", "wow6432node"}


def registry_key_allowed(key) -> bool:
    if not isinstance(key, str) or any(ord(c) < 0x20 or c in "[]" for c in key):
        return False
    lower = key.lower()
    short, _, rest = lower.partition("\\")
    lower = REGISTRY_ROOTS.get(short, short) + "\\" + rest
    drives = "hkey_local_machine\\system\\mounteddevices"
    if lower == drives or lower.startswith(drives + "\\"):
        return True
    for root in ("hkey_current_user\\software\\", "hkey_local_machine\\software\\"):
        if lower.startswith(root):
            rest = lower[len(root):]
            if rest.startswith("wow6432node\\"):
                rest = rest[len("wow6432node\\"):]
            vendor = rest.split("\\", 1)[0]
            return vendor != "" and vendor not in REGISTRY_BLOCKED_VENDORS
    return False

# Settings-style winetricks arguments ("sound=alsa", "hidewineexports=enable") are Linux/Proton
# knobs; Steam runtime verbs that make no sense outside Proton are dropped as well.
IGNORED_VERBS = {"ubisoftconnect"}
# Only plain install verbs reach the app, never an option or a winetricks command
# (`annihilate` deletes the whole prefix). Engine.isSafeWinetricksVerb checks the same.
WINETRICKS_COMMANDS = {"annihilate", "apps", "benchmarks", "dlls", "fonts", "games", "settings", "list", "help", "version"}
SAFE_VERB = re.compile(r"[a-z0-9_]{1,64}")


def safe_verb(verb) -> bool:
    return isinstance(verb, str) and SAFE_VERB.fullmatch(verb) is not None and verb not in WINETRICKS_COMMANDS


def literal(node):
    """The Python value of a literal argument, or raises ValueError."""
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Attribute) \
            and getattr(node.value, "attr", "") == "OverrideOrder":
        return ("order", node.attr)
    return ast.literal_eval(node)


def translate(path: pathlib.Path):
    """Returns (profile, partial) for one gamefix file, or (None, False) if it has no main()."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    name = (ast.get_docstring(tree) or "").removeprefix("Game fix for").strip() or None
    main = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "main"), None)
    if main is None:
        return None, False

    profile = {"name": name} if name else {}
    partial = False
    body = main.body
    if body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant):
        body = body[1:]  # docstring

    for statement in body:
        call = statement.value if isinstance(statement, ast.Expr) else None
        if not (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name) and call.func.value.id == "util"):
            if not isinstance(statement, ast.Pass):
                partial = True  # conditions, loops, file edits: can't be translated safely
            continue
        function = call.func.attr
        if function in IGNORED_CALLS:
            continue
        try:
            args = [literal(a) for a in call.args]
            kwargs = {k.arg: literal(k.value) for k in call.keywords}
        except (ValueError, SyntaxError, TypeError):
            partial = True
            continue

        if function == "protontricks" and args:
            verb = args[0]
            if verb in WINDOWS_VERSIONS:
                profile["windowsVersion"] = verb
            elif verb in IGNORED_VERBS or not safe_verb(verb):
                continue
            else:
                profile.setdefault("winetricks", [])
                if verb not in profile["winetricks"]:
                    profile["winetricks"].append(verb)
        elif function == "winedll_override" and len(args) == 2 and isinstance(args[1], tuple):
            order = OVERRIDE_ORDERS.get(args[1][1])
            if order is None:
                partial = True
                continue
            profile.setdefault("dllOverrides", {})[args[0].lower()] = order
        elif function == "disable_nvapi":
            for dll in ("nvapi", "nvapi64", "nvcuda", "nvcuvid"):
                profile.setdefault("dllOverrides", {})[dll] = ""
        elif function == "append_argument" and args:
            kept = [a for a in str(args[0]).split() if a.lower() not in IGNORED_ARGUMENTS]
            if kept:
                profile.setdefault("arguments", []).extend(kept)
        elif function == "regedit_add":
            # regedit_add(folder, name=None, typ=None, value=None, arch=False)
            bound = dict(zip(["folder", "name", "typ", "value", "arch"], args)) | kwargs
            if "folder" not in bound:
                partial = True
                continue
            if str(bound["folder"]).lower().startswith(IGNORED_REGISTRY_PREFIXES):
                continue
            if not registry_key_allowed(bound["folder"]):
                continue
            entry = {"key": str(bound["folder"])}
            for source, target in (("name", "name"), ("typ", "type"), ("value", "value")):
                if bound.get(source) is not None:
                    entry[target] = str(bound[source])
            profile.setdefault("registry", []).append(entry)
        else:
            partial = True  # replace_command, set_ini_options, environment, …

    if partial:
        profile["partial"] = True
    return profile, partial


def anticheat_block(game):
    """{"name", and "antiCheat" or "antiCheatOnline": anti-cheat names} for an AreWeAntiCheatYet
    game that can't run on a Mac, or not online; None for one that runs."""
    names = [n for n in game.get("anticheats") or [] if n not in HARMLESS_ANTICHEATS]
    if not names:
        return None
    if game.get("status") in BLOCKING_STATUSES:
        return {"name": game.get("name"), "antiCheatOnline" if set(names) <= SERVER_ANTICHEATS else "antiCheat": names}
    if game.get("status") in ONLINE_BLOCKING_STATUSES and LINUX_MODULE_ANTICHEATS.intersection(names):
        return {"name": game.get("name"), "antiCheatOnline": names}
    return None


def anticheat_blocks(games, titles=None):
    """Steam app ID → `anticheat_block`, for the AreWeAntiCheatYet games that can't run on a Mac,
    or not online. An entry without a Steam app ID takes `steam_app_id`'s, unless another entry
    has that ID as its own: that one says how the game runs."""
    own = {str((game.get("storeIds") or {}).get("steam") or "") for game in games}
    blocks = {}
    for game in games:
        app_id = steam_app_id(game, titles)
        if not (game.get("storeIds") or {}).get("steam") and app_id in own:
            continue
        block = anticheat_block(game)
        # Two entries for one app (a renamed game): the other's full block doesn't shrink to online.
        if app_id.isdigit() and block and not ("antiCheat" in blocks.get(app_id, {}) and "antiCheatOnline" in block):
            blocks[app_id] = block
    return blocks


def epic_anticheat_blocks(games, titles=None):
    """"epic.<namespace>" → the same as `anticheat_blocks`, for the games AreWeAntiCheatYet knows
    from the Epic Games Store (Nightforge's Epic games carry their catalog namespace). "steam" is
    the game's Steam app ID when it has one, so it can share that profile's GeForce Now id."""
    blocks = {}
    for game in games:
        store_ids = game.get("storeIds") or {}
        namespace = str((store_ids.get("epic") or {}).get("namespace") or "")
        block = anticheat_block(game)
        if not (namespace.isalnum() and block):
            continue
        steam = steam_app_id(game, titles)
        if steam.isdigit():
            block["steam"] = steam
        blocks["epic." + namespace] = block
    return blocks


def steam_app_id(game, titles=None) -> str:
    """An AreWeAntiCheatYet game's Steam app ID: its own, else STEAM_IDS_BY_SLUG's, else the one
    `titles` (`steam_titles`) has for exactly its name; "" when none."""
    own = str((game.get("storeIds") or {}).get("steam") or "")
    return own or STEAM_IDS_BY_SLUG.get(game.get("slug"), "") or (titles or {}).get(title_key(game.get("name")), "")


def title_key(name) -> str:
    """A game's name for comparing: without ™, ® and ©, case, punctuation and extra spaces."""
    name = re.sub(r"[™®©]", "", str(name or ""))
    return " ".join(re.sub(r"[\W_]+", " ", unicodedata.normalize("NFKC", name).casefold()).split())


def steam_titles(games):
    """`title_key` → Steam app ID, for the games GeForce Now streams from Steam; a name that stands
    for more than one app is left out."""
    ids = {}
    for game in games:
        for variant in game.get("variants") or []:
            store_id = str(variant.get("storeId") or "")
            if variant.get("appStore") == "STEAM" and store_id.isdigit() and title_key(game.get("title")):
                ids.setdefault(title_key(game.get("title")), set()).add(store_id)
    return {title: next(iter(app_ids)) for title, app_ids in ids.items() if len(app_ids) == 1}


def geforce_now_ids(games):
    """Steam app ID → GeForce Now game id, for the games GeForce Now streams from Steam."""
    ids = {}
    for game in games:
        for variant in game.get("variants") or []:
            store_id = str(variant.get("storeId") or "")
            if variant.get("appStore") == "STEAM" and store_id.isdigit() and game.get("id"):
                ids.setdefault(store_id, game["id"])
    return ids


def starts_without_anticheat(profile) -> bool:
    """Whether a profile's own arguments start its game without the anti-cheat."""
    return any(a.lower() in ANTICHEAT_OFF_ARGUMENTS for a in (profile or {}).get("arguments") or [])


def link_geforce_now(games, cloud):
    """Gives every Steam game something blocks (AreWeAntiCheatYet or profiles/mac.json, "notYet"
    too) its GeForce Now id, in place, when GeForce Now streams it and the profile doesn't name
    one itself."""
    for key, profile in games.items():
        if key in cloud and (profile.get("antiCheat") or profile.get("antiCheatOnline") or profile.get("notYet")):
            profile.setdefault("geforceNow", cloud[key])


def merge_mac(games, mac_games):
    """Nightforge's own profiles over upstream's, in place. A profile's "gog" list names the same
    game's GOG product IDs: each gets the merged profile as "gog.<id>" (Nightforge's GOG games
    carry their product ID), so a fix tested on one version reaches the other."""
    for app_id, own in mac_games.items():
        base = {} if own.get("ignoreUpstream") else games.get(app_id, {})
        merged = {**base, **{k: v for k, v in own.items() if k not in ("ignoreUpstream", "gog")}}
        merged["source"] = "mac" if not base else base["source"] + "+mac"
        games[app_id] = merged
        for product_id in own.get("gog", []):
            if str(product_id).isdigit():
                games["gog." + str(product_id)] = merged


def git_commit(path: pathlib.Path) -> str:
    try:
        return subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("protonfixes", type=pathlib.Path)
    parser.add_argument("--anticheat", type=pathlib.Path, help="AreWeAntiCheatYet games.json")
    parser.add_argument("--geforcenow", type=pathlib.Path, help="GeForce Now catalog from fetch-geforce-now.py")
    parser.add_argument("--mac", type=pathlib.Path, default=ROOT / "profiles" / "mac.json")
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "profiles" / "profiles.json")
    options = parser.parse_args()

    games = {}
    stats = {"files": 0, "translated": 0, "partial": 0, "empty": 0}
    for path in sorted((options.protonfixes / "gamefixes-steam").glob("*.py")):
        if not path.stem.isdigit():
            continue
        stats["files"] += 1
        profile, partial = translate(path)
        if profile is None:
            continue
        useful = {k: v for k, v in profile.items() if k not in ("name", "partial")}
        if not useful:
            stats["empty"] += 1
            continue
        stats["partial" if partial else "translated"] += 1
        profile["source"] = "umu"
        games[path.stem] = profile

    sources = {
        "umu-protonfixes": {
            "url": "https://github.com/Open-Wine-Components/umu-protonfixes",
            "commit": git_commit(options.protonfixes),
            "license": "BSD-2-Clause",
        },
    }
    blocked = 0
    cloud, titles = {}, {}
    if options.anticheat:
        if options.geforcenow:
            catalog = json.loads(options.geforcenow.read_text(encoding="utf-8"))
            cloud, titles = geforce_now_ids(catalog), steam_titles(catalog)
            sources["geforce-now"] = {"url": "https://play.geforcenow.com"}
        anticheat = json.loads(options.anticheat.read_text(encoding="utf-8"))
        for app_id, block in anticheat_blocks(anticheat, titles).items():
            if starts_without_anticheat(games.get(app_id)):
                if "antiCheatOnline" in block:
                    continue
                block = {"name": block["name"], "antiCheatOnline": block["antiCheat"]}
            profile = games.setdefault(app_id, {"name": block["name"], "source": "anticheat"})
            for field in ("antiCheat", "antiCheatOnline"):
                if field in block:
                    profile[field] = block[field]
            blocked += 1
        # Epic games by catalog namespace; older Nightforge versions skip keys that aren't numbers.
        for key, block in epic_anticheat_blocks(anticheat, titles).items():
            profile = {"name": block["name"], "source": "anticheat"}
            for field in ("antiCheat", "antiCheatOnline"):
                if field in block:
                    profile[field] = block[field]
            if block.get("steam") in cloud:
                profile["geforceNow"] = cloud[block["steam"]]
            games[key] = profile
            blocked += 1
        sources["areweanticheatyet"] = {"url": "https://areweanticheatyet.com", "license": "MIT"}

    mac = json.loads(options.mac.read_text(encoding="utf-8"))
    merge_mac(games, mac.get("games", {}))
    link_geforce_now(games, cloud)

    document = {
        "formatVersion": FORMAT_VERSION,
        "sources": sources | {
            "mac": {"url": "https://github.com/LordHayne/Nightforge/blob/main/profiles/mac.json"},
        },
        # Steam app IDs by number, then the other stores' keys ("epic.<namespace>", "gog.<product ID>").
        "games": dict(sorted(games.items(), key=lambda item: (0, int(item[0]), "") if item[0].isdigit() else (1, 0, item[0]))),
    }
    previous = None
    if options.out.exists():
        previous = json.loads(options.out.read_text(encoding="utf-8"))
    # Only touch the date when something changed, so the nightly run doesn't commit noise.
    unchanged = previous and {k: v for k, v in previous.items() if k != "generated"} == document
    document["generated"] = previous["generated"] if unchanged else \
        datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    options.out.parent.mkdir(parents=True, exist_ok=True)
    options.out.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(games)} games ({stats['translated']} fully, {stats['partial']} partly translated, "
          f"{stats['empty']} Linux-only skipped, {blocked} blocked by anti-cheat, {len(mac.get('games', {}))} Mac profiles) → {options.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
