<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHU6MQPMoGhVpu5i6By (1.11.2026) -->

## Fremd-Launcher unter Wine

*Recherche für Nightforge · Stand 1. November 2026 · nichts committet, nichts gepusht*

### Vorweg: Quellenlage und Kennzeichnung

- Direkt gelesen: Quellcode auf GitHub. Dazu gehören Proton (`steam_helper/steam.c`

), Valves Wine, winecx (dappermint/winecx, Branch wine1119, CrossOver‑26.3‑Änderungen auf Wine 11.19, Stand 26.10.2026; das ist die Quelle von Nightforges Engine), Heroic, legendary, umu-protonfixes, winetricks, Bottles und Playnite. Außerdem drei Mac-Projekte auf fast gleichem Stack: Highball-DB, D4Mac und Cosmopolitan. Dazu DroidDeck und die playport-Messprotokolle.
- Nicht direkt erreichbar: codeweavers.com (Kompatibilitäts-DB, Changelog, Forum), lutris.net, protondb.com, reddit sowie die Support-Seiten von EA, Rockstar und Blizzard waren aus der Recherche-Umgebung gesperrt. Was von dort stammt, kommt aus Suchmaschinen-Auszügen.
- Kennzeichnung: [Q] Quelle oder Code selbst gelesen · [B] Nutzerbericht oder Suchauszug · [S] eigene Schlussfolgerung, ungetestet.
- Offen: Ob die Runtime winecx 4.7.3 exakt aus dem gelesenen Quellstand gebaut ist, ist nicht geprüft. Die README von winecx-gptk nennt CrossOver 26.3 auf Wine 11.19 als aktuelle Basis.

---

### Kurzfassung

| Launcher | Ampel | Wichtigste Spiele | Was hilft | Was bremst |
|---|---|---|---|---|
| **Rockstar Games Launcher** | 🟡 gut machbar, nur Story-Modus | GTA V Legacy, RDR2 | Steam steuert die Kette. Der Launcher startet das Spiel im „min mode“ selbst. Am Mac auf CrossOver‑26.3‑Wine‑11 belegt. | GTA Online und Red Dead Online sind gesperrt (BattlEye). Die Chromium-Schalter fehlen in winecx. Der Launcher hängt beim Beenden. GTA V Enhanced läuft nur auf M4 Pro/M5 Pro. |
| **Battle.net** | 🟢 Steam-Fassungen · 🟡 eigener Client | Diablo IV, Overwatch 2, D2R | Die Steam-Fassungen brauchen keinen Client. Start per `--exec="launch Fen"`. Zwei fertige Referenzen, eine davon in Swift auf fast gleichem Stack (D4Mac). | Rosetta-Hänger mit Blizzards Anti-Cheat (braucht macOS 26.5 und die Wine-Änderungen von CrossOver 26.1). Das Login-Fenster ist auf Wine 11 teils schwarz. |
| **EA app** | 🟡 wackelig · 🔴 für FC, Battlefield, F1, Madden | Sims 4, Mass Effect LE, Dead Space, Star Wars Jedi | Der Proton-Code zeigt genau, was vor jedem Start zu reparieren ist. Stiller Installer vorhanden. | EA-Updates brechen sie regelmäßig. Javelin-Anti-Cheat sperrt die Sportspiele und Battlefield. Die App bleibt nach dem Spiel offen. |
| **Ubisoft Connect** | 🟡→🔴 unsicher | Assassin’s Creed, Far Cry, Anno | Stiller NSIS-Installer (`/S`), Start per `uplay://launch/<id>/0` | Das Fenster bleibt auf freiem Wine meist leer. CrossOvers Fix ist ein an die CEF-Version gebundener Binär-Patch. Es gibt keine Option „nach Spielende schließen“. |

**Empfohlene Reihenfolge** (Begründung in Abschnitt 6):

1. Steam-Fassungen ohne Launcher freischalten.
2. Rockstar über Steam, danach über Epic.
3. Battle.net-Client.
4. EA app.
5. Ubisoft Connect.

---

### 1. Gemeinsame Bausteine (gelten für alle vier)

#### 1.1 Alle vier sind Chromium-Fenster: dasselbe Problem wie bei Steam

| Launcher | Browser-Teil und Prozess | Was CrossOver ≤ 24 automatisch anhängte [Q] | Was heute belegt funktioniert |
|---|---|---|---|
| Steam (zum Vergleich) | CEF, `steamwebhelper.exe` | `--no-sandbox --in-process-gpu --disable-gpu` | Nightforge: `--disable-gpu --single-process` |
| Rockstar | CEF 143 im Social Club, `SocialClubHelper.exe` | `--in-process-gpu --use-gl=swiftshader` | `--in-process-gpu`, oder `--disable-gpu --disable-gpu-compositing`, oder der offizielle Schalter `Launcher.exe -scDisableGpu` [Q playport]. **`--single-process` bricht ab** mit `SC_INIT_ERR_WEBSITE_FAILED_LOAD (17)`. |
| Battle.net | CEF, 32 Bit, `Battle.net.exe` | `--in-process-gpu --use-gl=swiftshader` | D4Mac startet `Battle.net.exe --in-process-gpu --use-gl=swiftshader` [Q] |
| Ubisoft | CEF, 32 Bit, `upc.exe` und `UplayWebCore.exe` | `--use-angle=vulkan` (für UplayWebCore) | Cosmopolitan (Wine 11, 29.10.2026): `upc.exe -upc_desktop_mode --no-sandbox --in-process-gpu --disable-gpu`. Die Login-Seite zeichnet, ob die Anmeldung klappt, ist unbestätigt [Q]. |
| EA app | Qt Quick mit Qt WebEngine (Chromium), `EADesktop.exe` und `QtWebEngineProcess.exe` | – | Keine Schalter dokumentiert. Highball setzt `DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN=1` [Q]. |

**Was daraus folgt:**

- [Q] Die Schaltertabelle fehlt in Nightforges Engine. winecx enthält die Tabelle hack_append_command_line in `kernelbase/process.c`

 nicht. Der Patch „restore-cx25-cmd-hacks“ (101arrowz/cxbuilder, apply_to: 25.*.*) bringt sie zurück. [S] Daraus folgt: CodeWeavers veröffentlicht sie seit CrossOver 25 nicht mehr im Quellcode. Nightforge muss die Schalter also selbst setzen.
- Drei Wege, die Schalter zu setzen:
  1. Direkt beim Start übergeben, wo der Launcher sie annimmt. Das geht bei Battle.net.exe (er ist selbst der CEF-Host), bei upc.exe (nicht beim Stub UbisoftConnect.exe, der nichts durchreicht) und bei Rockstar über -scDisableGpu an Launcher.exe oder in commandline_launcher.txt. Das ist schnell umgesetzt. Es hilft aber nicht, wenn Steam, der Launcher oder das Spiel den Helfer selbst starten (SocialClubHelper.exe startet sowohl der Launcher als auch das Spiel über socialclub.dll).
  2. Wrapper-EXE wie steamwebhelper-wrapper.c. Funktioniert, aber die Launcher aktualisieren sich selbst und überschreiben dabei die Datei. Nur als Notlösung, mit Prüfung vor jedem Start.
  3. Die Tabelle in Nightforges eigenen Engine-Build zurückholen. Vorlagen sind der cxbuilder-Patch und Protons gleichnamige Funktion. Das ist am robustesten, weil Nightforge ohnehin eigene Engine-Teile baut (gamepad). Grenze: Ubisofts CEF ignoriert Kommandozeilen-Schalter, solange nicht CrossOvers Binär-Patch für genau diese CEF-Version greift (siehe 1.2).

- [Q] Die Steam-Schalter nicht blind übertragen. --single-process macht den Social Club kaputt (playport-Messreihe vom 15.10.2026).
- [Q] Chromium zeichnet über Prozessgrenzen. Highball (Mac-Launcher auf CrossOver‑26.3‑Wine‑11) setzt für alle vier Launcher DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN=1. Der Grund: Der GPU-Prozess von Chromium zeichnet in das Fenster eines anderen Prozesses, und DXMT verweigert das sonst. Die README von winecx nennt passend dazu „winemac CAContext layers … so Steam’s Chromium UI renders correctly“. [S] Auf winecx mit DXMT testen.
- [Q] Alternative: Launcher-Prozesse auf DXVK. Bei frankea/Whisky #276 (gleiche winecx-gptk-Linie, 26.09.2026) brauchten Launcher.exe und SocialClubHelper.exe per AppDefaults dxgi, d3d11 und d3d10core = native (DXVK) sowie `d3d12` = deaktiviert. Auf D3DMetal läuft Rockstars CEF in eine Absturzschleife, auf DXMT bleibt es schwarz.

#### 1.2 Was in winecx schon steckt (CrossOvers Launcher-Hacks) [Q]

| Hack | Datei | Wirkung |
|---|---|---|
| CW HACK 18582 | `ntdll/heap.c`

 | Heap-Puffer, damit der Rockstar-Installer läuft |
| CW HACK 20218 | `programs/services/services.c`

 | Dienste dürfen 40 s zum Starten brauchen: „Rockstar Launcher service takes 20+ seconds to launch under Rosetta“. Hilft auch dem `EABackgroundService`. |
| CW Hack 23741 | `ntdll/unix/process.c`

 | Kein alternativer Loader für `\Rockstar Games\Launcher\Launcher.exe` |
