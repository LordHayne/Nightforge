<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHS1f55w82yCUceRqAQ (1.11.2026) -->

## Nightforge läuft schon auf dem Stand von CrossOver 26.3

### 1. Kurzfassung und Empfehlung

**Die Ausgangsannahme stimmt nicht: winecx-gptk 4.7.3 liegt nicht hinter CrossOver 26.x zurück.** Auf der Wine-Seite steckt CrossOver 26.3.0 bereits drin, dazu neueres Upstream-Wine. Nightforge pinnt den Engine-Commit `e0aa380` aus `dappermint/winecx`. Dessen Git-Historie enthält, selbst geprüft:

- 9e92b77 crossover 26.3 on wine 11.0
- 84c0ec9 merge wine 11.15 into crossover 26.3
- 32df075 merge wine 11.16
- 5a5cf05 feat(wine): merge wine 11.17

Beleg: [dappermint/winecx Commit e0aa380](https://github.com/dappermint/winecx/commit/e0aa380780b73e20fabcfe78fd42713b94929a53).

26.3.0 ist auch der **neueste Quellstand, den CodeWeavers veröffentlicht hat**. Quellen für 26.4, 27 oder die Preview-Builds gibt es nicht ([calimocho Issue #8](https://github.com/dragoshont/calimocho/issues/8)). Auf der Wine-Seite ist „Stand CrossOver 26.x“ also schon erreicht.

Bei der Grafik ist Nightforge CrossOver voraus: D3DMetal 4.0b3 statt 3.0 und DXMT 0.80 statt 0.72. Welche DXMT-Version CX 26.3 genau mitbringt, ist widersprüchlich belegt (unsicher).

Was tatsächlich fehlt:

- Upstream-Wine 11.18 bis 11.21. Wichtig sind vor allem:
  - der SpatialMixer-Downmix in winecoreaudio.drv aus Wine 11.21 (Commit 0c61795 von Zhiyi Zhang, CodeWeavers). Er fehlt in CX 26.3, in 4.7.3 und in 4.8.1.
  - die wined3d-Arbeit an der CS-Queue aus 11.20.

- Die unveröffentlichte Preview- und 27-Arbeit von CodeWeavers. Sie zielt auf ARM64 und nur noch Apple Silicon.

Dazu kommt ein **im Code nachgewiesener msync-Fehler im CX-26.3-Baum**: Beim Ende eines Threads wird ein msync-Index geschlossen, als wäre er ein Dateideskriptor.

Gegen den Overwatch-Hänger hilft deshalb vor allem **macOS 26.5 oder neuer**, nicht eine neue Engine. CodeWeavers nennt zwei Voraussetzungen: die Wine-Änderungen aus 26.1, die in 4.7.3 schon enthalten sind, **und** die Rosetta-Änderungen aus macOS 26.5 ([CodeWeavers-Blog, 18.05.2026, nur als Suchsnippet gelesen](https://www.codeweavers.com/blog/mjohnson/2026/5/18/finally-diablo-iv-and-overwatch-are-playable-with-crossover-261-macos-265)).

**Empfehlung: Option (d), eine Mischform.** dappermints Runtime 4.7.3 bleibt die gepinnte Basis. Nightforge legt eigene Unix-Module darüber, gebaut aus demselben winecx-Commit. So arbeitet `gamepad.yml` heute schon für `winebus.so`.

**Konkrete Schritte**

1. Sofort, ohne Code: Auf dem Test-Mac sw_vers -productVersion prüfen.
  - Ist die Version kleiner als 26.5, zuerst macOS aktualisieren.
  - Danach Overwatch auf 4.7.3 neu testen, je einmal mit D3DMetal 4.0b3 und mit DXMT 0.80. Die belegten Overwatch-Setups auf CX-26.3-Wine nutzen DXMT.
  - Zusätzlich ein Lauf ohne msync (WINEMSYNC nicht setzen).
  - Das Steam-Symptom (0 % CPU, kein Fenster) passt zum dokumentierten Hänger vor macOS 26.5. Für die Steam-Version von Overwatch gibt es aber keine Quelle (unsicher).

2. Audio-Schnelltest: In Audio-MIDI-Setup das Ausgabeformat von „7.1 Wide“ auf „7.1 Surround“ stellen, danach auf Stereo. Verschwindet das Echo, stützt das die Vermutung eines Konflikts der Kanalmasken (Abschnitt 4).
3. msync-Fix als Patch: `engine/patches/winecx-ntdll-msync-alert-fd.patch` ersetzt in pthread_exit_wrapper (`dlls/ntdll/unix/thread.c`) das bedingungslose close( data->alert_fd ); durch if (!do_msync()) close( data->alert_fd );. Denselben Fix in `engine/patches/wine-11.18-msync.patch` nachziehen, für das Paket aus graphics.yml.
4. Downmix zurückportieren: Die fünf Wine-11.21-Commits 199ae1d, d20f6c7, 3e29c36, 8cf6408 und 0c61795 als `engine/patches/winecx-winecoreaudio-spatialmixer.patch` auf e0aa380 übertragen.
5. Overlay-Workflow nach dem Vorbild von `gamepad.yml`: Er baut aus dappermint/winecx @ e0aa380 nur ntdll.so und winecoreaudio.so. Beides erscheint als Nightforge-Release mit Quell-Asset (Abschnitt 7).
6. Manifest und App:
  - Neue Komponente in `components/sources.json`, z. B. enginefix, mit kind graphics wie gamepad.
  - In der App ein installEngineFix analog zu installGamepad. Es greift nur bei der passenden Runtime-Version.
  - winecx bleibt auf runtime-v4.7.3 gepinnt.

7. Upstream:
  - Ein Issue bei dappermint mit dem alert_fd-Fix und der Bitte um eine 11.21-Lane oder einen Cherry-Pick des Downmix.
  - Den Pin erst auf 4.7.4 oder 4.8.1 heben, wenn Issue [#24](https://github.com/LordHayne/Nightforge/issues/24) geklärt ist. Dort sind Regressionen gegenüber 4.7.3 gemeldet.
  - Beim Wechsel des Pins WINECX_COMMIT in gamepad.yml und im neuen Workflow mitziehen.

8. Plan B vorbereiten: ein eigener Workflow, der die ganze Engine aus dappermint/winecx baut, nicht aus dem rohen CX-Tarball. Er greift, falls dappermint stehen bleibt. Die Fristen:
  - nixpkgs führt x86_64-darwin nur bis Ende 2026.
  - macos-15-intel läuft bis August oder Herbst 2027.
  - Rosetta endet weitgehend mit macOS 28.

Die Schritte 1 und 2 kosten nichts und gehen sofort. Die Schritte 3 bis 8 passen in die Zeit nach dem Release 0.3.0, wie es für die Engine-Arbeit geplant ist.

### 2. Was CrossOver 26.x bringt

| Bereich | CrossOver 26.x | winecx-gptk 4.7.3 (Nightforge heute) | Gewinn für Nightforge | Sicherheit / Beleg |
|---|---|---|---|---|
| Wine-Basis | Wine 11.0 in allen Versionen 26.0 bis 26.3 ([dappermint/winecx Tag winecx-26.3.0](https://github.com/dappermint/winecx/tree/winecx-26.3.0)) | CX-26.3-Baum plus Wine 11.15 bis 11.17; `VERSION` ist „Wine version 11.17“ ([VERSION @ e0aa380](https://github.com/dappermint/winecx/blob/e0aa380780b73e20fabcfe78fd42713b94929a53/VERSION)) | Keiner, 4.7.3 ist neuer | Geprüft in Git |
| Blizzard-/Rosetta-Fix | „Wine changes in CrossOver 26.1“ plus Rosetta-Änderungen in macOS 26.5 | Alle Rosetta-CW-Hacks des 26.3-Baums sind da. Neu in 26.x: 25719 (Exec-Fault) und 26470/26456 (16-Bit-LDT). Dazu 18947, 24945, 24256, 24265, 23427 und 22131 | Von der Engine keiner. Der Hebel ist macOS ≥ 26.5 | Code geprüft ([virtual.c @ winecx-26.3.0](https://github.com/dappermint/winecx/blob/winecx-26.3.0/dlls/ntdll/unix/virtual.c)). Welche Commits die „26.1-Änderungen“ sind, ist **unbestätigt**. CodeWeavers-Aussage nur als Snippet ([CW-Blog](https://www.codeweavers.com/blog/mjohnson/2026/5/18/finally-diablo-iv-and-overwatch-are-playable-with-crossover-261-macos-265)) |
| D3DMetal | 3.0 ([Phoronix, Snippet](https://www.phoronix.com/news/CrossOver-26)) | Nicht im Tarball; Nightforge liefert 4.0b3 separat ([build.yml @ 4.7.3](https://github.com/dappermint/winecx-gptk/blob/runtime-v4.7.3/.github/workflows/build.yml#L838-L859)) | Keiner. CodeWeavers’ „läuft“-Aussagen gelten für 3.0, nicht für 4.0b3 | Snippets; welches macOS 4.0b3 mindestens braucht, ist **unsicher** |
| DXMT | Laut Snippets v0.72; das Endfield-Wiki sagt 0.80 ([Endfield-Wiki](https://github.com/stoicswe/Endfield_FineWine/wiki/graphics_backends)) | 0.80 von 3Shain und Nightforges eigener 0.80-Build mit Patches | Keiner. Interessanter sind DXMT-Upstream nach 0.80 und der Overwatch-Fork mit `releaseShaderIR` | **Unsicher**, Quellen widersprechen sich |
| DXVK / MoltenVK | Versionen unbekannt. Laut Traxis liegt ein `dxvk/` 1.10.3 im Archiv; das ist umstritten | DXVK-macOS 1.10.3 async (Gcenx), MoltenVK 1.4.2 | Keiner | Unsicher |
| wined3d / D3D9 | D3D9 läuft über wined3d auf OpenGL (CW HACK 18311). Dazu `multiply_special` und abschaltbares `csmt`. Einen eigenen CX-Weg für D3D9 gibt es nicht | Dasselbe, plus Wine-Änderungen bis 11.17 | Gering. Es fehlen 11.18 (Vertex Blending) und 11.20 (CS-Queue) | Code geprüft; Wine-ANNOUNCE |
| Audio-Downmix (Wine 11.21) | Nicht enthalten. CX ändert `winecoreaudio.drv` nur für die Mikrofonfreigabe | Nicht enthalten, auch nicht in 4.7.4 und 4.8.1 | **Hoch** für Mehrkanal-Spiele (GTA V Enhanced, Lego Star Wars). Plausibel auch für das Echo bei „7.1 Wide“ | Commit geprüft ([wine-mirror 0c61795](https://github.com/wine-mirror/wine/commit/0c61795bfd04e290fb3966cb0f62f869d0d84443)). Der Bezug zum Echo ist eine **Vermutung** |
| Remedy / Control | Keine Hacks für Remedy oder Northlight (0 Treffer im Diff) | Keine | Keiner | Geprüft (Suche im Diff) |
| Launcher-Fixes (Battle.net, Epic, GOG) | 26.1: Battle.net-Installation. 26.3: Epic-Downloads, GOG Galaxy. Zugehörige Hacks: 23881/27245 (ACLs für `Agent.exe` und `EpicGamesLauncher.exe`), Epic-Winstation, 24199, Rockstar 18582/23741, Ubisoft 19252 | Im Baum vorhanden, aus 26.3 übernommen | Keiner, alles schon da | Hacks geprüft ([advapi32/security.c](https://github.com/dappermint/winecx/blob/winecx-26.3.0/dlls/advapi32/security.c)). Die Zuordnung zu den Changelog-Punkten ist **unbestätigt** |
| msync | msync seit 25.x; NTSync nur unter Linux | msync plus dappermints Verbesserungen. **Fehler:** `pthread_exit_wrapper` schließt unter msync einen Index als Dateideskriptor | Einzeiler-Fix in eigener Hand | Code geprüft ([thread.c @ e0aa380](https://github.com/dappermint/winecx/blob/e0aa380780b73e20fabcfe78fd42713b94929a53/dlls/ntdll/unix/thread.c#L1119)). Dass der Fehler Overwatch abstürzen lässt, ist **unbestätigt** ([Recall](https://github.com/AsherJN/recall/blob/main/patches/README.md)) |

### 3. Quellen und Bau: CodeWeavers liefert Tarballs, die Community baut

#### CodeWeavers veröffentlicht nur Tarballs, der letzte ist 26.3.0

CodeWeavers stellt die Quellen als `crossover-sources-<version>.tar.gz` unter `https://media.codeweavers.com/pub/crossover/source/` bereit. Verlinkt sind sie auf der Seite „Download FOSS Code for CrossOver 26.3.0“ ([CodeWeavers-Quellseite, Snippet](https://www.codeweavers.com/crossover/source)). Mehrere Build-Repos pinnen diese URL ([dungeons-for-mac inputs.json](https://github.com/MrStickman202/dungeons-for-mac/blob/HEAD/engine/inputs.json), [highball-engine inputs.json](https://github.com/gauthierpiarrette/highball-engine/blob/HEAD/inputs.json), [traxis-runners README](https://github.com/ziyabnajeeb/traxis-runners/blob/HEAD/README.md)). Eine API gibt es nicht. calimocho erkennt neue Drops, indem es die Seite per Regex ausliest ([calimocho versions.json](https://github.com/dragoshont/calimocho/blob/HEAD/versions.json)).

Es gibt einen älteren FTP-Spiegel unter `ftp.codeweavers.com`. Ihn nutzt noch der offizielle MacPorts-Port ([MacPorts wine-crossover Portfile](https://github.com/macports/macports-ports/blob/master/x11/wine-crossover/Portfile)). Laut einem Community-Wiki liefert das Verzeichnislisting automatisierten Abrufen HTTP 403 ([Endfield-Wiki: building_crossover_wine](https://github.com/stoicswe/Endfield_FineWine/wiki/building_crossover_wine); unsicher). Den Tarball selbst kann CI aber mit `curl -sSfL` laden ([dungeons-for-mac sources.yml](https://github.com/MrStickman202/dungeons-for-mac/blob/HEAD/.github/workflows/sources.yml)).

| Version | Binär-Release | Quell-Tarball | Größe / SHA-256 | Wine-Basis |
|---|---|---|---|---|
| 26.0.0 | 10.02.2026 | Ja; Gcenx hat ihn kompiliert | Unbekannt | 11.0 |
| 26.1.0 | 09.04.2026 | Ja | SHA-256 `e4ec87d5821a009dd1f1d2e36ffe2e24b8fcbae9516375ea42f95a16928ab8fa` ([calimocho](https://github.com/dragoshont/calimocho/blob/HEAD/versions.json)) | 11.0 |
| 26.2.0 | 09.06.2026 | Kein Beleg | – | Wohl 11.0 (unbestätigt) |
| 26.3.0 | 21.07.2026 | Ja | **149.054.023 Byte**, SHA-256 `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872` | 11.0 |
| 26.4, 27, Preview | – | Keiner gefunden | – | – |

Die Termine der Binär-Releases stammen aus Gcenx’ MacPorts-Overlay ([Gcenx/macports-wine crossover Portfile](https://github.com/Gcenx/macports-wine/blob/HEAD/emulators/crossover/Portfile)) und aus Snippets des Changelogs. Der offizielle Homebrew-Cask `crossover` steht auf 26.3.0 ([homebrew-cask crossover.rb](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/c/crossover.rb)).

**Inhalt des Tarballs:**

- Oben liegt sources/, der Wine-Baum ist sources/wine.
- Eine Community-Liste nennt android, cabextract, freetype, glib, gnutls, makedep, moltenvk, po4a, vkd3d, wine (Endfield-Wiki). Das ist möglicherweise der Stand von 26.2.
- clang und llvm sind nicht mehr dabei, cx-llvm ist weg.
- Traxis kopiert ein dxvk/ (1.10.3) aus dem 26.3.0-Archiv (traxis build-wine.sh). Ob dxvk/ enthalten ist, bleibt offen.

Wine Mono und Wine Gecko liegen nicht im Tarball. Alle Builder lesen die Versionen aus `dlls/appwiz.cpl/addons.c` und laden sie von dl.winehq.org. Der 26.3-Runner von Traxis nutzt Gecko 2.47.4 und Mono 10.4.1. `e0aa380` pinnt Mono 11.3.0 ([addons.c @ e0aa380](https://github.com/dappermint/winecx/blob/e0aa380780b73e20fabcfe78fd42713b94929a53/dlls/appwiz.cpl/addons.c)).

**Proprietäres fehlt.** CrossOvers `ntdll.so` lädt `cxcompatdb.so`, D3DMetal kommt von Apple. Gcenx schrieb dazu am 29.04.2026: „there’s almost no point in compiling crossover-sources releases as of 25.0.0 as all the really useful hacks have been moved outside of the wine sources“ ([Gcenx im Gist von sarimarton](https://gist.github.com/sarimarton/471e9ff8046cc746f6ecb8340f942647)). Ein Bau aus dem Tarball ergibt also eher „Wine 11.0 plus 221 Dateien CX-Diff“ als „CrossOver ohne Oberfläche“.

**Git-Historie.** `dappermint/winecx` ist ein Fork von PhoenicisOrg/winecx und hat je Drop einen Commit mit Tag: `winecx-18.1.0` bis `winecx-25.1.0` sowie `winecx-26.3.0` vom 13.08.2026. Damit funktioniert `git diff winecx-25.1.0 winecx-26.3.0` ([dappermint/winecx Tags](https://github.com/dappermint/winecx/tags), [PhoenicisOrg/winecx](https://github.com/PhoenicisOrg/winecx)). 26.0, 26.1 und 26.2 sind nirgends importiert. Einen Diff von 26.1 nach 26.3 bekommt man nur, wenn man diese Tarballs selbst importiert.

Weitere Spiegel:

- Gcenx/winecx ist gelöscht. Übrig sind nur die Tags crossover-wine-19.0.0 bis 23.7.1 in Gcenx/game-porting-toolkit.
- TheShellLand/crossover-source hat vollständige Tarballs, aber nur bis 21.2.
- dungeons-for-mac veröffentlicht sources/wine aus 26.3.0 noch einmal als Release-Asset.

#### Wer CrossOver-Wine für macOS baut und wer aufgehört hat

Die Annahme, Gcenx, Homebrew `wine-crossover`, Whisky oder Sikarugir lieferten einen Build von CX 26, stimmt nicht. **Aktuelle CX-26-Builds kommen nur von neueren Projekten.**

| Projekt | Stand 01.11.2026 | Bauweise | Bedeutung für Nightforge |
|---|---|---|---|
| Gcenx (`wine-crossover`, `Gcenx/winecx`) | **Eingestellt.** Cask am 16.04.2026 gelöscht, letzte Version 23.7.1 ([Commit f201026](https://github.com/Gcenx/homebrew-wine/commit/f201026)); das Repo ist weg | – | Keine Quelle für CX 26 |
| Gcenx/macOS_Wine_builds | Upstream-WineHQ 11.21 (31.10.2026), ohne CI-Workflows ([README](https://github.com/Gcenx/macOS_Wine_builds/blob/HEAD/README.md)) | MacPorts mit Overlay, llvm-mingw | Nightforges Legacy-Engine `wine` |
| Gcenx/game-porting-toolkit | 3.0-3 (03.03.2026). Basis ist Apples GPTK-1.1-Formel, also `crossover-sources-22.1.1` ([apple/homebrew-apple](https://github.com/apple/homebrew-apple/blob/main/Formula/game-porting-toolkit.rb)) | Homebrew | Aus der Zeit von Wine 7.7, veraltet |
| Gcenx/macports-wine | CrossOver 26.3.0 nur als **Binär**-Demo; dazu wine-devel 11.21 und llvm-mingw 20261020 ([README](https://github.com/Gcenx/macports-wine/blob/HEAD/README.md)) | MacPorts | Referenzrezept für Wine 11 ([wine-devel Portfile](https://github.com/Gcenx/macports-wine/blob/HEAD/emulators/wine-devel/Portfile)) |
| Homebrew (offiziell) | Kein `wine-crossover`; `wine-stable` 11.0_1 verweist auf Gcenx ([wine-stable.rb](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/w/wine-stable.rb)) | – | – |
| MacPorts (offiziell) | `wine-crossover` 18.5.0 (Wine 4.0) | – | – |
| Whisky | Am 11.05.2025 archiviert; Basis CX 22.1.1 mit GPTK ([Whisky](https://github.com/Whisky-App/Whisky)) | Nicht öffentlich | – |
| Sikarugir | Neueste CX-Engine ist `WS12WineCX24.0.7_7`; CX 25 und 26 fehlen. Am 14.10.2026: „Remove anything incompatible with d3dmetal-4.0b3“ ([EngineList.txt](https://github.com/Sikarugir-App/Engines/blob/main/EngineList.txt)) | Keine öffentlichen Skripte | – |
| dappermint/winecx-gptk | CX 26.3 auf Wine 11.15, 11.16, 11.17 und 11.19 ([README](https://github.com/dappermint/winecx-gptk/blob/main/README.md)) | `macos-26` oder eigener ARM64-Runner, x86_64-Bibliotheken aus nix, mingw-w64 gcc, viele Prüfschritte ([build.yml](https://github.com/dappermint/winecx-gptk/blob/main/.github/workflows/build.yml)) | Heutige Basis |
| highball-engine, dungeons-for-mac | Unverändertes CX 26.3.0 ([highball build.yml](https://github.com/gauthierpiarrette/highball-engine/blob/HEAD/.github/workflows/build.yml), [dungeons build.yml](https://github.com/MrStickman202/dungeons-for-mac/blob/HEAD/.github/workflows/build.yml)) | `macos-15-intel`, Abhängigkeiten aus Homebrew, Deployment-Target 14.0 | Zeigt, dass es auf GitHub-Runnern geht |
| calimocho | CX 26.1.0 ([build.yml](https://github.com/dragoshont/calimocho/blob/HEAD/.github/workflows/build.yml)) | `macos-15` arm64 mit x86_64-Homebrew in `/usr/local` | Muster für x86_64-Bibliotheken auf arm64 |
| Endfield_FineWine | CX 26.3.0, nur 64-Bit ([build-wine.sh](https://github.com/stoicswe/Endfield_FineWine/blob/HEAD/scripts/build-wine.sh)) | Tauscht Dateien in einer lizenzierten CrossOver.app | Kein Vorbild |
| Traxis | CX 26.3.0, alle Komponenten aus dem Tarball ([toolchain.sh](https://github.com/ziyabnajeeb/traxis-runners/blob/HEAD/scripts/toolchain.sh)) | Lokal, llvm-mingw | Muster für selbst gebaute Bibliotheken |

Laut Suchsnippets, nicht geprüft, haben auch [Jason2866/crossover-wine-ci](https://github.com/Jason2866/crossover-wine-ci/releases/tag/26.3.0), [BRYANN2K/cartouche-wine](https://github.com/BRYANN2K/cartouche-wine/releases/tag/wine-crossover-26.3.0-1) und [AliJamalll/game-bridge](https://github.com/AliJamalll/game-bridge/releases/tag/wine-cx-26.3.0) Builds aus 26.3.0 veröffentlicht. [GabLeRoux/macos-crossover-wine-cloud-builder](https://github.com/GabLeRoux/macos-crossover-wine-cloud-builder) endet bei CX 22.0.1.

#### Werkzeuge: die normale Toolchain von Wine 11, aber der Host-Code muss x86_64 sein

CX 26.x braucht **keinen eigenen clang, kein wine32on64 und kein besonderes Configure-Flag**. Laut Gcenx braucht 26.0.0 „not even a single change“ ([Gist](https://gist.github.com/sarimarton/471e9ff8046cc746f6ecb8340f942647)). Alle aktuellen Builder nutzen das neue WoW64 mit `--enable-archs=i386,x86_64`. dappermint prüft das im Build ab: Fehlt die i386-Hälfte, stirbt jedes 32-Bit-Programm mit `c0000135` ([winecx-gptk README](https://github.com/dappermint/winecx-gptk/blob/main/README.md)).

**Der Host-Code muss x86_64 sein.** Der CX-Baum schützt seine Metal-Layer-Klasse mit `#if defined(__x86_64__)`, deshalb scheitert ein arm64-Build in `cocoa_window.m`. Auf arm64-Runnern baut man darum mit `clang -arch x86_64` ([highball README](https://github.com/gauthierpiarrette/highball-engine/blob/HEAD/README.md)). Weitere Vorgaben aus derselben Quelle:

- --with-opengl darf nicht gesetzt sein.
- MoltenVK muss beim Bauen vorhanden sein, sonst bricht `dlls/win32u/vulkan.c` ab.
- Ein CX-Hack nennt den Windows-Benutzer „crossover“; highball nimmt das in Patch 0001 zurück.

Für die PE-Hälfte nehmen winecx-gptk, highball und dungeons **mingw-w64 gcc** aus Homebrew. Grund ist ein Befund vom 04.08.2026: „an llvm-built `kernelbase.dll` stalls steam’s CM login“ ([winecx-gptk build.yml](https://github.com/dappermint/winecx-gptk/blob/main/.github/workflows/build.yml)). gcc schreibt DWARF-Debug-Daten in die PE-Dateien, deshalb wird gestrippt (`ntdll.dll` 3,0 MB statt 0,7 MB).

Weitere Anforderungen:

- bison ≥ 3 (macOS liefert nur 2.3).
- flex, pkg-config, gettext.
- freetype, gnutls und SDL2 als x86_64.
- GStreamer und FFmpeg sind optional. dappermint lässt den Build hart scheitern, wenn sie fehlen, weil Wines configure nur warnt.

Zum Deployment-Target warnt dappermint: Ohne `MACOSX_DEPLOYMENT_TARGET` bekommt jede Binary das `minos` des Build-Rechners. Das Beispiel dort: „v4.0.1 linked pipe2, macOS 27 only, weakly … calls a null pointer“. Daher kommen `-Werror=unguarded-availability-new` und `ac_cv_func_pipe2=no`. Xcode 26 ist nicht nötig: highball und dungeons bauen mit dem Standard-Xcode 16.4 von `macos-15-intel` und Target 14.0.

#### GitHub Actions: machbar, aber mit Ablaufdatum

**Es geht, das zeigen mindestens fünf öffentliche Projekte.** Die Standard-Runner haben ([github/docs supported-github-runners](https://github.com/github/docs/blob/main/data/reusables/actions/supported-github-runners.md)):

- macOS arm64: 3 CPU (M1), 7 GB RAM, 14 GB SSD.
- Intel: 4 CPU, 14 GB RAM, 14 GB SSD.

Ein Job darf 6 Stunden laufen, der Cache fasst 10 GB pro Repo, und Cache-Einträge verfallen nach 7 Tagen ohne Zugriff ([Limits](https://github.com/github/docs/blob/main/content/actions/reference/limits.md), [Caching](https://github.com/github/docs/blob/main/content/actions/reference/workflows-and-actions/dependency-caching.md)).

**Gemessene Dauern:**

- highball auf macos-15-intel: mit warmem Cache 12 bis 29 Minuten, ohne Cache bis 2 h 14 min (highball Actions).
- Endfield, ohne Cache auf dem 3-vCPU-M1: „~1.5-2.5 h“ (Endfield build-wine.yml).
- winecx-gptk: erfolgreiche Läufe 19 bis 28 Minuten, meist auf einem eigenen Runner („self-hosted is ~10x faster“) (winecx-gptk Actions).

Den Speicherbedarf hat niemand gemessen. Ausfälle wegen voller Platte sind nicht dokumentiert.

**Die Risiken sind die Fristen:**

- macos-15-intel ist das letzte x86_64-Image und bleibt bis August 2027 (runner-images #13045). Das GitHub-Changelog nennt dagegen „Fall 2027“ (GitHub Changelog).
- Homebrew hat seine Intel-CI am 28.08.2026 abgeschaltet und baut keine Intel-Bottles mehr (Homebrew Discussion #7044).
- nixpkgs führt x86_64-darwin nur bis Ende 2026 (winecx-gptk build.yml @ 4.7.3).
- Rosetta 2 endet weitgehend mit macOS 28 im September 2027 (highball README).

Für Nightforge bleibt arm64 (`macos-15` oder `macos-26`) mit `clang -arch x86_64` der Weg mit Zukunft, und so baut Nightforge heute schon. Nur die x86_64-Laufzeitbibliotheken brauchen eine eigene Quelle.

### 4. Was CrossOver 26.x gegenüber 4.7.3 ändert und was nicht

#### 4.7.3 ist der CX-26.3-Baum auf Wine 11.17

Neben der Commit-Kette oben belegt das auch der Tag `winecx-26.3.0`. Seine Nachricht lautet „imported from crossover-sources-26.3.0.tar.gz, sources/wine … wine 11.0 base, where 25.1.0 was wine 10.0“. Sein Tree-Hash ist identisch mit `9e92b77`, der Basis der Merges ([Tag winecx-26.3.0](https://github.com/dappermint/winecx/tree/winecx-26.3.0)).

Die Merge-Nachricht von `84c0ec9` nennt 32 Dateien mit Konflikten. Ganz verworfen wurde CW Hack 24557. Behalten wurden die für den Mac wichtigen Hacks: 24067, 24265 (Rosetta-mxcsr-Thunk), 24256 (Rosetta-Erkennung), 22435 (D3DMetal Client Surface), 23422, 21897 sowie die msync-Anbindung im Server ([Commit 84c0ec9](https://github.com/dappermint/winecx/commit/84c0ec92b161caf8cee034656d58379f6af32f3d)).

Ein Abgleich der Hack-Markierungen zwischen CX 26.3 und `e0aa380` zeigt nur wenige Unterschiede ([dappermint/winecx](https://github.com/dappermint/winecx)):

- Entfallen sind Bug 10151 (Suche nach dem gnutls-Soname), 26536 (Helldivers-Icon) und zweimal 22310 (AUMID).
- 24067 ist nur verschoben.
- In signal_x86_64.c (13) und virtual.c (4) ist die Zahl der Markierungen unverändert.

CX 26.3 ändert 221 Dateien gegenüber Wine 11.0. In 4.7.3 weichen davon noch 199 vom reinen Upstream-11.17 ab. Die übrigen 22 hat CodeWeavers vermutlich upstream gebracht (Schlussfolgerung). Ein Restrisiko bleibt: Die für Rosetta wichtigen ntdll-Dateien lagen unter den 32 Konfliktdateien. Ein Merge-Fehler ist unwahrscheinlich, aber nicht ausgeschlossen.

#### Changelogs: kurze Listen, keines der Zielspiele genannt

Eine vollständige Spieleliste pro Version gibt es nicht. Die Changelog-Seite ist laut Snippet unordentlich: kaputte Aufzählungspunkte, Office- und Quicken-Zeilen dazwischen, sehr alte Einträge daneben ([CodeWeavers-Changelog, Snippet](https://www.codeweavers.com/crossover/changelog)).

- 26.0 (10.02.2026): Basis Wine 11.0, D3DMetal 3.0, DXMT 0.72, vkd3d 1.18, Mono 10.4.1, NTSync für Linux. Die Berichte nennen Helldivers 2, Clair Obscur: Expedition 33, Kingdom Come: Deliverance II, God of War Ragnarök, Starfield, Final Fantasy VII Rebirth, Age of Empires IV AE, Borderlands 4, Mafia: The Old Country, Cronos und CloverPit (CodeWeavers-Blog 10.02.2026, Snippet, AppleInsider, Snippet). Keines der zehn Zielspiele ist dabei.
- 26.1 (09.04.2026): Workaround für Death Stranding 2, Mausfix für viele Unity-Spiele, Battle.net-Installation (devbytes, Snippet).
- 26.2 (09.06.2026): Helldivers 2 startet nach einem Spiel-Update wieder; Warnungen für 32-Bit-Bottles (PlayingTux, Snippet).
- 26.3 (21.07.2026): Diablo IV startet nach einem Update wieder; Epic-Downloads, GOG Galaxy, Oberfläche für Tahoe (Wine Reviews, Macworld, Snippet).

Der Wine-Anteil all dieser Punkte steckt in 4.7.3. Ohne die Tarballs 26.0 bis 26.2 lassen sich einzelne Code-Stücke aber nicht zuordnen.

#### Blizzard: ein Rosetta-Fehler, behoben durch CX 26.1 plus macOS 26.5

CodeWeavers schreibt: „You need both Wine changes in CrossOver 26.1 in addition to Rosetta changes in macOS 26.5. Using earlier versions of either one will not bring you joy.“ Vorher liefen Diablo IV und Overwatch nur in Preview-Builds, mit einem „imperfect fix“ ([CodeWeavers-Blog 18.05.2026, Snippet](https://www.codeweavers.com/blog/mjohnson/2026/5/18/finally-diablo-iv-and-overwatch-are-playable-with-crossover-261-macos-265)). **macOS 26.5 ist also nötig.**

Ein Thread im Apple-Entwicklerforum („Rosetta 2 Deadlock on M4 Pro“) beschreibt einen Deadlock in OW2, D4 und D2R seit dem Blizzard-Update vom Januar 2026. Er nennt FB21838832, FB15880492 und FB21763885, aber keine Version mit dem Fix ([Apple Developer Forums 814383](https://developer.apple.com/forums/thread/814383)). D4Mac findet den hängenden Thread in `os_sync_wait_on_address` in Apples `libd3dshared.dylib`. Auslöser ist laut D4Mac, dass Blizzards Anti-Cheat übersetzte x86_64-Codeseiten liest ([D4Mac README](https://github.com/MichaelLod/D4Mac)).

Recall ist ein freier Overwatch-Launcher auf Basis von CX-26.3-Wine mit DXMT. Er verlangt zwingend macOS 26.5 („macos_26_5_required“) ([AsherJN/recall](https://github.com/AsherJN/recall)). Laut seinen Release Notes haben ältere macOS-Versionen einen Rosetta-Fehler, „that stops the game before its window opens“ ([Recall Releases, Snippet](https://github.com/AsherJN/recall/releases)). Genau dazu passt Nightforges Symptom auf Steam: 0 % CPU, kein Fenster. Dass der Anti-Cheat der Auslöser ist, sagen nur Nutzer. Ob es Warden oder „Eidolon“ ist, bleibt widersprüchlich.

**Welche Commits die „26.1-Änderungen“ sind, ist unbestätigt.** Zwei Kandidaten, beide nur vermutet ([virtual.c @ winecx-26.3.0](https://github.com/dappermint/winecx/blob/winecx-26.3.0/dlls/ntdll/unix/virtual.c)):

- CW Hack 25719 schaltet bei Exec-Faults das Exec-Bit um; er fehlt in 25.1.
- CW HACK 18947 erzwingt nach einem prozessübergreifenden NtWriteVirtualMemory, dass Rosetta den Code neu übersetzt.

Beide sind in 4.7.3 vorhanden. Ebenfalls vorhanden sind CW HACK 23560, der die GPU-LUIDs zwischen setupapi und D3DMetal-dxgi für `Diablo IV.exe` angleicht ([setupapi/devinst.c](https://github.com/dappermint/winecx/blob/winecx-26.3.0/dlls/setupapi/devinst.c)), und die Battle.net-ACL-Hacks ([advapi32/security.c](https://github.com/dappermint/winecx/blob/winecx-26.3.0/dlls/advapi32/security.c)).

**Neu geprüft:** Nach Season 14 (Patch 3.1.0) meldete Diablo IV einen Fehler zu `FindNextFileNameW`, und nur die Preview behob ihn ([CodeWeavers-Forum D4, Snippet](https://www.codeweavers.com/compatibility/crossover/forum/diablo-iv?msg=355134)). Die Funktion wird in CX 26.3, in `e0aa380` und in Upstream-Wine 11.21 zwar exportiert, ist aber überall nur ein Stub (`FIXME … stub`, `ERROR_CALL_NOT_IMPLEMENTED`) ([kernelbase/file.c @ e0aa380](https://github.com/dappermint/winecx/blob/e0aa380780b73e20fabcfe78fd42713b94929a53/dlls/kernelbase/file.c), [kernelbase/file.c @ wine-11.21](https://github.com/wine-mirror/wine/blob/wine-11.21/dlls/kernelbase/file.c)). Ob genau das die Ursache ist, ist unbestätigt. Wenn ja, hilft weder ein Bau aus den 26.3-Quellen noch Wine 11.21.

D2R ist mit 26.1 und macOS 26.5 spielbar, „if you do not lose focus“. Ein Absturz nach Cmd-Tab wurde noch untersucht (Blog, Snippet).

#### Grafik: Nightforge ist CrossOver voraus

CX 26.x liefert D3DMetal 3.0 und laut Snippets DXMT v0.72 ([Phoronix, Snippet](https://www.phoronix.com/news/CrossOver-26), [MacHow2, Snippet](https://machow2.com/crossover-mac-review/)). Das Endfield-Wiki nennt dagegen DXMT 0.80 samt NGX-Bug ([Endfield-Wiki](https://github.com/stoicswe/Endfield_FineWine/wiki/graphics_backends)). Es hat aber offensichtliche Fehler, etwa „macOS 26 (Sequoia)“; die Angabe bleibt **unsicher**.

Bei Apple ist Game Porting Toolkit 4 aktuell ([Apple GPTK](https://developer.apple.com/games/game-porting-toolkit/)). Zwei Sekundärquellen behaupten, D3DMetal 4 brauche die macOS-27-Beta ([korben.info](https://korben.info/de/game-porting-toolkit-4-windows-spiele-mac-fluessig.html), [Endfield-Wiki gptk4_upgrade](https://github.com/stoicswe/Endfield_FineWine/wiki/gptk4_upgrade)). Das widerspricht Nightforges Betrieb von 4.0b3 auf macOS 26 und ist **unsicher**.

DXMT v0.80 erschien am 23.04.2026 und wechselte von MIT zu LGPL ([3Shain/dxmt Releases](https://github.com/3Shain/dxmt/releases)). Seitdem kamen upstream hinzu: eine D3D12-Implementierung in DXMT, arm64x-Builds, ein Fix für die Xcode-27-Toolchain und einer für einen Absturz in `D3D12CreateDevice()` ([NerRobDog/dxmt Branches](https://github.com/NerRobDog/dxmt)). Für Overwatch wichtig ist der Fork NerRobDog/dxmt v0.80-ow2-0.3 mit `d3d11.releaseShaderIR`. Er senkt den Speicherbedarf von **13 GB auf 3,9 GB** und hebt Killcam- und Respawn-Ruckler von 22 bis 28 auf 59,9 fps, getestet mit CX 26.3 auf macOS 26.5.

Welche DXVK- und MoltenVK-Versionen in CX 26.x stecken, ist nicht belegt. CX wählt das Backend über `CX_ACTIVE_GRAPHICS_BACKEND` (`d3dmetal`, `dxmt`, `dxvk`, `wined3d`). CW HACK 24905 setzt die D3DKMT-Caps je Backend ([win32u/d3dkmt.c](https://github.com/dappermint/winecx/blob/winecx-26.3.0/dlls/win32u/d3dkmt.c)). Zu KosmicKrisp in CrossOver fand sich nichts. dappermint hat dafür nur eine optionale Lane, die nie veröffentlicht wurde und Upstream-DXVK 3.1.1 braucht ([docs/kosmickrisp.md](https://github.com/dappermint/winecx-gptk/blob/main/docs/kosmickrisp.md)).

#### D3D9: kein eigener Weg in CrossOver

CW HACK 18311 wählt das Vulkan-Backend von wined3d nur bei MoltenVK **und** ab D3D10. Für D3D9 gilt „defaulting to the OpenGL backend“ ([wined3d/adapter_vk.c](https://github.com/dappermint/winecx/blob/winecx-26.3.0/dlls/wined3d/adapter_vk.c)). CX 26.3 bringt außerdem `multiply_special` für Shader-Mathematik unter SM < 4 und `csmt`=„disabled“ ([wined3d @ winecx-26.3.0](https://github.com/dappermint/winecx/tree/winecx-26.3.0/dlls/wined3d)). Beides hat 4.7.3 auch.

Neu wären nur Änderungen aus Upstream:

- 11.18: Vertex Blending in process_vertices_strided().
- 11.20: Die Felder der CS-Queue werden an Cache-Lines ausgerichtet, WriteRelease() ersetzt InterlockedExchange(), die Pixel-Shader-ID wird früher verglichen.
- 11.21: Reset der Vulkan-Swapchain, schnelleres OpenGL unter WoW64.

Quellen: [Wine 11.18 ANNOUNCE](https://raw.githubusercontent.com/wine-mirror/wine/wine-11.18/ANNOUNCE.md), [Wine 11.20 ANNOUNCE](https://raw.githubusercontent.com/wine-mirror/wine/wine-11.20/ANNOUNCE.md), [Wine 11.21 ANNOUNCE](https://raw.githubusercontent.com/wine-mirror/wine/wine-11.21/ANNOUNCE.md).

Ein Community-Repo veröffentlicht LGPL-Patches gegen den 26.3-Tarball ([LuidgiAlt/crossover-rosetta-patches](https://github.com/LuidgiAlt/crossover-rosetta-patches)):

- 0004 behebt DEP-Hänger von 1 bis 41 Sekunden in 32-Bit-Spielen von vor 2012 ohne NX_COMPAT.
- 0005 (PulseEvent) hob den Median in BO2 von 68 auf 97 fps.

#### Audio: Der Downmix kommt erst mit Wine 11.21

Commit `0c61795` von Zhiyi Zhang (CodeWeavers) heißt „winecoreaudio.drv: Add a SpatialMixer audio unit to mix input audio when necessary“. Er ändert `coreaudio.c` um +268/−35 Zeilen. Die Begründung: „HALOutput supports channel mapping but not downmixing“. Er behebt die fehlende Dialogstimme in **GTA V Enhanced** (7.1.4-Stream, Dialog auf `SPEAKER_FRONT_CENTER`) und in **Lego Star Wars: The Skywalker Saga** (5.1 auf einem 2.0-Gerät) ([wine-mirror 0c61795](https://github.com/wine-mirror/wine/commit/0c61795bfd04e290fb3966cb0f62f869d0d84443)).

Vorbereitet wird er durch `199ae1d`, `d20f6c7` ([Commit](https://github.com/wine-mirror/wine/commit/d20f6c71e746b76cd0cc19307c4c56e222526826)), `3e29c36` ([Commit](https://github.com/wine-mirror/wine/commit/3e29c3639e852fd9cfad8dc4d0a85015d7ab3f80)) und `8cf6408` ([Commit](https://github.com/wine-mirror/wine/commit/8cf640803ba9ab35fb6743fec5553e47faa34d56)). Alle fünf sind erst in 11.21 (30.10.2026).

`use_mixer()` schaltet den Mixer nur zu, wenn alle drei Bedingungen gelten ([coreaudio.c @ wine-11.21](https://github.com/wine-mirror/wine/blob/wine-11.21/dlls/winecoreaudio.drv/coreaudio.c)):

- Shared Mode,
- die Kanalmaske des App-Formats weicht von der des Geräts ab,
- das Format hat mehr als zwei Kanäle.

In CX 26.3 ändert `winecoreaudio.drv` nur die Mikrofonfreigabe (`authorization.m`). 4.7.3 und 4.8.1 haben den SpatialMixer nicht ([coreaudio.c @ wine1119](https://github.com/dappermint/winecx/blob/wine1119/dlls/winecoreaudio.drv/coreaudio.c)).

**Vermutung zum Echo bei „7.1 Wide“ (ungetestet):**

- Meldet macOS ein Layout mit LeftCenter/RightCenter, bildet Wine es auf KSAUDIO_SPEAKER_7POINT1 ab, also FLC/FRC statt SL/SR.
- Spiele geben meist 7POINT1_SURROUND aus.
- Ohne Mixer ordnet HALOutput die Kanäle nur zu. Die SIDE-Kanäle ohne passendes Ziel könnten dann doppelt oder versetzt ankommen.
- Genau hier greift mit 11.21 der SpatialMixer.

Der Backport betrifft nur `coreaudio.c`. Konflikte mit dem CX-Teil zur Mikrofonfreigabe sind nicht geprüft. Das Risiko ist vermutlich gering, weil andere Funktionen betroffen sind.

#### Remedy / Control: nichts in CrossOver

Die Suche im CX-26.3-Diff nach `control_dx`, `northlight`, `alan wake`, `remedy` und `quantumbreak` ergibt 0 Treffer. Hacks für einzelne Programme gibt es u. a. für `Agent.exe`, `Diablo IV.exe`, `GTA5.exe`, `cs2.exe`, `Fallout4.exe` und Ubisoft ([dappermint/winecx winecx-26.3.0](https://github.com/dappermint/winecx/tree/winecx-26.3.0)). Dokumentiert ist nur der Weg über **`Control_DX12.exe` mit D3DMetal** ([AppleGamingWiki Control, Snippet](https://www.applegamingwiki.com/wiki/Control)).

#### msync-Fehler und weitere Rosetta-Bremsen

**In `e0aa380` geprüft:** Unter `do_msync()` speichert `get_inproc_alert_fd()` in `dlls/ntdll/unix/sync.c` den Wert `reply->handle` in `data->alert_fd`. Das ist ein msync-Objektindex, kein Dateideskriptor. Trotzdem ruft `pthread_exit_wrapper` in `dlls/ntdll/unix/thread.c`, Zeile 1119, immer `close( data->alert_fd );` auf ([thread.c @ e0aa380](https://github.com/dappermint/winecx/blob/e0aa380780b73e20fabcfe78fd42713b94929a53/dlls/ntdll/unix/thread.c#L1119), [sync.c @ e0aa380](https://github.com/dappermint/winecx/blob/e0aa380780b73e20fabcfe78fd42713b94929a53/dlls/ntdll/unix/sync.c)). **Jedes Thread-Ende unter msync schließt damit eine fremde Datei, die zufällig dieselbe Nummer hat.**

Die Korrektur ist `if (!do_msync()) close( data->alert_fd );`. Recall beschreibt die Folge so: Es traf „often one of Overwatch’s game archives, whose next read then failed and crashed the game (issues [#40](https://github.com/LordHayne/Nightforge/issues/40) and [#50](https://github.com/LordHayne/Nightforge/issues/50))“ ([Recall patches/README.md](https://github.com/AsherJN/recall/blob/main/patches/README.md)). Für Nightforge ist dieser Bezug zu Overwatch **unbestätigt**.

Nightforges eigenes `engine/patches/wine-11.18-msync.patch` setzt unter msync ebenfalls `data->alert_fd = fd = reply->handle` und lässt `pthread_exit_wrapper` unverändert (per grep geprüft). Das Wine-11.18-Paket aus `graphics.yml` hat damit **sehr wahrscheinlich denselben Fehler**.

Recall nennt für den 26.3-Baum weitere Rosetta-Bremsen ([Recall HOW-IT-WORKS](https://github.com/AsherJN/recall/blob/main/docs/HOW-IT-WORKS.md)):

- Wine hält beim Laden einer Unix-Library den VM-Lock. Unter Rosetta dauert das jedes Mal 170 bis 770 ms und führt im Match zu Freezes von 150 bis 400 ms.
- Der wineserver pausiert alle 30 Sekunden etwa 0,1 Sekunden für die Sicherung der Registry.
- winemac liest bei jedem Linksklick die Liste der Displays neu.
- Mausdaten kommen nur mit 120 Hz an.

Das sind alles Kandidaten für spätere eigene Patches.

#### Nach 26.3: Wine 11.18 bis 11.21 und CrossOver 27

Upstream erschienen 11.18 am 18.09., 11.19 am 02.10., 11.20 am 16.10. und 11.21 am 30.10.2026 ([wine-mirror Tags](https://github.com/wine-mirror/wine/tags)). Für den Mac wichtig:

- 11.18: Aufräumarbeiten am GL-Kontext in winemac.
- 11.19: Fix für wineboot, das etwa 5 Sekunden blockierte ([#60322](https://github.com/LordHayne/Nightforge/issues/60322)), und Änderungen am IME.
- 11.20: Autorelease-Pools für WineMetalSwapChain.
- 11.21: SpatialMixer, Fixes an mmdevapi, Aufräumarbeiten von Brendan Shanks an ntdll für Systeme vor macOS 10.15.

dappermint hat 11.18 und 11.19 im Branch `wine1119` (Runtime 4.8.1). 11.20 und 11.21 hat noch niemand auf CX gesetzt ([compare e0aa380…wine1119](https://github.com/dappermint/winecx/compare/e0aa380780b73e20fabcfe78fd42713b94929a53...wine1119)).

CrossOver 27 wird nur noch Apple Silicon, nur 64-Bit-Bottles und nur macOS Sonoma oder neuer unterstützen ([CodeWeavers-Blog 11.06.2026, Snippet](https://www.codeweavers.com/blog/mjohnson/2026/6/11/whats-in-and-whats-out-for-crossover-27), [AppleInsider, Snippet](https://appleinsider.com/articles/26/06/11/crossover-a-windows-to-mac-gaming-tool-goes-apple-silicon-only)). Seit dem 31.07.2026 gibt es eine ARM64-Preview, deren ARM64-Teile macOS 26.5 verlangen ([CodeWeavers-Blog 31.07.2026, Snippet](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac)). Quellen dazu sind nicht veröffentlicht. ARM64 setzt außerdem das Apple-Entitlement `com.apple.developer.cross-architecture-support` voraus, das selbst signierte Builds nicht nutzen können ([winecx-gptk README](https://github.com/dappermint/winecx-gptk/blob/main/README.md)).

### 5. Optionen (a) bis (d)

| Option | Was konkret | Aufwand | Risiko | Wartung | Urteil |
|---|---|---|---|---|---|
| (a) dappermint bitten bzw. warten | Issue mit dem alert_fd-Fix und der Bitte um eine 11.21-Lane oder einen Cherry-Pick des Downmix; danach den Pin nachziehen | Stunden, plus Tests bei jedem neuen Tag | Regressionen (#24), wenige Maintainer, kein Zeitplan, Frist für x86_64-Bibliotheken Ende 2026 | Gering | Immer nebenher tun, allein aber zu passiv |
| (b1) Unveränderten CX-26.3-Tarball selbst bauen | `crossover-sources-26.3.0` nach dem Rezept von highball/dungeons | Hoch, Tage bis Wochen (Schätzung) | **Rückschritt auf Wine 11.0**: 11.15 bis 11.17 und die dappermint-Fixes gehen verloren | Hoch | Nicht empfohlen |
| (b2) Ganze Engine aus `dappermint/winecx` bauen | Derselbe Commit wie die Runtime, eigener Workflow im Stil von `graphics.yml` | Hoch, ähnlich wie (b1) | Mittel: abweichende Toolchain, Kompatibilität mit D3DMetal | Mittel bis hoch | Plan B |
| (b3) CX-Diff selbst auf 11.21 rebasen | Synthetischer Drei-Wege-Merge wie bei dappermint | Sehr hoch; der 11.15-Merge hatte 32 Konfliktdateien | Hoch | Sehr hoch | Nur, wenn dappermint aufgibt |
| (c) Gcenx-Builds | Upstream-Wine 11.21 oder GPTK 3.0-3 | Gering | Mit 11.21 fällt D3DMetal weg; GPTK 3.0-3 ist ein Rückfall auf CX 22.1.1 | Gering | Als Quelle für CX 26 unbrauchbar |
| (d) Mischform / Overlay | 4.7.3 plus eigene `ntdll.so`/`winecoreaudio.so` aus `e0aa380` mit Patches | Gering bis mittel, 1 bis 3 Tage (Schätzung) | Mittel: ABI und Unixcalls müssen zu D3DMetal passen, Bindung an den Pin | Gering bis mittel; bei jedem Runtime-Wechsel neu bauen | **Empfohlen** |

**Zu (a):** Eine formale Roadmap hat dappermint nicht. Sichtbar sind diese Signale:

- Der Satz „tracking upstream wine releases is sustainable“ im README (README).
- Ein Takt von 2 bis 5 Wochen je Wine-Lane: 11.15 am 13.08., 11.16 am 26.08., 11.17 am 17.09., 11.19 vom 09.10. bis 26.10.
- Eine arm64/FEX-Lane, die am Entitlement hängt.
- Eine optionale KosmicKrisp-Lane.
- Die Frist für x86_64-darwin in nixpkgs Ende 2026.

4.7.4 (25.10.) bringt nur einen winemac-Fix ([#11](https://github.com/LordHayne/Nightforge/issues/11)), 4.8.1 (26.10.) basiert auf Wine 11.19 ([winecx-gptk Releases](https://github.com/dappermint/winecx-gptk/releases)). Für beide meldet das offene Issue [dappermint/winecx-gptk#24](https://github.com/dappermint/winecx-gptk/issues/24) Regressionen gegenüber 4.7.3, etwa bei Witcher 3, bisher ohne Antwort ([Issue #24](https://github.com/dappermint/winecx-gptk/issues/24)). **Darum nicht blind dem neuesten Tag folgen, sondern die Pins behalten.** Einen CX-Import nach 26.3 kann es erst geben, wenn CodeWeavers neue Quellen veröffentlicht.

**Zu (b):** dappermint begründet die CX-Basis so: „apple’s game porting toolkit / d3dmetal payload only executes on crossover-derived wine builds, it patches their unixcall internals at load time“ ([README @ 4.7.3](https://github.com/dappermint/winecx-gptk/blob/runtime-v4.7.3/README.md)). Ein Bau aus dem unveränderten Tarball verliert also nichts an D3DMetal-Fähigkeit, wohl aber 17 Upstream-Releases.

Wenn Nightforge selbst baut, dann aus `dappermint/winecx`. Der Baum enthält schon 26.3 plus neueres Wine und hat eine echte Git-Historie. dappermints `build.yml` hat keine LICENSE-Datei. Nightforge sollte deshalb einen eigenen Workflow schreiben oder um Erlaubnis fragen.

**Zu (c):** Gcenx liefert keinen Build von CX 26. Sinnvoll wäre höchstens, die Legacy-Engine `wine` von 11.18 auf 11.21 zu heben, weil dort der Downmix enthalten ist. Dann müsste `graphics.yml` neu gegen 11.21 bauen: `winemac.so`, `ntdll.so`/`wineserver` (msync) und `winebus.so`, jeweils mit den Patches.

**Zu (d):** Das Muster gibt es schon zweimal ([gamepad.yml](https://github.com/LordHayne/Nightforge/blob/main/.github/workflows/gamepad.yml), [Engine.swift](https://github.com/LordHayne/Nightforge/blob/main/Sources/Nightforge/Engine.swift)):

- graphics.yml ersetzt ntdll.so und wineserver im Engine-Paket von Gcenx.
- gamepad.yml baut winebus.so aus e0aa380. Die App legt das Ergebnis per installGamepad über die Runtime und sichert das Original als winebus.so.engine.

Das Hauptrisiko: D3DMetal patcht beim Laden die Unixcall-Interna von ntdll. Ein neu gebautes `ntdll.so` braucht deshalb dieselben Configure-Flags wie dappermints Original (`--enable-archs=i386,x86_64`, Target 26.0). Danach ist ein Regressionstest mit einem DX12-Spiel unter D3DMetal 4.0b3 nötig. Bei `winecoreaudio.so` ist das Risiko gering.

#### Folgen für `components/manifest.json` und Prüfsummen

Heute hat `winecx` die Version 4.7.3 mit diesen Werten:

- URL https://github.com/dappermint/winecx-gptk/releases/download/runtime-v4.7.3/Libraries.tar.gz
- SHA-256 a4b5d63493f80698cce5cad8e7212d9a51c8292037b00c478f4652636fcfd331
- Größe 461.131.598 Byte

Gepinnt ist das in `sources.json` per `"tag": "runtime-v4.7.3"`. `scripts/update-components.py` übernimmt den SHA-256-Digest, den GitHub für Release-Assets veröffentlicht; sonst hasht es den Download. `scripts/validate-manifest.py` prüft die Felder `id`, `kind`, `version`, `url`, `sha256`, `size`, `license` und `source` und erlaubt nur die Kinds `engine`, `graphics` und `tool`.

**Bei (a)** reicht es, den `tag` umzustellen; der tägliche Lauf von `components.yml` schreibt URL, SHA-256 und Größe neu. Kritisch ist die **Bindung an den Commit**: `gamepad` (Version `4.7.3-7`) ist für `e0aa380` gebaut. Für `a54b824` (4.7.4) bzw. `9f3f644` (4.8.1) muss es neu gebaut werden, sonst landet ein `winebus.so` aus einem anderen Commit in der neuen Runtime. Für das Overlay gilt dasselbe.

**Bei (d)** kommt ein neuer Eintrag nach dem Muster von `gamepad` hinzu:

Die Version folgt dem Schema `4.7.3-N`, wie bei `gamepad-winecx4.7.3-7`. `kind` `graphics` statt `engine` ist ein Vorschlag, damit ältere App-Versionen den Eintrag nicht als wählbare Engine lesen. Wie ältere Versionen `engine`-Einträge auswerten, ist nicht geprüft.

Die Prüfsumme des Overlays kommt wie bei allen Nightforge-Assets aus dem GitHub-Digest. Zusätzlich sollte das Paket die SHA-256-Werte der **ersetzten Originaldateien** aus 4.7.3 mitführen. Die App legt das Overlay dann nur auf, wenn das vorhandene `ntdll.so` genau dem erwarteten Original entspricht und die Präfix-Version zu `winecx` passt.

**Bei (b2)** zeigt der Eintrag `winecx` auf `LordHayne/Nightforge` mit einem `tagPrefix` wie `engine-winecx-`; der Pin entfällt. Das Asset wird ähnlich groß, etwa 400 bis 460 MB. Der Name darf kein „crossover“ enthalten (Abschnitt 8).

### 6. Gewinn je Spiel

| Spiel | Stand unter CrossOver 26.x | Was 4.7.3 schon hat | Erwarteter Gewinn | Konkreter Hebel |
|---|---|---|---|---|
| Overwatch 2 | Läuft ab 26.1, nur mit macOS ≥ 26.5 ([CW-Blog, Snippet](https://www.codeweavers.com/blog/mjohnson/2026/5/18/finally-diablo-iv-and-overwatch-are-playable-with-crossover-261-macos-265)). Recall und NerRobDog laufen mit CX-26.3-Wine plus DXMT auf 26.5/26.6 | Die ganze Wine-Seite von CX 26.3, DXMT 0.80, D3DMetal 4.0b3 | Durch die Engine gering, durch **macOS 26.5 hoch**. Der msync-Fix hilft möglicherweise gegen Abstürze (unbestätigt) | macOS prüfen, DXMT testen, `releaseShaderIR` ([NerRobDog/dxmt](https://github.com/NerRobDog/dxmt)). Steam-Version **unsicher** |
| Diablo IV | Ab 26.1 mit macOS 26.5; 26.3 behebt einen Startfehler; nach Season 14 gab es nur einen Preview-Fix ([CW-Forum, Snippet](https://www.codeweavers.com/compatibility/crossover/forum/diablo-iv?msg=355134)) | CW HACK 23560, ACL-Hacks. `FindNextFileNameW` ist nur ein Stub (geprüft) | Durch die Engine gering, durch **macOS 26.5 hoch**. Ohne eigenen Fix bleibt das Risiko aus Season 14 | macOS 26.5; bei S14-Fehler `FindNextFileNameW` selbst implementieren |
| Diablo II: Resurrected | Mit 26.1 und macOS 26.5 spielbar, solange das Fenster den Fokus behält; Absturz nach Cmd-Tab offen. In der Kompatibilitäts-DB vermutlich „Limited Functionality“, aus der URL abgeleitet und **unsicher** ([CW-Kompatibilitäts-DB](https://www.codeweavers.com/compatibility/crossover/diablo-ii-resurrected)) | Rosetta-Hacks | Mittel, über macOS 26.5 | Hinweis „nicht mit Cmd-Tab wechseln“ |
| Control | Keine Daten zu 26.x; zuletzt 25.0.0 „In game via Wine“ ([CW Media, Snippet](https://www.codeweavers.com/compatibility/crossover/media/control-ultimate-edition)). Native Mac-Version seit 03/2025 im App Store und seit 31.12.2025 bei Steam ([alanwake.info](https://www.alanwake.info/2025/12/31st-december-2025-mac-version-of.html)) | Keine Remedy-Hacks, auch CX hat keine | Keiner | `Control_DX12.exe` mit D3DMetal; wer es bei Steam besitzt, nimmt die native Version |
| Mafia II (D3D9) | 26.0: etwa 15 fps bei 1080p Low auf dem M4 Mac mini, „barely playable“. Die Backend-Angabe „D3D_METAL“ ist fragwürdig ([MacGamingDB, Snippet](https://macgamingdb.app/games/mafia-ii-classic)) | wined3d auf OpenGL wie in CX | Durch CX keiner; durch wined3d aus 11.18/11.20 klein | GPU-PhysX aus ([CW-Tipp](https://www.codeweavers.com/compatibility/crossover/tips/mafia-ii-definitive-edition)); DXVK-d3d9 gegen wined3d testen; DEP-Patch 0004 (spekulativ) |
| GTA V | Enhanced: „Runs Well“ auf 26.3.0, nur Story ([CW-Kompatibilitäts-DB](https://www.codeweavers.com/compatibility/crossover/grand-theft-auto-v-enhanced)). Legacy: „Runs Great“ (abgeleitet, 25.0.1). Online ist durch BattlEye gesperrt ([CW-Forum](https://www.codeweavers.com/support/forums/general/?t=27&forumc__=&forumcurPos=0&msg=346704)) | Hacks für `GTA5.exe` und den Rockstar Launcher | **Downmix-Backport: hoch für Enhanced**, denn die fehlende Dialogstimme steht im Commit. Sonst gering | SpatialMixer-Backport; BattlEye für den Story-Modus aus; Rockstar Launcher zuerst starten |
| Elden Ring (offline) | „Runs Great“ (abgeleitet, 25.0.0), Median 60 fps bei 25 Berichten ([MacGamingDB](https://macgamingdb.app/games/1245620)); EAC erzwingt den Offline-Modus. Laut Bridgeplay läuft es nicht mit WineCX und D3DMetal auf M4 Max/M5 ([Bridgeplay #573](https://github.com/raymondchins/Bridgeplay/discussions/573)) | CX-Hacks, neueres D3DMetal | Unklar; warum es bei Bridgeplay scheitert, wurde nicht gelesen | D3DMetal mit esync/msync testen; EAC umgehen |
| Cyberpunk 2077 | „Runs Well“ auf 25.0.0 ([CW-Kompatibilitäts-DB](https://codeweavers.com/compatibility/crossover/cyberpunk-2077)). Die native Version braucht 16 GB und ist etwa 3 % schneller ([TechSpot](https://www.techspot.com/news/108739-how-well-does-cyberpunk-2077-run-m-series.html)) | Wie CX, neueres D3DMetal | Gering | Ab 16 GB die native Version |
| Baldur’s Gate 3 | „Runs Well“, getestete Version unbekannt. In Preview 20251023 scheiterte es mit D3DMetal und MSync ([CW-Forum, Snippet](https://www.codeweavers.com/compatibility/crossover/forum/baldurs-gate-3?msg=326841)) | Wie CX | Gering bis unklar | Native Mac-Version |
| Hogwarts Legacy | **„Runs Great“ auf 26.1.0**, das einzige Zielspiel mit einem Test auf 26.x ([CW-Kompatibilitäts-DB](https://www.codeweavers.com/compatibility/crossover/hogwarts-legacy)) | Gleiche Wine-Seite, neueres D3DMetal | Gering | D3DMetal mit DLSS→MetalFX |

Kernel-Anti-Cheat (BattlEye, EAC online) bleibt mit jeder CrossOver-Version unmöglich. Die großen Gewinne hängen am Betriebssystem (macOS 26.5 für die Blizzard-Titel) und am Audio-Backport für Mehrkanal-Spiele, nicht an CX 26.x selbst.

### 7. Bauschritte in Stichpunkten

**A. Overlay-Workflow (empfohlen), z. B. `.github/workflows/enginefix.yml`**

- Auslöser: workflow_dispatch und push auf den Workflow bzw. engine/patches/winecx-*.patch, wie bei gamepad.yml. Veröffentlicht wird nur von main aus.
- Runner: macos-15 (arm64), brew install bison flex pkg-config mingw-w64; bison und flex aus Homebrew im PATH vor /usr/bin.
- Quelle: dappermint/winecx bei WINECX_COMMIT: e0aa380780b73e20fabcfe78fd42713b94929a53 holen (git fetch --depth 1). Den unveränderten Baum per git archive als winecx-source.tar.xz sichern.
- Patches anwenden:
  - winecx-ntdll-msync-alert-fd.patch
  - winecx-winecoreaudio-spatialmixer.patch (Backport von 199ae1d, d20f6c7, 3e29c36, 8cf6408, 0c61795)
  - per grep prüfen, dass beide Änderungen im Baum sind.

- Configure wie bei dappermint (Empfehlung, nicht getestet):
  - --host=x86_64-apple-darwin --enable-archs=i386,x86_64 --disable-tests --without-x
  - CC="clang -arch x86_64", MACOSX_DEPLOYMENT_TARGET=26.0, ac_cv_func_pipe2=no, -Werror=unguarded-availability-new
  - kein --with-opengl; MoltenVK-Header bereitstellen.
  - gamepad.yml nutzt --enable-win64. Für ntdll.so besser die Flags des Originals übernehmen.

- Bauen: make dlls/ntdll/ntdll.so dlls/winecoreaudio.drv/winecoreaudio.so.
- Prüfschritte:
  - Das Runtime-Asset runtime-v4.7.3 laden und gegen SHA-256 a4b5d634… prüfen.
  - nm findet msync_wait_objs.
  - nm -gU und otool -L (Install-Names, @loader_path/@rpath) mit den Originalen vergleichen.
  - minos ≤ 26.0 (otool -l bzw. vtool -show-build).
  - Einen String aus dem Downmix-Patch in winecoreaudio.so suchen.

- Kurztest auf dem Runner: Runtime entpacken, Overlay darüberlegen, wineboot -i und ein 32-Bit-Programm starten. dappermints Prüfungen für Fenster und dlopen zeigen, dass so etwas auf GitHub-Runnern geht.
- Paket: nightforge-enginefix-winecx-4.7.3-N.tar.gz mit lib/wine/x86_64-unix/{ntdll.so,winecoreaudio.so} und dazu:
  - README.txt mit Herkunft, Commit, Patches, Lizenz und Hinweis auf die Quelle,
  - SHA-256-Werte der ersetzten Originale,
  - COPYING.LIB, LICENSE und AUTHORS von Wine.

- Quell-Asset `…-source.tar.xz`: unveränderter winecx-Baum, Patches, Workflow-Datei, Lizenzen und eine NOTICE mit den geänderten Dateien und Datum (§2b LGPL).
- Release: gh release create enginefix-winecx4.7.3-N … --latest=false. Danach den Eintrag in sources.json ergänzen. components.yml und update-components.py übernehmen URL, SHA-256 und Größe, validate-manifest.py prüft.
- App: installEngineFix analog zu installGamepad. Es sichert die Originale als *.engine, tauscht atomar per replaceItemAt und läuft nur, wenn Version und Original-Hashes passen.
- Test auf einem echten Mac (macOS ≥ 26.5):
  - Steam-Login (Regressionen beim CM-Login sind bekannt),
  - ein DX12-Spiel mit D3DMetal 4.0b3 (wegen des Unixcall-Patchings),
  - ein DXMT-Spiel und ein 32-Bit-Spiel,
  - ein 5.1/7.1-Spiel mit „7.1 Wide“ und mit Stereo,
  - Overwatch.

- Für den Gcenx-11.18-Pfad: den Fix auch in wine-11.18-msync.patch einbauen und graphics.yml neu laufen lassen.

**B. Ganze Engine bauen (Plan B)**

- Quelle: dappermint/winecx beim gepinnten Commit, nicht der unveränderte Tarball. Den Workflow selbst schreiben, weil dappermints Skripte keine Lizenz haben.
- Runner: macos-15 oder macos-26 (arm64) mit Rosetta (softwareupdate --install-rosetta --agree-to-license). Zuerst die nativen Wine-Werkzeuge bauen (make __tooldeps__), dann --with-wine-tools=….
- x86_64-Bibliotheken (freetype, gnutls, SDL2, MoltenVK als Pflicht, GStreamer/FFmpeg) aus einer von vier Quellen:
  - nix x86_64-darwin, bis Ende 2026,
  - x86_64-Homebrew in /usr/local wie bei calimocho,
  - selbst gebaut wie bei Traxis,
  - macos-15-intel, bis 2027.

- PE-Hälfte: mingw-w64 gcc, nicht llvm-mingw; danach strippen. Prüfschritt: mehr als 500 Dateien in i386-windows.
- Mono und Gecko: Versionen aus addons.c lesen (11.3.0 / 2.47.4) und nach share/wine/{mono,gecko} entpacken.
- Layout: DXMT-winemetal, DXVK-macOS und MoltenVK wie heute einbinden. lib/external für D3DMetal frei halten, mit Symlinks auf libd3dshared.dylib.
- Relocation: Pfade auf @loader_path umschreiben und nach absoluten Pfaden suchen; Prüfschritte für dlopen, Fenster und Media Foundation.
- Cache und Laufzeit: ccache mit actions/cache (10 GB, 7 Tage), timeout-minutes: 300. Zu erwarten sind 1 bis 2,5 Stunden ohne Cache und 15 bis 30 Minuten mit warmem Cache. Den Plattenverbrauch mit df -h loggen, weil niemand die 14 GB SSD nachgemessen hat.
- Paket: wie bei A, mit Quell-Asset im selben Release.

### 8. Lizenzteil

Das ist keine Rechtsberatung, sondern eine Lesart der Lizenztexte.

**Wine und LGPL-2.1-or-later.** Wine steht unter LGPL-2.1-or-later ([Wine LICENSE](https://raw.githubusercontent.com/wine-mirror/wine/master/LICENSE)), ebenso dappermints CX-Baum ([LICENSE @ wine1119](https://raw.githubusercontent.com/dappermint/winecx/wine1119/LICENSE)). Nightforge gibt die Bibliothek selbst weiter, und zwar verändert. Damit gelten §1, §2 und §4, nicht §6 ([COPYING.LIB](https://raw.githubusercontent.com/wine-mirror/wine/master/COPYING.LIB)):

- §4: Objektcode nur zusammen mit vollständigem, maschinenlesbarem Quellcode. „Offering equivalent access to copy the source code from the same place“ genügt. Nach §0 gehören zum „complete source code“ auch „the scripts used to control compilation and installation“, also Workflow, Configure-Flags und Relocation-Skripte.
- Kein schriftliches Angebot: Ein dreijähriges schriftliches Quellangebot reicht hier nicht. Das gibt es nur in §6c für „works that use the Library“, nicht in §4.
- §2b: Geänderte Dateien brauchen „prominent notices stating that you changed the files and the date“.
- §1: Lizenztext und Copyright-Hinweise beilegen.
- §10: keine zusätzlichen Einschränkungen.

Nightforges heutige Praxis erfüllt das: ein `-source.tar.xz` im selben Release mit dem unveränderten Baum, den Patches und dem Workflow. Ein Link auf codeweavers.com reicht als einzige Quelle nicht, denn das ist nicht „the same place“.

Nightforge startet `wine` und `wineserver` nur als eigene Prozesse. Nach gängiger FSF-Lesart sind das getrennte Programme (Auslegung). LGPL-2.1+ ist zudem mit GPL-3.0 vereinbar ([FSF-Lizenzliste, Spiegel](https://www.southampton.ac.uk/~qs2g22/mirror/www.gnu.org/licenses/license-list.html)).

**Mitgelieferte Komponenten:**

- DXMT steht seit v0.80 unter LGPL-2.1-or-later, nicht mehr unter MIT. Nightforges Manifest führt die Lizenz schon richtig, aber der Kommentar in graphics.yml nennt noch MIT (DXMT LICENSE).
- MoltenVK: Apache-2.0; Lizenz und gegebenenfalls NOTICE mitgeben (MoltenVK LICENSE).
- DXVK und FAudio: zlib; veränderte Fassungen kennzeichnen (DXVK LICENSE, FAudio LICENSE).
- wine-mono: gemischt aus MIT, LGPL, GPL mit Ausnahme und MS-PL (wine-mono COPYING).
- wine-gecko: MPL-2.0 laut Arch (Sekundärquelle) (Arch wine-gecko).

Für das Engine-Asset gibt es deshalb keine einzelne SPDX-ID; nötig ist eine Aufstellung pro Datei.

**Proprietäres und EULA.** CodeWeavers stellt den „FOSS Code“ bereit. CrossOver „also contains proprietary components“, und die EULA verbietet deren Weitergabe ([CrossOver EULA, Snippet](https://www.codeweavers.com/crossover/eula), [alte Linux-EULA bei Gentoo](https://raw.githubusercontent.com/gentoo/gentoo/master/licenses/CROSSOVER-3)). Deshalb nur aus dem FOSS-Tarball oder einem Git-Spiegel bauen und **nie Dateien aus einer installierten CrossOver.app übernehmen** (`cxcompatdb.so`, Skripte, Icons).

**Marke „CrossOver“.** CROSSOVER ist in den USA unter Reg. 4045200 eingetragen, CODEWEAVERS ebenfalls ([Justia CROSSOVER](https://trademarks.justia.com/852/81/crossover-85281373.html), [Justia CodeWeavers](https://trademarks.justia.com/owners/codeweavers-inc-2821885)). Eine Richtlinie zur Markennutzung fand sich nicht. Üblich ist in der Szene ein eigener Name mit sachlicher Nennung, z. B. „codeweavers’ crossover 26.3 wine changes“ bei winecx-gptk oder „built on top of CrossOver 22.1.1“ bei [Whisky](https://raw.githubusercontent.com/Whisky-App/Whisky/main/README.md).

Für Nightforge heißt das:

- Namen von Assets, Tags und Engine ohne „CrossOver“.
- Keine CodeWeavers-Logos.
- Nicht als „CrossOver gratis“ vermarkten.
- Im README den Satz „CrossOver is a trademark of CodeWeavers, Inc.; Nightforge is not affiliated with or endorsed by CodeWeavers“ ergänzen. Für Valve und Apple gibt es so einen Satz schon, für CodeWeavers fehlt er.

Eintragungen in der EU oder beim DPMA wurden nicht geprüft (unsicher).

**D3DMetal.** Die Apple-Lizenz EA18380 vom 17.08.2023 lag in Sikarugirs 4.0-Ordner ([License.pdf](https://raw.githubusercontent.com/Sikarugir-App/Sikarugir/main/D3DMetal/4.0/License.pdf)). Sie erlaubt die Weitergabe „solely for non-commercial purposes“, nur des ganzen Frameworks („in its entirety“), nur auf Apple-Hardware und ohne Veränderung. D3DMetal bleibt also wie heute eine **getrennte** Komponente und darf nie ins LGPL-Archiv. Das `License.pdf` im eigenen 4.0b3-Paket gegenprüfen.

**Gepflogenheit in der Community.** Whisky schrieb zum Abschied: „The revenue from CrossOver is what keeps Wine on Mac alive“ ([Whisky Maintenance Notice](https://raw.githubusercontent.com/Whisky-App/Whisky-Book/main/src/maintenance-notice.md)). Daraus folgt:

- CodeWeavers sichtbar nennen und auf den Kauf von CrossOver hinweisen.
- Allgemeine Fixes wie den alert_fd-Fix upstream melden.
- Fehler aus der Nightforge-Engine nur mit klarem Hinweis auf die Herkunft bei CodeWeavers oder WineHQ melden.

### 9. Gesperrte Hosts

Der Netzwerk-Proxy dieser Recherche sperrte am 01.11.2026 (meist CONNECT 403 oder DNS-Fehler):

- CodeWeavers: www.codeweavers.com, codeweavers.com, media.codeweavers.com, ftp.codeweavers.com.
- WineHQ: gitlab.winehq.org, www.winehq.org, wiki.winehq.org, lists.winehq.org, list.winehq.org, source.winehq.org, bugs.winehq.org, dl.winehq.org.
- Archive und Paketquellen: web.archive.org, archive.org, formulae.brew.sh, ports.macports.org, distfiles.macports.org, packages.macports.org, mirrors.mit.edu, repology.org.
- GitHub-Nebenseiten und andere Hoster: github.blog, docs.github.com, gist.githubusercontent.com, sourceforge.net (HTTP 403), gemfury.com, docs.getwhisky.app.
- Foren und News: reddit.com, news.ycombinator.com, phoronix.com, macworld.com, appleinsider.com, macrumors.com, 9to5mac.com, notebookcheck, omgubuntu.co.uk, alternativeto.net, wine-reviews.net, techspot.com, machow2.com, devbytes.co.in.
- Spiele-Datenbanken: applegamingwiki.com, macgamingdb.app, protondb.com, pcgamingwiki.com, steamcommunity.com, us.forums.blizzard.com.
- Sonstiges: en.wikipedia.org, www.gnu.org, youtube.com, google.com, duckduckgo.com, download.developer.apple.com, discussions.apple.com.
- Teilweise lesbar: Threads im Apple-Entwicklerforum lagen zum Teil hinter einer Bot-Prüfung; Thread 814383 war in einem Versuch lesbar.
- GitHub-API und -Werkzeuge: api.github.com und curl auf github.com lieferten für alle Repos außer LordHayne/Nightforge HTTP 403 („GitHub access to this repository is not enabled for this session“). Das GitHub-MCP war auf lordhayne/nightforge beschränkt, das gh-Token ungültig.
- Erreichbar: git clone und git ls-remote öffentlicher Repos, raw.githubusercontent.com, Seiten auf github.com über einen Abrufdienst, developer.apple.com und gitlab.com.

**Deshalb stammen alle CodeWeavers-Fakten aus Suchmaschinen-Snippets, Spiegeln und fremden Repos.** Das betrifft den Changelog, die Blogposts, die Kompatibilitäts-Datenbank, die Komponentenversionen in 26.x und die Prüfsummen der Tarballs. Die Spiegel und fremden Repos sind: dappermints Import des 26.3-Baums, die Pins in highball, dungeons-for-mac, Traxis und calimocho sowie Gcenx’ Portfiles. Vor einer Entscheidung sollte man das auf codeweavers.com gegenlesen. Der Code-Abgleich lief dagegen direkt in Git.

Zur Transparenz: Ein Rechercheschritt versuchte, per `add_repo` ein zusätzliches GitHub-Repository zum Lesen an die Sitzung zu hängen. Laut Sitzungsdaten wurde keines angehängt, geschrieben wurde nichts. Im Nightforge-Repo wurde nichts geändert; es gab keinen Push, keinen PR und keine Anmeldung.

### 10. Quellen

Aufgeführt sind alle Quellen, die im Text zitiert werden.

**Nightforge**

- LordHayne/Nightforge: .github/workflows/gamepad.yml
- LordHayne/Nightforge: Sources/Nightforge/Engine.swift

**CodeWeavers (Blog, Changelog, Foren, Kompatibilitäts-DB, Lizenz)**

- CodeWeavers-Blog, 18.05.2026
- CodeWeavers-Quellseite
- CodeWeavers-Changelog
- CodeWeavers-Blog 10.02.2026
- CodeWeavers-Forum D4
- CodeWeavers-Blog 11.06.2026
- CodeWeavers-Blog 31.07.2026
- codeweavers.com: compatibility/crossover/diablo-ii-resurrected
- codeweavers.com: compatibility/crossover/media/control-ultimate-edition
- codeweavers.com: compatibility/crossover/tips/mafia-ii-definitive-edition
- codeweavers.com: compatibility/crossover/grand-theft-auto-v-enhanced
- codeweavers.com: support/forums/general (msg 346704)
- codeweavers.com: compatibility/crossover/cyberpunk-2077
- codeweavers.com: compatibility/crossover/forum/baldurs-gate-3 (msg 326841)
- codeweavers.com: compatibility/crossover/hogwarts-legacy
- CrossOver EULA

**dappermint (winecx, winecx-gptk, Whisky-Fork)**

- dappermint/winecx Commit e0aa380
- dappermint/winecx Tag winecx-26.3.0
- VERSION @ e0aa380
- winecx-gptk build.yml @ 4.7.3, L838–L859 (lib/external)
- addons.c @ e0aa380
- dappermint/winecx Tags
- dappermint/winecx-gptk README
- dappermint/winecx-gptk build.yml
- winecx-gptk Actions
- winecx-gptk build.yml @ 4.7.3, L31–L48 (nixpkgs-Frist)
- dappermint/winecx Commit 84c0ec9 (merge wine 11.15 into crossover 26.3)
- dappermint/winecx (Repository)
- virtual.c @ winecx-26.3.0
- setupapi/devinst.c @ winecx-26.3.0
- advapi32/security.c @ winecx-26.3.0
- kernelbase/file.c @ e0aa380
- win32u/d3dkmt.c @ winecx-26.3.0
- dappermint/winecx-gptk docs/kosmickrisp.md
- wined3d/adapter_vk.c @ winecx-26.3.0
- wined3d @ winecx-26.3.0
- coreaudio.c @ wine1119
- thread.c @ e0aa380
- sync.c @ e0aa380
- compare e0aa380…wine1119
- winecx-gptk Releases
- dappermint/winecx-gptk Issue #24 (Regressionen 4.7.4/4.8.1)
- dappermint/winecx-gptk README @ runtime-v4.7.3
- LICENSE @ wine1119

**Wine upstream**

- kernelbase/file.c @ wine-11.21
- Wine 11.18 ANNOUNCE
- Wine 11.20 ANNOUNCE
- Wine 11.21 ANNOUNCE
- wine-mirror Commit 0c61795 (SpatialMixer)
- wine-mirror Commit d20f6c7 (get_format_channel_mask)
- wine-mirror Commit 3e29c36 (ca_get_layout_channel_mask)
- wine-mirror Commit 8cf6408 (get_device_channel_mask)
- coreaudio.c @ wine-11.21
- wine-mirror Tags
- Wine LICENSE
- Wine COPYING.LIB (LGPL-2.1)

**Gcenx, Homebrew, MacPorts, Apple-Tap**

- MacPorts wine-crossover Portfile
- Gcenx/macports-wine crossover Portfile
- homebrew-cask crossover.rb
- Gcenx/game-porting-toolkit Tags
- Gcenx/homebrew-wine Commit f201026 (Delete wine-crossover.rb)
- Gcenx/macOS_Wine_builds README
- apple/homebrew-apple game-porting-toolkit.rb (GPTK 1.1)
- Gcenx/macports-wine README
- Gcenx/macports-wine wine-devel Portfile
- homebrew-cask wine-stable.rb
- Homebrew Discussion #7044

**Lizenz und Marke**

- FSF-Lizenzliste, Spiegel
- DXMT LICENSE
- MoltenVK LICENSE
- DXVK LICENSE
- FAudio LICENSE
- wine-mono COPYING
- Arch wine-gecko
- alte Linux-EULA bei Gentoo
- Justia CROSSOVER
- Justia CodeWeavers
- Apple GPTK-Lizenz EA18380 (Sikarugir D3DMetal/4.0/License.pdf)
- Whisky Maintenance Notice

**Weitere CrossOver-Builder und Engines**

- calimocho Issue #8
- Endfield_FineWine Wiki: graphics_backends
- dungeons-for-mac inputs.json
- highball-engine inputs.json
- traxis-runners README
- calimocho versions.json
- Endfield-Wiki: building_crossover_wine
- dungeons-for-mac sources.yml
- traxis build-wine.sh
- Gcenx im Gist von sarimarton
- PhoenicisOrg/winecx
- TheShellLand/crossover-source
- dungeons-for-mac Release src-crossover-26.3.0
- Whisky-App/Whisky (archiviert)
- Sikarugir-App/Engines EngineList.txt
- highball build.yml
- dungeons build.yml
- calimocho build.yml
- Endfield_FineWine build-wine.sh
- traxis-runners toolchain.sh
- Jason2866/crossover-wine-ci
- BRYANN2K/cartouche-wine
- AliJamalll/game-bridge
- GabLeRoux/macos-crossover-wine-cloud-builder
- highball README
- highball Actions
- Endfield build-wine.yml
- Endfield-Wiki gptk4_upgrade
- Whisky README (raw)

**Grafik: D3DMetal/GPTK, DXMT, DXVK, MoltenVK**

- Apple Developer: Game Porting Toolkit
- korben.info: Game Porting Toolkit 4
- 3Shain/dxmt Releases
- NerRobDog/dxmt Branches

**GitHub Actions und Runner**

- github/docs supported-github-runners
- github/docs Actions-Limits
- github/docs Dependency Caching
- runner-images #13045
- GitHub Changelog

**Spiele-Projekte, Patches und Community**

- Apple Developer Forums 814383
- D4Mac README
- AsherJN/recall
- LuidgiAlt/crossover-rosetta-patches
- AppleGamingWiki Control
- Recall patches/README.md
- Recall HOW-IT-WORKS
- alanwake.info: Mac-Version, 31.12.2025
- macgamingdb.app: games/mafia-ii-classic
- macgamingdb.app: games/1245620
- Bridgeplay #573
- Recall Releases

**Presse, Rezensionen und Sonstiges**

- Phoronix: CrossOver 26
- AppleInsider: CrossOver 26 update (10.02.2026)
- devbytes.co.in: CrossOver v26.1
- PlayingTux: CrossOver 26.2 released
- Wine Reviews: CrossOver 26.3
- Macworld: CrossOver for Mac review
- MacHow2: CrossOver Mac review
- AppleInsider: CrossOver goes Apple-Silicon-only (11.06.2026)
- TechSpot: Cyberpunk 2077 on M-series
