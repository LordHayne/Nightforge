"""Tests for scripts/build-profiles.py. Run: python3 -m unittest tests/test_build_profiles.py"""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "build-profiles.py"
spec = importlib.util.spec_from_file_location("build_profiles", SCRIPT)
build_profiles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_profiles)


def translate(source: str):
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as file:
        file.write(textwrap.dedent(source))
    return build_profiles.translate(pathlib.Path(file.name))


class TranslateTests(unittest.TestCase):
    def test_plain_calls_become_profile_fields(self):
        profile, partial = translate('''
            """Game fix for Example"""
            from protonfixes import util

            def main() -> None:
                """Docstring is skipped."""
                util.protontricks('vcrun2019')
                util.protontricks('win7')
                util.protontricks('sound=alsa')
                util.winedll_override('dinput8', util.OverrideOrder.NATIVE_BUILTIN)
                util.append_argument('-dx11 -BattlEye')
                util.regedit_add('HKCU\\\\Software\\\\Example', 'Lang', 'REG_DWORD', '1')
                util.disable_esync()
        ''')
        self.assertFalse(partial)
        self.assertEqual(profile["name"], "Example")
        self.assertEqual(profile["winetricks"], ["vcrun2019"])
        self.assertEqual(profile["windowsVersion"], "win7")
        self.assertEqual(profile["dllOverrides"], {"dinput8": "native,builtin"})
        self.assertEqual(profile["arguments"], ["-dx11"])
        self.assertEqual(profile["registry"], [{"key": "HKCU\\Software\\Example", "name": "Lang",
                                                "type": "REG_DWORD", "value": "1"}])

    def test_registry_outside_game_settings_is_dropped(self):
        profile, _ = translate('''
            """Game fix for Example"""
            from protonfixes import util

            def main() -> None:
                util.regedit_add('HKCU\\\\Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run', 'x', 'REG_SZ', 'evil.exe')
                util.regedit_add('HKCU\\\\Software\\\\Wine\\\\Drivers', 'Audio', 'REG_SZ', '')
                util.regedit_add('HKCR\\\\exefile', 'x', 'REG_SZ', 'y')
                util.regedit_add('HKLM\\\\Software\\\\Wow6432Node\\\\Example', 'Lang', 'REG_SZ', 'en')
        ''')
        self.assertEqual([entry["key"] for entry in profile["registry"]], ["HKLM\\Software\\Wow6432Node\\Example"])

    def test_winetricks_commands_and_options_are_dropped(self):
        profile, _ = translate('''
            """Game fix for Example"""
            from protonfixes import util

            def main() -> None:
                util.protontricks('annihilate')
                util.protontricks('--self-update')
                util.protontricks('../evil.verb')
                util.protontricks('d3dcompiler_47')
        ''')
        self.assertEqual(profile["winetricks"], ["d3dcompiler_47"])

    def test_conditional_code_is_left_out_and_marked(self):
        profile, partial = translate('''
            from protonfixes import util

            def main() -> None:
                util.protontricks('d3dcompiler_47')
                if util.get_resolution():
                    util.protontricks('dotnet48')
                util.replace_command('Launcher.exe', 'Game.exe')
        ''')
        self.assertTrue(partial)
        self.assertTrue(profile["partial"])
        self.assertEqual(profile["winetricks"], ["d3dcompiler_47"])

    def test_linux_controller_keys_are_dropped(self):
        profile, _ = translate('''
            from protonfixes import util

            def main() -> None:
                util.regedit_add('HKLM\\\\System\\\\CurrentControlSet\\\\Services\\\\winebus', 'DisableHidraw', 'REG_DWORD', '1')
        ''')
        self.assertNotIn("registry", profile)


