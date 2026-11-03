# Adding a game profile

A profile tells Nightforge how to start one game: which graphics route, which arguments, which
setting files to fix. Nightforge's own profiles live in [`profiles/mac.json`](../profiles/mac.json).
They are tested on Macs and win over the community fixes from umu-protonfixes. Every night
[`scripts/build-profiles.py`](../scripts/build-profiles.py) merges both into `profiles/profiles.json`,
the [Update game profiles](../.github/workflows/profiles.yml) workflow checks the result, and the app
downloads it. A profile you add reaches every player the next morning, without an app update.

Only what you have tried on a Mac belongs in `mac.json`. One game, one pull request.

## 1. Find out what works

Start with the game's own options in Nightforge (the slider button next to Play). There you can try
the graphics route, arguments and the frame limit without a profile. Note which Mac you used, the
Nightforge version, what you changed and what you measured (FPS, crashes, how long it ran).

## 2. The key: which game

| Store | Key in `mac.json` | Where to find it |
|---|---|---|
| Steam | the bare app ID: `"550"` | the number in the game's store URL, `store.steampowered.com/app/550` |
| Epic | `"epic.<namespace>"`: `"epic.calluna"` | Epic's catalog namespace, not the app name (see below) |
| GOG | `"gog.<product ID>"`: `"gog.2049187585"` | the product ID; Nightforge's problem report names it as "GOG <id>" |

Epic's namespace for your installed games, from the library Nightforge keeps:

```sh
python3 -c 'import json, os; [print(g["appName"], "→ epic." + g["namespace"]) for g in json.load(open(os.path.expanduser("~/Library/Application Support/Nightforge/Epic/library.json")))["games"]]'
```

A game sold on Steam and GOG needs one profile only: put it under the Steam app ID and list the GOG
product IDs in `"gog"`. The builder copies the profile to each `gog.<id>`.

## 3. The fields

Every field is optional except `name` and `note`. Write `note` as on the existing entries: date, Mac,
what you measured (`"Tested 2026-10-26 on M5: steady 60 FPS with DXMT and -dx11."`). Nightforge never
shows it; it tells the next person why the profile is there.

| Field | Value | What it does |
|---|---|---|
| `name` | text | The game's name, for people reading the file. |
| `note` | text | What was tested and found. |
| `graphics` | `dxmt`, `dxvk`, `wined3d`, `d3dmetal` | The route "Automatic" takes. DXMT for DirectX 10/11, DXVK for Vulkan, WineD3D for old DirectX 9 games, D3DMetal for DirectX 12. |
| `arguments` | list of text | Added to the game's command line, e.g. `["-dx11"]`. |
| `dllOverrides` | `{"dll": "order"}` | Load order of a DLL as Wine writes it: `native`, `builtin`, `native,builtin`, `builtin,native`, or `""` to disable it. |
| `registry` | `[{"key", "name", "type", "value"}]` | Values in the game's own registry key. |
| `windowsVersion` | text, e.g. `"win7"` | The Windows version the game's programs see. The rest of the prefix keeps its own. |
| `winetricks` | list of verbs | Runtimes installed before the first start, e.g. `["vcrun2019"]`. |
| `metalFX` | `false` | Keeps MetalFX upscaling off for a game it doesn't suit. |
| `frameLimit` | whole number | The automatic FPS limit for this game, instead of the one from the display. |
| `vulkanSamplers` | whole number | For games that draw with Vulkan themselves: the samplers per shader stage reported to them, when MoltenVK's 16 make a game refuse to start. |
| `preferWindows` | `true` | Keeps the Windows version although Steam has a 64-bit Mac one (an old, broken port). |
| `saves` | `[{"root", "path", "pattern", "recursive", "mac", "macPath"}]` | Save folders Steam Cloud doesn't name, so saves come along when the game switches between its Windows and Mac version. `pattern` defaults to `*`, `recursive` to `true`. |
| `antiCheat`, `antiCheatOnline` | `[]` | An empty list says the game runs on a Mac although AreWeAntiCheatYet lists anti-cheat for it. |
| `notYet` | text | Why the game doesn't start on a Mac yet, in plain English. Nightforge says so before the download and offers GeForce Now when it has the game. The reason needs a German entry in `Sources/Nightforge/Strings.swift`. |
| `avx` | `false` | Starts the game without Rosetta's AVX hint, for games that crash on it. |
| `fileEdits` | `[{"path", "find", "replace", "root", "once"}]` | Replaces text in the game's own settings files before each start. `once: true` sets a starting value a single time, so what the player picks later stays. |
| `iniSettings` | `[{"root", "path", "section", "values"}]` | Sets values in the game's own `.ini` files before each start. |
| `retina` | `true` | The game sees the full Retina resolution. Steam restarts when this changes from one game to the next. |
| `resolution` | `{"root", "path", "fields"}` or `{"root", "path", "section", "keys"}` | Where the game keeps its resolution, so Nightforge fits it to the screen it plays on (see Mafia II in `mac.json`). |
| `executable` | path inside the game folder | The program to start instead of the store's, e.g. `"Control_DX12.exe"`. Epic and GOG games now; Steam games from 0.3.1 on. A game with its own DirectX 12 program beside the store's starts that one on D3DMetal without this field. |
| `environment` | `{"NAME": "value"}` | **Comes with 0.3.1.** Wine's and CrossOver's own switches for this game alone. Only `WINE_SIMULATE_WRITECOPY`, `CX_HACK_FILESYSTEM_TYPE`, `CX_ACTIVE_GRAPHICS_BACKEND`, `CX_GRAPHICS_BACKEND` and `WINE_LARGE_ADDRESS_AWARE`, with values of letters, digits, `.`, `_` and `-` (at most 32). |
| `gog` | list of GOG product IDs | The same game on GOG gets this profile too. |
| `ignoreUpstream` | `true` | Drops what umu-protonfixes has for the game; only your profile counts. |

