# Gegenlese-Audit vor 0.3.5: die Zweige von Worker 1 vom 23.11.2026

Nur gelesen, nichts gebaut, nichts ausgeführt. Grundlage: die Merges in `claude/staging-035` (Stand 1b563a4d) und der Code
dort. Zeilen gelten für diesen Stand.

| Zweig | Merge | Ergebnis |
|---|---|---|
| steam-wartezeit-035 (S3) | c85adfbe | in Ordnung |
| startzeit-04 | e0f84b9a | in Ordnung, eine Kleinigkeit (N5) |
| vorhang-kurz-04 | 410d61bc | in Ordnung |
| startphasen-stores-04 | 26027a9f | in Ordnung |
| sitzung-robust-04 | 91bdc909 | **N1**, N3, N4 |
| avx-zeile-035 | c6150396 | **N2** |
| abdeckung-04 | 57415a17 | Verhalten gleich (geprüft) |

Kein Fund verhindert den Release. N1 und N2 sollten vorher entschieden oder behoben werden.

## Funde

**N1 · Eine zweite kaputte Sitzung zählt doch gegen die Engine (mittel, selten).**
`LibraryModel.swift:3158–3163` (watchSteamStart) startet bei `steamSessionBroken()` neu über
`restartStuckSteam(wine, freshSession: brokenSessionReason, hung: true)`. Ausdrücklich gilt dabei: „Not the engine's fault, so not counted
against it“. `restartStuckSteam` (`LibraryModel.swift:3279–3314`) wartet danach aber bis zu 90 s auf die Anmeldung. Kommt die neue
Sitzung wieder ohne nsiproxy.sys hoch, ruft es `steamStartFailed(since:)` (Zeile 3306). Das zählt den Fehlstart gegen die Engine und kann
`EngineRollback` die vorige Engine für Steam festhalten lassen.
- Was schiefgehen kann: Steam läuft danach auf einer älteren Engine, obwohl die Engine nichts dafür kann.
- Wahrscheinlichkeit: gering. Es braucht zwei kaputte Sitzungen hintereinander; am 23.11. kam es einmal vor (11:34).
- Vorschlag: In `restartStuckSteam` vor `steamStartFailed` `Engine.steamSessionBroken()` fragen und dann nicht zählen, sondern
  nur protokollieren. Oder `restartStuckSteam` einen Parameter `countsAgainstEngine` geben.

**N2 · Vor jedem Wine-Start ein `ps`-Lauf, auch auf dem Hauptthread (mittel, selten spürbar).**
`RosettaSupport.swift:87` ruft `WineSessionStart.note(process)` auf, das fragt `Engine.sessionWine()`
(`WineSessionStart.swift:40`). `sessionWine` → `ownProcesses` → `ProcessList.listing`. Das cachet nicht und führt jedes Mal
`ps -axo …` aus (`Subprocess.swift:205`), dazu `proc_pidpath` für jeden Prozess.
- Auf dem Hauptthread läuft das mindestens bei `PadAnswerRun.send` (aus dem MainActor-Task in `LibraryModel.answerQuestion`,
  `LibraryModel.swift:4396`). Ein Druck auf Ⓐ/Ⓑ an einer Frage des Spiels kostet dann einen `ps`-Lauf auf dem Hauptthread, sonst
  einige zehn Millisekunden. Bei einem `ps`, das hängt (am 3.11. gesehen), dauert es bis zum Zeitlimit, danach pausiert
  `ProcessList`.
- Bei Steam-Starts, regedit, winetricks und Spielstarts (meist abseits des Hauptthreads) kostet es pro Start einen zusätzlichen `ps`-Lauf.
- Vorschlag: `note` nur abseits des Hauptthreads fragen (`Thread.isMainThread` → in einen Hintergrund-Task) oder ohne Prozessliste
  entscheiden: Ob ein wineserver läuft, sagt schon `pgrep -x wineserver` bzw. dessen Socket im Prefix-Ordner von
  `/tmp/.wine-<uid>`. Alternativ den Testschalter-Weg: die Zeile nur, wenn ohnehin eine frische Liste vorliegt.

**N3 · `steamSessionBroken` liest bis zu 4 MB wine.log je Blick (gering).**
`Engine.steamSessionBroken()` liest `GameLog.text(since:)` (`GameLog.swift:89`, gekappt auf die letzten 4 MB). Aufgerufen wird es
in `watchSteamStart` alle 5 s (höchstens 2 min) und in der Anmelde-Warteschleife des Starts jede Sekunde
(`LibraryModel.swift`, `waiting: while true`). Läuft Steam lange und meldet sich ab, liest jeder Start bis zur Anmeldung jede
Sekunde 4 MB.
- Vorschlag: Die gelesene Stelle merken und nur den Zuwachs prüfen, oder das Ergebnis je Steam-Start einfrieren, sobald
  nsiproxy.sys gesehen wurde.

