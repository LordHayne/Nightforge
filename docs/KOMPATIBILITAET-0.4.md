# Kompatibilitätsliste für 0.4

Stand 23.11.2026, Zweig `claude/kompat-liste-04` (Basis `claude/staging-035`, 3573765f). ROADMAP-0.4, Engine-Punkt 3.

Diese Liste ist nur aus dem Repo gelesen. Für dieses Dokument wurde kein Spiel neu gestartet. Jede Zeile nennt ihre Quelle als
Datei:Zeile. Steht „vermutet“ dabei, vermutet es schon die Quelle selbst. „Eigene Lesart“ heißt, dass die Schlussfolgerung
von hier stammt und nicht in der Quelle steht.

Teile, an denen sich die Liste ausrichtet (ROADMAP-0.4.md:40-42): winecx 4.7.3 (CrossOver 26.3, Wine 11.17), D3DMetal 3.0,
DXMT 0.80 mit eigenen Patches, DXVK-macOS 1.10.3, DXVK 3.1.1 für D3D9 auf KosmicKrisp (in Nightforge vorhanden, aber nicht
in der Komponentenliste, also aus: TODO.md:1458-1463), MoltenVK 1.4.2.

Abkürzungen der Quellen:
- **LAEUFT** = `docs/laeuft/LAEUFT.md`
- **TODO** = `docs/TODO.md`
- **PROF** = `profiles/profiles.json`
- **MA** = `docs/recherche/mac-abdeckung.md` (Top 200 nach Rang, Zeile = 92 + Rang)
- **T2** = `docs/recherche/top200.md`
- **EN** = `docs/recherche/engines.md`
- **CX** = `docs/recherche/engine-crossover26.md`
- **KK** = `docs/LIVE-TEST-KOSMICKRISP.md`

Spalte **Stand**:
- **gut**: läuft gut
- **Mängel**: läuft mit Mängeln
- **nicht**: läuft nicht
- **AC**: Anti-Cheat sperrt
- **offen**: nicht getestet oder kein Ergebnis

## Vorweg: was die Quellen hergeben und was nicht

- **Getestet hat Nightforge 25 Spiele.** In LAEUFT:13-56 laufen 18, 5 starten, GTA V Enhanced zeigte noch kein Bild, Dying
  Light wurde nie gestartet. Die Start-Runde vom 15.11. brachte 21 von 21 Spielen mit Bild: 6 über D3DMetal, 6 über DXMT,
  5 über WineD3D, 1 über DXVK, 3 als Mac-Version (TODO:854-858).
- **Gemessen während echten Spielens wurde noch keines.** Die Liste verlangt mindestens 16 Minuten Spielzeit
  (`docs/laeuft/ABHAKLISTE.md:10`).
- **Für die beliebten Spiele gibt es keine Spalte je Grafikweg.** Die Top 200 in MA:93-292 nennen die Mac-Version,
  Anti-Cheat und die AppleGamingWiki-Wertung für CrossOver bzw. Wine. Diese Wertungen stammen meist aus CrossOver 22–25, nicht
  aus Nightforges Teilen (MA:21). Von den Top 200 hat Nightforge 5 selbst getestet (MA:9-17).
- **Problemberichte von Spielern liegen nicht im Repo**, nur die Vorlage `.github/ISSUE_TEMPLATE/compat-report.yml`.
- **PROF und Tests widersprechen sich an drei Stellen:**
  - L4D2: Das Profil hat keinen Weg, `reported` sagt DXMT (PROF:5962).
  - Deadlock: Das Profil sagt DXVK, `reported` sagt DXMT (PROF:6828).
  - Control: Die Notiz „Not yet tested on D3DMetal“ ist veraltet (PROF:5811, LAEUFT:23).

## 1. Tabelle

### Getestete Windows-Spiele

