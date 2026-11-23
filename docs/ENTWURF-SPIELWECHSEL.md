# Entwurf: Spielwechsel ohne Steam-Neustart (0.4)

Stand 23.11.2026, Zweig `claude/spielwechsel-04` (von `claude/staging-035`, 6bf188f). Gelesen: `Engine.prepareLaunchEnvironment`,
`steamEnvironment`, F5 (`rememberLaunch`, `takeRememberedLaunch`), `SteamProgram`, `GameEnvironment`, `D3DMetalPace`,
`wrapper/d3dmetal-pace*.c/.m`, die Profile, `wine.log`/`wine.previous.log`, `start-evidence.jsonl`, `docs/ENTWURF-STARTZEIT.md`,
`docs/probes/starter-umgebung/`. Eine neue Probe ohne Steam und ohne Spiel: `docs/probes/spielwechsel-umgebung/`.

Aus den Release-Notizen, „Bekannt“: Brauchen zwei Spiele verschiedene Einstellungen, startet Steam beim Wechsel neu.

## Kurzfassung

- **Ein Neustart kostet 27–40 s** (ENTWURF-STARTZEIT, 22.11.: 38,5 s, 38,4 s, 26,9 s, 40,1 s). Am 21./22.11. kamen
  6 Neustarts fürs Spiel auf 14 Starts. Die meisten davon lagen vor F5; seit F5 bleiben die echten Wechsel.
- **Fast alles, was einen Neustart auslöst, liest die Unix-Seite beim Prozessstart:** Rosetta (`ROSETTA_ADVERTISE_AVX`),
  Wine (`WINE_*`, `CX_*`), D3DMetal (`D3DM_*`), der Vulkan-Treiber. Ein Spiel erbt diese Umgebung von steam.exe.
- **Ein Starter in Steams LaunchOptions trägt nicht** (Probe vom 22.11.): Er erreicht nur die Windows-Seite. Und LaunchOptions
  liest Steam selbst nur bei seinem Start.
- **Neu, Probe von heute:** Eine Bibliothek im *startenden* Prozess, die `execve` abfängt, kann die Unix-Umgebung des Kinds
  setzen oder wegnehmen. Rosetta folgt ihr: AVX ließ sich so ein- und ausschalten, ohne den Elternprozess neu zu starten.
  Auf steam.exe übertragen hieße das: Wechsel ohne Neustart für AVX, D3DMetal, Vulkan-Treiber und die Spiel-Schalter.
- **Gebaut: nichts an der App.** Der Weg bringt eine neue Abfangfunktion in `hide-steam-dock.dylib`, also in jeden
  Wine-Prozess, auch in Anti-Cheat-Spiele. Das ist eine Entscheidung (Abschnitt 4), kein kleiner, sicherer Bau. Weitere Neustarts,
  die ohne Neues im Spielprozess vermeidbar wären, fand ich nicht (Abschnitt 3).

## 1. Was sich zwischen Spielen unterscheidet und Steam neu starten lässt

`prepareLaunchEnvironment` vergleicht Steams Umgebung mit der, die das Spiel braucht; `changedParts` nennt die Namen,
`restartParts` dazu „program“, „debug“, „framelog“. Seit 0.3.5 steht die Liste im Protokoll („Steam restarts for … (…)“). Die
Zeilen vom 21./22.11. stammen noch aus Bauten ohne sie.

