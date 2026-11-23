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

## Nachtrag: Lichtnaht und Konsolenmodus (Worker B, in staging seit ad8d44c)

Gelesen: `ConsoleMode.swift`, `DockAutoHide.swift`, `FullScreen.swift` (DockAutoHide.run), `CurtainEscape.swift`,
`GameStage.swift`, `GameBackdrop.swift`, `LaunchPhase.swift`, `SetupView.swift` und die Aufrufer in `LibraryModel.swift` und
`InputRouter.swift`. Nur gelesen. Stand 1b563a4d.

| Prüfpunkt | Ergebnis |
|---|---|
| Dock: alter Wert zurück, auch nach Absturz | **in Ordnung.** `DockAutoHide.engage` merkt `console.dockAutoHideBefore`, *bevor* es die Einstellung ändert (`DockAutoHide.swift`, engage). `restore` läuft bei Konsolenmodus aus (`LibraryModel.swift:4342`), beim Beenden synchron (`App.swift:150`) und beim nächsten Start nach einem Absturz (`App.swift:65`). Ein Wert, den der Spieler selbst gesetzt hatte, wird nie angefasst; hat er ihn zwischendurch geändert, wird nichts zurückgestellt. |
| Fokusrahmen sofort sichtbar | **Fund K1**, siehe unten. Sonst wie entworfen: nur in Dialogen und offenen Panels, nicht auf Bibliothek und Startseite (`ConsoleMode.focusPlace`). |
| Esc beendet den Konsolenmodus nicht | **in Ordnung.** `InputRouter.swift:213`: Mit nichts zum Zurückgehen verlässt Esc nur außerhalb des Konsolenmodus das Vollbild. ⌃⌘F, Ansicht › Vollbild und der grüne Knopf beenden ihn absichtlich (`FullScreen.swift:78`, `toggleEndsConsoleMode`). |
| Anfrage nur einmal, erst nach „Los geht's“ | **in Ordnung.** `offers` verlangt `!asked && !firstStart` (`ConsoleMode.swift`); `showsFirstStart` = `setup.isActive \|\| needsSetup` (`LibraryModel.swift:430`), und die Enthüllungsseite schließt das Setup erst mit „Los geht's“ (`SetupView.swift:22`). Geprüft wird im 3-s-Takt (`LibraryModel.swift:905`). Kleinigkeit: `askedKey` wird beim *Zeigen* gesetzt (`LibraryModel.swift:4311`); beendet jemand Nightforge mit offener Anfrage, kommt sie nie wieder (dann bleiben kleines Menü und Einstellungen). |
| Ⓑ „Zurück zu Nightforge“ ab 30 s, sichtbar ab 90 s | **in Ordnung.** `CurtainEscape.openAfter` 30, `tipAfter` 90 (`CurtainEscape.swift`), gezählt ab „kein Prozess des Spiels und keine erklärende Phase“ (`noProcessSince`, `LibraryModel.swift:1750`). Ab 90 s kommt zusätzlich die Frage „… antwortet nicht“ (`askAfter` 90). |
| Nach 10 s ohne Spielfenster zurück | **in Ordnung, mit Lesart.** `GameStage.endingPatience` 10 s ab `pictureWentAt` (`LibraryModel.swift:2022`). `pictureWentAt` setzt `wentDark` erst nach 3 s ohne Bild (Audit E2): vom Verschwinden des Bilds bis „Back to Nightforge“ also ~13 s plus ein Blick. Mit Fenster irgendwo (nicht auf dem Bildschirm) geht nach 10 s nur der Vorhang hinter das Spiel (`curtainEnds`). |
| Satz beim langen Erststart ab 60 s | **in Ordnung.** `LaunchPhase.firstTimeAfter` 60; die Einrichtungsphasen haben keinen eigenen Vorhangtitel, also greift `firstTime` (`LibraryModel.swift:2264`, `longFirstTime`). Gemessen an `GameBackdrop.upFor` (wie lange der Vorhang *so* steht). |
| Vorhang blieb nach der Vorschau stehen | behoben in a78dacc2 (`GameBackdrop.fade`), siehe dort. |

**K1 · Der Fokus-Takt endet ganz, sobald einmal kein Schlüsselfenster da ist (mittel, heute Abend gut möglich).**
`LibraryModel.swift:4374–4376`: In der Schleife von `watchConsoleFocus` steht `guard let self, …, let key = NSApp.keyWindow else { return }`.
Gibt es einen Augenblick lang kein Schlüsselfenster, endet der Task, nicht nur dieser Blick. Das kann zwischen zwei Blättern sein,
während ein Blatt schließt, beim Wechsel ins Vollbild (`FullScreen.set`) oder während das kleine Menü aufgeht. Erst das nächste
Aktivieren von Nightforge (`didBecomeActive`) startet ihn wieder. Bis dahin erscheint der Rahmen in Dialogen nicht mehr von selbst,
sondern erst nach einem Druck aufs Steuerkreuz, wie außerhalb des Konsolenmodus.
- Wahrscheinlich: beim Einschalten des Konsolenmodus selbst. `setConsoleMode` schaltet das Vollbild um und ruft danach
  `watchConsoleFocus()`; liegt beim ersten Blick 0,25 s später kein Schlüsselfenster vor, ist der Takt schon aus.