class SafetyTests(unittest.TestCase):
    """DLL overrides and start arguments come from a stranger's repository (Audit M1)."""

    def test_dll_overrides_by_bare_name_with_wines_orders(self):
        for name, order in [("d3d9", "native,builtin"), ("*dsound", "builtin"), ("vulkan-1", ""), ("xactengine3_7", "native")]:
            self.assertTrue(build_profiles.dll_override_allowed(name, order), (name, order))
        for name, order in [("ntdll", "native"), ("kernel32.dll", ""), ("winemac.drv", ""), ("..", ""), ("*", ""),
                            ("../d3d9", ""), ("D3D9", ""), ("d3d9", "native;builtin"), ("d3d9", None), (9, "")]:
            self.assertFalse(build_profiles.dll_override_allowed(name, order), (name, order))

    def test_arguments_without_paths_out_of_the_game(self):
        for argument in ["-dx11", "/dx11", "+r_renderAPI", "1", "-vomstyle=layer", "Zonematch=true", "glide_fix.conf",
                         "../bundle", "-c=../x"]:
            self.assertTrue(build_profiles.argument_allowed(argument), argument)
        for argument in ["/Users/x/game", "--ini=/etc/passwd", "C:x", "Z:\\Users", "~/x", "../../x", "x/../y", "-c=../../x",
                         "//server/x", "file:///x", "-a b", '-a"', "-a;rm", "$HOME", "%TEMP%", "-x\n", "", "a" * 65]:
            self.assertFalse(build_profiles.argument_allowed(argument), argument)

    def test_how_many_is_limited(self):
        self.assertTrue(build_profiles.arguments_allowed(["-a"] * 16))
        self.assertFalse(build_profiles.arguments_allowed(["-a"] * 17))
        self.assertFalse(build_profiles.arguments_allowed("-dx11"), "a list, not a string")
        self.assertTrue(build_profiles.overrides_allowed({f"dll{i}": "" for i in range(32)}))
        self.assertFalse(build_profiles.overrides_allowed({f"dll{i}": "" for i in range(33)}))

    def test_translation_leaves_out_what_isnt_plain(self):
        profile, partial = translate('''
            from protonfixes import util

            def main():
                util.winedll_override('ntdll', util.OverrideOrder.NATIVE)
                util.winedll_override('d3dx9_43', util.OverrideOrder.NATIVE)
                util.append_argument('--ini=/etc/passwd -nosplash')
                util.append_argument('-dx11')
        ''')
        self.assertTrue(partial)
        self.assertEqual(profile["dllOverrides"], {"d3dx9_43": "native"})
        self.assertEqual(profile["arguments"], ["-dx11"], "all of a call or none of it")

    def test_the_workflow_check_takes_todays_list_and_nothing_unsafe(self):
        workflow = (ROOT / ".github/workflows/profiles.yml").read_text()
        check = textwrap.dedent(workflow.split("python3 -I - <<'PY'\n", 1)[1].split("\n          PY\n", 1)[0])
        run = lambda folder: subprocess.run([sys.executable, "-I", "-c", check], cwd=folder, capture_output=True, text=True)
        today = run(ROOT)
        self.assertEqual(today.returncode, 0, today.stdout + today.stderr)
        for field, value in [("dllOverrides", {"ntdll": "native"}), ("arguments", ["--ini=/etc/passwd"]),
                             ("arguments", ["-x"] * 17)]:
            with self.subTest(field=field, value=str(value)[:40]), tempfile.TemporaryDirectory() as folder:
                folder = pathlib.Path(folder)
                (folder / "scripts").mkdir()
                (folder / "profiles").mkdir()
                (folder / "scripts/build-profiles.py").write_text(SCRIPT.read_text())
                doc = json.loads((ROOT / "profiles/profiles.json").read_text())
                next(iter(doc["games"].values()))[field] = value
                (folder / "profiles/profiles.json").write_text(json.dumps(doc))
                result = run(folder)
                self.assertNotEqual(result.returncode, 0, "the workflow stops before anything is proposed")
                self.assertIn("AssertionError", result.stderr)