| Auslöser | Spiele (Profile und Wege heute) | Wer liest es | Wie teuer |
|---|---|---|---|
| `ROSETTA_ADVERTISE_AVX` aus | 2 von 745 Profilen (Wukong Benchmark, The Last Caretaker Demo); gelernt `learned.noAVX` | Rosetta beim exec | Steam-Neustart |
| `D3DM_MAX_FPS`, `D3DM_ENABLE_METALFX` | D3DMetal-Spiele mit anderer Bildratengrenze oder MetalFX; Spiele auf anderen Wegen lassen sie stehen | D3DMetal (MetalFX), `d3dmetal-pace` (Bildrate) | Steam-Neustart |
| Anti-Cheat leert `D3DM_MAX_FPS` | Overwatch nach einem D3DMetal-Spiel mit Grenze | – (Regel: nichts Neues im Prozess) | Steam-Neustart |
| Vulkan-Treiber (`CX_LIBVULKAN`, `VK_DRIVER_FILES`, `CX_ACTIVE_GRAPHICS_BACKEND`, `MESA_SHADER_CACHE_DIR`) | DX9 über KosmicKrisp ↔ DXVK über MoltenVK | Wine (winevulkan, D3DKMT) | Steam-Neustart |
| Spiel-Schalter (`GameEnvironment.allowed`) | Profile setzen heute keinen; nur Engine-Tests | Wine-Unix, D3DMetal | Steam-Neustart |
| Startprogramm in LaunchOptions („program“) | Spiele mit anderem Programm (Control DX12 u. a.) | Steam beim Start | Steam-Neustart |
| Retina | 1 Profil (The Last Caretaker Demo) | Wines Mac-Treiber, Registry | **Ende der ganzen Wine-Sitzung** |
| msync | nur der Test-Schalter | wineserver | Ende der Sitzung |

Belegt in den echten Starts (start-evidence, 21.11. 22:26 – 22.11. 18:34): OxyRail (DXMT, AVX) ↔ Wukong (D3DMetal, ohne AVX)
↔ Overwatch (DXMT, AVX, Anti-Cheat). Jeder dieser Wechsel kostet einen Neustart: AVX bzw. die D3DMetal-Grenze vor Overwatch.

## 2. Was sich auf dem Weg zum Spiel setzen ließe

| Weg | Erreicht | Ergebnis |
|---|---|---|
| Starter in LaunchOptions (`"starter.exe" %command%`) | nur die Windows-Seite | **nein** (Probe 22.11., `docs/probes/starter-umgebung/ERGEBNIS.md`); außerdem liest Steam LaunchOptions nur beim Start |
| `-applaunch`-Argumente | nur Argumente | nein |
| Konstruktor der Bibliothek *im Spiel* setzt Variablen | was Wine und D3DMetal später lesen | Rosettas AVX nicht (entscheidet beim exec); wirkt im Spielprozess, also auch in Anti-Cheat-Spielen |
| **Bibliothek im *startenden* Prozess fängt `execve` ab** | die ganze Unix-Umgebung des Kinds, vor dem exec | **ja** (Probe heute, unten) |

**Probe 23.11.** (`docs/probes/spielwechsel-umgebung/`, eigener Prefix, winecx 4.7.3, kein Steam, kein Spiel):
`starter.exe` startet `child.exe` mit `CreateProcessW`; `spawn-env.dylib` (x86_64, per `DYLD_INSERT_LIBRARIES` wie
`hide-steam-dock.dylib`) fängt `posix_spawn`, `posix_spawnp` und `execve` ab und ändert bei einem Kind, dessen Argumente
`child.exe` nennen, nur `ROSETTA_ADVERTISE_AVX`.

| Fall | Umgebung des Starters | Abfangen | CPUID AVX im Kind |
|---|---|---|---|
| Kontrolle | AVX=1 | nein | 1 |
| Kontrolle | ohne | nein | 0 |
| Abfangen nimmt weg | AVX=1 | ja, AVX aus | **0** |
| Abfangen setzt | ohne | ja, AVX an | **1** |

Wine startet das Kind über genau ein `execve` (`…/lib/wine/x86_64-unix/wine`, Argumente mit dem Windows-Pfad des Programms);
`posix_spawn` kam nicht vor. Die Windows-Seite des Kinds behält die Werte des Starters; das ist für Rosetta, Wine und D3DMetal
ohne Belang, die die Unix-Seite lesen.

## 3. Ohne Neues im Spielprozess: was sich sonst vermeiden ließe

Geprüft und verworfen:
- **AVX immer an:** Wukong stürzt damit nach ~30 s ab (Profilnotiz), Caretaker ebenso abgeschaltet. Bleibt.
- **Bildrate über die Erlaubnisdatei statt über `D3DM_MAX_FPS`:** Die Variable ist das Tor, das die Bibliothek in Prozessen
  ohne Grenze gar nicht erst aktiv werden lässt (`watchForD3DMetal`). Ohne sie würde sie in jedem Prozess Bilder beobachten,
  auch in Overwatch. MetalFX liest D3DMetal selbst. Kein Gewinn ohne Neues im Spielprozess.