- Vorschlag: Ohne Schlüsselfenster nur diesen Blick überspringen (`continue` nach dem Schlaf), `return` nur, wenn der Modus aus ist,
  ein Spiel läuft oder Nightforge nicht vorn ist.

**K2 · Zwei Dock-Schritte können sich beim Start überholen (gering).** `DockAutoHide.run` (`FullScreen.swift:20`) führt jeden Schritt in
einem eigenen losgelösten Task aus. Beim Start nach einem Absturz läuft `restore` (`App.swift:65`). Startet der Spieler im
Konsolenmodus sehr schnell ein Spiel, läuft gleichzeitig `engage` (`LibraryModel.swift:1463`). In ungünstiger Reihenfolge stellt
`restore` den Wert zurück, nachdem `engage` den Merker schon neu gesetzt hat. Dann bleibt das Dock beim ersten Spiel sichtbar. Beim
nächsten Spiel greift `engage` wieder (der Merker fehlt dann). Vorschlag: beide Schritte über eine serielle Schlange.

## Gegenlesen Worker C (Worker A, 23.11.2026, nur gelesen)

Gelesen wurden die Quellen der neun Zweige, wie sie in `claude/staging-035` stehen (`f7c1988c`), jeweils gegen ihren Merge
und gegen den Code um sie herum: zwei-kopien-035, bericht-ohne-pfade-035, tests-ohne-app-035, tests-ohne-steam-035,
vorhang-wiederheber-035, pad-only-04, tests-ohne-reste-04, dock-schlange-04 und haenger-erkennen-04. Gesucht waren
Fehler, keine Stilfragen. Nichts davon verhindert den Release. Es gibt drei kleine Funde; einer davon hängt hinter einem
Testschalter.

### Funde

**W1 · Das Zurückstellen des Docks beim Beenden geht an der neuen Schlange vorbei (gering).** `App.swift:150` ruft
`DockAutoHide.restore(DockAutoHide.live)` direkt auf dem Hauptthread auf. Die Schritte aus K2 laufen dagegen über
`DockAutoHide.serially` (`DockAutoHide.swift:25–30`, `FullScreen.swift:20`). Startet im Konsolenmodus ein Spiel und beendet
der Spieler Nightforge gleich danach, kann ein schon eingereihtes `engage` (`LibraryModel.swift:1463`) nach dem `restore`
des Beendens laufen, falls der Prozess dafür noch lebt.
- Was dann passiert: Das Dock bleibt ausgeblendet. Beim nächsten Öffnen holt `App.swift:65` den Wert zurück, die Einstellung
  des Spielers ist also nur bis dahin verstellt.
- Wahrscheinlichkeit: gering. Das Beenden müsste in die Sekunde fallen, in der der Schritt eingereiht und noch nicht gelaufen ist.
- Vorschlag: Beim Beenden über dieselbe Schlange und darauf warten, etwa eine Funktion `DockAutoHide.seriallyAndWait`, die
  `steps.sync` aufruft. Der Schritt meldet sich nie beim Hauptthread zurück, `sync` vom Hauptthread aus ist deshalb sicher.

**W2 · Ein Vorhang, der innerhalb von 0,3 s nach einer Ausblendung wieder kommt, kann trotzdem verblassen (gering, Vermutung).**
`GameBackdrop.fade` (`GameBackdrop.swift:350–359`) startet die Animation über den Animator und setzt den Endwert nach Ablauf selbst.
Das behebt den Hänger bei schlafendem Bildschirm. Kommt der Vorhang aber zurück, während die Ausblendung noch läuft
(`put` bricht `hiding` ab), setzt `put` die Deckkraft direkt (`GameBackdrop.swift:434`: `alphaValue = appearing ? 0 : 1`,
das Fenster ist noch sichtbar, also 1). Die laufende Animation des Animators wird davon nicht abgelöst. Läuft sie zu Ende, steht
der Vorhang oben, aber mit Deckkraft 0.
- Neu ist das nicht: Vor dem Fix bestand dasselbe Rennen, auch da lief die Animation nach dem Abbruch weiter. Der Fix lässt es nur
  bestehen.
- Wahrscheinlichkeit: gering. Es braucht ein Ausblenden und ein neues Heben in derselben Drittelsekunde. Ob AppKit die
  Animation bei direktem Setzen wirklich weiterlaufen lässt, ist ungeprüft.