class AntiCheatTests(unittest.TestCase):
    def test_only_games_that_cant_run_are_blocked(self):
        blocks = build_profiles.anticheat_blocks([
            {"name": "PUBG", "status": "Broken", "anticheats": ["BattlEye", "VAC"], "storeIds": {"steam": "578080"}},
            {"name": "Elden Ring", "status": "Supported", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "1245620"}},
            {"name": "Only VAC", "status": "Denied", "anticheats": ["VAC"], "storeIds": {"steam": "1"}},
            {"name": "Fortnite", "status": "Denied", "anticheats": ["Easy Anti-Cheat"], "storeIds": {}},
        ])
        self.assertEqual(blocks, {
            "578080": {"name": "PUBG", "antiCheat": ["BattlEye"]},
            "1245620": {"name": "Elden Ring", "antiCheatOnline": ["Easy Anti-Cheat"]},
        })

    def test_supported_loses_online_play_only_through_a_linux_module(self):
        # Proton runs Easy Anti-Cheat and BattlEye through their Linux module, which a Mac lacks;
        # every other anti-cheat runs inside Wine, on a Mac as well.
        blocks = build_profiles.anticheat_blocks([
            {"name": "Overwatch 2", "status": "Supported", "anticheats": ["Warden"], "storeIds": {"steam": "2357570"}},
            {"name": "Battlefield 4", "status": "Supported", "anticheats": ["PunkBuster", "FairFight"], "storeIds": {"steam": "1238860"}},
            {"name": "Call of Duty: Black Ops", "status": "Supported", "anticheats": ["Treyarch Anti-Cheat", "PunkBuster"],
             "storeIds": {"steam": "42700"}},
            {"name": "Elden Ring", "status": "Supported", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "1245620"}},
            {"name": "DayZ", "status": "Supported", "anticheats": ["BattlEye"], "storeIds": {"steam": "221100"}},
            {"name": "THE FINALS", "status": "Supported", "anticheats": ["Easy Anti-Cheat", "Denuvo Anti-Cheat", "AnyBrain"],
             "storeIds": {"steam": "2073850"}},
        ])
        self.assertEqual(blocks, {
            "1245620": {"name": "Elden Ring", "antiCheatOnline": ["Easy Anti-Cheat"]},
            "221100": {"name": "DayZ", "antiCheatOnline": ["BattlEye"]},
            "2073850": {"name": "THE FINALS", "antiCheatOnline": ["Easy Anti-Cheat", "Denuvo Anti-Cheat", "AnyBrain"]},
        })

    def test_epic_games_are_blocked_by_namespace(self):
        blocks = build_profiles.epic_anticheat_blocks([
            {"name": "Fortnite", "status": "Denied", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"epic": {"namespace": "fn", "slug": "fortnite"}}},
            {"name": "PUBG", "status": "Broken", "anticheats": ["BattlEye"],
             "storeIds": {"steam": "578080", "epic": {"namespace": "9361c8c6d2f34b42b5f2f61093eedf48"}}},
            {"name": "Back 4 Blood", "status": "Supported", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"epic": {"namespace": "57df"}}},
            {"name": "Paladins", "status": "Running", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"epic": {"namespace": "badb"}}},
            {"name": "Warframe", "status": "Supported", "anticheats": ["Unknown (Custom)"], "storeIds": {"epic": {"namespace": "244a"}}},
            {"name": "Splitgate", "status": "Supported", "anticheats": ["EQU8"], "storeIds": {"epic": {"namespace": "47cb"}}},
            {"name": "Wildgate", "status": "Running", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"epic": {"namespace": "0ad0"}}},
            {"name": "Odd", "status": "Denied", "anticheats": ["BattlEye"], "storeIds": {"epic": {"namespace": "../x"}}},
        ], titles={"wildgate": "3504780"})
        self.assertEqual(blocks, {
            "epic.fn": {"name": "Fortnite", "antiCheat": ["Easy Anti-Cheat"]},
            "epic.9361c8c6d2f34b42b5f2f61093eedf48": {"name": "PUBG", "antiCheat": ["BattlEye"], "steam": "578080"},
            "epic.57df": {"name": "Back 4 Blood", "antiCheatOnline": ["Easy Anti-Cheat"]},
            "epic.badb": {"name": "Paladins", "antiCheatOnline": ["Easy Anti-Cheat"]},
            "epic.0ad0": {"name": "Wildgate", "antiCheatOnline": ["Easy Anti-Cheat"], "steam": "3504780"},
        })

    def test_running_loses_online_play_through_a_linux_module_too(self):
        # "Running" under Proton with Easy Anti-Cheat or BattlEye means through their Linux module as
        # well; "Planned" doesn't run there yet.
        blocks = build_profiles.anticheat_blocks([
            {"name": "ARC Raiders", "status": "Running", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "1808500"}},
            {"name": "The Isle", "status": "Running", "anticheats": ["BattlEye"], "storeIds": {"steam": "376210"}},
            {"name": "HELLDIVERS 2", "status": "Running", "anticheats": ["nProtect GameGuard"], "storeIds": {"steam": "553850"}},
            {"name": "Due Process", "status": "Planned", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "753650"}},
        ])
        self.assertEqual(blocks, {
            "1808500": {"name": "ARC Raiders", "antiCheatOnline": ["Easy Anti-Cheat"]},
            "376210": {"name": "The Isle", "antiCheatOnline": ["BattlEye"]},
            "753650": {"name": "Due Process", "antiCheat": ["Easy Anti-Cheat"]},
        })

    def test_server_side_anticheat_never_stops_a_start(self):
        blocks = build_profiles.anticheat_blocks([
            {"name": "Crysis", "status": "Broken", "anticheats": ["PunkBuster"], "storeIds": {"steam": "17300"}},
            {"name": "Only FairFight", "status": "Denied", "anticheats": ["FairFight"], "storeIds": {"steam": "2"}},
            {"name": "Rainbow Six Siege", "status": "Denied", "anticheats": ["FairFight", "BattlEye"], "storeIds": {"steam": "359550"}},
            {"name": "War Rock", "status": "Broken", "anticheats": ["PunkBuster", "Easy Anti-Cheat"], "storeIds": {"steam": "880850"}},
        ])
        self.assertEqual(blocks, {
            "17300": {"name": "Crysis", "antiCheatOnline": ["PunkBuster"]},
            "2": {"name": "Only FairFight", "antiCheatOnline": ["FairFight"]},
            "359550": {"name": "Rainbow Six Siege", "antiCheat": ["FairFight", "BattlEye"]},
            "880850": {"name": "War Rock", "antiCheat": ["PunkBuster", "Easy Anti-Cheat"]},
        })

    def test_a_full_block_isnt_shrunk_by_a_second_entry(self):
        blocks = build_profiles.anticheat_blocks([
            {"name": "Post Scriptum", "status": "Denied", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "736220"}},
            {"name": "Squad 44", "status": "Running", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "736220"}},
        ])
        self.assertEqual(blocks, {"736220": {"name": "Post Scriptum", "antiCheat": ["Easy Anti-Cheat"]}})

    def test_entries_without_steam_id_by_slug_or_exact_name(self):
        titles = build_profiles.steam_titles([
            {"id": "a", "title": "Warhammer 40,000: Space Marine 2", "variants": [{"appStore": "STEAM", "storeId": "2183900"}]},
            {"id": "b", "title": "Counter-Strike 2", "variants": [{"appStore": "STEAM", "storeId": "730"}]},
            {"id": "c", "title": "Twins", "variants": [{"appStore": "STEAM", "storeId": "1"}]},
            {"id": "d", "title": "TWINS™", "variants": [{"appStore": "STEAM", "storeId": "2"}]},
            {"id": "e", "title": "Epic Only", "variants": [{"appStore": "EPIC", "storeId": "06bd"}]},
        ])
        self.assertEqual(titles, {"warhammer 40 000 space marine 2": "2183900", "counter strike 2": "730"})
        blocks = build_profiles.anticheat_blocks([
            {"name": "Warhammer 40,000: Space Marine 2", "slug": "w", "status": "Broken", "anticheats": ["Easy Anti-Cheat"], "storeIds": {}},
            {"name": "EA SPORTS FC™ 26", "slug": "ea-sports-fc26", "status": "Denied", "anticheats": ["EA anticheat"], "storeIds": {}},
            {"name": "EA SPORTS™ FC 26 (FACEIT)", "slug": "x", "status": "Broken", "anticheats": ["FACEIT"], "storeIds": {}},
            # Counter-Strike 2's own entry says how it runs; a second one without an ID doesn't override it.
            {"name": "Counter-Strike 2", "slug": "cs2", "status": "Supported", "anticheats": ["VAC"], "storeIds": {"steam": "730"}},
            {"name": "Counter-Strike 2", "slug": "cs2-faceit", "status": "Denied", "anticheats": ["FACEIT"], "storeIds": {}},
        ], titles)
        self.assertEqual(blocks, {
            "2183900": {"name": "Warhammer 40,000: Space Marine 2", "antiCheat": ["Easy Anti-Cheat"]},
            "3405690": {"name": "EA SPORTS FC™ 26", "antiCheat": ["EA anticheat"]},
        })

    def test_geforce_now_ids_come_from_steam_variants(self):
        ids = build_profiles.geforce_now_ids([
            {"id": "d176-uuid", "variants": [{"appStore": "EPIC", "storeId": "06bd"}, {"appStore": "STEAM", "storeId": "1085660"}]},
            {"id": "cb2b-uuid", "variants": [{"appStore": "EA_APP", "storeId": "Origin.OFR.50.0002694"}]},
        ])
        self.assertEqual(ids, {"1085660": "d176-uuid"})

    def test_mac_profiles_reach_the_gog_versions_they_name(self):
        games = {"50130": {"dllOverrides": {"xaudio2_7": "native"}, "source": "umu"}}
        build_profiles.merge_mac(games, {
            "50130": {"name": "Mafia II (Classic)", "graphics": "wined3d", "gog": ["1816059595", "../x"]},
            "3907790": {"name": "OxyRail", "graphics": "dxmt"},
        })
        mafia = {"dllOverrides": {"xaudio2_7": "native"}, "name": "Mafia II (Classic)", "graphics": "wined3d", "source": "umu+mac"}
        self.assertEqual(games, {
            "50130": mafia,
            "gog.1816059595": mafia,
            "3907790": {"name": "OxyRail", "graphics": "dxmt", "source": "mac"},
        })

    def test_games_that_dont_start_yet_get_their_geforce_now_id(self):
        games = {}
        build_profiles.merge_mac(games, {
            "2357570": {"name": "Overwatch", "notYet": "Hangs under Rosetta.", "note": "Tested on M5"},
            "3907790": {"name": "OxyRail", "graphics": "dxmt"},
            "1": {"name": "Own", "notYet": "Not yet.", "geforceNow": "gOwn"},
        })
        build_profiles.link_geforce_now(games, {"2357570": "gOverwatch", "3907790": "gOxy", "1": "gOther"})
        # The reason and the test note reach the list as they are; only a game that is held back gets the id.
        self.assertEqual(games["2357570"], {"name": "Overwatch", "notYet": "Hangs under Rosetta.", "note": "Tested on M5",
                                            "source": "mac", "geforceNow": "gOverwatch"})
        self.assertNotIn("geforceNow", games["3907790"])
        self.assertEqual(games["1"]["geforceNow"], "gOwn")