- **D3DMetal-Schalter bei Spielen auf anderen Wegen stehen lassen:** geschieht schon („A game on another layer leaves D3DMetal's
  as they are“). `D3DM_VENDOR_ID`/`D3DM_DEVICE_ID` liest auch winecx für jedes Spiel; `D3DM_SUPPORT_DXR` setzt kein Profil.
- **Neustart vor dem Warten auf das alte Steam entscheiden:** in ENTWURF-STARTZEIT als offen geführt (Reihenfolge um
  Cloud-Abgleich und Spielstand-Übernahme); gehört dorthin.
- **Steam schon beim Öffnen der Spielseite passend neu starten:** spart die Wartezeit beim Spielen, kostet aber Neustarts beim
  Blättern und Strom. Neue Verhaltensregel, zur Wahl (Abschnitt 4, Weg 2).

## 4. Zur Entscheidung

**Weg 1 · Startumgebung beim Spielstart (empfohlen zur Probe mit Steam).** `hide-steam-dock.dylib` fängt `execve` ab; wirksam
nur, wenn der Prozess steam.exe ist (wie die Netzwerk-Reihenfolge nur in winedevice.exe wirkt) und das Kind aus dem
Spielordner des Starts kommt. Nightforge schreibt vor dem Start, wie heute die D3DMetal-Erlaubnis, eine Datei: Spielordner
(Windows-Pfad) und die Variablen dieses Starts, nur aus einer festen Liste (`ROSETTA_ADVERTISE_AVX`, `D3DM_*`,
`GameEnvironment.allowed`, die Vulkan-Namen). Steam läuft dann mit einer neutralen Grundumgebung weiter.
- Wirkt für: AVX, D3DMetal-Grenze und MetalFX, Vulkan-Treiber, Spiel-Schalter. Nicht für Retina, msync und das Startprogramm in
  LaunchOptions: die bleiben Neustarts.
- **Anti-Cheat-Spiele:** keine Datei, also bekommen sie genau Steams Umgebung, wie heute. Ist darin etwas, das sie nicht haben
  dürfen, startet Steam neu wie heute. Aber: Die Abfangfunktion selbst liegt, wie jede Funktion der Bibliothek, in jedem
  Wine-Prozess, auch in Overwatch (dort reicht sie nur durch). Das fällt unter die Regel „nichts Neues in Anti-Cheat-Prozessen“
  und braucht das OK des Nutzers, wie bei M1 im Audit.
- Spiele, die über einen eigenen Starter laufen (Launcher → Spiel), erben die Umgebung vom Starter: passt.
- Risiko: eine Änderung an der Bibliothek in jedem Wine-Prozess. Zuletzt brach eine solche Änderung Wine (Revert von
  `claude/dock-dylib-ohne-appkit-04`). Also erst eine Probe mit Steam (ein Spiel ohne Anti-Cheat, zweimal mit
  anderer AVX-Einstellung), dann der Bau mit Tests der Regeln in C wie `d3dmetal-pace-rules.c`.
- Gewinn: 27–40 s je Wechsel zwischen solchen Spielen.

**Weg 2 · Steam vorab passend machen.** Wählt der Spieler ein Spiel und bleibt einige Sekunden auf dessen Seite, während
nichts läuft und nichts lädt, startet Steam im Hintergrund schon mit dessen Einstellungen. Kein Eingriff in Prozesse, aber
Neustarts beim Blättern; braucht eine Regel (Wartezeit, nur am Netzteil?).

**Weg 3 · So lassen** und nur den Vorhang beim Neustart ruhig halten (0.3.5).

## 5. Live (Nutzer bzw. Koordinator)

- Mit dem Protokoll von 0.3.5: bei jedem „Steam restarts for …“ die Namen in Klammern notieren, um die Tabelle in Abschnitt 1
  mit echten Wechseln zu füllen.
- Für Weg 1, erst nach der Entscheidung: Probe mit Steam, ein Spiel ohne Anti-Cheat, zweimal hintereinander gestartet,
  einmal mit, einmal ohne AVX, ohne Steam-Neustart; im Spiel CPUID prüfen lassen oder das Absturzverhalten von Wukong.