| CW HACK 18582 / 22584 | `ntdll/loader.c`

 | Binär-Patches für libcef 85.3.9 und 85.3.11 (Social Club) |
| CW HACK 21548 | `ntdll/loader.c`

 | Binär-Patch für `Qt5WebEngineCore.dll` 5.15.2.0, „used by the EA Launcher“ |
| CW HACK 19252, 25737 | `ntdll/loader.c`

, `kernelbase/process.c`

 | Ubisoft: patcht die 32‑Bit‑libcef 111.2.7 und 135.0.20, damit Kommandozeilen-Schalter wieder wirken, und legt die fehlende SwiftShader-Vulkan-Datei an. Ubisoft zeichnet damit in Software. |
| CW HACK 23881, 27245 | `advapi32/security.c`

 | Besitzer und Zugriffsrechte für die Ordner des Battle.net-Agent und für `EpicGamesLauncher.exe` |
| ohne Nummer | `ddraw/main.c`

 | Battle.net-Systemprüfung |
| CW Hack 22996 | `ntdll/unix/loader.c`

 | `WINE_SIMULATE_WRITECOPY`, **nur per Umgebungsvariable**, nicht automatisch |
| CW Hack 24938 | `kernelbase/process.c`

 | Verschiebt `EpicGamesLauncher.exe` auf die Standard-Winstation |

**Was daraus folgt:**

- [S] Die Binär-Patches hängen an exakten CEF- bzw. Qt-Versionen. Bringt ein Launcher-Update eine neue Chromium-Version, greift der Patch nicht mehr. Genau das erklären die wiederkehrenden Zeilen „Fix for latest … update“ im CrossOver-Changelog [B]:Nightforge bekommt diese Fixes nur, wenn winecx CrossOver-Updates nachzieht. Das ist ein dauerhafter Pflegeposten.
  - Rockstar: 24.0.5 (09/2024) und neuer
  - EA app: 25.0.1 (04/2025), 25.1.0
  - Battle.net: 24.0.6 (01/2025), 26.1.0 (04/2026)
  - Ubisoft: 24.0.7, 25.1.0, 26.0.0, 26.1.0