**N4 · „GetAdaptersAddresses returned 2“ kann auch von einem Spiel stammen (gering).**
`Engine.sessionBootBroken` wertet diese Zeile überall im Protokoll seit Steams Start als kaputte Sitzung. Spiele erben Steams stderr,
ihre Zeilen landen also ebenfalls dort. Meldet ein Spiel die Zeile, gilt Steams Sitzung beim nächsten Start in der Anmelde-Warteschleife als
kaputt (nur wenn Steam nicht angemeldet ist). Steam startet dann mit neuer Sitzung neu. Geschützt ist das durch
`windowsGameRunningKnown == false`.
- Vorschlag: Die Zeile nur zählen, wenn sie vor der ersten Zeile eines Spiels steht, oder nur in Steams eigenem `logs/connection_log.txt`
  bzw. `console_log.txt` suchen.

**N5 · `neverSyncs` zerlegt das ganze cloud_log bei jedem Aufruf (gering).**
`SteamSwitch.swift:114`: `before.components(separatedBy: "Client version:")` legt für jede Zeile eine Kopie an. `shouldWait` wird
beim Start abseits des Hauptthreads gefragt (`LibraryModel.swift:4048`). Bei einem großen cloud_log kostet das Zeit, ändert aber
nichts am Ergebnis.
- Vorschlag: `before.ranges(of:)`-Zählung bis `quietStarts` mit frühem Abbruch.

## Geprüft, in Ordnung

- **S3 (c85adfbe):** `stopSteam(…, leftovers:)` ist nur an den Stellen `true`, an denen danach Steams Dateien angefasst werden
  (DriveMoves 235/334, DriveTakeover 418, LibraryModel 6708). Alle übrigen Aufrufe enden mit `stopAll` oder mit einem neuen
  Steam-Start, der `waitForSteamToEnd` selbst wartet (geprüft: LibraryModel 5274, 5376, 5387; CompleteRemoval 392; D3DMetalFlow 250;
  SteamOnDemand 164). `seconds(_:of:)` rechnet Attosekunden richtig um.
  `IdleRest.pausesBeforeNextLook` überspringt die Pause höchstens für einen Blick (der nächste setzt `runningScanned`).
  Die Prozessliste ohne Antwort hat ihre eigene Pause.
- **startzeit-04 (e0f84b9a):** Alle `notePhase`-Zeilen hängen am Schalter `gameTest.startPhases`. Der Release liefert `false`, und
  `test_release_switches.py` kennt den Schlüssel. `GameLog.clock(tenths:)` ist richtig.
- **vorhang-kurz-04 (410d61bc):** Die kürzere Ruhezeit gilt nur mit Beweis, ohne Anti-Cheat, ohne Overwatch und bei unverändertem
  bildschirmfüllendem erstem Bild. Ohne `curtainProof` (Mac-Spiele, andere Wege) wird mit `antiCheat ?? true` die volle Ruhezeit
  genommen. `curtainProof` wird bei jedem Play geleert.
- **startphasen-stores-04 (26027a9f):** nur Protokollzeilen hinter demselben Schalter.
- **sitzung-robust-04 (91bdc909), sonst:** `restartHungSteam(reason:)` schreibt den Grund ins Protokoll, nie einen Pfad.
  `steamStartLogMark` wird nur bei einem frischen Start gesetzt, wie `lastSteamStart`. Neustarts mit neuer Sitzung gibt es nur mit
  `windowsGameRunningKnown == false`. Höchstens ein weiterer Versuch (`again: false`).
- **avx-zeile-035 (c6150396), sonst:** Die Zeile nennt nur den Dateinamen des Programms, keinen Pfad, also keinen Benutzernamen.
  Im Sandkasten wird der Helfer übersprungen.
- **abdeckung-04 (57415a17):** Verhalten gleich.
  - `shutdownArguments`: „-“ und Profil bei eingeschaltetem Sandkasten, sonst zwei leere Werte, wie vorher.
  - `steamEngineStep`: dieselbe Entscheidung. `windowsGameRunning` wird jetzt immer gefragt statt nur bei abweichender Sitzung, also
    ein `ps`-Lauf mehr; das Ergebnis ist gleich.
  - `hardStopSteam`: gleich.
  - `steamLaunch`: Die Umgebung wird jetzt vor `WineSandbox.process` gebaut statt danach. Sie hängt nicht von der Sitzung ab, die
    `settleSession` dort beenden könnte. Gleich.
  - `startSteps`: `!viaSteam, builtIn` wird zu `provider != .steam && builtIn`, dazu Battle.net. Gleich.
    `game.pendingUpdate` wird früher gelesen, aber am selben Wert.