class BuildTests(unittest.TestCase):
    def test_a_run_from_all_sources(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            fixes = root / "umu" / "gamefixes-steam"
            fixes.mkdir(parents=True)
            for app_id, argument in (("1361210", "-eac-untrusted"), ("678950", "-eac-nop-loaded")):
                (fixes / f"{app_id}.py").write_text(f"from protonfixes import util\n\ndef main() -> None:\n"
                                                     f"    util.append_argument('{argument}')\n")
            anticheat = [
                {"name": "Darktide", "status": "Running", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "1361210"}},
                {"name": "DRAGON BALL FighterZ", "status": "Broken", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "678950"}},
                {"name": "ARC Raiders", "status": "Running", "anticheats": ["Easy Anti-Cheat"], "storeIds": {"steam": "1808500"}},
            ]
            catalog = [
                {"id": "gArc", "title": "ARC Raiders", "variants": [{"appStore": "STEAM", "storeId": "1808500"}]},
                {"id": "gWar", "title": "WARDOGS", "variants": [{"appStore": "STEAM", "storeId": "1867240"}]},
                {"id": "gOw", "title": "Overwatch", "variants": [{"appStore": "STEAM", "storeId": "2357570"}]},
            ]
            mac = {"games": {"1867240": {"name": "WARDOGS", "antiCheat": ["Elytra"]},
                             "2357570": {"name": "Overwatch", "notYet": "Hangs under Rosetta."}}}
            for name, content in (("anticheat.json", anticheat), ("gfn.json", catalog), ("mac.json", mac)):
                (root / name).write_text(json.dumps(content))
            subprocess.run([sys.executable, "-I", str(SCRIPT), str(root / "umu"), "--anticheat", str(root / "anticheat.json"),
                            "--geforcenow", str(root / "gfn.json"), "--mac", str(root / "mac.json"), "--out", str(root / "out.json")],
                           check=True, capture_output=True)
            games = json.loads((root / "out.json").read_text())["games"]
        # Its profile starts Darktide in untrusted mode, as umu does: online play isn't lost.
        self.assertNotIn("antiCheatOnline", games["1361210"])
        # -eac-nop-loaded starts it without the anti-cheat: it runs, only online play is gone.
        self.assertEqual((games["678950"].get("antiCheat"), games["678950"].get("antiCheatOnline")), (None, ["Easy Anti-Cheat"]))
        self.assertEqual(games["1808500"], {"name": "ARC Raiders", "source": "anticheat", "antiCheatOnline": ["Easy Anti-Cheat"],
                                            "geforceNow": "gArc"})
        # A block from profiles/mac.json gets its GeForce Now link as well.
        self.assertEqual(games["1867240"]["geforceNow"], "gWar")
        # … and a game that doesn't start yet keeps its reason beside it.
        self.assertEqual(games["2357570"], {"name": "Overwatch", "notYet": "Hangs under Rosetta.", "source": "mac",
                                            "geforceNow": "gOw"})