`root` in `saves`, `fileEdits`, `iniSettings` and `resolution` is a Windows folder of the game's user:
`WinAppDataRoaming`, `WinAppDataLocal`, `WinAppDataLocalLow`, `WinMyDocuments`, `WinSavedGames`, or
`gameinstall` for the game folder. Leave it out in `fileEdits` and `resolution` to start from the game
folder. `mac` in `saves` is where the Mac version keeps them: `MacAppSupport`, `MacCaches` or
`gameinstall`.

## 4. What gets turned down

The workflow and the app refuse what could reach outside the game. In particular:

- `graphics` other than the four routes.
- A `registry` key outside the game's own settings: only `HKCU\Software\<vendor>…` and
  `HKLM\Software\<vendor>…` (not `Microsoft`, `Classes`, `Policies`, `Wine`), plus drive letters
  under `HKLM\System\MountedDevices`. No line breaks in any value.
- A `winetricks` entry that isn't a plain install verb (lowercase letters, digits, `_`): no options,
  no commands such as `annihilate`, which would delete the whole prefix.
- An `executable` that starts with `/` or `\`, or climbs out of the game folder with `..`.
- From 0.3.1 on also: `dllOverrides` other than bare DLL names (never Windows' own core DLLs such as
  `ntdll` or `kernel32`) with Wine's orders; `arguments` other than plain options and values (at most
  16; no drive, no path from the root, at most one folder up); `environment` outside the list above.

This entry fails four times:

```json
"1245620": {
  "name": "Elden Ring",
  "note": "Tested 2026-11-02 on M2 Pro.",
  "graphics": "metal",
  "registry": [{"key": "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "name": "x", "type": "REG_SZ", "value": "y"}],
  "winetricks": ["annihilate"],
  "executable": "../../Steam/steam.exe"
}
```

`metal` isn't a route (`d3dmetal` is), the registry key is an autostart entry, `annihilate` is a
winetricks command, and the program lies outside the game folder.

## 5. Check before the pull request

From the repository's folder:

```sh
python3 -m json.tool profiles/mac.json > /dev/null && echo "valid JSON"
python3 -m unittest tests/test_build_profiles.py
python3 -I - <<'PY'
import importlib.util, json, re
spec = importlib.util.spec_from_file_location("build_profiles", "scripts/build-profiles.py")
bp = importlib.util.module_from_spec(spec); spec.loader.exec_module(bp)
for key, game in json.load(open("profiles/mac.json"))["games"].items():
    assert re.fullmatch(r"[0-9]+|epic\.[A-Za-z0-9_-]{1,64}|gog\.[0-9]{1,20}", key), key
    assert game.get("note"), (key, "a note on what was tested")
    assert game.get("graphics") in (None, "dxmt", "dxvk", "wined3d", "d3dmetal"), (key, game.get("graphics"))
    assert all(bp.registry_key_allowed(e.get("key")) for e in game.get("registry") or []), (key, "registry")
    assert all(bp.safe_verb(v) for v in game.get("winetricks") or []), (key, "winetricks")
    program = game.get("executable")
    assert program is None or not program.startswith(("/", "\\")) and ".." not in re.split(r"[\\/]", program), (key, program)
    if hasattr(bp, "overrides_allowed"):  # builders from 0.3.1 on
        assert bp.overrides_allowed(game.get("dllOverrides") or {}), (key, "dllOverrides")
        assert bp.arguments_allowed(game.get("arguments") or []), (key, "arguments")
print("mac.json looks fine")
PY
```

The pull request then runs the same build and validator ("Update game profiles" in its checks).

To play the game with your profile before you send it, build the list and the app yourself (quit the
Nightforge you have installed first – only one may run):

```sh
git clone --depth 1 https://github.com/Open-Wine-Components/umu-protonfixes.git /tmp/umu-protonfixes
python3 -I scripts/build-profiles.py /tmp/umu-protonfixes
./build.sh && open build/Nightforge.app
```

Afterwards `git checkout profiles/profiles.json`: the pull request changes `mac.json` only, the nightly
build makes `profiles.json`.

## 6. Open the pull request

Commit only `profiles/mac.json` (and `Strings.swift` for a `notYet` reason). When you open the pull
request, add `?template=profile.md` to its address to get the checklist, or copy it from
[`.github/PULL_REQUEST_TEMPLATE/profile.md`](../.github/PULL_REQUEST_TEMPLATE/profile.md).

## Kurz auf Deutsch

Ein Profil für ein Spiel kommt nach `profiles/mac.json`, unter der Steam-App-ID (`"550"`), `epic.<namespace>`
oder `gog.<Produkt-ID>`, mit `name` und einer `note`: Datum, Mac, was gemessen wurde. Erlaubt sind nur die
Felder aus der Tabelle oben. Der Validator lehnt alles ab, was über das Spiel hinausreicht: Registry außerhalb
der eigenen Schlüssel, winetricks-Befehle, Programme außerhalb des Spielordners. Vorher die Prüfung aus
Abschnitt 5 laufen lassen, dann einen Pull Request nur mit `mac.json` öffnen. `environment` und `executable`
für Steam-Spiele kommen mit 0.3.1.
