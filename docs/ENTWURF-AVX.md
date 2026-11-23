# Entwurf: AVX unter Wine – `IsProcessorFeaturePresent` gegen CPUID

Stand 23.11.2026, Zweig `claude/avx-meldung-04` (von `claude/staging-035`, c417c929). Nur Doku und eine Probe im eigenen Prefix
(`docs/probes/avx-sitzung/`), winecx 4.7.3, macOS 27.2; kein Steam, kein Spiel, nichts an Nightforges Prefix.

Ausgang: Nebenbefund der Starter-Probe vom 22.11. – unter Wine meldete `IsProcessorFeaturePresent(PF_AVX_INSTRUCTIONS_AVAILABLE)`
immer 0, obwohl CPUID AVX zeigte.

## Kurzfassung

- **Es fehlt nicht immer, und es liegt nicht an XSAVE/XGETBV.** `IsProcessorFeaturePresent(AVX)` zeigt für die **ganze
  Wine-Sitzung**, was der **erste Prozess** der Sitzung beim Start hatte: mit `ROSETTA_ADVERTISE_AVX=1` 1, ohne 0. CPUID folgt
  dagegen jedem Prozess einzeln. Die Starter-Probe vom 22.11. begann ihre Sitzung mit einem Fall ohne AVX; daher „immer 0“.
- **In Nightforge ist es deshalb Zufall der Reihenfolge.** Nightforges Grundumgebung für Wine (`Engine.environment`) hat kein
  AVX; nur Steams Umgebung und die eines direkten Spielstarts haben es (`gameEnvironment`). Beginnt eine Sitzung mit regedit,
  winetricks, Unitys Helfer, dem Pad-Helfer oder einem Steam-Start für Wukong bzw. Caretaker, sieht **jedes** Spiel dieser
  Sitzung über `IsProcessorFeaturePresent` kein AVX – auch die, deren CPUID AVX meldet. Umgekehrt sieht Wukong in einer mit AVX
  begonnenen Sitzung AVX über diese Funktion, obwohl sein Profil es abschaltet.
- **Vorschlag (zur Wahl, nicht gebaut):** AVX als Sitzungseinstellung wie Retina und msync. Jede Wine-Sitzung beginnt mit dem
  AVX-Wert des Spiels, für das sie beginnt (Standard: an); weicht ein Spiel ab, endet die Sitzung wie heute bei Retina. Dann
  stimmen `IsProcessorFeaturePresent` und CPUID für jedes Spiel überein. Kein Engine-Patch, nichts Neues im Spielprozess.

## 1. Probe 23.11. (`docs/probes/avx-sitzung/`)

Eigener Prefix, `child.exe` meldet CPUID (Blatt 1, ECX 28/27) und `IsProcessorFeaturePresent(39)`. Jeder Fall beginnt eine neue
Sitzung (`wineserver -k`), deren erster Prozess (`cmd /c ping`) offen bleibt, während die Kinder laufen.

| Sitzung begonnen mit | Kind mit | CPUID AVX | `IsProcessorFeaturePresent(AVX)` |
|---|---|---|---|
| AVX=1 | AVX=1 | 1 | **1** |
| AVX=1 | ohne | 0 | **1** |
| ohne | AVX=1 | 1 | **0** |
| ohne | ohne | 0 | 0 |
| (Kind beginnt sie) | AVX=1 | 1 | 1 |
| (Kind beginnt sie) | ohne | 0 | 0 |

Lesart: Wine legt die Prozessormerkmale einmal je Sitzung in der gemeinsamen Seite `KUSER_SHARED_DATA` ab, aus dem CPUID, das der
erste Prozess sieht (Rosetta meldet AVX nur mit `ROSETTA_ADVERTISE_AVX`), und `IsProcessorFeaturePresent` liest nur diese Seite.
Der Quelltext bestätigt das (Abschnitt 3).

## 2. Was das in Nightforge heißt

Wer beginnt eine Sitzung? Der erste Wine-Prozess, wenn keine läuft (nach Nightforges Beenden, nach `stopAll` bei
msync/Bibliothek/Retina, nach „Steam endete nicht“, wenn der wineserver nach dem letzten Prozess gegangen ist):