class EnvironmentTests(unittest.TestCase):
    """A profile's "environment": Wine's and CrossOver's own switches only, with plain values."""

    def test_the_switches_recall_sets_pass(self):
        self.assertTrue(build_profiles.environment_allowed(
            {"WINE_SIMULATE_WRITECOPY": "1", "CX_HACK_FILESYSTEM_TYPE": "1", "CX_ACTIVE_GRAPHICS_BACKEND": "dxmt"}))

    def test_anything_that_can_load_code_or_name_a_path_is_refused(self):
        for environment in ({"DYLD_INSERT_LIBRARIES": "/tmp/x.dylib"}, {"WINE_SIMULATE_WRITECOPY": "/tmp"},
                            {"CX_ACTIVE_GRAPHICS_BACKEND": "dxmt; rm -rf ~"}, {"WINEDLLOVERRIDES": "d3d11=n"},
                            {"WINE_SIMULATE_WRITECOPY": 1}, ["WINE_SIMULATE_WRITECOPY"], {"WINE_SIMULATE_WRITECOPY": ""}):
            self.assertFalse(build_profiles.environment_allowed(environment), environment)

    def test_the_app_allows_the_same_names(self):
        swift = (SCRIPT.parent.parent / "Sources/Nightforge/GameEnvironment.swift").read_text(encoding="utf-8")
        block = swift[swift.index("static let allowed"):swift.index("]\n", swift.index("static let allowed"))]
        import re
        self.assertEqual(set(re.findall(r'^\s*"([A-Z_]+)":', block, re.M)), build_profiles.ENVIRONMENT_NAMES)


if __name__ == "__main__":
    unittest.main()