- [Q] Writecopy muss Nightforge selbst einschalten. Valves Wine schaltet WINE_SIMULATE_WRITECOPY für UplayWebCore.exe und Battle.net.exe automatisch ein, winecx nicht. Ohne die Variable stürzt CEF mit int3 in libcef ab (D4Mac-Kommentar), und Trackmania meldet „Gamestarter must be initialized“ (Proton #6507).
  - [S] Haken: Bei Ketten, die Steam startet, erbt alles die Umgebung von Steam. Die Variable global für Steam zu setzen, kann andere Spiele treffen. Sauber ist es, sie wie Proton im Engine-Build an den Prozessnamen zu koppeln.

- [Q] Valves Wine hat außerdem fsync-Hacks für upc.exe und GTA5.exe. Das betrifft Linux-fsync. Ob msync auf dem Mac Ähnliches braucht, ist offen.

#### 1.3 Ein Prefix: das von Steam

- [Q] Steam installiert die Launcher in sein eigenes Prefix:
  - Rockstar: Redistributables\Rockstar-Games-Launcher.exe
  - EA: __Installer\EAappInstaller.exe
  - Ubisoft: Support/Software/GameLauncher

- [Q] Rockstar braucht den Steam-Client im selben Prefix. Im Steam-Modus ruft der Launcher SteamAPI_Init auf. Ohne angemeldeten Client kommen die Fehler 113 bzw. 133.
- [S] Also alle Fremd-Launcher ins bestehende Steam-Prefix, mit einem gemeinsamen Wineserver. Anmeldungen, Controller-Einrichtung, D3DMetal und Schriften gibt es dann nur einmal.
- [Q] Overrides lieber per Registry als per Umgebung. Windows-Dienste wie RockstarService und EABackgroundService erben die Umgebung, mit der der Wineserver gestartet wurde, nicht die des Launchers (Highball, gemessen am 18.09.2026). Deshalb DLL-Overrides über HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides setzen statt über WINEDLLOVERRIDES.

#### 1.4 Spielende erkennen

**Ist-Zustand [Q]:** `Engine.steamShutdownScript` zählt jeden Prozess mit `\steamapps\common\` in der Befehlszeile als „Spiel läuft“. Das Spiel gilt als beendet, wenn der Prozess bei 3 Prüfungen im Abstand von 2 s fehlt.

**Was das mit Launchern bricht:**

- Die Übergabe dauert länger als 6 s. Rockstars Dienst braucht unter Rosetta über 20 s. Battle.net nimmt Befehle erst an, wenn seine Oberfläche voll geladen ist.
- Rockstars Redirector kann ewig „Spiel läuft“ melden. PlayRDR2.exe (vermutlich auch PlayGTAV.exe) liegt in steamapps\common und wartet ohne Zeitlimit auf Launcher.exe. Hängt der Launcher beim Beenden in SHUTDOWN_IN_PROGRESS (frankea #276), sieht Nightforge das Spiel nie enden.
- Launcher-Käufe liegen nicht unter `steamapps`. Ubisoft installiert nach …\Ubisoft Game Launcher\games\, bei Battle.net ist der Ort frei wählbar.

**Vorschlag [S]** nach dem Vorbild von DroidDeck und Playnite [Q]:

1. Pro Spiel die echten Spiel-EXEs kennen, z. B. GTA5.exe, GTA5_Enhanced.exe, RDR2.exe, Diablo IV.exe. Pro Launcher eine Liste der Prozesse führen, die nicht zählen. Für unbekannte Spiele gilt die Regel von DroidDeck: Spiel ist jeder Prozess außerhalb der Launcher-Ordner.
2. In drei Phasen beobachten:
  - „Launcher startet“: bis die Spiel-EXE auftaucht, höchstens etwa 3 min, mit Anzeige. Das passt zum ROADMAP-Punkt LaunchPhase.
  - „Spiel läuft“.
  - „Spiel beendet“: die Spiel-EXE ist mindestens 15 s weg. DroidDeck wartet 15 s, Playnite wartet 40 s bis zur ersten Prüfung.

3. Danach den Launcher gezielt beenden (1.5) und erst dann Nightforge zurückholen.

#### 1.5 Launcher sauber beenden

- [Q] Was Wines `taskkill` macht:
  - Ohne /F schickt es WM_CLOSE an alle Fenster des Prozesses.
  - /T nimmt die Kindprozesse mit.
  - /F ruft `TerminateProcess(…, 1)` auf, also mit Exit-Code 1.

- [B] Problem: Viele Launcher verkriechen sich beim Schließen in den Tray. WM_CLOSE versteckt sie dann nur.
- [S] Reihenfolge beim Beenden:
  1. Den eigenen Weg des Launchers nutzen: Battle.net-Einstellung „beim Spielstart beenden“, Ubisoft closebehavior: CloseBehavior_Close.
  2. taskkill /IM <exe> /T, dann 10 s warten.
  3. taskkill /F /T.
  4. Dienste beenden sich selbst (RockstarService 22–30 s nach dem Pipe-Ende) oder per net stop.
  5. wineserver -k nur, wenn auch Steam gehen soll. Das erledigt Nightforge beim Beenden ohnehin.

- [Q] Sonderfall Rockstar: Launcher.exe muss mit Exit-Code 0 enden, sonst zeigt Steams Redirector „Unable to launch game“ (playport, Entscheidung 0156). Ein taskkill /F liefert 1. Nötig ist also ein kleiner Helfer mit TerminateProcess(h, 0), oder Nightforge lässt den Launcher selbst schließen.

#### 1.6 Einmal anmelden, danach Controller

- Die Anmeldung braucht einmal Maus und Tastatur. Jede Anmeldung läuft im eingebetteten Browser. Rockstar verlangt beim Verknüpfen mit Steam einen E-Mail-Code, dazu kommen Blizzard-Authenticator und die 2FA von EA und Ubisoft. [S] Das sollte in Nightforge ein eigener, ehrlicher Schritt sein: „Einmal anmelden, danach startet das Spiel direkt.“ Das Launcher-Fenster kommt dafür nach vorn, danach nie wieder.
- [Q] Xalia für den Controller. Xalia (MIT, vom CodeWeavers-Entwickler madewokherd) bringt fertige Controller-Regeln für die EA app mit. Proton schaltet es standardmäßig ein (PROTON_USE_XALIA=1). [S] Kandidat, um die Login-Fenster mit dem Controller bedienbar zu machen.
- [Q] Rockstar-Anmeldefehler `#1.000.7` bzw. `#1.500.7` kommen von der Zeitzone. Wine nimmt die erste Windows-Zone mit passendem Versatz, z. B. wird Istanbul zu „Arab Standard Time“, und Rockstar lehnt das ab (Highball #478). [S] Für MEZ wahrscheinlich unkritisch, im Live-Test trotzdem prüfen.

#### 1.7 Epic-Käufe: so lösen es legendary und Heroic [Q, Quellcode]

- `--wrapper` ist nicht die Lösung. Es ist ein Wrapper auf der Mac-/Linux-Seite (z. B. gamemoderun).
- `LEGENDARY_WRAPPER_EXE` ist der Hebel. legendary setzt den Inhalt dieser Umgebungsvariable zwischen Wine und die Spiel-EXE (cli.py, launch_game).
  - Heroic kopiert dafür eine Attrappe EpicGamesLauncher.exe (heroic-epic-integration v0.4, MIT) nach C:\windows\command\EpicGamesLauncher.exe im Prefix und lässt die Variable darauf zeigen.
  - Das passiert nur für Spiele, deren „known fix“ USE_FAKE_EPIC_EXE=true setzt: GTA V, GTA V Enhanced, RDR2 (Epic-ID Heather), RDR1, GTA San Andreas DE, außerdem Returnal und Phantom Blade.

- Was die Attrappe tut (108 Zeilen C):
  - wandelt den Unix-Pfad in einen DOS-Pfad um,
  - setzt den Arbeitsordner,
  - löscht SteamAppId,
  - startet das Spiel per ShellExecuteExW,
  - wartet mit WaitForSingleObject.

- Vor jedem Epic-Start: reg add HKEY_CLASSES_ROOT\com.epicgames.launcher /f (Heroic setup.ts). Das behebt auch Fallout New Vegas und Dishonored: Death of the Outsider.
- Anmeldeargumente: legendary hängt immer an:
- EA-verwaltete Epic-Spiele:
  - Installation: EAappInstaller.exe EAX_LAUNCH_CLIENT=0 IGNORE_INSTALLED=1, Quelle https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe.
  - Start: legendary launch --origin <app>, das wird zu wine start "link2ea://launchgame/<app>?AUTH_PASSWORD=…&AUTH_TYPE=exchangecode&epicusername=…".

- Ubisoft-verwaltete Epic-Spiele:
  - Installation: UbisoftConnectInstaller.exe /S, Quelle https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe.
  - Einmalig legendary activate --uplay. Die Konten müssen vorher unter epicgames.com/id/link/ubisoft verknüpft sein.
  - Start: legendary launch --ubisoft <app> (ab legendary 0.21.0), das wird zu wine start "uplay://launch/<GameID>?AUTH_PASSWORD=…".

- Wichtig: Bei --origin und --ubisoft startet legendary nur die URL und wartet nicht. Nightforge braucht dafür die Prozessbeobachtung aus 1.4.
- EOS-Overlay: Heroic schaltet es nur unter Linux ein („On mac, the overlay doesn’t work“). Für Rockstar spielt es keine Rolle.

#### 1.8 Anti-Cheat-Daten in Nightforge [Q]

- GTA V ist falsch komplett gesperrt. `profiles/profiles.json`

 führt GTA V (271590) mit antiCheat: ["BattlEye"], Nightforge blockiert es also schon vor dem Download. Der Story-Modus läuft aber mit -nobattleye. [S] Nach dem Test in mac.json auf antiCheatOnline herabstufen und -nobattleye automatisch anhängen.
- Richtig gesperrt: Die meisten Javelin-Titel stehen schon drin: FIFA 23, FC 25, Madden 24/26, F1 24, WRC 24, BF1, BFV, BF2042, BF6. FC 24 (2195250) fehlt. FC 26, Madden 25 und skate prüfen.
- Overwatch 2 steht mit Warden als `antiCheatOnline`. Warden braucht aber keine Linux-Laufzeit und gilt bei AreWeAntiCheatYet als „Supported“. [S] Eintrag prüfen. Der eigentliche Mac-Haken bei Overwatch 2 ist der Rosetta-Hänger (Abschnitt 3).

---

### 2. Rockstar Games Launcher (GTA V, RDR2) – 🟡

**Machbarkeit:** Gut machbar für den Story-Modus und am Mac belegt. Online ist ausgeschlossen. Der meiste Aufwand steckt in den Chromium-Schaltern, den DLL-Overrides und dem sauberen Beenden.

#### Läuft es?

- Mac, CrossOver‑26.3‑Wine‑11 (Highball, M1 Pro, 05.–18.09.2026) [Q]:
  - Die Anmeldung zeichnet mit DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN=1. Launcher.exe ist auf DXVK festgelegt.
  - HKLM\System\CurrentControlSet\Control\ServicesPipeTimeout = "60000".
  - Auf einer Wine‑10-Engine stirbt CEF 143 am fehlenden user32-Export IsWindowArranged. Wine 11 ist also Pflicht.
  - Beim ersten Start nach der Installation kann das Login-Fenster leer bleiben. Grund: Der Launcher startet sich nach seinem Selbst-Update über seinen Dienst neu und erbt dabei die Grafik-Umgebung des Wineservers. Abhilfe: Prefix neu starten.

- winecx-gptk-Linie (frankea/Whisky #276, 26.09.2026) [Q]:
  - Launcher.exe und SocialClubHelper.exe laufen auf DXVK, mit d3d12 deaktiviert.
  - Ohne das hängt eine D3D12-Abfrage. Der Launcher bleibt dann in SHUTDOWN_IN_PROGRESS, und Steam zeigt das Spiel weiter als laufend.
  - --in-process-gpu war auf 4.5.105 nötig, auf 4.6.4 nicht mehr.

- Proton [Q]: Social Club läuft mit --in-process-gpu oder --disable-gpu --disable-gpu-compositing (playport, Proton 10). Anmelde-Störungen im September 2026 (Proton #10125 „Code: 2“, [#10153](https://github.com/LordHayne/Nightforge/issues/10153)) verschwanden laut einem Nutzer um den 20.09. ohne Änderung [B].
- Grafik der Spiele am Mac [Q]:
  - GTA V Legacy (DX11): spielbar auf DXMT mit 60–120 fps (M1 Pro, 09.09.2026), Berichte von M1 bis M5.
  - RDR2: läuft auf D3DMetal (DX12) mit einem atiadlxx-Stub (frankea), oder auf Vulkan mit gepatchtem MoltenVK (Highball).
  - Nightforges Profil übernimmt von umu -fullscreen -vulkan. [S] Am Mac gegen D3DMetal/DX12 testen.
  - GTA V Enhanced (nur DX12): bricht auf M1/M2 mit ERR_GFX_D3D_NOD3D12 ab und läuft nur auf M4 Pro/M5 Pro (highball-db, 09–10/2026). Laut Heroic-Wiki „currently does not work“.

- Veraltet: Laut Heroic-Wiki laufen Rockstar-Spiele am Mac „nur mit kaufpflichtigem CrossOver“. Das stimmt für die alten freien wine-crossover- und GPTK-Builds, Wine‑11-Engines mit CrossOver‑26.3-Code widerlegen es inzwischen.

#### Steam-Fall [Q]

1. Steam bringt die Installer mit. Das Depot legt Redistributables\Rockstar-Games-Launcher.exe und Social-Club-Setup.exe in den Spielordner. installscript_sdk.vdf startet nacheinander:`/s /t` ist **nicht still**: Sprache, AGB, Zielordner und „Fertig“ erscheinen trotzdem.
  - Social-Club-Setup.exe /silent, geschützt durch den Schlüssel HKLM\Software\Rockstar Games\Steam\SDK;
  - Rockstar-Games-Launcher.exe /s /t, geschützt durch HKLM\Software\Rockstar Games\Steam\Launcher.

2. Was `PlayRDR2.exe` tut (Rockstar Games Launcher Redirector, 1.0.0.69):Weitere Schalter: `-skipInstallers`, `-launchDirectly` (startet RDR2.exe ohne Launcher), `-epicAppId=`. [S] `PlayGTAV.exe` ist sehr wahrscheinlich derselbe Redirector.
  - liest HKLM\SOFTWARE\WOW6432Node\Rockstar Games\Launcher\InstallFolder;
  - fehlt der Wert, installiert er den Launcher interaktiv;
  - dann startet er Launcher.exe -skipPatcherCheck -steamAppId=1174180 -steamLocation "<Spielordner>" … @args.txt und wartet ohne Zeitlimit;
  - endet der Launcher mit einem Exit-Code ungleich 0, erscheint ein Fehlerdialog.

3. Prozesskette: PlayRDR2.exe → Launcher.exe → RockstarService.exe → SocialClubHelper.exe → RDR2.exe -fromRGL -useSteam. Der Launcher arbeitet im „Steam min mode“ und startet das Spiel ohne Klick.
4. Kontoverknüpfung: Bei der ersten Anmeldung wird das Steam-Konto mit dem Rockstar-Konto verknüpft, mit E-Mail-Code. Pro Steam-Konto geht nur ein Rockstar-Konto.
5. `-nobattleye` ist offiziell für den Story-Modus (Rockstar-FAQ, Auszug). CrossOver ≤ 24 hängte es automatisch an PlayGTAV.exe an, winecx tut das nicht mehr.

#### Epic-Fall [Q]

- Der Rockstar Launcher erkennt den Epic-Besitz nur, wenn das Spiel über einen Prozess namens EpicGamesLauncher.exe startet. Die Lösung von Heroic steht in 1.7: Attrappe als LEGENDARY_WRAPPER_EXE plus reg add HKCR\com.epicgames.launcher /f.
- umu-protonfixes löscht für GTA V bei Starts außerhalb von Steam SteamAppId („Rockstar reads SteamAppId and tries to init Steam API“). Die Attrappe macht das ebenfalls.
- Startet man PlayGTAV.exe direkt statt über die Attrappe, findet der Launcher das Spiel beim ersten Mal, verweigert aber den Start. Nach einem Neustart findet er es gar nicht mehr (unifideck-Notiz).

#### Automatisierung

- Stille Installation [Q]: Rockstar-Games-Launcher.exe /s /f.
  - Laut winget-Manifest von Version 1.0.109.3031 (09/2026) braucht er Adminrechte (unter Wine automatisch erfüllt) sowie die VC++‑2015+-Pakete für x64 und x86.
  - /f gibt es seit RGL 1.0.105.2705 (11/2025) [B].
  - Quelle: https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe.
  - [S] Einmal vor dem ersten Steam-Start ausführen. Dann ist InstallFolder gesetzt, und der Redirector überspringt die interaktive Installation.

- Was die Installation hinterlässt [Q]:
  - Programme unter C:\Program Files\Rockstar Games\Launcher\.
  - Dienst Rockstar Service (LocalSystem, Start bei Bedarf, kein Neustart nötig). Er ist Pflicht, ohne ihn kommt Fehler 135.
  - Protokoll rockstar://.
  - Logs: C:\ProgramData\Rockstar Games\Launcher\service_log.txt und Documents\Rockstar Games\Launcher\launcher.log.

- Offline: Es gibt -scOfflineOnly (in den Strings gefunden, Wirkung unbestätigt). Offline geht ohnehin nur nach einer Online-Anmeldung auf diesem Rechner.
- Spielende: Die Spiel-EXEs sind GTA5.exe, GTA5_Enhanced.exe und RDR2.exe, alle Kinder von Launcher.exe. Während des Spiels bleiben 11 Launcher-Prozesse mit etwa 3,5 GiB aktiv.
  - Launcher.exe während des Spiels zu beenden, schadet nicht: RDR2 lief 62 min weiter und speicherte (playport).
  - Aber: Baut sich die Launcher-Oberfläche neu auf, erscheint sie im Vollbild über dem Spiel.

- Beenden: Es gibt keinen dokumentierten Shutdown-Schalter.
  - PlayGTAVLinux beendet nach dem Spielende PlayGTAV, Launcher und RockstarService.
  - Dabei auf Exit-Code 0 achten (1.5).
  - Außerdem RockstarErrorHandler.exe und die SocialClubHelper.exe-Prozesse des Launchers beenden.

#### Anti-Cheat und Online

- GTA Online: BattlEye seit 17.09.2024, ohne Linux-Freigabe, also unter Wine gesperrt [Q GamingOnLinux].
- Story-Modus: läuft mit -nobattleye. Für Enhanced gibt es den Steam-Deck-Pfad (SteamDeck=1 bzw. -onSteamDeck setzt -nobattleye automatisch) [B]. Ein Proton-Hotfix vom 07.03.2025 reparierte den Offline-Start von Enhanced.
- Red Dead Online: Rauswürfe werden auch 2026 noch gemeldet [B].
- [S] Online ist auf dem Mac ein klares Nein. Das sollte Nightforge vor dem Kauf bzw. Download sagen.

#### Konkrete Schritte für Nightforge

1. Vor dem ersten Steam-Start installieren: VC++‑Redist x86/x64, dann Rockstar-Games-Launcher.exe /s /f.
2. Registry setzen:
  - ServicesPipeTimeout = "60000".
  - AppDefaults für Launcher.exe und SocialClubHelper.exe: dxgi, d3d11, d3d10core = native (DXVK) und d3d12 = deaktiviert. Alternativ DXMT mit DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN=1. Beides testen.

3. Chromium-Schalter: -scDisableGpu in commandline_launcher.txt als ersten, einfachsten Versuch. Wirkt das nicht, --in-process-gpu per Engine-Patch (1.1, Weg 3) an SocialClubHelper.exe hängen, ohne `--single-process`.
4. GTA V: -nobattleye immer anhängen und den Profileintrag 271590 auf „nur online gesperrt“ ändern.
5. Spielende: GTA5*.exe bzw. RDR2.exe beobachten (1.4). Danach Launcher.exe mit Exit-Code 0 beenden, damit PlayRDR2.exe bzw. PlayGTAV.exe ohne Fehlerdialog endet.
6. Epic: Attrappe EpicGamesLauncher.exe (MIT, GPL-kompatibel) mitliefern, LEGENDARY_WRAPPER_EXE setzen, reg add HKCR\com.epicgames.launcher /f.

#### Stolpersteine

- Erster Start nach der Installation mit leerem Login-Fenster (Dienst erbt die falsche Umgebung).
- Zeitzonen-Fehler #1.000.7.
- GTA V Enhanced auf kleinen Chips.
- Social Club wird zweimal gestartet: vom Launcher und vom Spiel über socialclub.dll. Beide Kopien brauchen dieselben Schalter.
- Jedes Launcher-Update mit neuer CEF-Version kann alles wieder brechen.

#### Quellen

- Heroic-Wiki „Rockstar Games from Epic Games“: https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/Rockstar-Games-from-Epic-Games
- Heroic-Code (`src/backend/storeManagers/legendary/games.ts`

, setup.ts): https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher · known-fixes: https://github.com/Heroic-Games-Launcher/known-fixes
- Attrappe: https://github.com/Etaash-mathamsetty/heroic-epic-integration (main.c)
- legendary (cli.py, core.py): https://github.com/derrod/legendary
- playport-Messungen:
  - https://github.com/playportdev/playport/blob/HEAD/docs/evidence/2026-10-15-rockstar-launcher-recon.md
  - https://github.com/playportdev/playport/blob/HEAD/docs/evidence/2026-10-15-rdr2-launcher-in-game.md
  - https://github.com/playportdev/playport/blob/HEAD/docs/decisions/0156-end-the-rockstar-launcher-with-exit-code-0.md

- RDR2 und Launcher-Reparatur am Mac: https://github.com/dazi2011/RealSteamOnMac/blob/HEAD/docs/research/rdr2-rockstar-recovery-2026-06-11.md
- winget-Manifest: https://github.com/microsoft/winget-pkgs/blob/master/manifests/r/RockstarGames/Launcher/1.0.109.3031/RockstarGames.Launcher.installer.yaml
- Highball-Rezepte:
  - https://github.com/gauthierpiarrette/highball-db/blob/HEAD/recipes/launchers/rockstar.json
  - …/recipes/games/grand-theft-auto-v.json · …/db/games/grand-theft-auto-v-enhanced.json
  - Zeitzonen-Fehler: [gauthierpiarrette/highball#478](https://github.com/gauthierpiarrette/highball/issues/478)

- frankea/Whisky [frankea/Whisky#276](https://github.com/frankea/Whisky/issues/276): [frankea/Whisky#276](https://github.com/frankea/Whisky/issues/276) · Sikarugir [Sikarugir-App/Sikarugir#258](https://github.com/Sikarugir-App/Sikarugir/issues/258): [Sikarugir-App/Sikarugir#258](https://github.com/Sikarugir-App/Sikarugir/issues/258)
- Alte CrossOver-Schaltertabelle: https://github.com/101arrowz/cxbuilder/blob/HEAD/patches/0004-restore-cx25-cmd-hacks.patch · Social-Club-Patch für CrossOver 26.3: https://github.com/kurexi/wine-wrap/blob/HEAD/scripts/wine-patches/0005-kernelbase-run-social-club-gpu-in-process.patch
- winecx: https://github.com/dappermint/winecx/tree/wine1119
- umu-protonfixes (`gamefixes-steam/271590.py`

, 1174180.py): https://github.com/Open-Wine-Components/umu-protonfixes
- Proton-Issues: [ValveSoftware/Proton#3291](https://github.com/ValveSoftware/Proton/issues/3291) · [ValveSoftware/Proton#8495](https://github.com/ValveSoftware/Proton/issues/8495)
- PlayGTAVLinux: https://github.com/treviasxk/PlayGTAVLinux
- GamingOnLinux zu BattlEye: https://gamingonlinux.com/2024/09/grand-theft-auto-v-gets-battleye-anti-cheat-breaks-online-play-on-steam-deck-linux/
- Rockstar-FAQ zu BattlEye (Auszug): https://support.rockstargames.com/articles/1nenwhZlVrJY6CTFeSS2Fx

---

### 3. Battle.net (Diablo IV, Overwatch 2, D2R) – 🟢 Steam-Fassungen / 🟡 eigener Client

**Machbarkeit:** Am besten automatisierbar von allen vier, mit zwei Referenz-Implementierungen. Die Windows-only-Hauptspiele gibt es auf Steam **ohne** Battle.net-Client. Der gemeinsame Mac-Haken ist ein Rosetta-Hänger mit Blizzards Anti-Cheat.

#### Läuft es?

**D4Mac** (Swift, MIT) ist die wichtigste Referenz [Q]. Sein Stack ist Wine 11 aus CrossOver‑26.1-Quellen, GPTK 3.0 (D3DMetal), DXMT 0.72 und Rosetta, also fast Nightforges Stack. Was D4Mac macht:

- Start: Battle.net.exe --in-process-gpu --use-gl=swiftshader. Das ist das Gegenstück zu Nightforges Steam-Wrapper.
- Umgebung für Battle.net und den Installer:
  - WINE_SIMULATE_WRITECOPY=1 schaltet CW Hack 22996 ein. Ohne die Variable trifft CEF bei libcef.dll+0x16D00E1 auf int3.
  - außerdem WINE_LARGE_ADDRESS_AWARE=1, WINE_HEAP_ZERO_MEMORY=1 und ROSETTA_ADVERTISE_AVX=1.

- Overrides: winemenubuilder.exe=d;mscoree=d;mshtml=d.
- esync/msync aus: Auf macOS 26 unter Rosetta belegen sie sonst einen Kern voll und bremsen den Downloader auf etwa 4 KB/s.
- Grafik: Battle.net selbst ist 32 Bit, seine CEF-Oberfläche läuft über DXMT. Diablo IV läuft auf D3DMetal.
- Voraussetzungen: vc_redist.x86 und vc_redist.x64 mit /passive /norestart, MS Core Fonts plus Source Han Sans, und HKCU\Software\Wine\WineDbg ShowCrashDialog=0.
- Sony-Controller: HKLM\System\CurrentControlSet\Services\WineBus\Devices\054c/<pid> Hidraw=0, sonst sieht Diablo IV auf dem Mac keinen Controller. [S] Mit Nightforges gamepad-Komponente abgleichen.
- Erst-Login: In Battle.net.config werden Services.LastLoginAddress="us.actual.battle.net" und LastLoginTassadar="account.battle.net" vorbelegt. Sonst hängt die Oberfläche auf „Region wählen“.
- Installer: Battle.net-Setup.exe arbeitet in zwei Stufen und startet Battle.net danach selbst, aber ohne die CEF-Schalter, was in eine Absturzschleife führt. D4Mac beendet ihn deshalb (wineserver -k) und startet ihn richtig neu.

**Weitere Befunde:**

- CrossOver [B]: Battle.net offiziell unterstützt seit 23.7. Fixes in 24.0.6 (01/2025, „latest Battle.net update“) und 26.1.0 (04/2026, „not installing for some users“). Bekannter Hänger: „Updating Battle.net Update Agent“ bleibt bei 45 % stehen (2025/2026). Abhilfe: älteren Agent.<build> verwenden.
- Highball [Q]: Auf seinen Wine‑11-Engines (r8–r10) bleibt der Browser-Bereich im Login schwarz (Unterfenster, „unconfirmed“). Auf Wine 10 (Sikarugir) zeichnet das Login. Ohne den Swapchain-Schalter stürzt CEF mit int3 ab. [S] D4Mac belegt Wine 11 mit den Schaltern oben, also zuerst dessen Rezept übernehmen.
- winecx [Q]: enthält CrossOvers Rechte-Hack für den Battle.net-Agent (CW HACK 23881) und die Systemprüfungs-Anpassung in ddraw.
- Valves Wine [Q]: schaltet WINE_SIMULATE_WRITECOPY für Battle.net.exe automatisch ein.

#### Steam-Fall

- Overwatch 2 (Steam seit 08/2023), Diablo IV (Steam seit 17.10.2023) und D2R (Steam seit 02/2026): Sie brauchen keinen Battle.net-Client, aber ein verknüpftes Battle.net-Konto [B, Blizzard-Aussage]. Verknüpft wird beim ersten Start per Code im Browser oder per QR-Code. Ein anderes Steam-Konto lässt sich erst nach einem Jahr verknüpfen.
- Diablo IV unter Proton [Q]: Patch 3.1.0 vom 30.06.2026 brach den Start (Proton #9926, [#9931](https://github.com/LordHayne/Nightforge/issues/9931): Stub FindNextFileNameW). Behoben über Proton Hotfix/Experimental [B]. [S] Mit winecx 4.7.3 testen.

#### Automatisierung [Q]

- Produkt-Codes für `--exec="launch X"` (Lutris, Playnite und bnetlauncher stimmen überein; Groß-/Kleinschreibung zählt):SpielCodeDiablo IV`Fen`Overwatch 2`Pro`Diablo II: Resurrected`OSI`Diablo III`D3`World of Warcraft`WoW`Hearthstone`WTCG`StarCraft II`S2`
- Ablauf nach Playnite und DroidDeck:
  1. Battle.net Launcher.exe bzw. Battle.net.exe starten.
  2. Warten, bis mindestens 5 `Battle.net.exe`-Prozesse laufen, dann noch etwa 5 s. Seit Shadowlands nimmt der Client Befehle erst mit voll geladener Oberfläche an.
  3. Battle.net.exe --exec="launch Fen" ausführen. DroidDeck wiederholt das bis zu dreimal im Abstand von 15 s.
  4. Spiel ist jeder Prozess außerhalb von …\Battle.net\ und …\ProgramData\Battle.net\. Gestartete Spiele tragen -uid <uid>, Diablo IV zusätzlich -sso.
  5. Das Spiel gilt nach 15 s ohne Spielprozess als beendet.

- Battle.net nach dem Spielstart schließen: In …\AppData\Roaming\Battle.net\Battle.net.config setzen:DroidDeck beendet Battle.net nach 20 s zusätzlich selbst, **außer** bei Spielen mit `-sso` (Diablo IV), die den Client brauchen. [S] Wie sich Wert 2 mit Diablo IV verträgt, im Test klären. Unter winecx liegt die Datei im Benutzerordner `crossover`.
  - Client.GameLaunchWindowBehavior = "2", laut DroidDeck-PR „beim Spielstart ganz beenden“;
  - Client.HardwareAcceleration = "false";
  - Client.Streaming.StreamingEnabled = "false".

- Installer:
  - Battle.net-Setup.exe --lang=enUS --installpath="C:\Program Files (x86)\Battle.net" läuft ohne Rückfragen, ist aber nicht wirklich still (Fenster, danach Autostart). Einen offiziellen --silent gibt es nicht.
  - Quelle: https://downloader.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live.

- Spiele ohne Oberfläche installieren: Agent.exe --internalclienttools bietet eine lokale HTTP-API mit /install, /update und /uninstall (barncastle/Battle.Net-Installer, von DroidDeck genutzt). Sie braucht eine frische Battle.net-Anmeldung.
- Spiele ohne Launcher starten: Für Diablo IV gibt es nur wackelige Tricks (D4Launcher, archiviert). [S] Nicht verfolgen, --exec nutzen.
- Beenden: Es gibt keinen Beenden-Schalter. Alle Referenzen beenden den Prozessbaum, Agent.exe eingeschlossen.
  - Agent.exe kann ein minimiertes Battle.net wiederbeleben (Lutris #6614).
  - Nach hartem Beenden aufräumen, wie D4Mac es tut: `Agent/aggregate.json`

, .product.db*, Agent.dat, .patch.result und die Browser-Caches löschen.

#### Anti-Cheat und Online

- Warden [Q AreWeAntiCheatYet]: Overwatch 2 gilt als „Supported“, mit Blizzard-Zitat von 2018: Wine ist kein Bann-Grund. Diablo IV, WoW, D2R, D3 und SC2 laufen.
- Call of Duty (Ricochet): gesperrt und verlangt inzwischen Secure Boot und TPM 2.0. Ausschließen.
- Alle Blizzard-Spiele sind immer online. Overwatch 2 verlangt zusätzlich eine Telefonnummer am Konto [B].
- Der Mac-Haken [Q D4Mac-README]: Diablo IV, Overwatch 2 und D2R (dieses seit 01/2026) hängen unter Rosetta. Threads bleiben in os_sync_wait_on_address in libd3dshared.dylib stehen, wenn Blizzards Anti-Cheat übersetzte Speicherseiten liest. Laut CodeWeavers-Blog vom 18.05.2026 (über D4Mac) braucht der Fix die Wine-Änderungen von CrossOver 26.1 und macOS 26.5. [S] Für diese drei Spiele macOS ≥ 26.5 voraussetzen und prüfen, ob winecx die 26.1-Änderungen enthält. Laut README basiert winecx auf 26.3.
- Diablo IV Season 14 (Patch 3.1.0) brach CrossOver 26.2.0 mit einem fehlenden KERNEL32-Export [B].

#### Konkrete Schritte für Nightforge

1. Phase 0, sofort: Overwatch 2, Diablo IV und D2R aus der Steam-Bibliothek freigeben. Kein Launcher nötig, nur einmal die Kontoverknüpfung im Browser. macOS ≥ 26.5 voraussetzen und den Overwatch‑2-Eintrag korrigieren.
2. Eigener Client:
  - Installer mit --lang/--installpath ausführen, den Autostart abfangen und mit Schaltern neu starten.
  - Battle.net.config vorbelegen: Fenster-Verhalten 2, Hardware-Beschleunigung aus, Streaming aus, Login-Region.
  - WINE_SIMULATE_WRITECOPY=1, Start mit --in-process-gpu --use-gl=swiftshader.

3. Start aus Nightforge: 5 Prozesse abwarten, dann --exec="launch <Code>", danach die Spielende-Logik aus 1.4.
4. Vorlagen: D4Mac für Prefix-Setup und Umgebung (Swift, MIT), DroidDeck für den Ablauf und das Spielende.

#### Stolpersteine

- Updater-Hänger bei 45 %.
- Der Agent lebt nach dem Beenden weiter.
- Schwarzes Login auf manchen Wine‑11-Builds.
- Ein Spiel-Patch kann jederzeit einen fehlenden Wine-Export verlangen (Diablo IV 3.1).
- Rosetta-Abhängigkeit des Anti-Cheat.

#### Quellen

- D4Mac: https://github.com/MichaelLod/D4Mac (`Sources/D4Mac/BNetLauncher.swift`

, BottleManager.swift, README)
- DroidDeck:
  - Skript: https://github.com/Droid-Deck/DroidDeck/blob/main/tools/linuxfs/overlay/usr/local/bin/droiddeck-battlenet
  - PR: [Droid-Deck/DroidDeck#979](https://github.com/Droid-Deck/DroidDeck/pull/979)

- Playnite: https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/BattleNetLibrary/BattleNetGameController.cs
- Agent-API: https://github.com/barncastle/Battle.Net-Installer
- Highball-Rezept: https://github.com/gauthierpiarrette/highball-db/blob/HEAD/recipes/launchers/battle-net.json
- Lutris-Doku: https://github.com/lutris/docs/blob/master/Battle.Net.md · Lutris [lutris/lutris#6614](https://github.com/lutris/lutris/issues/6614): [lutris/lutris#6614](https://github.com/lutris/lutris/issues/6614)
- NixOS-Wiki: https://wiki.nixos.org/wiki/Battle.net
- Proton [ValveSoftware/Proton#9926](https://github.com/ValveSoftware/Proton/issues/9926): [ValveSoftware/Proton#9926](https://github.com/ValveSoftware/Proton/issues/9926)
- AreWeAntiCheatYet: https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet/blob/master/games.json
- CrossOver-Changelog (Auszug): https://www.codeweavers.com/crossover/changelog
- Valves Wine (`dlls/ntdll/unix/loader.c`

, Branch proton_10.0): https://github.com/ValveSoftware/wine

---

### 4. EA app (Sims 4, Mass Effect LE, Dead Space …) – 🟡 / 🔴 für Javelin-Spiele

**Machbarkeit:** Machbar, aber der wackeligste Launcher mit dem höchsten Pflegeaufwand. Die Sportspiele und Battlefield fallen wegen Anti-Cheat komplett weg.

#### Läuft es?

- Aufbau [Q]: Die Oberfläche ist Qt Quick/QML. Web-Inhalte laufen über Qt WebEngine (QtWebEngineProcess.exe). Dazu kommen EABackgroundService.exe (Windows-Dienst), EALauncher.exe, Link2EA.exe und EASteamProxy.exe.
- Mac, Wine 11 mit CrossOver‑26.3-Code (Highball, verifiziert r15, 10/2026) [Q]: Installation, Dienst und Login-Fenster laufen. Wichtig dabei:
  - Wine 11 ist Pflicht. Die Custom Action JunoSetupSymlinkMode legt einen Verzeichnis-Symlink an (EA Desktop\EA Desktop → EA Desktop\<Version>). Außerdem braucht der Installer einen funktionierenden Dienst-Manager. Auf Wine 10 bricht er mit INST-14-1627 bzw. -1603 ab und rollt alles zurück.
  - Leeres, dunkles Fenster: Chromium zeichnet prozessübergreifend, deshalb DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN=1.
  - Hängender Installer: Auf r10 blieb der Burn-Bootstrapper ohne Fenster stehen, Ursache unklar.

- winecx [Q]: Enthält CW HACK 21548, einen Binär-Patch für Qt5WebEngineCore.dll 5.15.2.0 („EA Launcher“). [S] Ob die aktuelle EA app noch genau diese Qt-Version mitbringt, ist offen. Wenn nicht, greift der Patch nicht.
- Proton-Changelog [Q]: Die EA app wird ständig neu repariert:
  - 7.0-6 und 8.0-4: leeres Login-Fenster
  - 9.0-3: Installer
  - 11.0-1 (2026): „many EA games unplayable after a recent EA Desktop update“
  - Experimental 01/2026: erneut [B]

- CrossOver [B]: „Support for EA App“ seit 23.0 (08/2023). Fixes in 25.0.1 (04/2025) und 25.1.0. Die Kompatibilitäts-DB sagt „Limited Functionality“, getestet mit 23.0 und damit veraltet.
- Keine Chromium-Schalter für die EA app dokumentiert, weder bei Proton noch bei CrossOver noch bei Lutris [Q/B].

#### Steam-Fall [Q]

- Das Installskript enthält:Steam überspringt die Installation, wenn `…\EA Desktop\InstallSuccessful = "true"` gesetzt ist.
- Der Start-Eintrag ist eine URL: link2ea://launchgame/<SteamAppID>?platform=steam…. Zuständig ist C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\Link2EA.exe.
- Was Protons `steam.exe` vorher repariert (`steam_helper/steam.c`

, Commit bc89621 vom 09.10.2026), wenn die Befehlszeile mit link2ea:// oder steam2ea:// beginnt:
  1. Desktop-Timeout auf 3000 ms setzen.
  2. HKLM\Software\Electronic Arts\EA Desktop\IsUnavailable (DWORD) auf 0 setzen.
  3. Ist der Dienst EABackgroundService gestoppt, C:\ProgramData\EA Desktop\backgroundservice.ini löschen.
  4. Die URL per ShellExecute öffnen und nicht warten.
  5. Datei nicht gefunden: den Symlink …\EA Desktop\EA Desktop neu anlegen und es noch einmal versuchen.
  6. Keine Verknüpfung für das Protokoll: per MsiConfigureProductExW("{C2622085-ABD2-49E5-8AB9-D3D6A642C091}", REMOVE=ALL) deinstallieren und die Schlüssel Classes\link2ea, Electronic Arts\EA Desktop und EA Core löschen. Dann installiert Steam die App beim nächsten Start neu.

- [S] Wichtig für Nightforge: Nightforge startet die echte Windows-Steam im Prefix, nicht Protons steam.exe. Keiner dieser Schritte passiert also von allein, Nightforge muss sie vor jedem EA-Start selbst ausführen.
- Kontoverknüpfung: nur beim ersten EA-Spiel über Steam nötig, ein Steam-Konto pro EA-Konto [B, EA-Hilfe].
- Steam-Spiele ohne EA-app-Zwang: Split Fiction, It Takes Two (per Update entfernt), Dragon Age: The Veilguard, Battlefield 6 (auf Steam nur EA-Konto, aber Javelin). F1 23 und EA Sports WRC laut Nutzerberichten [B].
- Weiter mit EA-app-Zwang: Mass Effect LE, Sims 4, die FC-Reihe, BF2042.

#### Epic-Fall [Q]

- Siehe 1.7: EAappInstaller.exe EAX_LAUNCH_CLIENT=0 IGNORE_INSTALLED=1, danach legendary launch --origin → wine start "link2ea://launchgame/<app>?AUTH_PASSWORD=…".
- Es wird nicht gewartet. Die Proton-Reparaturschritte von oben gelten genauso.

#### Automatisierung

- Stille Installation [Q]: Der Installer ist ein WiX-Burn-Bundle (winget, Version 13.813.1.6327 vom 22.10.2026).
  - Schalter: /passive /norestart, Zielordner per InstallFolder="<Pfad>".
  - Registrierte Protokolle: ealink, link2ea, origin, origin2.
  - Heroic nutzt EAX_LAUNCH_CLIENT=0 IGNORE_INSTALLED=1, Lutris akzeptiert Exit-Code 768.
  - [S] Kandidat: EAappInstaller.exe /passive /norestart EAX_LAUNCH_CLIENT=0 IGNORE_INSTALLED=1, ungetestet.

- Spiel direkt starten: origin2://game/launch?offerIds=<contentID>&autoDownload=1 [B]. Die contentID steht in __Installer\installerdata.xml. Bei Steam- und Epic-Käufen startet ohnehin die Plattform das Spiel.
- Playnite-Vorlage (EA-Plugin, Ende 10/2025 entfernt) [Q]:
  - Die Spiel-EXE direkt starten.
  - Bei Spielen mit Aktivierung bzw. EAC 40 s warten, dann alle Prozesse im Installationsordner beobachten.
  - Am Ende die EA app per taskkill /pid ohne `/F` schließen.

- Nach dem Spiel: Die EA app springt wieder auf, und EA nennt das gewollt [B]. Es gibt keine Option „nach Spiel schließen“. EADesktop.exe --silent startet angeblich minimiert, die Berichte widersprechen sich [B].
- Offline: Menü → „Offline gehen“. Funktioniert nur bei offline-fähigen Spielen wie Sims 4 und muss online aktiviert werden.
- Benutzer-Einstellungen [Q]: %LOCALAPPDATA%\Electronic Arts\EA Desktop\user_<id>.ini, z. B. user.gamecommandline.<offerid>=. Der Client überschreibt die Datei, solange er läuft.
- Spielende: Der EA-Dienst ist unter Wine ein „System“-Prozess und hält die Sitzung nicht offen, EADesktop.exe dagegen schon [Q/S]. Die Spiel-EXE also wie in 1.4 beobachten.
- Alternativen zur EA app [Q]: Maxima (GPL-3, „pre-pre-pre-alpha“, letzter Commit 01/2026). GameNative emuliert den lokalen LSX-Dienst der EA app mit EAs Client-Schlüssel. [S] Rechtlich riskant, nicht übernehmen.

#### Anti-Cheat und Online

- EA Javelin (Kernel-Treiber) verweigert Wine und Proton [B]. Betroffen: FIFA 23, FC 24/25/26, Battlefield 2042, Battlefield V (seit 04/2024), Battlefield 1 (seit 09/2024), EA Sports WRC, PvZ Garden Warfare 2, F1 24, Madden 25/26, skate. Battlefield 6 verlangt zusätzlich Secure Boot.
- Apex Legends (EAC) sperrt Linux seit 31.10.2024.
- Realistische Ziele ohne Anti-Cheat: Sims 4, Mass Effect LE, Dead Space, Star Wars Jedi, Titanfall 2 (Einzelspieler).

#### Konkrete Schritte für Nightforge

1. Vor dem ersten EA-Spiel die EA app selbst still installieren. Steam überspringt dann seinen interaktiven Installer. Prüfen, dass der Symlink EA Desktop\EA Desktop steht und EABackgroundService startet.
2. Pre-Launch-Schritt vor jedem EA-Start, nachgebaut nach Proton: IsUnavailable auf 0, backgroundservice.ini löschen wenn der Dienst steht, Symlink reparieren. Wenn link2ea nicht verknüpft ist, neu installieren.
3. Grafik: DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN=1 für EADesktop.exe testen, sonst DXVK per AppDefaults.
4. Spielende: Spiel-EXE beobachten, dann die EA app schließen (taskkill ohne /F, dann mit).
5. Javelin-Spiele vor dem Download klar als gesperrt kennzeichnen (die meisten stehen schon im Profil). FC 24 ergänzen, FC 26, Madden 25 und skate prüfen.
6. Controller: Xalia für das Login-Fenster prüfen.

#### Stolpersteine

- EA-Updates kommen mehrmals im Jahr und brechen immer wieder etwas (Login leer, Installer, Spielstart).
- Der Qt-Binär-Patch in winecx hängt an der Qt-Version.
- Der Dienst braucht Zeit (CW HACK 20218 hilft).
- Anmeldefehler INST-14-12157 („trouble getting online“) [B].

#### Quellen

- Proton `steam_helper/steam.c`

: https://github.com/ValveSoftware/Proton/blob/bc896217ffcd67f892f952b010f898fe7bd0f0a1/steam_helper/steam.c
- Proton-Changelog: https://github.com/ValveSoftware/Proton/wiki/Changelog · Proton [ValveSoftware/Proton#9433](https://github.com/ValveSoftware/Proton/issues/9433) (Symlink-Stub): [ValveSoftware/Proton#9433](https://github.com/ValveSoftware/Proton/issues/9433)
- Highball-Rezept: https://github.com/gauthierpiarrette/highball-db/blob/HEAD/recipes/launchers/ea-app.json
- winget-Manifest: https://github.com/microsoft/winget-pkgs/tree/master/manifests/e/ElectronicArts/EADesktop/13.813.1.6327
- Heroic setup.ts: https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/blob/main/src/backend/storeManagers/legendary/setup.ts
- legendary core.py (get_origin_uri): https://github.com/derrod/legendary
- winecx `dlls/ntdll/loader.c`

 (CW HACK 21548): https://github.com/dappermint/winecx/tree/wine1119
- GameNative (EaLaunchSupport.kt): https://github.com/utkarshdalal/GameNative · Steam-Installskript: https://github.com/p0358/Fuck_off_EA_App
- Playnite (EA-Plugin bis Commit f61dfdc): https://github.com/JosefNemec/PlayniteExtensions
- Xalia: https://github.com/madewokherd/xalia · Maxima: https://github.com/ArmchairDevelopers/Maxima
- Javelin-Überblick: https://www.gamingonlinux.com/anticheat/vendor/ea-javelin-anticheat/
- Battlefield 6 auf Steam ohne EA app: https://www.pcgamer.com/games/fps/thank-god-battlefield-6-wont-make-you-use-the-ea-app-on-steam-but-it-will-if-youre-on-epic
- Battlefield 6 und Secure Boot: https://www.techspot.com/news/108925-battlefield-6-anti-cheat-system-requires-secure-boot.html
- CrossOver 23 mit EA app: https://www.phoronix.com/news/CrossOver-23-Released

---

### 5. Ubisoft Connect (Assassin’s Creed, Far Cry, Anno) – 🟡→🔴

**Machbarkeit:** Auf freiem Wine derzeit unsicher. Die Automatisierung wäre einfach, das Hindernis ist die Darstellung des Fensters.

#### Läuft es?

- winecx [Q]:
  - CW HACK 19252 und 25737 patchen Ubisofts 32‑Bit-libcef.dll (CEF 111.2.7 und 135.0.20) so, dass CEF command_line_args_disabled ignoriert. Ohne den Patch kommen keine Schalter an.
  - Dazu legt Wine die SwiftShader-Vulkan-Datei an, die upc.exe bzw. UplayWebCore.exe verlangen. Ubisoft zeichnet damit in Software.
  - [S] Jede CEF-Version, die nicht exakt passt, macht den Patch wirkungslos.

- Cosmopolitan (gemergt 29.10.2026, Highball-Wine-11 r29) [Q]: upc.exe -upc_desktop_mode --no-sandbox --in-process-gpu --disable-gpu direkt starten. Der Stub UbisoftConnect.exe reicht keine Schalter durch. Mit diesen Schaltern zeichnet die Login-Seite, die Anmeldung ist nicht belegt. Laut PR startet CrossOver upc.exe genauso [B].
- Highball (25.08.2026) [Q]: Das Fenster zeichnet nie, weiß unter D3DMetal/DXMT/wined3d und schwarz unter DXVK, auch mit WINE_SIMULATE_WRITECOPY=1. Läuft nur in CrossOver ab 25.1.
- Heroic-Wiki (09.04.2026) [Q]: „wine-crossover, wine-staging and game-porting-toolkit can’t run Ubisoft Connect“. Am Mac nur mit aktuellem kaufpflichtigem CrossOver.
- mapc-engine #9 (21.10.2026, Wine 11.18 Staging, M5) [Q]:
  - --disable-gpu --disable-gpu-compositing --in-process-gpu --no-sandbox beseitigt das schwarze Fenster.
  - WINE_D3D_CONFIG=renderer=no3d beseitigt den Absturz des GPU-Prozesses.
  - Danach stürzen aber die 32‑Bit-Renderer unter Rosetta in wow64cpu.dll ab.
  - winecx enthält CrossOvers Rosetta-Workaround dafür (CW HACK 20760). [S] Möglich, dass winecx diesen Absturz nicht hat. Ungetestet.

- Proton [Q]: schaltet WINE_SIMULATE_WRITECOPY für UplayWebCore.exe automatisch ein. Ohne die Variable meldet Trackmania „Gamestarter must be initialized“ (Proton #6507).
- Linux-Tipps [B]: WINEDLLOVERRIDES="libglesv2.dll=d" gegen schwarze Fenster (Lutris #5412, etwa 5 Bestätigungen).

#### Steam-Fall

- [B/Q] Installation über Steam: Das Spiel bringt einen Installer unter Support/Software/GameLauncher mit, den Steam beim ersten Start ausführt. Ältere UplayInstaller.exe hängen bei „Looking for patches“.
  - umu-protonfixes installiert deshalb für einige Titel per winetricks-Verb ubisoftconnect nach: R6 Siege, Anno 1800 (916440) u. a.
  - Nightforges build-profiles.py ignoriert dieses Verb bisher (IGNORED_VERBS) [Q].

- [B] Ubisoft Connect bleibt nach dem Spiel offen, und Steam zählt das Spiel weiter als laufend (Proton #5212). Eine Option „nach Spiel schließen“ gibt es nicht.
- [Q] Steam-Kopien haben andere Ubisoft-IDs, z. B. Valhalla 13504 im Ubisoft-Shop gegenüber 7013 auf Steam. [S] Steam-Kopien deshalb immer über -applaunch starten, nicht über uplay://.
- [B] Neu seit 10.09.2026: Mit „Ubisoft Connect Services“ läuft Prince of Persia: The Lost Crown auf Steam ohne Ubisoft-Launcher, nur mit verknüpftem Konto. Weitere Titel sollen folgen (TechSpot). Das wäre Phase 0.

#### Epic-Fall [Q]

- Siehe 1.7: UbisoftConnectInstaller.exe /S, einmal legendary activate --uplay, danach legendary launch --ubisoft → wine start "uplay://launch/<GameID>?…".
- Ab legendary 0.21.0 (08/2026). Heroic 2.22 mit legendary 0.20.43 konnte diese Spiele nicht starten (Heroic #5805).
- Auch bei Heroic bleibt Ubisoft Connect nach dem Spiel offen ([#2962](https://github.com/LordHayne/Nightforge/issues/2962)). Der Wiki-Workaround ist pkill -f Ubisoft -9.

#### Automatisierung

- Stille Installation [Q]: NSIS mit /S, belegt durch winetricks, Heroic und Bottles. Ziel ist C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\.
- Einstellungen vorbelegen [Q Bottles]: …\AppData\Local\Ubisoft Game Launcher\settings.yml (in manchen Quellen .yaml):`offline: true` hatte laut Notebookcheck (02/2026) keine Wirkung. Die Schlüssel `gpu_acceleration` und `forceoffline` existieren laut Recherche nicht.
- Direkter Start [Q Bottles]: UbisoftConnect.exe uplay://launch/<id>/0. Installierte Spiele stehen unter HKLM\SOFTWARE\Ubisoft\Launcher\Installs\<id>\InstallDir.
  - [S] Für Nightforge: zuerst upc.exe mit den Schaltern starten, dann wine start uplay://launch/<id>/0, damit die laufende Instanz den Auftrag übernimmt.

- IDs: AC Valhalla 13504, Anno 1800 4553, Trackmania 5595 [Q umu-database]. AC Origins 3539, AC Odyssey 5059, AC Mirage 6100, Far Cry 5 1803, Far Cry 6 5266 [B].
- Prozesskette [B]: upc.exe -upc_game_starter … → UbisoftGameLauncher.exe → Spiel. Die CEF-Hilfe ist UplayWebCore.exe.
- Spielende: Die Spiel-EXE beobachten. Danach upc.exe schließen (closebehavior sorgt dafür, dass WM_CLOSE wirklich beendet), notfalls hart.

#### Anti-Cheat und Online

Stand bei AreWeAntiCheatYet unter Linux [Q]:

| Spiel | Anti-Cheat | Status |
|---|---|---|
| Rainbow Six Siege / Siege X | BattlEye u. a. | Denied |
| The Division 2 | EAC | Supported |
| For Honor | EAC | Supported |
| Ghost Recon Breakpoint | BattlEye | Supported |
| Ghost Recon Wildlands | EAC | Broken |
| The Crew 2 | BattlEye | Broken |
| The Crew Motorfest | BattlEye | Supported |

- [S] Auf dem Mac gilt „Supported“ trotzdem nicht. „Supported“ beruht auf den Linux-Laufzeiten von EAC und BattlEye, die es unter Wine auf dem Mac nicht gibt. Geschützter Mehrspieler fällt also aus.
- Online-Pflicht: Einzelspieler mit Denuvo braucht beim ersten Start eine Online-Prüfung (z. B. AC Shadows) [B]. Der Offline-Modus geht nur nach einer früheren Online-Anmeldung.
- Am Mac nativ: AC Shadows ist nativ für Apple Silicon (Mac App Store). Von AC Mirage gibt es nur die iPhone/iPad-Fassung.

#### Konkrete Schritte für Nightforge

1. Zuerst testen, nicht bauen. Mit winecx:Zeichnet das Login und klappt die Anmeldung, weiter mit 2. Sonst Ubisoft zurückstellen und Phase 0 nutzen („Ubisoft Connect Services“ auf Steam).
  - UbisoftConnectInstaller.exe /S,
  - Einstellungen vorbelegen,
  - WINE_SIMULATE_WRITECOPY=1,
  - upc.exe -upc_desktop_mode --no-sandbox --in-process-gpu --disable-gpu.

2. Steam-Kopien per -applaunch starten. Ubisoft Connect nach dem Spielende schließen.
3. Epic-Kopien: einmal legendary activate --uplay, dann --ubisoft.

#### Stolpersteine

- Der versionsgebundene CEF-Patch: jedes Ubisoft-Update kann ihn brechen.
- Software-Rendering macht die Oberfläche träge.
- Ubisoft Connect bleibt hängen.
- Die IDs unterscheiden sich je nach Shop.

#### Quellen

- winecx (`dlls/ntdll/loader.c`

, `dlls/kernelbase/process.c`

): https://github.com/dappermint/winecx/tree/wine1119
- Cosmopolitan PR 22: [cyber-prinzesse/Cosmopolitan#22](https://github.com/cyber-prinzesse/Cosmopolitan/pull/22)
- mapc-engine [abduzeedo/mapc-engine#9](https://github.com/abduzeedo/mapc-engine/issues/9): [abduzeedo/mapc-engine#9](https://github.com/abduzeedo/mapc-engine/issues/9)
- Highball-Rezept: https://github.com/gauthierpiarrette/highball-db/blob/HEAD/recipes/launchers/ubisoft-connect.json
- Heroic-Wiki: https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/How-to-install-Ubisoft-Connect-on-Linux-and-Mac
- Heroic [Heroic-Games-Launcher/HeroicGamesLauncher#5805](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/5805) und [Heroic-Games-Launcher/HeroicGamesLauncher#2962](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/2962): [Heroic-Games-Launcher/HeroicGamesLauncher#5805](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/5805) · [Heroic-Games-Launcher/HeroicGamesLauncher#2962](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/2962)
- winetricks (Verb ubisoftconnect): https://github.com/Winetricks/winetricks/blob/master/src/winetricks
- Bottles:
  - https://github.com/bottlesdevs/programs/blob/main/Games/ubisoftconnect.yml
  - https://github.com/bottlesdevs/Bottles/blob/main/bottles/backend/managers/ubisoftconnect.py

- umu-protonfixes: https://github.com/Open-Wine-Components/umu-protonfixes/tree/master/gamefixes-steam
- Proton [ValveSoftware/Proton#5212](https://github.com/ValveSoftware/Proton/issues/5212), [ValveSoftware/Proton#6507](https://github.com/ValveSoftware/Proton/issues/6507), [ValveSoftware/Proton#6528](https://github.com/ValveSoftware/Proton/issues/6528): [ValveSoftware/Proton#5212](https://github.com/ValveSoftware/Proton/issues/5212) · [ValveSoftware/Proton#6507](https://github.com/ValveSoftware/Proton/issues/6507) · [ValveSoftware/Proton#6528](https://github.com/ValveSoftware/Proton/issues/6528)
- Lutris [lutris/lutris#5412](https://github.com/lutris/lutris/issues/5412): [lutris/lutris#5412](https://github.com/lutris/lutris/issues/5412) · Whisky [Whisky-App/Whisky#1004](https://github.com/Whisky-App/Whisky/issues/1004): [Whisky-App/Whisky#1004](https://github.com/Whisky-App/Whisky/issues/1004)
- Ubisoft-IDs: https://github.com/Haoose/UPLAY_GAME_ID
- Ubisoft Connect Services: https://techspot.com/news/113817-ubisoft-finally-testing-way-ditch-own-connect-launcher.html
- Offline-Modus: https://www.notebookcheck.net/How-to-run-Ubisoft-Connect-in-offline-mode.1164697.0.html
- AreWeAntiCheatYet: https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet/blob/master/games.json

---

### 6. Empfohlene Reihenfolge

| Phase | Was | Warum zuerst bzw. später |
|---|---|---|
| **0 – sofort** | Steam-Fassungen ohne Fremd-Launcher: Overwatch 2, Diablo IV, D2R (nur Kontoverknüpfung), Split Fiction, It Takes Two, Dragon Age: The Veilguard, PoP: The Lost Crown. Profil-Korrekturen: GTA V nur online sperren, Javelin-Liste ergänzen, Overwatch‑2-Eintrag prüfen. | Kein Launcher, also kaum Code. Nur Profildaten und der Hinweis „Konto einmal verknüpfen“. Für die Blizzard-Spiele macOS ≥ 26.5 voraussetzen (Rosetta-Hänger). |
| **1** | **Rockstar über Steam, danach Epic** (GTA V Legacy, RDR2) | Die meistgewünschten Spiele, und der Story-Modus läuft offline. Am Mac auf demselben Engine-Stamm belegt (Highball, frankea). Steam übernimmt die ganze Kette, der Launcher startet das Spiel selbst. Für Epic gibt es mit der Attrappe eine fertige, MIT-lizenzierte Lösung. Die Bausteine, die hier entstehen (Schalter-Mechanik, AppDefaults, Spielende-Phasen, sauberes Beenden), braucht jeder weitere Launcher. |
| **2** | **Battle.net-Client** (für direkt bei Blizzard gekaufte Spiele) | Technisch am besten dokumentiert: Startcodes, Config-Schalter, D4Mac als Swift-Vorlage auf fast gleichem Stack, DroidDeck für den Ablauf. Später als Rockstar, weil die Hauptspiele über Steam (Phase 0) schon ohne Client laufen. |
| **3** | **EA app** (Sims 4, Mass Effect LE, Dead Space, Jedi) | Machbar mit Protons Reparaturschritten, aber die wackeligste App mit dem höchsten Pflegeaufwand. Die zugkräftigsten EA-Spiele (FC, Battlefield) bleiben wegen Javelin ohnehin gesperrt. |
| **4** | **Ubisoft Connect** | Auf freiem Wine derzeit nicht verlässlich darstellbar. Erst angehen, wenn der Test aus Abschnitt 5 grün ist. Bis dahin auf „Ubisoft Connect Services“ bei Steam setzen. |

---

### 7. Checkliste für den Live-Test

Reihenfolge für den ersten Abend, jeweils im Nightforge-Steam-Prefix auf winecx 4.7.3:

1. Rockstar installieren: Rockstar-Games-Launcher.exe /s /f ausführen. Prüfen, ob HKLM\SOFTWARE\WOW6432Node\Rockstar Games\Launcher\InstallFolder gesetzt ist und der Dienst Rockstar Service existiert.
2. Rockstar-Login: Launcher.exe starten, einmal ohne Schalter, einmal mit -scDisableGpu, einmal mit DXVK-AppDefaults plus d3d12 aus. Wann zeichnet das Login? Zeitzone und Fehler #1.000.7 beobachten.
3. GTA V oder RDR2 über Steam (-applaunch): Startet der Launcher das Spiel ohne Klick? Taucht die Spiel-EXE auf? Endet nach dem Beenden PlayGTAV.exe/PlayRDR2.exe, oder hängt Launcher.exe in SHUTDOWN_IN_PROGRESS?
4. GTA V mit `-nobattleye`: Startet der Story-Modus?
5. Battle.net: Installer, dann Battle.net.exe --in-process-gpu --use-gl=swiftshader mit WINE_SIMULATE_WRITECOPY=1. Zeichnet das Login? Danach --exec="launch Fen" bzw. "launch Pro".
6. EA app: EAappInstaller.exe /passive /norestart EAX_LAUNCH_CLIENT=0 IGNORE_INSTALLED=1. Steht der Symlink EA Desktop\EA Desktop? Läuft EABackgroundService? Zeichnet das Login mit DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN=1?
7. Ubisoft: /S, Einstellungen vorbelegen, upc.exe -upc_desktop_mode --no-sandbox --in-process-gpu --disable-gpu mit WINE_SIMULATE_WRITECOPY=1. Zeichnet das Login?
8. Logs sichern:
  - Rockstar: C:\ProgramData\Rockstar Games\Launcher\service_log.txt, Documents\Rockstar Games\Launcher\launcher.log
  - Battle.net: …\ProgramData\Battle.net\Agent\ (Logs)
  - Nightforge: GameLog mit WINEDEBUG