| Spiel | Store | Weg | Stand | Befund | Nächster Schritt | Quelle |
|---|---|---|---|---|---|---|
| Black Myth: Wukong Benchmark | Steam | D3DMetal (DX12) | Mängel | Bild in 4 von 7. Mit AVX stürzt es nach ~30 s ab, mit Frame Generation auch, darum hat das Profil beides aus. Bis ~70 s zum ersten Bild (Shader). Etwa 48 s zum Beenden. Ohne Limit Ø 201 FPS. Seit Weg A gibt es ein Limit (am 22.11. mit 60 FPS gelaufen), noch nicht gemessen. | Messplan zum Limit (D3DMETAL-FPS); Nachlauf-Probe (`docs/probes/wukong-nachlauf`, Zweig start-schneller-04) | LAEUFT:22, PROF:5207, TODO:618-630, TODO:168-176, AUDIT-0.3.5.md:40, ENTWURF-D3DMETAL-FPS.md:82-87, ROADMAP-0.4.md:48 |
| Overwatch | Steam (Battle.net) | DXMT | Mängel, eigener Anti-Cheat | Bild in 9 von 20. Im exklusiven Vollbild schaltet es auf 60 Hz, und das Fenster bleibt verborgen. Mit „Randloses Fenster“ 3 von 3 Starts. Kalter Shader-Cache ruckelt (schlimmster Frame 500 ms). Kein Shader-Vorbereiten wegen Anti-Cheat. | Vollbild-Hinweis live sehen (Abnahme offen); DXMT-Fork mit `releaseShaderIR` prüfen (13 GB → 3,9 GB, Killcam 22–28 → 59,9 fps laut CX) | LAEUFT:33, PROF:4808, TODO:212-215, TODO:270-283, TODO:43, ENTWURF-SHADER.md:92-97, CX:236 |
| Control | Epic, GOG | D3DMetal (`Control_DX12.exe`) | gut | Bild in 7 von 7. Die DX11-Exe stürzt auf DXMT und DXVK ab (Seitenfehler). | Profilnotiz berichtigen | LAEUFT:23, TODO:1807-1844, PROF:5811, PROF:5936 |
| It Takes Two | Steam | D3DMetal `-dx12` | gut (mit Profil) | Bild in 7 von 9. Der PhysX-Absturz ist behoben (0df3c58). Mit `-dx11` auf DXMT/DXVK bleibt nur ein kleines Fenster ohne Bild. | – | LAEUFT:27, PROF:3678, TODO:1295-1300 |
| Hogwarts Legacy | Epic | D3DMetal | Mängel | Bild in 3 von 4. Erster Start ~80 s (Shader), „Composited“ statt Direct, die Pixelzahl ist ohne Retina halbiert. Das Pad-Menü ging nur mit der Maus; unklar, welches Menü gemeint war. | Test E2 ohne Profil (TODO:1365) | LAEUFT:26, TODO:1301-1304, TODO:1315-1316 |
| Guardians of the Galaxy | Epic | D3DMetal | gut | Bild in 3 von 4. `-nolauncher` und der Vollbild-Fix sind live bestätigt. „Composited“. | – | LAEUFT:31, TODO:1283-1293 |
| Rise of the Tomb Raider | Epic | D3DMetal (DX12) | gut | Bild in 2 von 2. Der Weg ist noch nicht bestätigt. | Weg bestätigen | LAEUFT:46, TODO:997-1001 |
| The Last Caretaker Demo | Steam | D3DMetal (DX12) | Mängel | DX11 scheitert auf jedem Weg (DXMT schwarz, DXVK auf KosmicKrisp und D3DMetal stürzen ab). DX12 spielt mit 50–55 FPS, ohne AVX, ohne Nanite. Menüvideo schwarz, Maus träge. | – (Demo) | PROF:5313, TODO:3252-3274 |
| GTA V Enhanced | Steam | D3DMetal | nicht (bisher) | Wartet auf einen Klick in einem 332×134-Fenster, laut Quelle vermutlich der Rockstar Launcher. BattlEye sperrt nur online. | Rockstar-Fenster mit Pad/Profil lösen; `-nobattleye` für die Story (T2:83); Downmix für die Dialogstimme (CX:259) | LAEUFT:56, TODO:1312-1314, MA:116 |
| Metal Gear Solid V | Steam | DXMT | gut | Bild in 4 von 10. „Failed to load SteamAPI“ ist behoben (VeriSign-Wurzel), ~60 FPS. Der Shader-Hinweis kommt zu oft. | Vergleich mit D3DMetal (TODO:1415) | LAEUFT:32, TODO:1403-1415, TODO:941 |
| ABZU | Epic | DXMT `-dx11` | gut | Bild in 11 von 14. Früher brauchte es manchmal einen zweiten Versuch, live 21.11. ohne. Im echten Vollbild stürzte es ab, darum läuft es im Fenster in Bildschirmgröße. | Stillen Neustart live sehen | LAEUFT:19, TODO:779, TODO:3060-3086 |
| Just Cause 4 | Epic | DXMT | gut | Bild in 4 von 4, hält 60 FPS. | – | LAEUFT:28 |
| Frostpunk | Epic | DXMT | gut | Bild in 2 von 2, hält 60 FPS. Ein Start am 15.11. ohne Bild. | – | LAEUFT:25, TODO:175 |
| REANIMAL | Steam | DXMT `-dx11` | gut | Bild in 3 von 3 (auf Akku gemessen). | – | LAEUFT:35 |
| OxyRail | Steam | DXMT (DXVK geht auch) | gut | Bild in 5 von 5, ~75 FPS auf DXMT gegen 45–50 auf DXVK. In der Läuft-Liste steht DXVK, im Profil DXMT. | Weg in LAEUFT angleichen | LAEUFT:34, PROF:5307, TODO:1732-1733 |
| Palworld | Steam | DXMT `-dx11` | offen | 60 FPS, aber auf Wine 11.18 gemessen. Auf DXVK nur das HUD über schwarzer Welt. | Auf winecx neu prüfen | PROF:3923, TODO:1730-1733 |
| 7 Days to Die | Steam (auch Mac) | DXMT | offen | ~63 FPS auf DXMT, DXVK sieht nur 128 MB VRAM. Startoption ohne EAC wird automatisch gewählt. Auf winecx nicht neu geprüft. | Auf winecx neu prüfen | PROF:913, TODO:1731 |
| The Forest | Steam | DXVK + MetalFX | gut | Bild in 5 von 7, 60 FPS. Auf DXMT hing es ohne Bild. Inzwischen gelöscht. | – | LAEUFT:36, TODO:2142-2196, TODO:1008 |
| Deadlock | Steam | DXVK | offen | 60–120 FPS auf Wine 11.18. Der Weg in PROF widerspricht sich (siehe oben). | Auf winecx neu prüfen | PROF:3672, PROF:6828, TODO:1730 |
| Mafia II (Classic) | GOG | WineD3D | Mängel | Bild in 9 von 9, Ø 120 FPS. 230–440 % CPU, der Ton knackt (32 Bit, OpenGL-Thunks im WoW64). KosmicKrisp brachte 46–60 FPS, aber Stopps von 3–7,7 s und dunkle Rechtecke, darum aus. | Live-Test KosmicKrisp (Ergebnistabelle leer) | LAEUFT:30, PROF:389, PROF:5918, TODO:3487-3518, TODO:1458-1463, KK:5-7 |
| Left 4 Dead 2 | Steam | WineD3D | Mängel | Bild in 5 von 5. Der Wert Ø 24 FPS war das Intro-Video. Der Mikrofon-Hänger ist behoben. DXVK scheitert an MoltenVK. VAC: nur Einzelspieler testen. | `-novid` und neu messen; KosmicKrisp-Test | LAEUFT:29, PROF:25, TODO:1513, TODO:1734-1741, KK:74-83 |
| Alan Wake | Epic | WineD3D (DX9, 32 Bit) | gut | Bild in 3 von 6, Ø 210 FPS. DEVICE_CREATE_ERROR ist behoben (fe1b8fa). Ein Start am 14.11. ohne Bild. | – | LAEUFT:20, TODO:1395-1401 |
| Dishonored | Epic | WineD3D (Unreal 3) | gut | Bild in 5 von 5, Ø 105 FPS. | – | LAEUFT:24, TODO:163 |
| Batman: Arkham Asylum | Steam | WineD3D (Unreal 3) | Mängel | Bild in 3 von 3, Ø 48 FPS, aber 156 s bis zum Bild. | Die Wartezeit klären | LAEUFT:21, TODO:1418-1424, TODO:301-303 |

