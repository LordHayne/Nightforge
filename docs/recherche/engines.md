<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHRED6c5jNnUw9T561s (1.11.2026) -->

Unten folgt der vollständige Bericht. Am Nightforge-Repo wurde nichts geändert, `git status` ist sauber. Die Notizen und der Bericht liegen nur im Scratchpad: `/tmp/claude-0/-home-user-Nightforge/65fe21cc-9e5e-5976-baf1-dadd27bd5cbb/scratchpad/reports/Windows Spiele auf Apple Silicon 2026.md`.

Wichtigste Einschränkung: In dieser Sitzung war das Netz für codeweavers.com, winehq.org, phoronix.com, applegamingwiki.com, pcgamingwiki.com und einige weitere Seiten gesperrt. Was von dort stammt, kommt nur aus Suchmaschinen-Auszügen und ist im Text als unsicher markiert. Wenn du diese Seiten in den Netzwerkeinstellungen der Umgebung freigibst, lassen sich die Angaben in einer zweiten Runde an den Originalseiten prüfen.

---

## Windows-Spiele auf Apple Silicon: Metal führt, Rosetta setzt die Frist

*Stand: 1. November 2026. Grundlage für die Entscheidung, welche Engines und Grafikwege Nightforge nach Release 0.3.0 verfolgt.*

### Kurzfassung

- Drei Wege sind heute ernst zu nehmen.
  - Wine mit Metal-Übersetzern (D3DMetal, DXMT) unter Rosetta 2. Das ist der Hauptweg aller Mac-Launcher.
  - Wine mit Vulkan-Übersetzern (DXVK, vkd3d-proton) auf MoltenVK oder KosmicKrisp. Das ist ein Nebenweg mit Lücken und Rucklern.
  - Wege ohne Mac-Wine: Windows on ARM in Parallels (bis DirectX 11.1), Linux-VMs mit Proton und FEX (steamac) und Cloud-Gaming (GeForce NOW).

- Je DirectX-Version:
  - Für DX12 gibt es nur D3DMetal.
  - Für DX10 und DX11 ist DXMT der beste Standard. D3DMetal ist pro Spiel gleichwertig.
  - Für DX9 und älter bleibt WineD3D über OpenGL die breiteste Basis.
  - Bei CPU-gebundenen 32-Bit-DX9-Spielen ist DXVK 3 auf KosmicKrisp messbar schneller, ruckelt aber.
  - Die Tabelle in „Ergebnis 1“ zeigt alle Stufen.

- Nightforges Grundaufteilung stimmt. Bessere Varianten gibt es vor allem im Detail:
  - D3DMetal 3.0 oder 4.0 pro Spiel, mit Notschalter für das Metal-4-Backend
  - ein bewusst gewählter DXMT-Kanal
  - Wine 7.7 abschalten
  - sauber getrennte Shader-Caches
  - ein Frame-Limiter, der nur Teiler der Bildwiederholrate nutzt
  - offene Daten (highball-db, umu-database) neben den eigenen Profilen

- Für alte Spiele zählt vor allem, OpenGL zu umgehen. Apples OpenGL 4.1 hat keine der Erweiterungen, mit denen Wine den 32-Bit-OpenGL-Engpass behebt. Kandidaten sind DXVK 3 auf KosmicKrisp, das neue Metal-native mtld3d und Zink auf KosmicKrisp. Alle drei sind noch experimentell.
- Die harte Frist heißt Rosetta.
  - Apple unterstützt Rosetta als Allzweckwerkzeug nur bis macOS 27.
  - Ab macOS 28 (erwartet Herbst 2027) bleibt nur ein „Spiele-Subset“. Ob Wine dazugehört, ist offen.
  - CodeWeavers plant mit nativem ARM64-Wine und FEX.
  - D3DMetal gibt es bisher nur für x86_64.

- Vulkan auf dem Mac wechselt die Grundlage. Khronos hat MoltenVK am 13. Oktober 2026 abgekündigt. KosmicKrisp ist Vulkan-1.4-konform, braucht aber macOS 26. Upstream fehlen noch Graphics Pipeline Library, Geometry Shader und ein verlässlicher Disk-Cache.
- Rechtlich heikel ist vor allem D3DMetal. Apples Lizenz erlaubt nicht-kommerzielle Weitergabe, erlaubt die Nutzung aber nur zum „developing, testing, or evaluating video games“. Bei DXMT widersprechen sich Nightforges Hinweisdatei und Manifest. Das ist leicht zu beheben.
- Mehrkanal-Audio über AV-Receiver: Die bekannten Fehler (Center und LFE vertauscht, Knacksen, fehlender Downmix) sind in Wine 11.0, 11.16 und 11.21 behoben. Wine 7.7 hat keinen dieser Fixes. Ob 7.1-Anlagen richtig erkannt werden, ist ungeprüft.

### So ist dieser Bericht entstanden

Der Bericht fasst neun Rechercheprotokolle vom 1. November 2026 zusammen. Eigene Messungen gibt es nicht.

Direkt lesbar waren in der Recherche-Sitzung nur developer.apple.com, github.com und raw.githubusercontent.com. Gesperrt waren unter anderem:

- codeweavers.com
- winehq.org und gitlab.winehq.org (der Wine-Code wurde über den GitHub-Spiegel gelesen)
- phoronix.com
- applegamingwiki.com und pcgamingwiki.com
- lunarg.com und docs.mesa3d.org
- appleinsider.com und macworld.com

Aussagen von diesen Seiten stammen nur aus Zusammenfassungen von Suchmaschinen. Sie sind markiert mit *(unsicher, nur Suchauszug)*.

Viele Daten aus 2026 kommen aus Issues und Pull Requests kleiner GitHub-Projekte. Manche davon sind mit KI-Hilfe geschrieben. Es sind echte Testprotokolle, aber keine Herstellerangaben. Sie sind markiert mit *(Feldbericht)*.

Weitere Kennzeichnungen:

- Absätze mit Einschätzung: sind Schlussfolgerungen der Rechercheure oder dieses Berichts, keine belegten Fakten.
- Verweise auf Nightforges eigenes Repository tragen den Zusatz „Repo-Stand main“, weil der GitHub-Stand älter ist als der lokale Stand des Autors.
- Die rechtlichen Teile sind keine Rechtsberatung.

### Ergebnis 1: DX-Version × bester Weg auf Apple Silicon heute