| Start | Umgebung | AVX zu Beginn |
|---|---|---|
| Steam im Hintergrund oder fürs Spiel (`startSteam`) | `environment` + `steamEnvironment` | an, außer das (letzte) Spiel schaltet es ab (Wukong, Caretaker, gelernt `noAVX`) |
| Direkter Start (Epic, GOG) | `environment` + `gameEnvironment` | wie das Spiel |
| regedit (`importRegistry`: Prefix-Registry, Retina, DLL-Ladereihenfolge, Bildschirmschlüssel `GameResolution`, Wurzelzertifikate) | nur `environment` | **aus** |
| winetricks (`installWinetricks`, vor dem Start eines Spiels mit fehlenden Laufzeiten) | nur `environment` | **aus** |
| Unitys „Play!“-Helfer, Pad-Helfer, GOG-Redists, `wineboot` | nur `environment` | **aus** |

Beginnt etwa ein regedit für die Bildschirmschlüssel die Sitzung, kurz bevor Steam startet, tritt Steam dieser Sitzung bei –
ohne AVX in der gemeinsamen Seite, für alle Spiele bis zum Ende der Sitzung. Welcher Fall auf diesem Mac wie oft vorkam, sagt das
Protokoll nicht (es nennt nicht, wer eine Sitzung beginnt). Messen ließe es sich mit einer Zeile „Wine session begins with …“.
**Seit `claude/avx-zeile-035`** steht die Zeile in wine.log, für jede Sitzung, die Nightforge beginnt: „Wine session begins
with <Programm>, AVX on|off“ (`WineSessionStart`, direkt vor dem Start in `RosettaSupport.run`). Das Programm steht nur mit
seinem Dateinamen da, etwa steam.exe, regedit, msiexec, wineboot, winetricks oder die .exe des Spiels. Auszählen mit
`grep -a "Wine session begins with" wine.log | sort | uniq -c`. Am Verhalten ändert sich nichts.

## 3. Woher Wine die Merkmale nimmt

Quelle: upstream Wine (wine-mirror, master), nicht der Quelltext von winecx 4.7.3; die Probe zeigt aber dasselbe Verhalten.

- `dlls/ntdll/unix/system.c`, `init_shared_data_cpuinfo(KUSER_SHARED_DATA *data)`: `features[PF_AVX_INSTRUCTIONS_AVAILABLE] =
  !!(regs[2] & (1 << 28))` aus CPUID Blatt 1, ECX; AVX2 aus Blatt 7 EBX Bit 5. **Keine** Prüfung von OSXSAVE oder XGETBV
  dafür (`xgetbv` nur in `init_xstate_features`). Unter Rosetta ist Bit 28 genau dann gesetzt, wenn der Prozess
  `ROSETTA_ADVERTISE_AVX=1` hat.
- Aufgerufen nur von `virtual_init_user_shared_data()` (`virtual.c`), und das nur aus `start_wineboot()` (`env.c`), wenn das
  Ereignis `\__wineboot_event` neu angelegt wird, also im **ersten Prozess der wineserver-Sitzung**. Alle späteren Prozesse
  bekommen die Seite nur lesend eingeblendet (`virtual_map_user_shared_data`, `server/mapping.c`).
- So gebaut seit 2020 (Commit e854ea34cc), 2025 vor den Start von wineboot gezogen (8c56742f18). Kein gemeldeter Fehler, kein Patch
  „Merkmale je Prozess“ gefunden.
- Ergebnis: Kein XSAVE-Problem unter Rosetta, sondern eine Frage, mit welcher Umgebung die Sitzung beginnt.
  Quellen: https://github.com/wine-mirror/wine/blob/master/dlls/ntdll/unix/system.c, …/env.c, …/virtual.c.

## 4. Welche Spiele so fragen

Belegt ist wenig; eine Recherche (Websuche, 23.11.) fand:

