# Contributing a game profile

**Auf Deutsch:** Ein Spielprofil sagt Nightforge, wie es ein bestimmtes Spiel startet, zum Beispiel mit welcher Grafikschicht. Nightforges eigene Profile stehen in `profiles/mac.json`. Nur was du auf einem Mac ausprobiert hast, gehört hinein. Trag dein Spiel dort ein, schreib in `note`, was du auf welchem Mac gemessen hast, prüf es wie unten beschrieben und öffne einen Pull Request. Die Anleitung unten ist englisch.

A profile tells Nightforge how to start one game: which graphics layer, which arguments, which settings to fix before the start. Nightforge applies it by itself when the game is on **Automatic**. Profiles come from three places, merged every night by `scripts/build-profiles.py` into `profiles/profiles.json`, which the app downloads:

- [umu-protonfixes](https://github.com/Open-Wine-Components/umu-protonfixes), the fixes behind Proton-GE,
- [AreWeAntiCheatYet](https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet) and the GeForce Now catalog, for games anti-cheat stops,
- **`profiles/mac.json`, Nightforge's own profiles, tested on Macs.** They win over the other two. This is the file you change.

**Only what you have tried on a Mac belongs in `mac.json`.** A profile you add reaches every player the next morning, without an app update.

## The key

Each game in `mac.json` sits under `games`, keyed by its store:

| Store | Key | Where to find it |
|---|---|---|
| Steam | the app ID as it is, e.g. `"3907790"` | the number in the store address, `store.steampowered.com/app/<id>/` |
| Epic Games | `"epic.<namespace>"` – the catalog namespace, not the app name | in Nightforge's Epic library, see below |
| GOG | `"gog.<product ID>"` | in Nightforge's GOG library, see below |

To print the Epic namespaces and GOG product IDs of the games in your Nightforge library:

```bash
python3 -c 'import json, os; [print(g["namespace"], g["title"]) for g in json.load(open(os.path.expanduser("~/Library/Application Support/Nightforge/Epic/library.json")))["games"]]'
```

```bash
python3 -c 'import json, os; [print(g["id"], g["title"]) for g in json.load(open(os.path.expanduser("~/Library/Application Support/Nightforge/GOG/library.json")))["games"]]'
```

The same game in another store doesn't need an entry of its own: `"gog": ["<product ID>", …]` in a Steam or Epic entry gives those GOG versions the same profile.

## An example

OxyRail, as it is in `mac.json`:

```json
"3907790": {
  "name": "OxyRail",
  "graphics": "dxmt",
  "note": "Tested 2026-10-24 on M5: ~75 FPS with DXMT vs 45-50 with DXVK on Extreme."
}
```

7 Days to Die with its save folders, so they come along when the game changes between its Windows and Mac version (note shortened here):

```json
"251570": {
  "name": "7 Days to Die",
  "graphics": "dxmt",
  "note": "Tested 2026-10-24 on M5: ~63 FPS with DXMT; …",
  "saves": [
    {"root": "WinAppDataRoaming", "path": "7DaysToDie/Saves", "mac": "MacAppSupport"},
    {"root": "WinAppDataRoaming", "path": "7DaysToDie/GeneratedWorlds", "mac": "MacAppSupport"}
  ]
}
```

Always write a `note`: the date, the Mac (chip, macOS), the Nightforge version if you know it, and what you measured – with your setting and without it. That's what lets the next person trust the profile, or know when to test it again.

## Fields

All fields are optional. They're read by `GameProfile` in `Sources/Nightforge/Profiles.swift`.

| Field | Value | What it does |
|---|---|---|
| `name` | text | The game's name, for people reading the file. |
| `note` | text | What testing found (see above). |
| `graphics` | `"dxmt"`, `"dxvk"`, `"wined3d"` or `"d3dmetal"` | The graphics layer when the game is on Automatic: DXMT takes Direct3D 10 and 11 straight to Metal, DXVK goes through Vulkan and MoltenVK, WineD3D is Wine's own Direct3D 9 on OpenGL for older games, D3DMetal is Apple's, the way DirectX 12 runs. |
| `arguments` | list of text | Added to the game's command line, e.g. `["-changedir"]`. At most 16, each of letters, digits and `_ . = + / -` (up to 64 characters): no drive, no path from the root, at most one folder up. |
| `dllOverrides` | `{"dll": "order"}` | DLL load order for the game's programs. At most 32, each a bare DLL name (a `*` in front is allowed) with one of Wine's orders: `"native"`, `"builtin"`, `"native,builtin"`, `"builtin,native"` or `""` (disabled). Never Wine's core DLLs such as `ntdll` or `kernel32`. |
| `registry` | list of `{"key", "name", "type", "value"}` | Registry values written before the start. `type` is `REG_SZ` or `REG_DWORD` (a number, or hex as `0x…`). Keys only under `HKCU\Software\<vendor>`, `HKLM\Software\<vendor>` (also through `Wow6432Node`) or `HKLM\System\MountedDevices`; the vendor can't be `Microsoft`, `Classes`, `Policies` or `Wine`. |
| `windowsVersion` | `"win2k"`, `"winxp"`, `"win2k3"`, `"vista"`, `"win7"`, `"win8"`, `"win81"`, `"win10"` or `"win11"` | The Windows version the game's programs see; the rest of Wine keeps its own. |
| `winetricks` | list of verbs | Installed before the first start, e.g. `["vcrun2019"]`. Only verbs that install something: no Windows version (that's `windowsVersion`) and nothing that changes the prefix every game shares, such as `dsound`, `sandbox` or `isolate_home`. |
| `metalFX` | `true` / `false` | `false` keeps MetalFX upscaling off for a game it doesn't suit. |
| `frameLimit` | whole number | The FPS limit Automatic uses for this game instead of the one that fits the display. |
| `avx` | `true` / `false` | `false` starts the game without Rosetta's AVX hint, for games that crash on it. |
| `retina` | `true` / `false` | `true`: the game sees the screen's full Retina resolution. Wine sets that for a whole session, so Steam restarts when it changes from one game to the next. |
| `vulkanSamplers` | whole number | Games that draw with Vulkan themselves: the samplers per shader stage reported to them, when MoltenVK's 16 make a game refuse to start. |
| `preferWindows` | `true` / `false` | `true` keeps the game on its Windows version although Steam has a 64-bit Mac version (an old, broken Mac port, say). |
| `saves` | list of `{"root", "path", "mac"}`, optional `"pattern"` (default `"*"`), `"recursive"` (default `true`), `"macPath"` | Save folders Steam Cloud doesn't name, carried over when the game changes between its Windows and Mac version. |
| `fileEdits` | list of `{"path", "find", "replace"}`, optional `"root"`, `"once"` | Changes to the game's own settings files before each start: in `path`, `find` becomes `replace`. Without `root`, `path` starts in the game folder. `"once": true` applies it a single time, as a starting value the player can change. |
| `iniSettings` | list of `{"root", "path", "section", "values"}` | Values set in the game's own `.ini` files before every start (Unreal deletes an `Engine.ini` it didn't write itself). |
| `resolution` | `{"path", "fields": {"width", "height", "fullscreen"}}` or `{"path", "section", "keys": {…}}`, optional `"root"`, `"fullscreenOn"` | Where the game keeps the resolution it starts in, so Nightforge sets it to the screen it plays on. `fields` counts the values of a line separated by spaces from 0; `keys` names them in an `.ini` section. `fullscreenOn`: the values that mean full screen, `"1"` if not given. |
| `executable` | path inside the game folder | The program to start instead of the store's, e.g. `"Control_DX12.exe"`, for Steam, Epic and GOG games (Steam's through its own launch options). A game with a DirectX 12 program of its own beside the store's starts that one on D3DMetal without this field. |
| `environment` | `{"NAME": "value"}` | Wine's and CrossOver's own switches for this game alone. Only `WINE_SIMULATE_WRITECOPY`, `CX_HACK_FILESYSTEM_TYPE`, `CX_ACTIVE_GRAPHICS_BACKEND`, `CX_GRAPHICS_BACKEND` and `WINE_LARGE_ADDRESS_AWARE`, with values of letters, digits, `.`, `_` and `-` (up to 32). |
| `dlss` | `true` | The game's DLSS was seen working on D3DMetal (through MetalFX), so with MetalFX on it gets Retina mode as well. A DLSS library in the game folder alone isn't enough. |
| `skipUnityDialog` | `false` | Leaves Unity's configuration window before the game to the player, for a game that asks something there that matters. Otherwise Nightforge presses "Play!" itself. |
| `antiCheat`, `antiCheatOnline` | list of text | `[]` says the game runs on a Mac after all, whatever AreWeAntiCheatYet lists. |
| `notYet` | text in plain English | The game doesn't start on a Mac yet and Nightforge is working on it: Nightforge says so before the download and offers GeForce Now when it has the game. The reason also needs its German text in `Sources/Nightforge/Strings.swift`, the one other file such a pull request changes. |
| `gog` | list of GOG product IDs | The same game's GOG versions get this profile too. |
| `ignoreUpstream` | `true` | Leave out umu-protonfixes' fixes for this game; only this profile applies. |