### Mac-Versionen (laufen ohne Grafikweg)

| Spiel | Store | Stand | Befund | Nächster Schritt | Quelle |
|---|---|---|---|---|---|
| Valheim | Steam für Mac | gut | Startet seit F1 im Vollbild (live 22.11.). | – | LAEUFT:48, TODO:577-587 |
| Drawful 2 | Steam für Mac | gut | Live 21.11. ohne Frage. | – | TODO:780, TODO:1598-1602 |
| Hearthstone | Battle.net | gut | Live 21.11. | – | TODO:780 |
| Tomb Raider (2013) | Steam für Mac | gut | Startet. Die macOS-Abfrage unter dem Vorhang ist behoben. | – | LAEUFT:47, TODO:2929-2977 |
| Asphalt Legends | Steam für Mac | gut | Startet. | – | LAEUFT:44 |
| No Man's Sky | Steam (Mac) | offen | Startet unter Windows-Wine nur mit Nightforges Vulkan-Schicht. MoltenVK 1.4.0 scheiterte an den Shadern. | Vulkan-Prüfung | PROF:1069, TODO:4033 |
| Dying Light | Steam für Mac | offen | Nie gestartet. | Erster Start von Hand | ABHAKLISTE.md:42 |
| A New Beginning: Final Cut | GOG (Mac, x86_64) | gut | Live 31.10. | – | TODO:3460-3461 |