- **Über `IsProcessorFeaturePresent(39)`:** kein großes Spiel und keine große Engine sicher belegt. Belegt: Werkzeuge und Installer,
  etwa das verbreitete Enshrouded-Fix-Werkzeug der Community (prüft so und meldet „the game will not be able to start“,
  https://github.com/LiaNdrY/Enshrouded-Tool-Fix), Inno-Setup-Skripte, JavaScriptCore. **Vermutung:** Repacks und Installer tun es
  öfter als Spiele; Unreal, Unity, .NET und Chromium lesen CPUID selbst (dann zählt die Umgebung des Spielprozesses, die Nightforge
  schon richtig setzt).
- **AVX-Prüfungen auf Apple Silicon (CrossOver):** Death Stranding und The Last of Us Part II Remastered laufen mit
  `ROSETTA_ADVERTISE_AVX`; bei NBA 2K25 verschwindet die AVX-Meldung, ein anderer Fehler folgt; Dune: Awakening hilft es nicht
  (AVX2); Age of Empires IV galt vor macOS 15 als ohne AVX. CrossOver 25 schaltet AVX für einzelne Spiele selbst ein.
  Die CodeWeavers-Seiten waren nicht abrufbar (403); diese Angaben stammen aus Suchauszügen und sind **nicht nachgelesen**.
- **Vermutung:** Manche Berichte „die Variable hilft nicht“ könnten genau dieser Sitzungseffekt sein (Launcher oder wineboot ohne
  die Variable zuerst gestartet). Belegt ist das nirgends.
- **Unsere Profile:** Wukong und Caretaker schalten AVX ab, weil sie *mit* AVX abstürzen. Mit Weg A sähen sie auch über die Funktion
  kein AVX – stimmiger als heute, wo eine mit AVX begonnene Sitzung es ihnen dort meldet. Ein Profil „braucht AVX“ gibt es nicht:
  AVX ist für alle anderen an.

## 5. Wege (zur Wahl; gebaut wird erst danach)

**A · AVX als Sitzungseinstellung (Vorschlag).** `Engine.environment` bekommt den AVX-Wert der Sitzung; `applySessionSettings` merkt
ihn wie Retina (`avxSession`) und beendet eine Sitzung, die mit dem anderen Wert begann, nie unter einem Spiel.
- Wirkung: `IsProcessorFeaturePresent` und CPUID stimmen für jedes Spiel überein, gleich wer die Sitzung beginnt.
- Kosten: Der Wechsel zwischen Wukong/Caretaker und anderen Spielen beendet die Sitzung statt nur Steam neu zu starten
  (heute schon ein Steam-Neustart, also wenige Sekunden mehr). Andere Wechsel: nichts.
- Anti-Cheat: nur Umgebung, wie heute; nichts im Prozess. Overwatch hat AVX an.
- Für heute laufende Spiele: Wer in einer ohne AVX begonnenen Sitzung lief und AVX an hat, sieht über die Funktion künftig AVX.
  Rosetta führt AVX/AVX2 seit macOS 15 aus; Spiele, die damit abstürzen, sind die, die ihr Profil ohnehin abschaltet.
- Tests: Regel als Funktion wie `msyncSessionEnds`, dazu die Probe oben als Beleg.

**B · Engine-Patch:** `IsProcessorFeaturePresent` je Prozess aus CPUID statt aus der gemeinsamen Seite (bzw. die Seite je Prozess
füllen). Greift in winecx ein, braucht einen eigenen Engine-Bau und gilt für jeden Prozess, auch in Anti-Cheat-Spielen. Nicht
empfohlen, solange A reicht.

**C · Profilfeld je Spiel:** hilft nicht an der Wurzel; die Sitzung bestimmt der erste Prozess, nicht das Spiel.

**D · Nichts tun:** bleibt Zufall der Reihenfolge.

## 6. Live (Koordinator, vor 16:30)

- Mit A gebaut: Nightforge neu starten, ein Spiel mit AVX und eines ohne (Wukong) nacheinander; im Protokoll die Zeile zum
  Sitzungsende „AVX changes“ genau einmal je Wechsel.
- Ohne Bau, nur zur Häufigkeit: eine Protokollzeile, wer die Sitzung beginnt, ein paar Tage mitlaufen lassen.
