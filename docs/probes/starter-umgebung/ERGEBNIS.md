# Probe: Kommt eine Variable, die ein Windows-Starter setzt, im Spielprozess an?

Stand 22.11.2026, Worker A für den Koordinator, Zweig `claude/spielwechsel-035`. Nicht Teil von Nightforge.

**Frage:** Ein Starter in Steams LaunchOptions (`"C:\…\starter.exe" %command%`) sollte die Einstellungen eines
Spiels setzen, ohne dass Steam neu startet. Dafür müssten Variablen, die er mit `SetEnvironmentVariableW` setzt,
im Kindprozess dort ankommen, wo sie gelesen werden: Rosetta (`ROSETTA_ADVERTISE_AVX`), Wines Unix-Seite
(`WINE_SIMULATE_WRITECOPY`, `CX_*`) und D3DMetal (`D3DM_*`) lesen die Unix-Umgebung.

**Aufbau:** Wine aus Nightforges Komponenten (winecx 4.7.3, `wine-11.17`), macOS 27.2.1, eigener Prefix im
Scratchpad des Workers. Nicht Nightforges Prefix, kein Steam. `starter.exe` setzt `NF_PROBE` und setzt
`ROSETTA_ADVERTISE_AVX` (set), nimmt es weg (unset) oder lässt es (keep), dann `CreateProcessW` auf `child.exe`.
`child.exe` meldet beide Variablen auf der Windows-Seite, CPUID Blatt 1 (AVX, OSXSAVE) und
`IsProcessorFeaturePresent(PF_AVX_INSTRUCTIONS_AVAILABLE)`. `procenv` liest die Unix-Umgebung, mit der das Kind
gestartet wurde (KERN_PROCARGS2, wie `DockHider.startValue`). Die Befehle stehen in `run.sh`, die Ausgabe in `result.txt`.

## Ergebnis

| Fall | Umgebung außen | Windows-Seite des Kinds | Unix-Seite des Kinds | CPUID AVX |
|---|---|---|---|---|
| Kind direkt | ohne AVX | – | – | 0 |
| Kind direkt | AVX=1 | AVX=1 | AVX=1 | 1 |
| Starter setzt AVX=1 | ohne AVX | **NF_PROBE, AVX=1** | **keins von beiden** | **0** |
| Starter nimmt AVX weg | AVX=1 | **AVX fehlt** | **AVX=1** | **1** |
| Starter lässt AVX | AVX=1 | NF_PROBE, AVX=1 | AVX=1, kein NF_PROBE | 1 |

1. **Windows-Seite: ja.** Was der Starter setzt, sieht das Kind mit `GetEnvironmentVariable`.
2. **Unix-Seite: nein.** Das Kind startet mit der Unix-Umgebung des Prozesses, der es startet. Variablen, die
   der Starter auf Windows-Seite setzt oder wegnimmt, erscheinen dort nicht. `NF_PROBE` fehlt in allen Fällen.
3. **Rosetta folgt der Unix-Seite.** CPUID meldet AVX genau dann, wenn `ROSETTA_ADVERTISE_AVX` in der
   Unix-Umgebung beim Start stand, egal was der Starter gesetzt hat.
4. Nebenbei: `IsProcessorFeaturePresent(AVX)` ist in allen Fällen 0, auch wenn CPUID AVX meldet. Wine füllt die
   Prozessormerkmale also nicht aus dieser Angabe. Spiele, die über diese Funktion fragen, sehen kein AVX.

## Folge für den Starter-Vorschlag

Ein Windows-Starter in den LaunchOptions **trägt nicht** für das, was Steams Neustart heute verursacht:
Rosettas AVX, Wines Hacks (`WINE_SIMULATE_WRITECOPY`, `CX_*`) und D3DMetals `D3DM_*` lesen die Unix-Umgebung, und
die erbt das Spiel von steam.exe. Er hilft nur bei Variablen, die Windows-Code liest (etwa DXVK). Die lösen keinen
Neustart aus, weil sie in `gameEnvironment` für alle Spiele gleich sind.

Ein anderer Weg, nicht geprobt und nur als Notiz: `hide-steam-dock.dylib` läuft schon in jedem Wine-Prozess und liest
für die D3DMetal-Sperre eine Erlaubnisdatei im Spielordner (`wrapper/d3dmetal-pace.m`). Ein Konstruktor dort könnte
vor Wines Start `setenv` für die Variablen eines Starts aufrufen. Damit wären die Variablen erreichbar, die Wine und
D3DMetal erst beim Start lesen. Rosettas AVX vermutlich nicht: Rosetta entscheidet beim exec, bevor eine Bibliothek
läuft (ungeprüft). Der Weg greift tief in jeden Spielstart ein und bräuchte eine eigene Probe und eine Entscheidung.