### Beliebte Spiele ohne eigenen Test (Auswahl aus den Top 200, Rang nach MA)

| Spiel (Rang) | Weg laut Quelle | Stand | Befund | Nächster Schritt | Quelle |
|---|---|---|---|---|---|
| Counter-Strike 2 (1) | D3DMetal (Feldbericht) | offen | AGW: CrossOver perfekt. D3DMetal schlimmster Frame 94 ms, DXVK über 1,5 s. VAC: Nightforge-Regel vorgeschlagen, nicht gesetzt. | Entscheidung zu VAC (TODO:1211-1212), dann Test | MA:93, EN:104 |
| Cyberpunk 2077 (8) | Mac-Version | – | Mac-Version vorhanden. | – | MA:100 |
| GTA V Legacy (9) | DXMT/D3DMetal | AC (online) | BattlEye nur online. Vorschlag `-nobattleye`, Story offline. | Profil nach T2:84, Test | MA:101, T2:84 |
| Overwatch (18) | DXMT | Mängel | siehe oben | – | MA:110 |
| Warframe (19) | D3DMetal (AGW) | offen | Vorschlag: Sperre lockern, DXMT; alternativ der eigene Mac-Client. | Test | MA:111, T2:91 |
| Helldivers 2 (21) | DXMT `--use-d3d11` oder D3DMetal (DX12) | offen | Stingray bekommt den DX11-Schalter nicht von selbst. | Profil nach T2:80, Test | MA:113, T2:80 |
| GTA V Enhanced (24) | D3DMetal | nicht | siehe oben | – | MA:116 |
| Team Fortress 2 (31), Garry's Mod (50) | WineD3D | offen | D3D9-Leiter: DXVK-D3D9 scheitert an MoltenVK und kostete früher einen Fehlstart; unter winecx nur noch WineD3D. Nie getestet. | Ein Start je Spiel | MA:123, MA:142, T2:46, TODO:1747-1757 |
| Marvel Rivals (33) | D3DMetal (AGW), Unreal auf DXMT | offen | AGW spielbar. DXMT stolpert bei Unreal 5 über eine Timestamp-Query (#230). | D3DMetal zuerst testen | MA:125, EN:170, TODO:1758-1760 |
| Witcher 3 Remastered (41) | DXMT `--launcher-skip` / D3DMetal | offen | AGW: CrossOver perfekt. | Profil nach T2:81 | MA:133, T2:81 |
| Red Dead Redemption 2 (46) | D3DMetal, `-fullscreen` | offen | umu erzwingt `-vulkan`, auf MoltenVK riskant. In PROF als verified-local auf DXMT geführt. | Profil nach T2:82; Rockstar Launcher | MA:138, T2:82, PROF (reported 1174180) |
| Baldur's Gate 3 (48) | Mac-Version | – | Mac-Version vorhanden. | – | MA:140 |
| Elden Ring (62) | D3DMetal | AC (online) | Offline nur mit getauschter EXE. Scheiterte bei Bridgeplay mit WineCX + D3DMetal. | Zurückstellen | MA:154, T2:93, CX:378 |
| Satisfactory (97) | D3DMetal | offen | D3DMetal 3.0 stürzt ab (UE 5.6), 4.0b2 behebt es. | Mit Engine-Punkt 1 (D3DMetal 4 je Spiel) | MA:189, EN:112 |
| Diablo IV (133) | D3DMetal | offen | Braucht macOS 26.5. Nach Season 14 ein Fehler bei `FindNextFileNameW` (Stub). | Prüfen, ob winecx den Stub hat | MA:225, CX:226, CX:373 |
| Apex, PUBG, CoD, R6, Battlefield 6, Destiny 2, Tarkov, Fortnite u. a. | – | AC | Gesperrt, Play führt zu GeForce Now. 13 Sperren fehlen noch in PROF (ARC Raiders, Delta Force, WARDOGS, EA FC 26/27, Space Marine 2, Tarkov, Nightreign, The Isle, Gray Zone, FiveM, F1 25, skate.). | Die 13 Einträge nachtragen | MA:95-99, T2:58-72, TODO:3395 |

## 2. Die zehn wichtigsten nächsten Fixes

Gewichtet nach Beliebtheit (Rang in MA, wie viele Spiele es betrifft) und Aufwand (Profil < Regel im Code < Engine-Patch <
neuer Weg). Die Reihenfolge ist eigene Lesart.

1. **13 fehlende Anti-Cheat-Sperren in die Profile** (T2:58-72): ARC Raiders (30), Delta Force (34), EA FC 26/27 u. a.
   *Aufwand klein, nur Profil.* Schützt Spieler vor einem Download, der nicht spielen kann.
2. **Profile für vier Top-50-Spiele ohne Anti-Cheat-Sperre** (T2:80-84): Helldivers 2 (`--use-d3d11`, DXMT), Witcher 3
   (`--launcher-skip`), RDR2 (D3DMetal, `-fullscreen`), GTA V Legacy und Enhanced (`-nobattleye`, nur Story). *Aufwand klein
   (Profil), dann je ein Test.* Keines davon ist auf dem Mac getestet (T2:52).
3. **D3DMetal-Limit messen** (ENTWURF-D3DMETAL-FPS.md:82-87). Weg A ist gebaut, betroffen sind Wukong, Control, Hogwarts und
   It Takes Two (TODO:168-170). *Aufwand: eine Messrunde.* Danach halten alle D3DMetal-Spiele 60 FPS wie DXMT.
4. **GTA V Enhanced: das Rockstar-Fenster** (TODO:1312-1314). Rang 24, heute ohne Bild. *Aufwand mittel:* erst klären, was
   das 332×134-Fenster will (laut Quelle vermutlich der Rockstar Launcher). Dasselbe trifft RDR2 (T2:104 nennt Rockstar als Bruchstelle).
5. **D3DMetal 4 je Spiel** (Engine-Punkt 1, ROADMAP-0.4.md:44-46). Satisfactory braucht 4.x (EN:112), Wukong muss auf 3.0
   bleiben (EN:113). *Aufwand mittel*, ist schon der nächste Engine-Punkt.
6. **Overwatch ruhig bekommen** (Rang 18). Den Vollbild-Hinweis live sehen (TODO:782-786). Gegen den Shader-Speicher und
   die Killcam-Ruckler die DXMT-Änderung `releaseShaderIR` übernehmen (CX:236). *Aufwand mittel (Engine-Patch an DXMT,
   LGPL-Regel beachten: docs/ENTSCHEIDUNG-DXMT-LGPL.md).*
7. **Neu prüfen auf winecx: Palworld, Deadlock, 7 Days to Die** (TODO:1730-1731). Die Werte stammen von Wine 11.18.
   *Aufwand klein, je ein Start.* Dabei die Widersprüche in PROF auflösen (Deadlock, L4D2, Control-Notiz, OxyRail in LAEUFT).
8. **Source-Spiele CS2, TF2, Garry's Mod, L4D2** (Ränge 1, 31, 50, 32). Zuerst die VAC-Entscheidung des Nutzers
   (TODO:1211-1212). Danach je ein Einzelspieler-Start, für L4D2 mit `-novid` neu messen (TODO:1122). *Aufwand klein.*
9. **KosmicKrisp für DX9 wieder an, je Spiel** (Mafia II, L4D2). Erst die Ruckler beheben: Graphics Pipeline Library bzw.
   der Disk-Cache-Patch in `scripts/kosmickrisp/proposed/` (TODO:4130-4155). Dann der Live-Test (KK:5-7). *Aufwand groß
   (Mesa-Patch).* Das ist auch die Grundlage für die Klassiker (Abschnitt 3).
10. **WineD3D unter WoW64 schneller** (Mafia II, Batman, alle 32-Bit-DX9-Spiele). Die OpenGL-Thunks kosten zwei volle
    CPU-Threads (TODO:3503-3515, EN:232-247). Wine 11.18–11.21 haben Teile davon, winecx 4.7.3 nicht (CX:240-254). Dazu
    der DEP-Patch gegen Hänger von 1–41 s bei 32-Bit-Spielen vor 2012 (CX:254). *Aufwand groß (Engine).*

Nicht in der Liste: Anti-Cheat-Spiele, die nur über eine Linux-Laufzeit liefen (TODO:3838-3839). Nightforge umgeht keinen
Anti-Cheat.

## 3. Klassiker (Direct3D 3–9, GOG)

Thomas' Wahl vom 23.11., wörtlich (ROADMAP-0.4.md:52-53): „Direct3D 3–7 über D7VK auf KosmicKrisp, Direct3D 8/9 über DXVK
3.1.1 bzw. WineD3D als Rückfall. Testfälle sind GOG-Klassiker.“

### Was heute über WineD3D läuft

- **DX9, belegt:** Mafia II (32 Bit, Mängel), Alan Wake (32 Bit), L4D2 (Mängel), Dishonored und Batman (Unreal 3).
  Die Runde vom 15.11. hatte 5 WineD3D-Spiele mit Bild (TODO:855, ENTWURF-STARTREZEPT.md:156-159, LAEUFT:20-30).
  Dass Batman und Dishonored DX9 sind, steht in den Quellen nicht, nur „Unreal 3 auf WineD3D“.
- **DX8:** läuft über Wines d3d8 (`.legacy`). DXVK 3.1.1 bringt ein eigenes `d3d8.dll` mit (TODO:4148). Ein DX8-Spiel ist
  in Nightforge nicht getestet.
- **DirectDraw / DX1–7:** In EN:73 ist WineD3D über OpenGL der Standard, cnc-ddraw der Rückfall für 2D-DirectDraw. Getestet
  ist kein solches Spiel. PROF hat Profile aus umu für mehrere Klassiker, ungetestet (z. B. Gothic 1 Classic PROF:285 mit
  ddraw/dinput, Outlaws PROF:2069, Re-Volt PROF:1102, Tomb Raider I PROF:763 mit glide_fix).
- **Die Regeln:** Unbekannte 32-Bit-Spiele bekommen WineD3D als ersten Weg (TODO:1400-1401). Lädt ein Spiel auf D3DMetal oder
  DXMT nur `d3d9.dll`, empfiehlt die Diagnose WineD3D (ENTWURF-STARTREZEPT.md:186). Unter winecx ohne KosmicKrisp ist
  die D3D9-Leiter nur „WineD3D“ (TODO:1747-1756, TODO:4160-4162).
- **Engpass:** Apples OpenGL 4.1 unter WoW64. Jeder GL-Aufruf wird gethunkt, gemappte Puffer werden kopiert (EN:232-247).
  Bei x87-lastigen Spielen bremst Rosetta unabhängig vom Renderer (EN:262-266).

### Was D7VK auf KosmicKrisp brächte

**Im Repo nicht belegt.** Außer ROADMAP-0.4.md:52 gibt es keine Recherche, keine Messung und keinen Code zu D7VK. EN:73 sagt
nur, dass DXVK upstream keinen D3D7-Pfad hat. Bevor gebaut wird, braucht es eine Recherche: Stand von D7VK, Lizenz, welche
Vulkan-Funktionen es von KosmicKrisp braucht.

Belegt ist, was dieselbe Grundlage (KosmicKrisp) heute für DX9 leistet:
- **Schneller:** DXVK auf KosmicKrisp war 1,4× (Portal) bis 2,5× (Sonic Adventure DX) schneller als WineD3D (EN:75), bei
  Mafia II 46–60 FPS (TODO:1458-1463).
- **Ruckelt:** KosmicKrisp hat keine Graphics Pipeline Library, also werden Pipelines erst beim Zeichnen kompiliert. Geometry
  Shader und Transform Feedback fehlen upstream. Ab Mesa 26.3 gibt es eine Regression, und es braucht macOS 26
  (EN:195-202). Fallout NV fällt alle 10–20 s auf 1–3 fps (EN:217-219). Bei Mafia II gab es Stopps von 3–7,7 s und dunkle
  Rechtecke (KK:5-7).
- **Eigene Lesart:** D7VK erbt diese Ruckler, solange KosmicKrisp keinen Pipeline-Cache hat. Fix 9 aus Abschnitt 2 kommt
  darum vor D7VK.
- **Alternativen aus EN:** dgVoodoo2 → DXMT nur als Versuch. Es ist ohne Quellcode, ab 2.81 scheitert es unter Wine, und die
  Lizenz ist informell (EN:268-275, EN:757-759). mtld3d (D3D9 direkt auf Metal) ist ein ungemessener Kandidat (EN:260,
  EN:699-701).
- **ARM64 (macOS 28):** 32-Bit-Spiele brauchen dort ein eingeschränktes Entitlement (ENTWURF-ARM64.md:103-106). Das betrifft
  fast alle Klassiker.

### GOG-Klassiker als Testfälle

In der GOG-Bibliothek auf dem Test-Mac (nur die Titel gelesen, nichts davon steht hier außer den zwei Spielen, die schon in
TODO.md vorkommen) sind nur zwei Titel älter als DX11:

| Spiel | API | Warum als Testfall | Stand | Quelle |
|---|---|---|---|---|
| Mafia II (Classic) | D3D9, 32 Bit | Bekannte Referenz für WineD3D gegen KosmicKrisp, mit Messwerten | WineD3D Mängel, KosmicKrisp aus | LAEUFT:30, TODO:3487-3518, KK:5-7 |
| A New Beginning: Final Cut | – (GOG-Mac-Version, x86_64) | Nur für Rosetta, nicht für den Grafikweg: Nightforge startet die Mac-Version | gut (live 31.10.) | TODO:3460-3461 |

Die übrigen sind DX11/12-Spiele.
Für Direct3D 3–8 gibt es im Konto keinen Testfall. **Vorschlag zur Wahl:** Thomas holt sich zwei, drei günstige
GOG-Klassiker, etwa je einen mit DirectDraw/D3D5–7 und einen mit D3D8. Welche, entscheidet er. Ohne sie lässt sich
D7VK nicht prüfen.