`source` is set by the nightly build; don't set it. `geforceNow` the build fills in from the GeForce Now catalog; a value in `mac.json` is kept.

**Roots** for `saves`, `fileEdits`, `iniSettings` and `resolution`: `GameInstall` (the game folder), `WinAppDataRoaming`, `WinAppDataLocal`, `WinAppDataLocalLow`, `WinMyDocuments`, `WinSavedGames`. The Mac side of `saves` (`mac`): `MacAppSupport`, `MacCaches` or `GameInstall`. A path may not lead out of its root: no `..`, no drive, nothing from `/` or `~`. The build stops on such a path.

## What the check rejects

Every pull request that touches `profiles/` runs the **Update game profiles** workflow (`.github/workflows/profiles.yml`). It runs the builder's tests, builds `profiles.json` with your `mac.json` and checks the result. It fails when:

- `mac.json` isn't valid JSON,
- a key isn't a Steam app ID (digits only), `epic.<namespace>` (letters, digits, `_` and `-`, up to 64) or `gog.<product ID>` (digits),
- `graphics` is anything but `dxmt`, `dxvk`, `wined3d` or `d3dmetal`,
- `metalFX` isn't `true` or `false`, `frameLimit` isn't a whole number, `antiCheat` or `antiCheatOnline` isn't a list, `notYet` isn't text,
- `executable` is empty, starts with `/` or `\`, or contains a `..` part,
- `arguments`, `dllOverrides` or `environment` break the rules in the table above,
- `windowsVersion` isn't one of the nine names above,
- `fileEdits`, `iniSettings`, `resolution` or `saves` name a root that doesn't exist or a path that leaves it,
- a `registry` key is outside the places listed above, or a registry entry contains a line break,
- a `winetricks` verb isn't made of lowercase letters, digits and `_` (up to 64), is a winetricks command rather than something to install (`annihilate`, `apps`, `benchmarks`, `dlls`, `fonts`, `games`, `settings`, `list`, `help`, `version`), sets a Windows version or changes the shared prefix.

Most checks on `mac.json` run in `scripts/build-profiles.py` itself: it stops with a list of what's wrong before it writes `profiles.json`. The rest (`graphics`, `executable`, the types of the simple fields) the workflow checks on the built list. This entry fails four times:

```json
"1245620": {
  "name": "Elden Ring",
  "note": "An example of what fails.",
  "graphics": "metal",
  "registry": [{"key": "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "name": "x", "type": "REG_SZ", "value": "y"}],
  "winetricks": ["annihilate"],
  "executable": "../../Steam/steam.exe"
}
```

`metal` isn't a layer (`d3dmetal` is), the registry key is an autostart entry, `annihilate` is a winetricks command, and the program lies outside the game folder.

The check doesn't look at every field. The app skips a field it can't read without a word – `"retina": "yes"` simply does nothing –, keeps `frameLimit` within 0–240 and `vulkanSamplers` within 1–128, and writes only `REG_SZ` and `REG_DWORD` registry values. So test the profile in the app as well.

## Test before you open the pull request

1. **Try the setting by hand.** In Nightforge, open the game's options and try the graphics route, arguments and the frame limit there, without a profile, then play for a few minutes. DXMT writes the frame rate to `~/Library/Application Support/Nightforge/Logs/wine.log` every so often, in lines like `[nightforge-dxmt] Game: 58.2 FPS over 60 s, …`; D3DMetal writes none. Compare with the game on Automatic.
2. **Build the list the way the check does**, from the repository's folder:

   ```bash
   git clone --depth 1 https://github.com/Open-Wine-Components/umu-protonfixes.git /tmp/umu-protonfixes
   curl -fsSL -o /tmp/anticheat.json https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/HEAD/games.json
   python3 -I scripts/fetch-geforce-now.py /tmp/geforcenow.json
   python3 -I scripts/build-profiles.py /tmp/umu-protonfixes --anticheat /tmp/anticheat.json --geforcenow /tmp/geforcenow.json
   ```

   Then run the builder's tests and the workflow's own check on the result:

   ```bash
   python3 -m unittest tests/test_build_profiles.py tests/test_fetch_agw.py
   ```

   ```bash
   sed -n "/<<'PY'/,/^ *PY$/p" .github/workflows/profiles.yml | sed '1d;$d' | sed 's/^          //' | python3 -I -
   ```

   It ends with a line like `ok: 744 games, 332 blocked by anti-cheat, 170 on GeForce Now`.
3. **Play it with your profile.** `./build.sh --install` (see Build from source in the README) puts the list you just built into the app, and a list built later than the online one wins over it. Set the game's graphics to Automatic and start it.
4. **Commit only `profiles/mac.json`** (and, for a `notYet` reason, its German text in `Sources/Nightforge/Strings.swift`). Put `profiles/profiles.json` back with `git checkout profiles/profiles.json`: it's rebuilt every night and after your change is merged.

## The pull request

One game, one pull request. The template asks for the game, its key, your Mac and what you measured. If the profile works around something that's broken upstream (in Wine, DXMT, MoltenVK or the game itself), say so in the `note` – then it's clear when the profile can go again.