- Vorschlag: In `put` und am Ende von `fade` die Deckkraft über eine Animationsgruppe mit `duration = 0` setzen
  (`window.animator().alphaValue = …`). Eine neue Animation derselben Eigenschaft löst die laufende ab.

**W3 · „moves again“ auch dann, wenn sich nichts bewegt hat (gering, hinter dem Testschalter).** `HangRule.change`
(`HangRule.swift:90`) meldet bei jedem Wechsel von `.hung` zu etwas anderem `.movesAgain`, also auch zu `.unknown`. Das passiert,
wenn der Spieler das Overlay öffnet (`paused`), das Spiel nicht mehr vorn ist oder sein Fenster nicht mehr zeigt. Gerade wenn
jemand ein hängendes Spiel über das Overlay beendet, schreibt wine.log dann „Hang watch: … moves again after … s“.
- Was schiefgeht: Die Messung von Stufe 1, die über das Angebot „Spiel beenden“ entscheiden soll, zählt Hänger als erholt, die
  nur verlassen wurden.
- Vorschlag: `.movesAgain` nur beim Wechsel `.hung → .busy`. Bei `.hung → .unknown` den Hänger halten oder eine eigene Zeile
  schreiben („left the watch“).

### Geprüft, in Ordnung

- **zwei-kopien-035:**
  - `DockHider.startValue` gibt für eine fehlende Variable `""` zurück, nicht nil. Eine Sitzung von 0.3.4 ohne Kennung zählt
    damit als fremd, wie gewollt.
  - Der Fingerabdruck wird zwischengespeichert.
  - `environment(wine:)` ruft `DockHider.path()` vor dem Fingerabdruck auf; Kennung und geladene Bibliothek passen zueinander.
  - Jeder Wine-Start von Nightforges eigener Sitzung baut auf `environment(wine:)` auf: msiexec, winetricks, regedit,
    GOG-Redists, PadAnswerRun, UnityDialog und `directEnvironment`. Nur Flaschen von CrossOver oder Whisky nicht, und die sind
    nicht Nightforges Sitzung.
  - Hinweis ohne Fund: `librarySessionMarkers` liest die Kennung aller eigenen wineserver unter dem Datenordner. Startete
    Nightforge einmal einen zweiten Prefix unter Wine, etwa Battle.net, beendete dessen fremde Kennung die Hauptsitzung. Heute
    liest Nightforge den Battle.net-Prefix nur. Falls das kommt, nach `WINEPREFIX` des wineservers filtern.
- **bericht-ohne-pfade-035:**
  - `outbound` ersetzt die gemerkten Pfade, längste zuerst, vor `redacted`; ein gemerkter Pfad mit dem Home darin geht also ganz.
  - Die Muster für Benutzerordner lassen Wines eigene Namen und schon ersetzte Stellen stehen.
  - Die Standardwerte (`launchMemoryPaths`) werden je Bericht einmal gelesen, nicht je Zeile.
- **tests-ohne-app-035 und tests-ohne-steam-035:**
  - `gameAtQuit` zählt „unbekannt“ jetzt nicht mehr als Spiel.
  - Im Beenden-Skript zählen Windows-Spiele nur noch als eigene Prozesse (`own_pids` über lsof txt, der Datenordner mit
    `pwd -P` aufgelöst, wie lsof ihn zeigt).
  - `has_own_process` sagt ohne Liste „läuft“, wartet also lieber.
  - `TestGuard` greift nur in Programmen ohne eigenes Bundle mit dem echten Home; die App und Tests mit eigenem Home berührt er nicht.
  - Mac-Spiele zählen im Skript weiter über jeden Prozess mit `/steamapps/common/`, das ist so gewollt. Zurück holt der Zweig
    Nightforge nur noch mit `GAME_AT_QUIT=1`.
- **vorhang-wiederheber-035:** Der Fix ist richtig; das Rennen aus W2 ist älter.
- **pad-only-04:** `@FocusState` und `padFocus` der beiden Felder sind korrekt verdrahtet.
- **tests-ohne-reste-04:** `MacUnityScreen.look` liest über einen übergebenen `kept` statt über CFPreferences; der Standard ist
  derselbe Aufruf wie vorher.
- **dock-schlange-04:** Die serielle Schlange schließt K2. Für das Beenden siehe W1.
- **haenger-erkennen-04:**
  - Ohne Schalter läuft nichts; der Schalter wird je Blick gelesen.
  - `proc_pid_rusage`, die Prozessobjekte von Core Audio und `CGWindowList` lesen von außen; in den Prozess des Spiels gelangt nichts.
  - Ein neuer Prozess (andere PID) beginnt frisch.
  - `quiet` teilt nur durch eine Zeitspanne über null.
  - Bis auf W3 in Ordnung.