| DX-Version | Bester Weg heute | Fallback | Begründung und Quellen |
|---|---|---|---|
| **DirectDraw / DX1–7** | WineD3D über OpenGL | cnc-ddraw für 2D-DirectDraw; dgVoodoo2 → DXMT nur als Versuch | D3DMetal kann nur DX11/12 ([MacPorts-Portfile](https://github.com/macports/macports-ports/blob/master/devel/d3dmetal/Portfile)). DXVK hat upstream keinen D3D7-Pfad, nur D3D8 ab 2.4 ([DXVK v2.4](https://github.com/doitsujin/dxvk/releases/tag/v2.4)). Sikarugir nutzt für DX7 und älter standardmäßig WineD3D und cnc-ddraw ([Sikarugir](https://github.com/Sikarugir-App/Sikarugir)). dgVoodoo2 ab 2.81 scheitert unter Wine an der Geräteerkennung ([DXVK #5217](https://github.com/doitsujin/dxvk/issues/5217)); Mac-Tests fehlen. |
| **DX8** | WineD3D über OpenGL | DXVK 3 (enthält D8VK) auf KosmicKrisp, nur macOS 26+, pro Spiel | D8VK ist seit DXVK 2.4 Teil von DXVK und baut auf dessen D3D9 auf ([DXVK v2.4](https://github.com/doitsujin/dxvk/releases/tag/v2.4)). DXVK-macOS 1.10 hat kein D3D8/9 ([DXVK-macOS](https://github.com/Gcenx/DXVK-macOS/releases)). Sikarugirs D9VK für MoltenVK ist archiviert ([Sikarugir d9vk](https://github.com/Sikarugir-App/d9vk/releases/)). DXVK 3 braucht für d3d8/d3d9 einen bestimmten KosmicKrisp-Stand ([Sikarugir dxvk v3.0.2](https://github.com/Sikarugir-App/dxvk/releases/tag/v3.0.2)). |
| **DX9 32-Bit** | WineD3D über OpenGL als sicherer Standard; DXVK 3.1.1 auf KosmicKrisp pro Spiel, wenn CPU-gebunden, offline und macOS 26+ | mtld3d (Metal-natives D3D9) prüfen; Zink auf KosmicKrisp als Forschung | Unter dem neuen WoW64 gehen OpenGL-Aufrufe durch Thunks und Pufferkopien, weil Apples OpenGL die nötigen Erweiterungen fehlen ([unix_wgl.c, Wine 11.21](https://github.com/wine-mirror/wine/blob/wine-11.21/dlls/opengl32/unix_wgl.c)). DXVK 3 auf KosmicKrisp war 1,4× (Portal) bis 2,5× (Sonic Adventure DX) schneller als WineD3D, ruckelt aber beim Kompilieren ([Whisky #264](https://github.com/frankea/Whisky/issues/264)) *(Feldbericht)*. Manche Spiele hängen an Rosettas x87-Emulation; dort hilft kein Rendererwechsel ([Meridian PR #18](https://github.com/aftrnd/Meridian/pull/18)) *(Feldbericht)*. |
| **DX9 64-Bit** | WineD3D über OpenGL | DXVK 3 auf KosmicKrisp (macOS 26+) | 64-Bit-Code braucht keine WoW64-Thunks; die gelten nur für 32-Bit-Code ([Wine 9.0 ANNOUNCE](https://github.com/wine-mirror/wine/blob/wine-9.0/ANNOUNCE.md)). Apples OpenGL reicht WineD3D für Featurelevel 9_3, also für DX9 ([athei/wine-build #21](https://github.com/athei/wine-build/issues/21)). DXVK-3-D3D9 besteht auf KosmicKrisp Smoke-Tests in 32 und 64 Bit ([Meridian PR #18](https://github.com/aftrnd/Meridian/pull/18)) *(Feldbericht)*. Seltene Kategorie, wenig Daten. |
| **DX10** | DXMT (D3D10 seit v0.60) | DXVK-macOS 1.10 async auf MoltenVK; dann WineD3D | DXMT bringt D3D10 seit v0.60 und 32-Bit seit v0.50 ([DXMT Releases](https://github.com/3Shain/dxmt/releases)). Die d3d10-DLLs in D3DMetal sind nutzlose Stubs ([MacPorts-Portfile](https://github.com/macports/macports-ports/blob/master/devel/d3dmetal/Portfile)). DXVK-macOS kann nur DX10/11 ([DXVK-macOS](https://github.com/Gcenx/DXVK-macOS/releases)). |
| **DX11 64-Bit** | DXMT als Standard; D3DMetal pro Spiel gleichwertig | DXVK-macOS 1.10 async | DXMT lief in Feldberichten oft flüssiger und brauchte weniger RAM, etwa 120 fps gegen „unspielbar“ bei 8–12 statt ca. 16 GB in Arknights: Endfield ([Endfield_FineWine PR #36](https://github.com/stoicswe/Endfield_FineWine/pull/36)) *(Feldbericht)*. In Split Fiction hatte D3DMetal-DX11 die niedrigere GPU-Zeit (11,9 gegen 12,7 ms) ([gamify](https://github.com/itzhakos/gamify/blob/main/docs/perf-research.md)) *(Feldbericht)*. DXMT fehlt GS-Stream-Output ([COMPATIBILITY_FLAG.md](https://github.com/3Shain/dxmt/blob/main/docs/COMPATIBILITY_FLAG.md)). Ein kontrollierter Vergleich fehlt. |
| **DX11 32-Bit** | DXMT (WoW64-Build) | DXVK-macOS 1.10 async; WineD3D | D3DMetal ist nur 64-Bit ([MacPorts-Portfile](https://github.com/macports/macports-ports/blob/master/devel/d3dmetal/Portfile)). Alien: Isolation lief mit DXMT bei 134–150 fps, über WineD3D/Zink bei 11–14 fps ([Hadron #145](https://github.com/Broyojo/hadron/issues/145)) *(Feldbericht)*. CrossOver 26.3 nennt „Support for 32-bit DirectX 10/11 games“ ([CodeWeavers-Changelog](https://www.codeweavers.com/crossover/changelog)) *(unsicher, nur Suchauszug)*. |
| **DX12** | D3DMetal: 3.0 als stabile Basis, 4.0 Beta 3 pro Spiel; Metal-4-Backend auf macOS 27 mit `D3DM_MTL4=0` als Notschalter | DX11-Modus des Spiels über DXMT; vkd3d-proton auf gepatchtem KosmicKrisp als letzter Ausweg | DXMT-D3D12 ist unveröffentlicht, der Entwickler rät vom Testen ab ([DXMT #194](https://github.com/3Shain/dxmt/issues/194)). GPTK 4 brachte in einzelnen Spielen große Gewinne, etwa GTA V von ca. 106 auf 176 fps ([Macworld](https://www.macworld.com/article/3189951/apples-latest-game-porting-toolkit-beta-changed-how-i-think-about-mac-gaming.html)) *(unsicher, nur Suchauszug)*, aber auch Regressionen ([corkscrew #11](https://github.com/prateek-srivastav/corkscrew/issues/11)). vkd3d-proton läuft nur mit Community-Patches ([Cosmopolitan PR #20](https://github.com/cyber-prinzesse/Cosmopolitan/pull/20)) *(Feldbericht)*. |

### D3DMetal bleibt der einzige praktikable DX12-Weg

D3DMetal ist Apples geschlossener Übersetzer von Direct3D 11 und 12 nach Metal, Apples eigener Grafik-Schnittstelle. Er steckt in der „evaluation environment for Windows games“ des Game Porting Toolkit (GPTK) ([Apple GPTK-Seite](https://developer.apple.com/games/game-porting-toolkit/)). Apple bringt jedes Jahr zur WWDC eine neue Hauptversion.

**Versionen:**

- GPTK 2.0 kam zur WWDC 2024 mit Raytracing und AVX2 (AppleInsider, 16.01.2025) (unsicher, nur Suchauszug). Laut Read Me braucht es macOS 14 und Rosetta 2 (GPTK 2.0 Read Me, Spiegel).
- GPTK 3 kam am 9. Juni 2025 mit Sparse Buffers, Sparse Textures und experimentellen MetalFX-Funktionen (AppleInsider, 09.06.2025) (unsicher, nur Suchauszug). Die finale 3.0 erschien am 5. Dezember 2025 und verlangt macOS 14 (Gcenx-Releases).
- GPTK 4 wurde am 8. Juni 2026 vorgestellt (AppleInsider, 08.06.2026) (unsicher, nur Suchauszug). Apples Seite bietet heute „Download Game Porting Toolkit 4“ an und verspricht „full Metal 4 support“ (Apple GPTK-Seite). Die neueste mehrfach belegte Version ist 4.0 Beta 3 vom 13. Oktober 2026 (MacGameFix) (Feldbericht). Ob es schon eine finale 4.0 gibt, ist unbelegt.

**Was D3DMetal kann.**

- Es übersetzt nur 64-Bit-Spiele mit DX11 und DX12. Die d3d10-Dateien sind laut MacPorts nutzlose Stubs (MacPorts-Portfile).
- Raytracing (DXR) lässt sich auf M3 und neuer mit D3DM_SUPPORT_DXR einschalten (GPTK 2.0 Read Me).
- ROSETTA_ADVERTISE_AVX meldet dem Spiel AVX, ändert aber nicht, was Rosetta ausführen kann (GPTK 2.0 Read Me). Bei Black Myth: Wukong scheiterte der Benchmark mit diesem Hinweis, Nightforges Profil schaltet ihn dort ab (Nightforge PR #7, Repo-Stand main).
- Seit GPTK 4 gibt es ein Metal-4-Backend für DX12. Es ist ab Beta 2 auf macOS 27 Standard und lässt sich mit D3DM_MTL4=0 abschalten (Silo EnvFlags.swift) (Feldbericht). Auf macOS 26 fällt 4.0 auf Metal 3 zurück (webmonarch/crossover-dx12-fix) (Feldbericht).

**Leistung.**

- GPTK 4 brachte je nach Spiel und Mac 6 bis 66 Prozent mehr (Macs Only!) (unsicher, nur Suchauszug).
- Red Dead Redemption 2 stieg von ca. 60 auf 75 fps (Soy de Mac) (unsicher, nur Suchauszug).
- Cyberpunk 2077 gewann nur rund 10 Prozent (AppleInsider, 17.06.2026) (unsicher, nur Suchauszug).
- In Counter-Strike 2 hatte D3DMetal den schlimmsten Einzelframe bei 94 ms, DXVK dagegen Hänger von über 1,5 Sekunden (cs2mac TUNING.md) (Feldbericht).

**Schwächen.**

- Ein Entwickler meldete Apple starke Über-Synchronisation in DX12-Titeln (FB22426600). Ein Apple-Techniker hielt dagegen, dass Frame-Zeiten Rosetta, Wine und D3DMetal zusammen enthalten (Apple-Forum 821733).
- D3DMetal meldet kein Tearing und keinen Depth-Bounds-Test, und HDR wird als SDR gemeldet (FB22330617).
- Mit 4.0 Beta 2 hängt die Ausgabe dauerhaft, wenn das Fenster verdeckt ist (Apple-Forum, GPTK-Tag).
- Die Versionen haben jeweils eigene Fehler:
  - D3DMetal 3.0 lässt Unreal-5.6-Spiele wie Satisfactory beim Start abstürzen, 4.0 Beta 2 behebt das (webmonarch) (Feldbericht).
  - Dafür zeichnet 4.0 Beta 2 Wukongs Texturen als Blöcke, weshalb Corkscrew dort bei 3.0 bleibt (corkscrew #11) (Feldbericht).
  - 4.0 Beta 3 lässt mehrere Spiele ohne Community-Fixes laufen, andere brauchen sie weiter (MacGameFix) (Feldbericht).

**Verbreitung.**

- CrossOver 26.0 bis 26.3 liefert D3DMetal 3.0 aus (webmonarch).
- Die CrossOver-Preview vom 21. August 2026 enthält D3DMetal 4 Beta 2, aber nur in Intel-Builds (CodeWeavers auf X) (unsicher, nur Suchauszug).
- Nightforge verpackt seit PR [#7](https://github.com/LordHayne/Nightforge/pull/7) das unveränderte, von Apple signierte D3DMetal 4.0 Beta 3 als eigenes Release (Nightforge PR #7, Repo-Stand main).

**metal-shaderconverter** ist kein API-Übersetzer, sondern nur ein Shader-Compiler.

- Er wandelt DXIL (das Shader-Format ab DX12, Shader Model 6.0 bis 6.6) in Metal-Bibliotheken um. Aktuell ist Version 4.0 Beta (Apple MSC-Seite).
- Ein vkd3d-proton-Fork nutzt ihn zur Laufzeit und übersetzt große Shader in 1–4 ms statt 0,4–1,7 s (VKD3D-Proton-MacOS PR #5) (Feldbericht).
- Älteren DXBC-Bytecode (das Shader-Format bis DX11) nimmt er nicht direkt; Microsofts dxilconv kann ihn vorher umwandeln (DirectXShaderCompiler) (unsicher, nur Suchauszug).
- Ob man die Bibliothek mit einer App ausliefern darf, blieb in Apples Forum unbeantwortet (Apple-Forum 829379).
- Der DXMT-Entwickler lehnt das proprietäre Werkzeug ab und baut einen eigenen Compiler (DXMT Discussion #15).

**Einschätzung:** Für DX12 gibt es heute keine realistische Alternative zu D3DMetal. Weil jede Version andere Spiele bricht, sollte Nightforge die D3DMetal-Version pro Spiel wählen und `D3DM_MTL4=0` als Notschalter führen. Für Nightforge ist metal-shaderconverter nur indirekt wichtig, als Baustein eines möglichen Vulkan-DX12-Pfads.

### DXMT liefert die ruhigsten DX10/11-Bilder, hängt aber an einem alten Release

DXMT ist ein offener Übersetzer von Direct3D 10 und 11 nach Metal für Wine. Fast alles schreibt eine Person: Feifan He („3Shain“) verfasste rund 95 Prozent der 1.481 Commits. Seit dem 25. April 2026 nutzt er eine CodeWeavers-Adresse ([DXMT-Commits](https://github.com/3Shain/dxmt/commits/main)).

Von v0.10 (Januar 2025) bis v0.80 (23. April 2026) gab es 14 Releases. **v0.80 ist bis heute das neueste Release.** Seitdem sind 365 Commits auf main gelandet, allein 119 im Oktober 2026 ([DXMT v0.80](https://github.com/3Shain/dxmt/releases/tag/v0.80)). Die angekündigte Fehlerkorrektur-Version v0.81 fehlt. Eine 1.0 ist für die „not-too-distant future“ geplant, ohne Datum ([DXMT #151](https://github.com/3Shain/dxmt/issues/151)).

**Lizenz.** main steht seit dem 25. April 2026 unter LGPL-2.1-or-later ([Commit ec357fd](https://github.com/3Shain/dxmt/commit/ec357fd582f0b7e0fee3803f6102ab786f1ba616)). Alle Releases bis einschließlich v0.80 bleiben MIT ([LICENSE.OLD](https://github.com/3Shain/dxmt/blob/main/LICENSE.OLD)). Wer heute DXMT ausliefert, hat also zwei Wege: das eingefrorene v0.80 unter MIT oder einen unversionierten Build von main unter LGPL.

**APIs und Pläne.**

- Das Release kann D3D11, D3D10 (seit v0.60) und 32-Bit-Spiele über WoW64 (seit v0.50) (DXMT Releases).
- D3D12: Seit dem 6. Juli 2026 entsteht auf main eine umfangreiche D3D12-Umsetzung, seit dem 22. Oktober 2026 kommt ein DXIL-Compiler dazu. D3D12 ist per Build-Schalter standardmäßig aus (meson.options). Auf die Frage nach Tests antwortete der Entwickler „Don’t (at the moment)“ (DXMT #194).
- D3D9: Dafür gibt es weder Code noch Branch. Die Prioritäten des Entwicklers von 2024 lauten „DX11 > DX12 (SM 5.1) = DX10 > DX9 > DX12 (SM 6.0+)“ (DXMT Discussion #4).
- Ein Metal-4-Backend steht erst nach 1.0 auf dem Plan (DXMT #151).

**Voraussetzungen.**

- DXMT braucht mindestens macOS 14, empfohlen ist macOS 15 (DXMT-Wiki).
- Wine muss mindestens 8 sein und bestimmte winemac.drv-Symbole exportieren. Geteilte Ressourcen über D3DKMT brauchen Wine 10.18 oder neuer (DXMT Releases).
- Seit dem 9. März 2026 gibt es Unterstützung für ARM64EC (ein Windows-Format, in dem ARM- und emulierter x86-Code zusammen laufen), seit dem 4. August 2026 entsprechende CI-Pakete (Commit 7ef5d9c). Das ist wichtig für eine Zeit ohne Rosetta.

**Funktionen.**

- MetalFX: DXMT hat einen MetalFX-Spatial-Upscaler auf der Swapchain, der aber nur hochrechnet (bis Faktor 2) und keine Leistung spart (CUSTOMIZATION.md).
- DLSS: DLSS Super Resolution wird mit DXMT_ENABLE_NVEXT=1 auf den MetalFX-Temporal-Scaler übersetzt. Der Entwickler rät ausdrücklich, das nicht global einzuschalten (Vendor Extensions).
- Frame-Limiter: d3d11.preferredMaxFrameRate lässt Metal das Frame-Pacing steuern. Der Wert muss ein Teiler der Bildwiederholrate sein (dxmt.conf).
- Weitere Funktionen: HDR seit v0.60, Geometry Shader seit v0.40, Tessellation über Metal-Mesh-Shader seit v0.70 (DXMT Releases).
- Fehlt: unter anderem GS-Stream-Output, DrawAuto und Predication (COMPATIBILITY_FLAG.md).

**Leistung.** Kontrollierte Vergleiche gibt es nicht.

- In Arknights: Endfield auf einem M4 Pro schaffte DXMT 120 fps, D3DMetal galt als „unspielbar“ (Endfield_FineWine PR #36) (Feldbericht; ein späterer PR markierte einzelne Werte als ungeprüft).
- In einer Linux-VM erreichte DXMT in Star Swarm 102,5 fps gegenüber 59,1 fps auf dem Vulkan-Pfad (steamac #14) (Feldbericht, kein nativer Mac-Aufbau).
- CodeWeavers’ QA sah 2025 „especially good performance benefits on lower-spec Macs“ (CodeWeavers-Blog CrossOver 25) (unsicher, nur Suchauszug).

**Offene Fehler** ([DXMT Issues](https://github.com/3Shain/dxmt/issues?q=is%3Aissue+sort%3Aupdated-desc)):

- Die Steam-Weboberfläche (CEF über ANGLE) bleibt mit DXMT schwarz ([#141](https://github.com/LordHayne/Nightforge/issues/141)).
- Unreal Engine 5 stolpert über eine Timestamp-Query ([#230](https://github.com/LordHayne/Nightforge/issues/230)).
- Ein Fehler kann mehrsekündige GPU-Stalls auslösen ([#200](https://github.com/LordHayne/Nightforge/issues/200)).
- Im Oktober 2026 wurden Abstürze in Skyrim SE, schwarze Unity-LUTs, DLSS-Schwarzbilder und Speicherlecks behoben, aber nur auf main.
- Dem dxgi.dll von DXMT fehlt eine Schnittstelle, die Wines vkd3d braucht ([#239](https://github.com/LordHayne/Nightforge/issues/239)). Der Whisky-Fork musste deshalb DX12-Spiele in DXMT-Bottles reparieren (frankea/Whisky Releases).

**Verbreitung.**

- CrossOver liefert DXMT seit 25.0 (v0.30) aus, CrossOver 26.0 enthält v0.72 (Phoronix) (unsicher, nur Suchauszug).
- Heroic hat seit 2.19 DXMT-Varianten (Heroic v2.19.0).
- Der Whisky-Fork von frankea bündelt v0.80 und wählt DXMT als „Recommended“, wenn die Engine es enthält (frankea/Whisky Releases).
- Das Projekt nimmt keine KI-gestützten Beiträge an (CONTRIBUTING.md).

**Einschätzung:** DXMT bleibt der richtige Standard für DX10/11. Seine Overrides gehören aber nur an DX10/11-Spiele, nie an den Steam-Client oder an DX12-Titel. DXMT-D3D12 ist ein Thema für 2027.

### Der Vulkan-Pfad steht zwischen abgekündigtem MoltenVK und unfertigem KosmicKrisp

Vulkan ist eine offene Grafik-API. Auf dem Mac braucht sie eine Übersetzung nach Metal. Das leisteten bisher MoltenVK und neu KosmicKrisp. Darauf laufen DXVK (Direct3D 8–11 nach Vulkan) und vkd3d-proton (Direct3D 12 nach Vulkan).

**MoltenVK ist am Ende.**

- Die letzte Version 1.4.2 erschien am 24. Juli 2026 (MoltenVK-Releases).
- Am 13. Oktober 2026 setzte Khronos einen Abkündigungshinweis in die README (MoltenVK-Commit-Historie). Für Apple Silicon empfiehlt Khronos nun KosmicKrisp, MoltenVK nur noch für Intel-Macs und iOS (MoltenVK README).
- MoltenVK fehlen robustness2 und nullDescriptor, die DXVK braucht (Meridian PR #18).
- Sein Pipeline-Cache speichert nur übersetzten MSL-Quelltext, keine fertigen GPU-Binärdaten (MoltenVK-Konfiguration).

**KosmicKrisp ist konform, aber nicht fertig.**

- Der Treiber von LunarG kam mit Mesa 26.0 (Phoronix) (unsicher, nur Suchauszug). Im September 2026 bestand er die Vulkan-1.4-Konformitätstests (Phoronix) (unsicher, nur Suchauszug).
- Er baut auf Metal 4 und braucht daher macOS 26 (LunarG-Produktseite) (unsicher, nur Suchauszug).
- Upstream fehlt die Graphics Pipeline Library (GPL). Diese Vulkan-Erweiterung lässt DXVK Shader schon beim Laden kompilieren statt erst beim Zeichnen. Ohne sie gibt es Ruckler beim ersten Auftreten eines Shaders (Sikarugir dxvk v3.1.1).
- Geometry Shader und Transform Feedback sind nur offene Mesa-Merge-Requests (steamac).
- fillModeNonSolid, das DXVK 3 in der Praxis braucht, fehlte Ende September 2026 noch upstream (Whisky #264) (Feldbericht).
- Ab Mesa 26.3 gibt es eine Leistungsregression, ein Projekt bleibt deshalb bei 26.2.4 (RecoilEngine PR #15) (Feldbericht).

**DXVK-macOS 1.10** ist seit Mai 2023 praktisch eingefroren.

- Es kann nur DX10 und DX11 (DXVK-macOS Releases). Es hängt auf 1.10, weil MoltenVK die Erweiterungen für DXVK 2.x nie bekam.
- Der Async-Patch kompiliert Pipelines im Hintergrund und ist per DXVK_ASYNC=1 einschaltbar. Dazu kommt der alte State-Cache, der Pipelines beim nächsten Start vorab baut.
- Der dxvk-async-Patch könnte laut seinem Autor theoretisch clientseitige Anti-Cheats auslösen (Sporif/dxvk-async) (unsicher, nur Suchauszug).

**Einschätzung:** Deshalb ruckelt das alte DXVK-macOS weniger als DXVK 3 auf KosmicKrisp. Es bleibt für macOS-15-Nutzer wichtig, ist aber eine Sackgasse.

**Upstream-DXVK 3.**

- Version 3.0 erschien am 25. Juni 2026, aktuell ist 3.1.1 vom 15. September 2026 (DXVK-Releases).
- 3.0 nutzt den neuen Compiler dxbc-spirv, auch für D3D9-Shader, verlangt Vulkan 1.4 und entfernt DXVK_FRAME_RATE (DXVK v3.0).
- Der State-Cache fiel schon in 2.7 weg. 3.x speichert nur noch seine Zwischenform der Shader, nicht die teuren Metal-Pipelines. GPL ist optional (DXVK-Wiki Driver support).
- Auf KosmicKrisp lief Portal in 32 Bit mit 72,3 statt 51,1 fps (Minimum 27,1 statt 4,7) gegenüber WineD3D (Whisky #264) (Feldbericht, nicht szenengleich).
- Fallout: New Vegas fiel dagegen alle 10–20 Sekunden auf 1–3 fps, weil ohne GPL beim Zeichnen kompiliert wird (Meridian PR #18) (Feldbericht).
- Sikarugir liefert DXVK 3.1.1 für KosmicKrisp und empfiehlt gegen Ruckler einen „gplasync“-Build (Sikarugir dxvk v3.1.1). Async tauscht Ruckler gegen kurz fehlende oder spät erscheinende Effekte („Pop-in“) (RPCS3 #19986).

**vkd3d-proton** (LGPL-2.1) läuft auf KosmicKrisp nur mit Community-Patches für Sparse Binding ([steamac](https://github.com/fxgl/steamac)).

- In einer VM lief die Stellar-Blade-Demo auf KosmicKrisp mit ca. 29 fps, auf MoltenVK mit ca. 18 fps. Der erste Start brauchte aber rund 28 Minuten Shader-Kompilierung (steamac) (Feldbericht).
- Cosmopolitan nutzt vkd3d-proton nur als Rückfall, wenn D3DMetal abstürzt (Cosmopolitan PR #20) (Feldbericht).

**Einschätzung:**

- Der Vulkan-Pfad ist auf dem Mac ein Rückfallweg. Upstream-GPL für KosmicKrisp ist nicht in Sicht.
- gplasync widerspricht dem Prinzip „Optik und Flüssigkeit vor FPS“ nur teilweise: Es glättet, kostet aber Bildkorrektheit. Es passt daher höchstens als bewusste Option pro Offline-Spiel.
- Als Ersatz für das tote DXVK-macOS kommt DXVK-Sarek in Frage, ein gepflegter 1.10.x-Zweig aus der Android-Szene (WinlatorWCPHub). Die MoltenVK-Patches müssten aber portiert werden. Das ist ungeprüft.

### DX9 und älter: OpenGL ist auf dem Mac der Flaschenhals

Neuere macOS-Versionen führen keine 32-Bit-Prozesse mehr aus. Wine löst das für 32-Bit-Spiele mit dem „neuen WoW64“: 32-Bit-Windows-Code läuft in einem 64-Bit-Prozess, und jeder Aufruf an das 64-Bit-System geht durch einen „Thunk“ (eine Übersetzungsfunktion zwischen 32 und 64 Bit) ([Wine 9.0 ANNOUNCE](https://github.com/wine-mirror/wine/blob/wine-9.0/ANNOUNCE.md)). Schon Wine 9.0 nannte als Grenze „Reduced OpenGL performance and lack of ARB_buffer_storage“.

**Die Ursache ist doppelt.**

- Jeder OpenGL-Aufruf von WineD3D wird gethunkt.
- Gemappte GL-Puffer liegen oberhalb von 4 GB, wo 32-Bit-Code sie nicht sieht. Wine kopiert sie dann in einen Zwischenpuffer und wieder zurück („Doing a copy of a mapped buffer (expect performance issues)“) (unix_wgl.c).

Upstream gibt es drei schnelle Wege:

- Vulkan-Speicherimport (Wine 11.0)
- GL_AMD_pinned_memory
- neu GL_MESA_map_buffer_client_pointer in Wine 11.21 vom 30. Oktober 2026 (Commit c44867a). Diese Mesa-Erweiterung unterstützt bisher nur Zink (Phoronix) (unsicher, nur Suchauszug).

**Einschätzung:** Alle drei Wege brauchen Erweiterungen, die Apples eingefrorenes OpenGL 4.1 nicht hat. Auf Apples OpenGL bleibt der langsame Kopierweg also bestehen. Eine Mac-spezifische Lösung ist nicht angekündigt.

**WineD3D über Vulkan** ist laut Wine 11.0 „not yet at parity with the GL renderer“ und nicht Standard ([Wine 11.0 ANNOUNCE](https://raw.githubusercontent.com/wine-mirror/wine/wine-11.0/ANNOUNCE.md)). Bis Wine 11.21 hat sich das nicht geändert ([Wine 11.21 ANNOUNCE](https://github.com/wine-mirror/wine/blob/wine-11.21/ANNOUNCE.md)). Mac-Messungen gibt es keine.

**Zink auf KosmicKrisp** ist ein neuer Community-Weg. Zink setzt OpenGL auf Vulkan um. Ein Wine-Build nutzt damit statt Apples OpenGL den Stack Zink → KosmicKrisp → Metal.

- WineD3D erreicht so Featurelevel 11_1 statt 9_3. Die d3d9-Tests scheitern an denselben 8 Stellen wie mit Apples OpenGL (athei/wine-build #21) (Feldbericht).
- Ein Noita-Spieler fand Zink aber langsamer und ruckeliger als Apples OpenGL (Hadron PR #45) (unsicher, nur Suchauszug).

**Einschätzung:** Zink löst Featurelevel-Grenzen, nicht den CPU-Aufwand. Es ist aber der einzige Mac-GL-Stack, der Wines neuen 11.21-Pfad nutzen könnte.

**DXVK 3 auf KosmicKrisp** umgeht OpenGL ganz. **Einschätzung der Recherche:** DXVK läuft als Windows-DLL im 32-Bit-Prozess und bündelt Arbeit in Befehlspuffer. Nur Vulkan-Einstiegspunkte kreuzen die WoW64-Grenze. Das passt zu den gemessenen Gewinnen (Portal, Sonic Adventure DX, siehe oben). Die Kosten pro Vulkan-Thunk hat niemand gemessen.

**mtld3d** ist ein neues, freies Direct3D 9 auf Metal (zlib-Lizenz). Es ersetzt `d3d9.dll`, übersetzt Shader Model 1–3 und Fixed Function nach MSL und will „the fastest Direct3D 9 implementation for Wine on macOS“ werden ([athei/mtld3d](https://github.com/athei/mtld3d)). Auf x86_64-Wine braucht es einen x87-Patch. Benchmarks gibt es nicht.

**x87 ist ein eigenes Problem.** x87 ist der alte Gleitkomma-Befehlssatz von Intel, den Rosetta nur langsam in Software nachbildet.

- FalloutNV.exe enthält 69.791 x87- gegen 740 SSE-Befehle. Der Hauptthread lief mit WineD3D und DXVK gleichermaßen voll ausgelastet (Meridian PR #18) (Feldbericht).
- Ein Apple-Forenbeitrag berichtet von D3D9-Spielen mit 0–0,5 fps ohne den Workaround „rosettax87“ (Apple-Forum, GPTK-Tag).
- Das Projekt WineMetalGL liefert dafür einen „x87sidecar“, seine Zahlen sind aber Eigenangaben (WineMetalGL Releases) (Feldbericht).

**dgVoodoo2** übersetzt Glide, DirectDraw und D3D1–9 nach D3D11 oder D3D12.

- Es ist Freeware ohne Quellcode, aktuell v2.87.6 vom 25. Oktober (Jahr aus der Reihenfolge erschlossen) (dgVoodoo2-Releases).
- Ab 2.81 scheitert es unter Wine an der Geräteerkennung (DXVK #5217).
- Ein Nutzer berichtet gute Ergebnisse mit dgVoodoo 2.79.3 auf DXMT für DX9-Spiele (DXMT Discussion #4) (Feldbericht).
- Die Weitergaberegeln sind informell (VOGONS) (unsicher, nur Suchauszug).

**Einschätzung:** Für 32-Bit-DX9 braucht es eine Entscheidung pro Spiel (siehe Tabelle). Meridians Zählung von x87- und SSE-Befehlen ist dafür ein billiges statisches Signal. mtld3d ist der vielversprechendste neue Kandidat, aber unerprobt.

### Wine 11 aus CrossOver-Quellen ist der Konsens der freien Launcher

Wine übersetzt Windows-Systemaufrufe nach macOS. Ein „Prefix“ oder eine „Bottle“ ist ein eigenes, simuliertes Windows-Verzeichnis.

**Upstream-Wine.**

- Wine 10.0 erschien am 21. Januar 2025 mit voller ARM64EC-Unterstützung (Wine 10.0 ANNOUNCE).
- Wine 11.0 kam am 13. Januar 2026. Es erklärt das neue WoW64 für „fully supported“, erklärt reine 32-Bit-Prefixe (WINEARCH=win32) für veraltet und entfernt den wine64-Loader (Wine 11.0 ANNOUNCE).
- Das neue WoW64 muss man beim Bauen trotzdem mit --enable-archs=i386,x86_64 anfordern (configure.ac).
- Die aktuelle Entwicklerversion ist 11.21 vom 30. Oktober 2026 (Wine-Tags).

**CrossOver.**

- CrossOver 25.0 vom 11. März 2025 basierte auf Wine 10.0, brachte D3DMetal 2.1, erstmals DXMT und eine automatische Backend-Wahl (Phoronix) (unsicher, nur Suchauszug).
- CrossOver 26.0 vom 10. Februar 2026 basiert auf Wine 11.0 mit D3DMetal 3.0, DXMT 0.72, Wine Mono 10.4.1 und vkd3d 1.18 (Phoronix) (unsicher, nur Suchauszug). Es enthält MSync für den Mac und kein ESync mehr (linux.org/OMG! Ubuntu) (unsicher, nur Suchauszug).
- Die aktuelle stabile Version ist 26.3.0 vom 21. Juli 2026 (CodeWeavers-Changelog) (unsicher, nur Suchauszug). Die Quellen von 26.3.0 sind öffentlich. Ein Projekt baut daraus Wine für x86_64 unter Rosetta (cartouche-wine).

**CrossOver 27** soll Anfang 2027 kommen. Es läuft nur noch auf Apple Silicon ab macOS Sonoma. 32-Bit-Bottles „will no longer run, full stop“ ([CodeWeavers-Blog, 11.06.2026](https://www.codeweavers.com/blog/mjohnson/2026/6/11/whats-in-and-whats-out-for-crossover-27)) *(unsicher, nur Suchauszug)*.

Seit dem 31. Juli 2026 gibt es außerdem eine native ARM64-Preview mit ARM64-Wine, ARM64EC und einer eigenen macOS-Version von FEX. Sie braucht macOS 26.5, hat kein D3DMetal und kein DX12 und ist „not expected to be useful for anything beyond testing“ ([CodeWeavers-Blog, 31.07.2026](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac)) *(unsicher, nur Suchauszug)*.

**Nightforges Basis.**

- Laut PR [#7](https://github.com/LordHayne/Nightforge/pull/7) nutzt Nightforge bereits winecx 4.7.3, also Wine 11.17 plus CrossOver-Änderungen plus msync (Nightforge PR #7, Repo-Stand main). Damit liegt die Hauptengine auf dem Stand, den auch frankea/Whisky, Silo und Nightport aus CrossOver-26.x-Quellen bauen. Highball bietet ebenfalls eine Wine-11-Engine aus dem 26.3-Baum (frankea/Whisky Releases; Silo; Nightport; Highball).
- Der Altlast-Teil ist Wine 7.7. Es entspricht der Generation CrossOver 22.1.1, auf der auch das alte Whisky lief (Whisky).
  - GPTK-4-DLLs scheitern auf Wine 7.7 an einer ABI-Abweichung und müssen gepatcht werden (heroic-gtpk4.0-b3) (Feldbericht).
  - DXMT braucht Wine 8 oder neuer (siehe oben).

**Apples GPTK-Wine** ist aus CrossOver-Quellen gebaut ([CodeWeavers-Blog 2023](https://codeweavers.com/blog/mjohnson/2023/6/6/wine-comes-to-macos-apple-s-game-porting-toolkit-powered-by-crossover-source-code)) *(unsicher, nur Suchauszug)*. Apple positioniert es als Werkzeug, um Spiele zu „evaluieren“, und verweist Endnutzer an Homebrew und CrossOver ([Apple GPTK-Seite](https://developer.apple.com/games/game-porting-toolkit/)). Laut einem Projekt läuft das D3DMetal-Paket nur auf Wine-Builds, die von CrossOver abstammen ([dappermint/winecx-gptk](https://github.com/dappermint/winecx-gptk)) *(Feldbericht)*.

**msync** ersetzt die langsame Synchronisation über den wineserver durch Mach-Semaphoren. Auf einem M2 Max erreichte Final Fantasy XIV damit 219 fps gegenüber 93 fps mit serverseitiger Synchronisation ([marzent/wine-msync](https://github.com/marzent/wine-msync)) *(Messung des Autors)*. msync ist nicht in Upstream-Wine. Upstreams Antwort heißt NTSync und ist ein Linux-Kerneltreiber ([Wine 11.0 ANNOUNCE](https://github.com/wine-mirror/wine/blob/wine-11.0/ANNOUNCE.md)).

**Natives ARM64-Wine upstream** ist mit Wine 11.21 noch nicht da. Es sind nur Vorarbeiten gelandet, und alter i386-macOS-Code wird gelöscht ([Wine-Commits](https://github.com/wine-mirror/wine/commits/master); [macgameport #16](https://github.com/macgameport/cities-skylines-2-macos/issues/16)). Brendan Shanks (CodeWeavers) schrieb, macOS 26.5 bringe die nötigen Bausteine: einen „x18 custom ABI“-Modus, Prozesse mit 4K-Seiten und TSO pro Thread ([wine-devel](https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/thread/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/)) *(unsicher, nur Suchauszug)*.

**Einschätzung:** Nightforge sollte Wine 7.7 abschalten und nur noch winecx mit neuem WoW64 und 64-Bit-Prefixen nutzen. Apples GPTK-Wine taugt nicht als Basis.

### Rosetta endet als Allzweckwerkzeug mit macOS 27

Rosetta 2 übersetzt x86_64-Programme nach ARM. Auch CrossOver braucht es dafür ([CodeWeavers-Blog, 11.06.2026](https://www.codeweavers.com/blog/mjohnson/2026/6/11/whats-in-and-whats-out-for-crossover-27)) *(unsicher, nur Suchauszug)*.

**Apples Ankündigungen.**

- Apple schreibt: Rosetta „will be available through macOS 27 — as a general-purpose tool“. Danach bleibt „a subset of Rosetta functionality aimed at supporting older unmaintained gaming titles, that rely on Intel-based frameworks“ (Apple: About the Rosetta translation environment).
- Apples Developer News vom 1. September 2026 nennt macOS 27 die „Final release to support Rosetta“ (Apple Developer News).
- Die Notizen zu macOS 26.4 sichern Rosetta auch für Intel-Binärdateien in Linux-VMs zu (macOS 26.4 Release Notes).

Die Release Notes zu macOS 27 enthalten drei wichtige Punkte ([macOS 27 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)):

1. Nur in Betas gibt es das Werkzeug sudo game-test-tool enable für „legacy Intel-based games“. Es schaltet Rosetta ab und nutzt eine „new underlying system behavior“. Andere Prozesse können dabei abstürzen.
2. Rosetta wird nach dem Upgrade auf macOS 27.0 nicht automatisch wiederhergestellt.
3. Alle Intel-Software ist mit macOS 28 inkompatibel, „excluding legacy games“.

macOS 27 erschien laut Berichten am 14. September 2026 ([MacTrast](https://www.mactrast.com/2026/09/apple-announces-27-operating-systems-public-release-date/)) *(unsicher, nur Suchauszug)*.

**Einschätzung:**

- Das „Spiele-Subset“ wirkt wie ein eigener Mechanismus, nicht wie das allgemeine Rosetta.
- Ein Wine-Stack ist ein Baum aus vielen x86_64-Hilfsprozessen (wineserver, Loader, Dienste, Steam-Client, Spiel). Ob Apple das als „older unmaintained game“ erkennt, ist offen.
- Ein einzelner Bericht zeigt, dass macOS 27.0.1 einen Wine-plus-DXMT-Wrapper als „will not open in macOS 28“ markierte (macgameport #16) (Feldbericht, unbestätigt).
- CodeWeavers plant ausdrücklich mit ARM64 und FEX und sagt, CrossOver werde „alive and thriving“ bleiben (CodeWeavers auf X) (unsicher, nur Suchauszug).

**Die Alternativen.** ARM64EC ist ein Windows-Format, in dem nativer ARM-Code und emulierter x86-64-Code im selben Prozess laufen. Wine unterstützt es seit 10.0 mit externem Emulator, zum Beispiel FEX ([Wine 10.0 ANNOUNCE](https://github.com/wine-mirror/wine/blob/wine-10.0/ANNOUNCE.md)). Rosetta kann dieser Emulator nicht sein, weil macOS ARM- und x86-Code im selben Prozess verbietet ([Apple Rosetta-Doku](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment)).

- FEX (MIT) ist ein x86-Emulator für ARM. Upstream sagte 2023 „We still don’t have plans to support MacOS“ (FEX Discussion #3267). Die aktuelle Version ist FEX-2610 vom 7. Oktober 2026 (FEX-Releases). Es gibt erste Darwin-Ports wie FEX-darwin mit 3 Sternen (FEX-darwin).
- MetalSharp-Wine ist Wine 11.20 als natives arm64-Programm mit FEX-2610 und 22 nicht eingereichten Patches (MetalSharp-Wine) (Feldbericht).
  - Es läuft nur aus dem Terminal.
  - Für i386 braucht es macOS 26.4 und das Entitlement com.apple.developer.cross-architecture-support. Der Name des Entitlements fehlt in Apples öffentlicher Doku (unsicher).
  - TSO bildet FEX in Software nach.

- Box64 und Hangover laufen nur auf Linux (Hangover; box86.org).
- Linux-VM: steamac startet Valves ARM64-SteamOS in einer libkrun-VM mit FEX, Proton und KosmicKrisp oder MoltenVK (steamac). Es funktioniert, ist aber schwer und erreicht für DX12 nur Featurelevel 12_0.
- Proton 11 zeigt, wie FEX pro Spiel abgestimmt wird: TSO, Multiblock und x87-Präzision kommen aus Steams App-Daten (Proton-11-Skript).

**Einschätzung:**

- Bis macOS 27, also bis etwa Herbst 2027, ist x86_64-Wine sicher.
- Nightforge sollte bis etwa Mai/Juni 2027, wenn die macOS-28-Betas erwartet werden, eine arm64-Engine (ARM64-Wine, ARM64EC, FEX) als Beta haben.
- Grafik dafür: DXMT hat ARM64EC-Builds, D3DMetal für arm64 ist unbekannt.
- Das Entitlement ist für ein freies Projekt das größte offene Risiko.

### Die Konkurrenz holt bei Automatik und Datenbanken auf

**CrossOver** wählt im Modus „Auto“ das Backend pro Spiel aus einer proprietären Datenbank. Fehlt ein Eintrag, nimmt es wined3d ([CrossOver-Mac-Handbuch](https://support.codeweavers.com/user-guides/crossover-mac-user-guide)) *(unsicher, nur Suchauszug)*. Die Einstellung gilt pro Bottle, nicht pro Spiel ([CrossOver 26 Advanced Settings](https://codeweavers.helpjuice.com/en_US/advanced-settings-in-crossover-mac-26)) *(unsicher, nur Suchauszug)*. Die Lebenszeitlizenz kostet 494 Dollar ([CodeWeavers-Store](https://www.codeweavers.com/store?ad=1101)) *(unsicher, nur Suchauszug)*.

**Whisky** wurde im April 2025 eingestellt ([AppleInsider, 16.04.2025](https://appleinsider.com/articles/25/04/16/whisky-development-ends-on-macos-to-help-wine-flourish)). Sein aktivster Fork ist **frankea/Whisky** 3.7.0 vom 30. August 2026 ([frankea/Whisky Releases](https://github.com/frankea/Whisky/releases)):

- Er schaltet für D3DMetal Metal 4 und MetalFX standardmäßig ein und hat einen Schalter pro Programm gegen Metal 4.
- Er leitet DLSS über Apples Brücke und lässt Frame-Generation standardmäßig aus.
- Seine Engines enthalten DXMT 0.80 und verlangen den eigenen GPTK-Download des Nutzers.

**Sikarugir** (Nachfolger von Wineskin) wählt nach DirectX-Generation: DXMT für DX10/11, D9VK für DX8/9, WineD3D für DX7 und älter, dazu cnc-ddraw ([Sikarugir](https://github.com/Sikarugir-App/Sikarugir)).

**Heroic** 2.22.4 vom 15. Oktober 2026 (Jahr erschlossen) lässt den Nutzer pro Spiel wählen und aktualisiert DXMT in installierten Wine-Versionen automatisch ([Heroic-Releases](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases)).

2026 kamen viele neue freie Launcher dazu:

- Highball (GPL-3.0, 2.100 Sterne) wählt den Renderer aus einer offenen CC0-Datenbank mit Herkunftsangabe pro Aussage. Spiele mit Kernel-Anti-Cheat markiert es schon vor dem Download als unmöglich. Renderer werden pro Start über WINEDLLPATH_PREPEND eingeblendet (Highball).
- Silo wechselt ein Spiel dauerhaft auf DXMT, wenn D3DMetal still auf WineD3D zurückfällt (Silo).
- Nightport wählt den Übersetzer nach gemessener Bildrate und Frametime-Stabilität. Konzeptionell ist es Nightforge fast gleich, aber sehr früh (Nightport).
- Bridgeplay startet Windows-Spiele aus dem nativen Mac-Steam als „Steam Play“-Werkzeug. Dafür verändert es Steam.app. Die README warnt vor einem möglichen Konflikt mit dem Steam Subscriber Agreement (Bridgeplay).
- Ein steamac-Fork namens „1.9.4-eac.1“ zielt auf Spiele mit Easy Anti-Cheat. Ob er offizielle Laufzeiten nutzt oder Schutz umgeht, ist unklar (StonkGuy/steamac) (unsicher, nur Suchauszug). Nach Nightforges Prinzip 2 nicht übernehmen.

**Ohne Wine:**

- Parallels deckelt Windows 11 auf Apple Silicon bei DirectX 11.1 und OpenGL 4.3 (tech-insider) (unsicher, nur Suchauszug).
- GeForce NOW streamt im Ultimate-Tarif bis 5K mit 120 fps (NVIDIA FAQ).

**Einschätzung:** Das sind sinnvolle Hinweise für Spiele, die Nightforge wegen Anti-Cheat oder fehlender DX12-Funktionen nicht starten kann.

**Einschätzung:** Nightforges Alleinstellung bleibt die Wahl ohne Konfiguration, der automatische Frame-Limiter und die strikte Anti-Cheat-Haltung. Bei Datenbanken und Rückmeldeschleifen holen andere auf.

### Android und Linux zeigen, wie Presets und Caches skalieren

**Valves Schichtenmodell.** Proton kombiniert vier Ebenen ([Proton-11-Skript](https://raw.githubusercontent.com/ValveSoftware/Proton/proton_11.0/proton)):

- fest eingebaute Voreinstellungen pro Steam-AppID (rund 200 IDs im Skript)
- serverseitige Konfiguration aus Steams App-Daten
- Nutzer-Umgebungsvariablen
- eine user_settings.py

Der Proton-Code steht unter einer BSD-artigen Lizenz.

**umu.**

- Die umu-database (GPL-3.0) ordnet Epic-, GOG- und Amazon-Titel Steam-AppIDs zu. Sie hat 1.213 Zeilen, davon 210 GOG und 110 Epic, und eine öffentliche API (umu-database).
- umu-protonfixes (BSD-2) enthält rund 490 Fix-Dateien, meist winetricks-Verben, DLL-Overrides, Umgebungsvariablen und Registry-Einträge (umu-protonfixes). Nightforges Spiel-Fixes stammen schon daraus (Nightforge README, Repo-Stand main).

**Fossilize** (MIT) zeichnet Vulkan-Pipeline-Zustände auf und spielt sie später wieder ab, damit der Treiber sie vorab kompiliert ([Fossilize](https://github.com/ValveSoftware/Fossilize)). In steamacs VM funktioniert das über MoltenVK oder KosmicKrisp. Danach sinkt die Pipeline-Erstellung dank Metals Disk-Cache von ca. 102 ms auf 0,95 ms ([steamac README](https://raw.githubusercontent.com/fxgl/steamac/main/README.md)) *(Feldbericht)*.

**Android.**

- Winlator-Forks verteilen DXVK, VKD3D, FEX und Treiber als versionierte Komponentenpakete und erlauben Einstellungen pro Verknüpfung (WinlatorWCPHub).
- GameNative wendet Community-Konfigurationen automatisch an, sammelt aber immer anonyme Analysedaten (GameNative).
- GameHub ist geschlossen, verlangt Login und steht wegen Trackern und fehlender Namensnennung in der Kritik (Emulation General Wiki) (unsicher, nur Suchauszug).
- BannerHub warnt beim Import einer Konfiguration, wenn sie auf einem anderen Chip erstellt wurde (BannerHub).

**Einschätzung:**

- Übertragbar: das Schichtenmodell (eingebaute Defaults, signierte Spieldaten, Nutzer-Overrides), die Store-ID-Normalisierung, eine offline in JSON übersetzte Teilmenge der protonfixes und Fossilize als Prototyp.
- Nicht übertragbar: NTSync (Linux-Kernel), Android-Treibertausch und Anti-Cheat-Laufzeiten.
- Login-Zwang und Dauer-Telemetrie widersprechen Nightforges Haltung.

### Shader-Caches: jede Schicht hat ihren eigenen Ort und ihre eigenen Fallen

Ein Shader-Cache speichert übersetzte oder kompilierte Shader, damit spätere Starts nicht erneut ruckeln.

**D3DMetal** legt pro EXE eine Datei unter `$(getconf DARWIN_USER_CACHE_DIR)/d3dm/<Spiel>/shaders.cache` ab ([GPTK 2.0 Read Me](https://github.com/HmWhyNot/macOS-SMW-Tools/blob/main/common/Frameworks/renderer/d3dmetal/2.0/Read%20Me.rtf)).

- Ein Projekt beobachtete 869 MB (gamify) (Feldbericht).
- Der Cache gilt für alle Bottles und alle GPTK-Versionen gemeinsam. Eine Umgebungsvariable zum Verschieben ist nicht bekannt (corkscrew #13) (Feldbericht).
- Veraltete Caches können nach einem Versionswechsel Abstürze auslösen. NotProton löscht sie deshalb automatisch (NotProton PR #267) (Feldbericht).
- Ein Log zeigt „AGX: exceeded compiled variants footprint limit“ (Bridgeplay #653) (Feldbericht).

**DXMT** cacht übersetzte Shader seit v0.71. Mit `DXMT_SHADER_CACHE_PATH` lässt sich der Ort setzen, mit `DXMT_SHADER_CACHE=0` abschalten ([DEVELOPMENT.md](https://github.com/3Shain/dxmt/blob/main/docs/DEVELOPMENT.md)).

**Metal selbst** hat einen Systemcache unter `com.apple.metal` ([aras-p Gist](https://gist.github.com/aras-p/5a9ae8f1f7d9998f732aff26dfa62617)).

- In macOS 27 liegt er laut Nutzern pro Bundle-ID in einem eigenen Unterordner (claude-code #80472) (Feldbericht, undokumentiert).
- Vorab gebaute Metal-Archive verfehlen bei anderem OS oder anderer GPU-Architektur (WWDC25 Session 254).

**DXVK-macOS 1.10** speichert portable Pipeline-Beschreibungen in `.dxvk-cache`. Ohne `DXVK_STATE_CACHE_PATH` landen sie im Arbeitsverzeichnis des Spiels ([Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS)). MoltenVK kann mit `MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=1` mehr parallel kompilieren ([MoltenVK-Konfiguration](https://raw.githubusercontent.com/KhronosGroup/MoltenVK/main/Docs/MoltenVK_Configuration_Parameters.md)).

**KosmicKrisp.**

- Ein Patchsatz von steamac fügt einen Pipeline-Cache im Speicher und Mesas Disk-Cache hinzu. Der Schlüssel enthält Dylib-UUID, GPU-Familie und MSL-Version. Der erste Start von Dragon’s Dogma 2 sank damit von ca. 62 auf 8,5 Minuten (steamac PR #18) (Feldbericht).
- Ein anderes Projekt fand, dass KosmicKrisps Disk-Cache Pointer speicherte, die nur im selben Prozess gültig sind, und schaltete ihn ab (lucamignatti Gist) (Feldbericht, Datum unbekannt).

**Einschätzung:**

- Realistisch für Nightforge sind drei Schritte:
  - den D3DMetal-Cache bei Versionswechsel löschen, aber nicht beim Löschen einer Bottle
  - DXMT- und DXVK-Caches pro Spiel und Version trennen
  - die erste Sitzung als ruckelig ankündigen

- Geteilte Caches funktionieren robust nur für DXVK-1.10-State-Caches.
- Metal-Binärcaches passen nur bei gleicher GPU-Familie und gleichem OS.

### Upscaling und Frame-Pacing: MetalFX ist da, Frame-Generation bleibt Glückssache

**MetalFX** ist Apples Upscaling-Technik.

- Spatial und Temporal gibt es seit 2022 (WWDC22 Session 10103).
- Frame-Interpolation (Zwischenbilder berechnen) braucht macOS 26 (Apple-Doku MTLFXFrameInterpolatorDescriptor).
- Zur WWDC 2026 kam ein neuer neuronaler Temporal-Upscaler für M5 Pro und M5 Max (WWDC26 Metal-Guide).

**DLSS → MetalFX über D3DMetal** braucht macOS 26, `D3DM_ENABLE_METALFX=1`, die Brücken-DLLs im Prefix und DLSS im Spiel ([webmonarch](https://github.com/webmonarch/crossover-dx12-fix)) *(Feldbericht)*.

- In Satisfactory greift die Brücke nicht, weil D3DMetal einen „AMD Compatibility Mode“-Adapter meldet und NGX eine NVIDIA-Karte verlangt. FSR 3.1.5 und XeSS laufen dort (webmonarch).
- In Senua’s Saga: Hellblade II funktioniert DLSS über MetalFX (Heroic PR #5984) (Feldbericht).
- CrossOver bietet den Schalter „Enable DLSS powered by MetalFX“ für D3DMetal und DXMT (CrossOver 26 Advanced Settings) (unsicher, nur Suchauszug).

**Launcher-seitig** gibt es lsfg-metal. Es hängt Lossless-Scaling-Frame-Generation in Wine-Spiele ein, auch bei DXMT und D3DMetal. Der Nutzer braucht dafür seine eigene Lossless-Scaling-DLL. Das Projekt ist sehr früh ([lsfg-metal](https://github.com/namo-2938/lsfg-metal)) *(Feldbericht)*. MoltenVK skaliert die Swapchain standardmäßig mit Nearest-Neighbor, was bei krummen Faktoren flimmert ([MoltenVK-Konfiguration](https://raw.githubusercontent.com/KhronosGroup/MoltenVK/main/Docs/MoltenVK_Configuration_Parameters.md)).

**Frame-Pacing.**

- MoltenVK und KosmicKrisp kennen nur die Present-Modi FIFO und IMMEDIATE.
- Eine Begrenzung auf 100 fps bei 120 Hz wiederholt etwa jedes sechste Bild und ruckelt sichtbar (supcom-engine #23) (unsicher, nur Suchauszug).
- Es gibt drei schichteigene Limiter: DXMT d3d11.preferredMaxFrameRate (nur Teiler der Bildwiederholrate), D3DMetal D3DM_MAX_FPS und DXVK_FRAME_RATE in DXVK-macOS. Upstream-DXVK 3.0 hat DXVK_FRAME_RATE entfernt (DXVK v3.0).
- Game Mode gibt Spielen höchste CPU- und GPU-Priorität, greift aber nur im nativen macOS-Vollbild (Apple Support).
- Apple rät für Frame-Interpolation zu mindestens 30 fps Grundrate (Apple-Forum MetalFX) (unsicher, nur Suchauszug).

**Einschätzung:**

- Nightforges Limiter sollte nur Teiler der Bildwiederholrate nutzen (120 Hz: 120/60/40/30) und jeweils den schichteigenen Limiter setzen.
- Frame-Generation fügt Eingabeverzögerung hinzu und ist unzuverlässig (siehe „Widersprüche“). Sie gehört nicht in die Voreinstellung.
- Für den Vulkan-Pfad ist lineare Swapchain-Skalierung ein billiger Qualitätsgewinn.

### Kompatibilitätsdaten: offen ist nur ein Teil

**CodeWeavers’ Compatibility Center** hat Sternebewertungen pro Programm und CrossOver-Version. Eine öffentliche API oder Lizenz fand die Recherche nicht ([CodeWeavers-Kompatibilitätsdatenbank](https://support.codeweavers.com/en_US/the-compatibility-database)) *(unsicher, nur Suchauszug)*. Die Backend-Wahl von „Auto“ liegt in einer nicht veröffentlichten Datenbank.

**AppleGamingWiki** warnt selbst, seine GPTK-Liste „is querying any Wine compatibility“ und zeige nicht GPTK-spezifisch ([AGW](https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit)) *(unsicher, nur Suchauszug)*. Die Lizenz blieb unklar.

**PCGamingWiki** hat genau die nützlichen Felder: Direct3D-Versionen, 64-Bit-EXE, Engine und Anti-Cheat. Seit Ende August 2026 ist der Zugang aber eingeschränkt:

- Anonyme cargoquery-Abfragen sind abgeschaltet und Tabellen umbenannt (PCGW-Startseite; PCGamingWiki:API) (unsicher, nur Suchauszug).
- Der Fehler kommt mit HTTP 200 und löschte bei einem Projekt einen Cache mit 51.885 Einträgen (proton-pulse-web #497).
- Ein Swift-Projekt liest stattdessen den Wikitext über die MediaWiki-Parse-API (Meridian PR #15).
- Die Inhalte stehen laut Sekundärquellen unter CC BY-NC-SA 3.0 (Wikidata).

**ProtonDB** gibt Daten unter ODbL frei ([protondb-data](https://github.com/bdefore/protondb-data)). Sie beschreiben Linux und taugen für den Mac nur als Prognose.

**AreWeAntiCheatYet** (MIT) hat 1.167 Einträge. Die Status beschreiben Linux und Proton, nicht macOS. Die letzte Änderung war am 21. August 2026 ([games.json](https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/HEAD/games.json)). Nightforge nutzt die Daten schon ([Nightforge README, Repo-Stand main](https://github.com/LordHayne/Nightforge)).

**highball-db** ist der beste offene Mac-Datensatz ([highball-db](https://github.com/gauthierpiarrette/highball-db)).

- Er steht überwiegend unter CC0 und hat 674 Spiele: 243 mit DXMT, 123 mit D3DMetal, 32 mit DXVK und 13 mit WineD3D als Renderer.
- Nur 21 Einträge sind lokal verifiziert, 586 sind Community-Berichte.
- Die Berichte stammen laut den Einträgen von einer anderen Engine (Sikarugir-basiertes Wine 10), obwohl Highball auch eine Wine-11-Engine anbietet.

**Einschätzung:**

- Die Erkennung der D3D-Importe in den EXE-Dateien bleibt das Hauptsignal. highball-db taugt als Vorwissen.
- Für den Mac sollte Nightforge AWACY-Status umdeuten: Kernel-Anti-Cheat blockieren, Linux-„Supported“ nur als Warnung werten.
- PCGW-Daten gehören in eine getrennte Datei mit eigener Lizenz und kommen am besten aus einem CI-Job mit Bot-Zugang.

### Rechtliches: D3DMetal ist das größte Fragezeichen

**Apples GPTK-Lizenz** (Dokument EA18380 vom 17.08.2023) steckt laut einem Spiegel noch im Paket von GPTK 4.0 Beta 2 ([dbc-hbin/d3dmetal-redistributable](https://github.com/dbc-hbin/d3dmetal-redistributable)) *(Spiegel eines Dritten)*. Die wichtigsten Klauseln:

- §2A(i) erlaubt Nutzung „for the sole purpose of developing, testing, or evaluating video games“.
- §2A(iii) erlaubt Weitergabe „solely for non-commercial purposes“.
- §2C erlaubt, das Framework als Ganzes oder Teile von /redist getrennt weiterzugeben.
- §2D verbietet Änderungen und Reverse Engineering.
- §5 lässt Apple die Rechte jederzeit beenden.

**Die Praxis ist uneinheitlich.**

- Heroic lädt GPTK-Builds von Gcenx (Heroic constants.ts).
- Sikarugir hostet D3DMetal 4.0 (Sikarugir).
- Highball, frankea/Whisky und MaPC lassen den Nutzer Apples Download selbst importieren (Highball; frankea/Whisky #163).
- Nightforge hostet das unveränderte D3DMetal 4.0 Beta 3 mit Apples Lizenz und Signaturprüfung (Nightforge-Release d3dmetal-4.0b3, Repo-Stand main).
- Eine Abmahnung durch Apple fand die Recherche nicht.

**Einschätzung:**

- Nightforges Verpackung erfüllt den ausdrücklichen Wortlaut zur Weitergabe.
- Unklar bleibt, ob Spielen beim Endnutzer als „evaluating video games“ gilt. „Non-commercial“ ist nicht definiert.
- Die GPL erlaubt kommerzielle Forks, Apple verbietet aber kommerzielle Weitergabe von D3DMetal. Ein Hinweis an Forks wie bei D4Mac ist sinnvoll (D4Mac THIRD_PARTY_LICENSES).
- Als günstige Absicherung bietet sich eine Zustimmung zur Apple-Lizenz in der App an, dazu ein vorbereiteter Weg „Apples DMG selbst importieren“.

**Andere Bausteine.**

- DXVK und DXVK-macOS stehen unter zlib (DXVK LICENSE).
- MoltenVK steht unter Apache-2.0 (MoltenVK LICENSE).
- vkd3d-proton steht unter LGPL-2.1 (vkd3d-proton LICENSE).
- FEX steht unter MIT (FEX LICENSE).
- KosmicKrisp gehört zu Mesa. Mesa-Treiber sind meist MIT, das wurde aber nicht an einer Lizenzdatei geprüft (Mesa-Doku).
- Für metal-shaderconverter wurde kein Lizenztext gefunden.
- dgVoodoo2 hat nur informelle Weitergaberegeln (dgVoodoo2 README).

Nightforge selbst steht unter GPL-3.0. Getrennt geladene Komponenten bilden ein „aggregate“, auf das die GPL nicht übergreift ([Nightforge LICENSE, Repo-Stand main](https://github.com/LordHayne/Nightforge/blob/main/LICENSE)). CC-BY-NC-SA-Daten (PCGW) und ODbL-Daten (ProtonDB) gehören in getrennte Dateien mit eigenem Lizenzhinweis.

### Audio: die AVR-Probleme sind großteils in Wine 11 gelöst

Wines macOS-Audiotreiber heißt winecoreaudio.

- Er liest die Lautsprecheranordnung aus der „Audio-MIDI-Setup“-Einstellung „Lautsprecher konfigurieren“ (coreaudio.c, Wine 11.21).
- Er meldet Spielen immer 32-Bit-Float mit der aktuellen Abtastrate des Geräts (coreaudio.c).
- Registry-Schalter oder Umgebungsvariablen für Kanäle gibt es nicht. Die winecfg-Lautsprechereinstellung wirkt nicht auf das gemeldete Format (coreaudio.c, get_prop_value).

**Behobene Fehler.**

- Center und LFE vertauscht: Seit Wine 11.0 setzt Wine ein Kanal-Layout auf den Ausgang. Der Commit nennt ausdrücklich „Fixes center/LFE channels being swapped“ (Commit 7d1fd7ba). Das passt zu einem Forenbericht über fehlende Stimmen an einem Mac mini M4 mit Denon-Receiver, die mit CrossOver 26 behoben waren (CodeWeavers-Forum) (unsicher, nur Suchauszug).
- Knacksen: Wine setzte die gewünschte Puffergröße nie in Core Audio. Spiele mit 480 statt 512 Frames liefen daher leer. Wine 11.16 behebt das (Commit 07c7fcc8), Wine 11.21 korrigiert nach (Commit 8891603b).
- Fehlender Downmix: Seit Wine 11.21 mischt Apples SpatialMixer abweichende Formate um. Ein Beispiel sind 7.1.4-Dialoge in GTA V Enhanced (Commit 0c61795b).
- DirectSound: Seit Wine 11.7 unterstützt DirectSound 7.1 (Commit 0af0a69e), seit 11.14 auch Umwandlungen nach 7.1 (Commit fcd0c30c).

**Wine 7.7 hat keinen dieser Fixes.** Sein winecoreaudio setzt kein Kanal-Layout ([coreaudio.c, Wine 7.7](https://gitlab.winehq.org/wine/wine/-/blob/wine-7.7/dlls/winecoreaudio.drv/coreaudio.c)).

**Offene Punkte.**

1. Labels und „7.1 wide“: Die Label-Tabelle kennt die Apple-Labels „Rear Surround“ nicht (coreaudio.c). Wine rundet auf „typische“ Windows-Layouts und prüft dabei das veraltete „7.1 wide“ vor „7.1 Surround“ (coreaudio.c). Einschätzung (aus dem Code, ungeprüft am Gerät): Heimkino-7.1-Anlagen werden wahrscheinlich als „7.1 wide“ gemeldet. Seitliche und hintere Kanäle landen dann falsch.
2. DirectSound auf Stereo: Das eingebaute DirectSound klemmt laut Code anfangs auf Stereo (dsound primary.c). Ein anderer Commit deutet aber auf 7.1-Ausgabe hin, das ist also widersprüchlich.
3. Geräteänderungen: winecoreaudio registriert keine Listener dafür. Schaltet der Receiver mitten im Spiel um, bekommt Wine das nicht mit (coreaudio.c).
4. macOS 26: Viele Nutzer melden nach Updates auf macOS 26 Knacksen durch coreaudiod (Apple Community).

**Einschätzung:**

- Ob winecx 4.7.3 (Wine 11.17) den 11.16-Fix enthält, hängt von der Basis ab. Wahrscheinlich ja, den SpatialMixer aus 11.21 aber nicht.
- Ein „Audio-Doktor“ vor dem Start ist machbar. Er würde dieselben Core-Audio-Eigenschaften lesen wie Wine und warnen bei Stereo-Aushandlung am Receiver, bei verworfenen Labels, bei „7.1 wide“ und bei ungewöhnlichen Abtastraten. mpv ist dafür eine gute Vorlage (mpv ao_coreaudio_chmap.c).
- Apple empfiehlt für Heimkino-7.1 (drei vorne, vier hinten) die Einstellung „7.1 Rear Surround“ (Apple Audio-MIDI-Setup) (unsicher, nur Suchauszug).

### Widersprüche in den Notizen und wie sie sich auflösen

**(a) DXMT-Lizenz.**

- Belegt: Die DXMT-Notizen lasen das Repository direkt. v0.80 vom 23. April 2026 ist das neueste Release und steht unter MIT. Am 25. April 2026 wechselte main zu LGPL-2.1-or-later (LICENSE.OLD; Commit ec357fd). Ein Tag v0.81 existiert nicht.
- Andere Lesart: Die Rechts-Notizen zitieren D4Mac mit „v0.72 MIT, v0.81+ LGPL“ (D4Mac). Das widerspricht dem nicht, ist aber ungenau: Auch v0.73 bis v0.80 sind MIT. LGPL gilt für jeden Build aus main nach dem 25. April 2026, egal wie er heißt, auch für CI-Artefakte und Forks wie „v0.80 plus 262 upstream commits“ (elseform/dxmt).
- Nightforge-Repo (Repo-Stand main, lokal geprüft am Commit ffd6285): `Resources/THIRD_PARTY_NOTICES.txt`

 nennt „DXMT 0.80 MIT“. `components/sources.json`

 sagt „LGPL-2.1-or-later“ und lädt per Muster ^dxmt-v[0-9.]+-builtin\.tar\.gz$ das neueste 3Shain-Release, also heute v0.80 (Nightforge-Repository). Die Rechts-Notiz schloss daraus fälschlich, das neueste Release sei LGPL.
- Auflösung: Für das heute geladene v0.80 stimmt die Hinweisdatei (MIT), und das Manifest ist zu streng. Sobald v0.81 erscheint, lädt das Manifest automatisch eine LGPL-Version, und dann wäre die Hinweisdatei falsch. Die Hinweisdatei spricht auch von „Nightforge’s own builds of … DXMT“. Stammt so ein Build aus main nach dem 25. April, ist er LGPL.
- Empfehlung: Version fest pinnen und die Lizenz pro Version angeben.

**(b) DLSS-Frame-Generation über D3DMetal.**

- Dafür: Apple nennt „frame generation“ unter den Funktionen der Evaluierungsumgebung (Apple GPTK-Seite). Eine Binäranalyse behauptet, GPTK 4 verdrahte DLSS-FG mit dem Metal-4-Interpolator (Skyfire Works) (unsicher, nur Suchauszug, nicht prüfbar).
- Dagegen:
  - „DLSS-G unsupported“ im Log unter 4.0 Beta 2 (webmonarch)
  - keine FG in The Witcher 3 unter 4.0 Beta 2 (MacGameFix)
  - ein Absturz im Wukong-Benchmark (Nightforge PR #7, Repo-Stand main)

- Laut gamify braucht FG zusätzlich macOS 26 und einen HAGS-Hack in CrossOver 26.1 (gamify) (Feldbericht, teils auf Skyfire gestützt).
- Auflösung: Der Mechanismus existiert, aber kein Spiel ist in den Notizen unabhängig als funktionierend belegt. frankea/Whisky und Bridgeplay lassen FG standardmäßig aus. Nightforge sollte das ebenso tun.

**(c) Whisky-Archivdatum.**

- Die GitHub-Seite nennt den 11. Mai 2025, die frankea-README den 9. April 2025 (Whisky; frankea/Whisky). Die Einstellung wurde Mitte April angekündigt (AppleInsider).
- Auflösung: Ankündigung und Archivierung waren wohl getrennte Schritte. Der GitHub-Banner vom 11. Mai 2025 ist der direkte Beleg für die Archivierung. Für Nightforge ist das unerheblich.

**(d) Weitere Abweichungen.**

- Nightforges Wine-Basis: Die Launcher-Notiz nennt Nightforges winecx „well behind“. Laut PR [#7](https://github.com/LordHayne/Nightforge/pull/7) ist winecx 4.7.3 aber Wine 11.17 plus CrossOver-Änderungen (PR #7). Rückständig ist nur Wine 7.7.
- DXMT in CrossOver 26.x: Für 26.0 ist v0.72 mehrfach belegt (unsicher, nur Suchauszug). Für 26.1 nennt ein Auszug ebenfalls v0.72, für 26.2 und 26.3 ist nichts bekannt (CodeWeavers-Changelog). Sicher ist also nur v0.72 für 26.0. Nightforges v0.80 ist neuer als jede belegte CrossOver-Version.
- GPTK 4 final: Apples Seite sagt „Download Game Porting Toolkit 4“ ohne „Beta“. Ein Bot meldete am 19. Oktober „Game Porting Toolkit 4 is out“ ohne Versionsangabe (corkscrew #47). Belegt ist nur 4.0 Beta 3. GPTK 4 gilt hier als Beta.
- KosmicKrisp bei Wine-Launchern: Die Launcher-Notiz schreibt, keiner nutze es. Die Vulkan-Notiz zeigt aber frankea/Whisky (experimentell), Sikarugir (DXVK 3.1.1 für KosmicKrisp), Meridian, Cosmopolitan und dappermint mit Opt-in-Pfaden (Whisky #264; dappermint/winecx-gptk). Auflösung: Mehrere nutzen es als Option, keiner als Standard.
- KosmicKrisp-Mindest-macOS: 2025 zielte der Treiber auf macOS 15 (Metal 3.2) (LunarG XDC 2025) (unsicher, nur Suchauszug). Der heutige Treiber braucht Metal 4, also macOS 26 (Mesa-Doku) (unsicher, nur Suchauszug). Es gilt macOS 26.
- DXMT-Cache-Variablen: Die Cache-Notiz fand sie nur in einer Fork-README. Die DXMT-Notiz las sie direkt in der Upstream-Datei `docs/DEVELOPMENT.md`

 (DEVELOPMENT.md). Sie sind also upstream dokumentiert.
- Fossilize auf dem Mac: Die Cache-Notiz fand keinen Beleg, die Plattform-Notiz verweist auf steamac. Auflösung: Es ist nur in einer Linux-VM belegt, nicht mit nativem Wine.
- Transform Feedback in DXVK 3: Das DXVK-Wiki nennt es Pflicht (DXVK-Wiki), ein Tester sah es auf KosmicKrisp als optional behandelt (Whisky #264). Das ist ungelöst.
- Metal 4 auf macOS 26: Silo sagt, Beta 1 erlaube Metal 4 dort per Opt-in. webmonarch sagt, D3DM_MTL4 wirke erst ab macOS 27. Das ist ungelöst. Sicher ist nur macOS 27.
- Frame-Interpolation auf macOS 15: Ein Auszug nennt eine „Metal 3 variant (macOS 15+)“ (skills.sh) (unsicher, nur Suchauszug). Apples Doku sagt macOS 26 (Apple-Doku). Apple gilt.
- dgVoodoo2: Die Rechts-Notiz zitiert die README mit „archived state“, die Vulkan-Notiz sieht Releases bis zum 25. Oktober (dgVoodoo2 README; dgVoodoo2-Releases). Wahrscheinlich ist die README-Aussage älter. Das ist ungeklärt.
- Kleinere Punkte:
  - GPTK 2 verlor das Beta-Etikett laut AppleInsider im Januar 2025, laut Pingle Studio im April 2025. Pingle gilt als unzuverlässig (Pingle).
  - Das CrossOver-Jahresabo kostet je nach Quelle 59,95 oder 74 Dollar (Macworld) (unsicher, nur Suchauszug).
  - D3DMetal-d3d10 nennt MacPorts für 3.0 Stubs, webmonarch sagt, 4.0 „adds d3d10“. Funktionierendes D3D10 belegt keine Quelle.

### Ergebnis 2: Was Nightforge übernehmen oder ändern sollte

Sortiert nach Nutzen, innerhalb gleichen Nutzens nach Aufwand.

#### Hoher Nutzen, niedriger Aufwand

1. Wine 7.7 abschalten. Nur noch winecx (Wine 11.x) mit neuem WoW64 und 64-Bit-Prefixen.
  - Nutzen: hoch. Aufwand: niedrig bis mittel, je nachdem, welche Spiele heute noch 7.7 brauchen.
  - Wine 11.0 erklärt 32-Bit-Prefixe für veraltet (Wine 11.0 ANNOUNCE). CrossOver 27 streicht 32-Bit-Bottles (CodeWeavers-Blog) (unsicher, nur Suchauszug).
  - Wine 7.7 kann weder DXMT (braucht Wine 8+) (DXMT-Wiki) noch unverändertes GPTK 4 (heroic-gtpk4.0-b3) und hat keinen Audio-Fix (coreaudio.c, Wine 7.7).

2. DXMT-Overrides nur an DX10/11-Spiel-EXEs, nie an Steam-Client, CEF-Helfer, Launcher oder DX12-Titel.
  - Nutzen: hoch. Aufwand: niedrig.
  - Sonst wird die Steam-Oberfläche schwarz ([#141](https://github.com/LordHayne/Nightforge/issues/141)), und DX12-Spiele brechen am DXMT-dxgi ([#239](https://github.com/LordHayne/Nightforge/issues/239)) (DXMT Issues; frankea/Whisky Releases).

3. D3DMetal-Version pro Spiel (3.0 oder 4.0 Beta 3) und `D3DM_MTL4=0` als Notschalter.
  - Nutzen: hoch. Aufwand: niedrig.
  - Jede Version bricht andere Spiele (corkscrew #11; webmonarch; MacGameFix). frankea/Whisky hat denselben Schalter pro Programm (frankea/Whisky Releases).

4. Shader-Cache-Hygiene.
  - Nutzen: hoch. Aufwand: niedrig.
  - Den D3DMetal-Cache beim Versionswechsel löschen, nicht beim Löschen einer Bottle (NotProton PR #267; gamify).
  - DXMT_SHADER_CACHE_PATH pro Spiel und Version setzen (DEVELOPMENT.md).
  - DXVK_STATE_CACHE_PATH pro Spiel setzen (Gcenx/DXVK-macOS).

5. Frame-Limiter nur auf Teiler der Bildwiederholrate, über den Limiter der jeweiligen Schicht.
  - Nutzen: hoch. Aufwand: niedrig.
  - DXMT preferredMaxFrameRate (dxmt.conf), D3DMetal D3DM_MAX_FPS (webmonarch), DXVK_FRAME_RATE nur bei DXVK-macOS.
  - DXVK 3 hat diesen Schalter nicht mehr (DXVK v3.0) und braucht einen eigenen Limiter.
  - Werte wie 100 fps bei 120 Hz ruckeln (supcom-engine #23) (unsicher, nur Suchauszug).

6. Rosetta vor dem Start prüfen und die Installation anbieten.
  - Nutzen: hoch. Aufwand: niedrig.
  - macOS 27 stellt Rosetta nach dem Upgrade nicht automatisch wieder her (macOS 27 Release Notes). Heroic warnt bereits (Heroic-Releases).

#### Hoher Nutzen, mittlerer Aufwand

1. Offene Datengrundlage aufbauen.
  - Nutzen: hoch. Aufwand: mittel.
  - highball-db (CC0) als Vorwissen importieren und verified-local höher gewichten (highball-db).
  - Epic- und GOG-IDs über umu-database auf Steam-AppIDs abbilden (umu-database).
  - AWACY für den Mac umdeuten (games.json).
  - PCGW nur über einen CI-Job mit Bot-Zugang in eine getrennte CC-BY-NC-SA-Datei holen (Meridian PR #15; RHI #98).
  - Eigene Profile unter CC0 oder CC-BY zurückgeben.

2. Stillen Fehlschlag erkennen und den Rückfall speichern, dazu Messauswahl nach Frametime-Stabilität.
  - Nutzen: hoch. Aufwand: mittel.
  - Silo wechselt auf DXMT, wenn D3DMetal still auf WineD3D zurückfällt (Silo).
  - Nightport misst Frametime-Stabilität statt Spitzen-FPS (Nightport). Das passt zu „Optik und Flüssigkeit vor FPS“.
  - Eine einmalige, freiwillige Frage „Wie lief es?“ wie bei Bridgeplay speist die Daten (Bridgeplay).

3. Weiche für 32-Bit-DX9 (nur macOS 26+).
  - Nutzen: hoch. Aufwand: mittel.
  - DXVK 3.1.1 auf KosmicKrisp für CPU-gebundene Offline-Spiele (Whisky #264).
  - x87-lastige Spiele bleiben per Befehlszählung auf WineD3D (Meridian PR #18).
  - Standardmäßig ohne Async. gplasync nur als bewusste Option pro Offline-Spiel, nie bei Online- oder Anti-Cheat-Titeln (Sikarugir dxvk v3.1.1; Sporif/dxvk-async).

4. Audio: Laufzeit mit allen Wine-Fixes und ein „Audio-Doktor“.
  - Nutzen: hoch für Receiver-Nutzer. Aufwand: mittel.
  - Prüfen, ob winecx die Commits 7d1fd7ba (Wine 11.0) und 07c7fcc8 (11.16) enthält.
  - 8891603b und 0c61795b (SpatialMixer, beide 11.21) zurückportieren (Commit 0c61795b).
  - Vor dem Start das Core-Audio-Layout lesen und vor „7.1 wide“, Stereo-Aushandlung und verworfenen Labels warnen (coreaudio.c; mpv).

5. D3DMetal-Bezug absichern.
  - Nutzen: hoch, weil es eine Kernabhängigkeit sichert. Aufwand: mittel.
  - Vor dem ersten D3DMetal-Download die Apple-Lizenz in der App bestätigen lassen, wie Highball es tut (Highball).
  - Einen Weg „Apples DMG selbst importieren“ bereithalten (frankea/Whisky #163).
  - Forks in README und Hinweisen auf das Verbot kommerzieller Weitergabe hinweisen (GPTK-Lizenz, Spiegel; D4Mac).

6. mtld3d als D3D9-Weg evaluieren.
  - Nutzen: potenziell hoch, aber unbelegt. Aufwand: mittel.
  - Es umgeht OpenGL-Thunks und die Vulkan-Schicht zugleich (athei/mtld3d). Benchmarks fehlen, Nightforge müsste selbst messen.

#### Hoher Nutzen, hoher Aufwand

1. arm64-Engine parallel aufbauen (ARM64-Wine, ARM64EC, FEX), Beta bis etwa Mai/Juni 2027.
  - Nutzen: sehr hoch, weil davon der Fortbestand nach Rosetta abhängt. Aufwand: hoch.
  - CodeWeavers geht diesen Weg (CodeWeavers-Blog, 31.07.2026) (unsicher, nur Suchauszug).
  - Bausteine sind Shanks’ kommende Upstream-MRs, FEX-Darwin-Ports und MetalSharp-Wine (MetalSharp-Wine; FEX-darwin), dazu DXMT-ARM64EC-Builds (Commit 7ef5d9c).
  - Das Entitlement früh bei Apple klären.
  - FEX-Profile pro Spiel nach Proton-11-Vorbild planen (Proton-11-Skript).

2. Eigener KosmicKrisp-Build mit Disk-Cache- und Parallel-Patches, danach Fossilize prüfen.
  - Nutzen: hoch (weniger Ruckler). Aufwand: hoch.
  - steamacs Patches senkten einen Erststart von 62 auf 8,5 Minuten (steamac PR #18).
  - Den Pointer-Fehler im Disk-Cache vorher ausschließen (Gist).
  - Fossilize-Capture pro Spiel und DXVK-Version, Replay im Hintergrund (Fossilize).
  - Mesa-Version pinnen (26.3-Regression) (RecoilEngine PR #15).

#### Mittlerer Nutzen, niedriger Aufwand

1. DXMT-Lizenzangaben bereinigen und Version fest pinnen; Kanäle bewusst wählen.
  - Nutzen: mittel. Aufwand: niedrig.
  - v0.80 unter MIT als stabiler Kanal, ein gepinnter main-Build unter LGPL als Option für die Oktober-Fixes (DXMT v0.80; LICENSE). Details unter „Widersprüche (a)“.

2. DLSS → MetalFX nur per Spiel-Whitelist, Frame-Generation standardmäßig aus.
  - Nutzen: mittel. Aufwand: niedrig.
  - Die Brücke scheitert je nach Adapter-Kennung (webmonarch). FG stürzte in Wukong ab (PR #7).
  - Bei DXMT nie global NVEXT einschalten (Vendor Extensions).
  - Keine nvngx.dll in Spielordner von Anti-Cheat-Titeln kopieren.

3. MoltenVK-Schalter setzen.
  - Nutzen: mittel. Aufwand: niedrig.
  - MVK_CONFIG_SWAPCHAIN_MIN_MAG_FILTER_USE_NEAREST=0 für weichere Skalierung und MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=1 für schnelleres Kompilieren (MoltenVK-Konfiguration). Ungemessen.

4. Spiele bevorzugt im nativen macOS-Vollbild starten.
  - Nutzen: mittel (unsicher). Aufwand: niedrig.
  - Nur dort greift Game Mode (Apple Support). Ob Wine-Spiele als Spiel erkannt werden, ist offen.

5. DXMT 1.0, DXMT-D3D12 und Metal-4-Backend beobachten.
  - Nutzen: mittel, ab 2027. Aufwand: niedrig.
  - Ein offenes D3D12 auf Metal wäre die erste Alternative zu D3DMetal (DXMT #151; DXMT #194).

#### Mittlerer oder niedriger Nutzen, mittlerer bis hoher Aufwand

1. Zink auf KosmicKrisp für WineD3D testen.
  - Nutzen: unklar. Aufwand: mittel.
  - Es bringt Featurelevel 11_1 und als einziger Mac-GL-Stack Wines 11.21-Pfad (athei/wine-build #21), war aber in einem Bericht langsamer (Hadron PR #45) (unsicher, nur Suchauszug).

2. DXVK-Sarek als Ersatz für DXVK-macOS 1.10 prüfen.
  - Nutzen: mittel. Aufwand: hoch.
  - Sarek ist ein gepflegter 1.10.x-Zweig (WinlatorWCPHub). Die MoltenVK-Patches müssten portiert werden.

3. vkd3d-proton auf KosmicKrisp als letzter DX12-Rückfall.
  - Nutzen: niedrig bis mittel. Aufwand: hoch.
  - Das braucht Community-Patches, LGPL-Quellen und sehr lange Erstkompilierung (Cosmopolitan PR #20; steamac).

4. dgVoodoo2 → DXMT für einzelne DX≤9-Spiele testen, aber nicht bündeln.
  - Nutzen: niedrig bis mittel. Aufwand: mittel.
  - Es gibt einen positiven Nutzerbericht (DXMT Discussion #4), aber den Wine-Fehler ab 2.81 (DXVK #5217) und informelle Lizenzregeln.

#### Nicht übernehmen

- Den steamac-Fork „eac“. Es ist unklar, ob er Anti-Cheat umgeht. Das widerspricht Prinzip 2 (StonkGuy/steamac) (unsicher, nur Suchauszug).
- Den Eingriff in Steam.app wie bei Bridgeplay. Er birgt ein Risiko mit dem Steam Subscriber Agreement (Bridgeplay).
- Dauerhafte Telemetrie und Login-Zwang wie bei GameNative oder GameHub (GameNative).
- EAC- und BattlEye-Laufzeit-Installationen aus protonfixes ungeprüft übernehmen (umu-protonfixes).
- D9VK oder DXVK-macOS-D3D9 (archiviert bzw. nicht unterstützt) (Sikarugir d9vk; DXVK-macOS).
- metal-shaderconverter und dgVoodoo2 bündeln, solange die Lizenz unklar ist (Apple-Forum 829379; dgVoodoo2 README).

### Ergebnis 3: Risiken mit Zeitachse

| Zeitpunkt | Risiko | Folge für Nightforge | Quelle |
|---|---|---|---|
| seit 23./25.04.2026 | DXMT: letztes MIT-Release v0.80, main unter LGPL, v0.81 seit über 6 Monaten angekündigt, 365 Commits ohne Release | Wahl zwischen alt und stabil (MIT) oder neu und ungeprüft (LGPL); Lizenzhinweise pflegen | [DXMT v0.80](https://github.com/3Shain/dxmt/releases/tag/v0.80); [Commit ec357fd](https://github.com/3Shain/dxmt/commit/ec357fd582f0b7e0fee3803f6102ab786f1ba616) |
| seit Ende 08/2026 | PCGamingWiki: anonyme Cargo-Abfragen aus, Tabellen umbenannt, Fehler mit HTTP 200 | Datenabruf bricht still; Bot-Zugang und eigener Cache nötig | [PCGW-Startseite](https://www.pcgamingwiki.com/wiki/Home) *(unsicher, nur Suchauszug)*; [proton-pulse-web #497](https://github.com/mdeguzis/proton-pulse-web/issues/497) |
| seit macOS 27 (ca. 14.09.2026) | Rosetta nach dem Upgrade nicht automatisch da; Metal-Cache-Pfad pro Bundle-ID; Metal-4-Backend Standard in D3DMetal 4 | Rosetta-Check; neue Regressionen pro Spiel | [macOS 27 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes); [claude-code #80472](https://github.com/anthropics/claude-code/issues/80472) |
| seit 13.10.2026 | MoltenVK abgekündigt, letzte Version 1.4.2 (24.07.2026) | DXVK-macOS-Pfad ohne Zukunft; macOS-15-Nutzer hängen daran | [MoltenVK README](https://raw.githubusercontent.com/KhronosGroup/MoltenVK/main/README.md); [MoltenVK-Releases](https://github.com/KhronosGroup/MoltenVK/releases) |
| laufend | GPTK-Lizenz: Zweck „evaluating“ unklar, Kündigung durch Apple jederzeit möglich (§5); GPTK 4 nur als Beta belegt | DX12-Weg rechtlich und technisch von Apple abhängig | [GPTK-Lizenz, Spiegel](https://github.com/dbc-hbin/d3dmetal-redistributable); [MacGameFix](https://github.com/MathiasKowoll/MacGameFix/blob/main/legacy/wiki/Games.md) |
| laufend | KosmicKrisp ohne GPL und verlässlichen Disk-Cache; Regression ab Mesa 26.3 | Ruckler im Vulkan-Pfad; Version pinnen | [Sikarugir dxvk v3.1.1](https://github.com/Sikarugir-App/dxvk/releases/tag/v3.1.1); [RecoilEngine PR #15](https://github.com/leonseemann/RecoilEngine/pull/15) |
| laufend | AWACY wird nur sporadisch gepflegt (letzte Änderung 21.08.2026); Status beschreiben Linux | Anti-Cheat-Sperre braucht eigene Mac-Deutung | [games.json](https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/HEAD/games.json) |
| laufend | DXMT hängt an einer Person (95 % der Commits), jetzt mit CodeWeavers im Rücken | Ausfallrisiko gemildert, nicht beseitigt | [DXMT-Commits](https://github.com/3Shain/dxmt/commits/main) |
| Anfang 2027 | CrossOver 27: nur Apple Silicon und Sonoma+, keine 32-Bit-Bottles | Endgültiges Signal: 32-Bit nur noch über neues WoW64 | [CodeWeavers-Blog](https://www.codeweavers.com/blog/mjohnson/2026/6/11/whats-in-and-whats-out-for-crossover-27) *(unsicher, nur Suchauszug)* |
| ca. Januar 2027 | Wine 12.0 nach dem Jahresmuster (Spekulation); darin evtl. ARM64-macOS-Teile | Neue Basis, neue Regressionen | [Wine-Tags](https://github.com/wine-mirror/wine/tags) |
| 2027, ohne Datum | DXMT 1.0, später D3D12 und Metal 4 | Chance auf offenes DX12; Umbau der Auswahl | [DXMT #151](https://github.com/3Shain/dxmt/issues/151) |
| ca. Juni 2027 | macOS-28-Betas (Erwartung, kein Apple-Datum) | Erster Test, ob Wine unter dem „Spiele-Subset“ läuft | [macgameport #16](https://github.com/macgameport/cities-skylines-2-macos/issues/16) |
| ca. Herbst 2027 | macOS 28: Rosetta nur noch für „older unmaintained gaming titles“; D3DMetal nur x86_64; DXMT entfernt Intel-Mac-Unterstützung | Ohne arm64-Engine droht der Ausfall aller Spiele auf macOS 28 | [Apple Rosetta-Doku](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment); [MacPorts-Portfile](https://github.com/macports/macports-ports/blob/master/devel/d3dmetal/Portfile); [DXMT-Wiki](https://github.com/3Shain/dxmt/wiki/Device-System-Runtime-Specifications) |
| offen | Eingeschränktes Entitlement für natives arm64-Wine | Für ein freies Projekt möglicherweise ein Blocker | [MetalSharp-Wine](https://github.com/metalsharp/MetalSharp-Wine) *(Name des Entitlements unsicher)* |

### Ergebnis 4: Offene Fragen

**Nightforge selbst:**

1. Welche Spiele brauchen in Nightforge heute noch Wine 7.7, und warum?
2. Enthält winecx 4.7.3 (Wine 11.17) den Audio-Fix aus 11.16? Lassen sich der SpatialMixer und map_buffer_client_pointer aus 11.21 zurückportieren?

**Apple und Rosetta:**

1. Deckt Rosettas „Spiele-Subset“ in macOS 28 Wine-Prozessbäume ab? Was genau macht das game-test-tool?
2. Bringt Apple ein arm64-D3DMetal, und gilt für GPTK 4 final noch die Lizenz EA18380?
3. Braucht natives arm64-Wine wirklich ein eingeschränktes Entitlement, und kann ein freies Projekt es bekommen?
4. Erkennt Game Mode Wine-Spiele, und welche Bundle-Metadaten braucht es dafür?

**Grafik und Caches:**

1. Wann bekommt KosmicKrisp upstream GPL, Geometry Shader, Transform Feedback und einen funktionierenden Disk-Cache?
2. Trifft ein Fossilize-Replay bei nativem Wine denselben Metal-Cache wie das Spiel, besonders mit dem Pfad pro Bundle-ID in macOS 27?
3. Wie schneidet mtld3d gegen WineD3D und DXVK 3 im selben Spiel ab?
4. Wie viel kostet ein Thunk unter WoW64 bei OpenGL im Vergleich zu Vulkan auf macOS?
5. Welche DXMT-Version liefern CrossOver 26.2 und 26.3?

**Audio:**

1. Werden Heimkino-7.1-Anlagen wirklich als „7.1 wide“ gemeldet? Klemmt das eingebaute DirectSound auf Stereo? Beides braucht einen Gerätetest mit WINEDEBUG=+coreaudio,+dsound.

**Anti-Cheat, Daten und Lizenzen:**

1. Funktionieren die offiziellen EAC- oder BattlEye-Laufzeiten unter CrossOver-basiertem Wine auf macOS? Das betrifft Spiele mit Linux-Status „Supported“ und wäre keine Umgehung.
2. Erlaubt PCGamingWiki Bot-Konten wieder beliebige Cargo-Abfragen? Wie lautet die Lizenz von AppleGamingWiki?
3. Darf man metal-shaderconverter weitergeben? Ist dgVoodoo2 archiviert oder aktiv?

### Quellenhinweis

Alle Links stammen aus den neun Rechercheprotokollen vom 1. November 2026. Primärquellen sind Apples Entwicklerseiten, der Wine-Quellcode bis wine-11.21 (über den GitHub-Spiegel) und die GitHub-Repositories der genannten Projekte. Gesperrte Seiten sind als *(unsicher, nur Suchauszug)* markiert.

Für den DXMT-Lizenzwiderspruch wurden zusätzlich `components/sources.json`

 und `Resources/THIRD_PARTY_NOTICES.txt`

 im lokalen Nightforge-Klon gelesen (Repo-Stand main, Commit ffd6285), ohne etwas zu ändern. Der experimentelle DXVK-3-auf-KosmicKrisp-Pfad steht laut Auftrag nur im lokalen Stand des Autors.
