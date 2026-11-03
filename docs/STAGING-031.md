# Probe-Zusammenführung für 0.3.1 (Zweig `claude/staging-031`, 3.11.)

Nur eine Probe, damit die echten Merges schnell gehen: `claude/staging-031` von `claude/ux-roadmap-next` 29e458a,
in einem eigenen Worktree im Scratchpad der Kleinkram-Sitzung. Alle Merges mit `--no-ff`. Nichts davon ist in
`claude/ux-roadmap-next`, nichts gepusht. Nach jedem Merge lief `./build.sh`.

## Reihenfolge und Ergebnis

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 1 | `claude/kleinkram-031-766fe2` | ff0e240 | 18fb6b9 | keine (`ci.yml` mit dem neuen AGW-Schritt von 29e458a von selbst zusammen) | 0 |
| 2 | `claude/h1-h3-031` | 8edccc5 | 0c9fcff | keine (enthält 1) | 0 |
| 3 | `claude/storage-fixes` | f1ce003 | aba7a63 | keine | 0 |
| 4 | `claude/audit-low` | a652cee | bb26e9d | keine | 0 |
| 5 | `claude/d3dmetal-import-m4` | 7829e1b | b0ee20f | keine | 0 |
| 6 | `claude/system-prompt-curtain-1a4e06` | 1fdddf6 | 568977a | keine | 0 |
| 7 | `claude/update-progress-1a4e06` | a2fc520 | e10298d | keine | 0 |
| 8 | `claude/small-fixes-1a4e06` | 395a9c7 | 439e324 | `tests/UpdateStateTest/main.swift`, siehe unten | 0 |
| 9 | `claude/engine-env-0f3a` | 381ba5d | bfb4e34, dazu 8b5314d | keine; eine Anpassung, siehe unten | 0 (auf 8b5314d) |
| 10 | `claude/wine-sandbox` (mit `claude/laufwerke-z`) | ce39bf7 | 84ab3f2 | keine | 0 |
| 11 | `claude/tested-on-mac` | 1516a46 | c55971b | keine | 0 |
| 12 | `claude/audit-sicherheit` | efee15e | 64cd815 | keine | 0 |
| 2b | `claude/h1-h3-031`, neuer Kopf | d6032e7 | f1d52b8 | keine | 0 |

`claude/h1-h3-031` bekam nach Merge 2 einen Commit dazu (d6032e7, das Beenden-Skript). Er ist als 2b am Ende
nachgezogen. Ein weiterer Commit ist dort noch angekündigt.

## Konflikte und Anpassungen

- **Merge 8, `tests/UpdateStateTest/main.swift`:** Beide Seiten haben an derselben Stelle eine Testgruppe angefügt.
  update-progress hat `progress()` (der Fortschritt von „Aktualisieren und spielen“, seine Geschwindigkeit),
  small-fixes hat `lastPlayed()` (Steams LastPlayed beim Installieren). Gelöst: beide behalten, beide in `main()`
  aufgerufen, die beiden Funktionen hintereinander. Keine Entscheidung nötig.
- **Merge 9, ohne Textkonflikt:** engine-env legt in `EngineLayoutTest` die Suite
  `nightforge.game-environment-test.<PID>` an. Sie landet im echten `~/Library/Preferences` und wird am Ende nur
  geleert, die Datei bleibt. Seit Merge 1 kompiliert die Reihe `tests/Shared/TestDefaults.swift`. Deshalb wechselt
  8b5314d, ein eigener Commit auf Staging, zu `TestDefaults.suite("game-environment")`. Entschieden (Hauptsitzung):
  engine-04 übernimmt das in seinen Zweig, bis dahin bleibt 8b5314d auf Staging.
- Von selbst zusammengegangen und von Hand geprüft:
  - `build.sh`: die Prüfsumme des Wrappers (audit-low) und der Bau von `nightforge-sandbox` (wine-sandbox).
  - `Library.swift`: `installedSize` (storage-fixes) und der Fortschritt über `UpdateState` mit `stagedSoFar`
    (update-progress).
  - `GameOverlay.swift`: Der Vorhang fragt macOS' eigene Dialoge über `GameProcesses` ab, also über h1-h3s
    `ProcessList`. `/bin/ps` steht danach nur noch in `Subprocess.swift`.

## Tests der ersten Runde (auf f1d52b8)

- **pytest:** 80 von 80.
- **Swift-Reihen ohne echte Prozessliste:** 48 von 48 grün, jede mit rc=0. Je Reihe höchstens 7 Minuten; keine
  hat das gebraucht. CloudSaves, Compatibility, ComponentsSmoke, ControllerCompatibility, D3DMetal, DownloadRate,
  DuplicateGames, EngineLayout, EngineRollback, ExternalDrive, FirstStart, GameAnalysis, GameAudio, GameDisplay,
  GameID, GameInfo, GameResolution, GameShortcut, GameTest, GraphicsPreset, LaunchHealth, LibraryFilters,
  LibraryReveal, MacSources, Navigation, OfflineReadiness, PadFocus, PadGuide, PadRules, ProfileFiles,
  ScanFreshness, Search, ShaderCaches, SpaceCheck, Stage, SteamBootstrap, SteamOwnership, SteamPackages, SteamStop,
  SteamSwitch, StoreFacts, StoreSearch, Strings, TextScale, Trackpad, UpdateState, VDF, WineSandbox.
- Während des Laufs hat sich in `~/Library/Preferences` keine Datei mit Testnamen geändert. Das Aufräumen aus
  Merge 1 greift also auch für die Reihen der anderen Zweige.
- **Offen wegen des ps-Hängers (3.11.), nach dem Neustart laufen lassen:**
  - `CompleteRemovalTest`: Stand-in für ps, schaltet aber auf `/bin/ps` zurück.
  - `DetachedProcessTest`: `ownProcesses`, `stopAll`.
  - `EpicTest`, `GOGTest`: `library()` ruft `runningDownloads`, also ps.
  - `GameOverlayTest`: `GameProcesses`.
  - `MacVersionTest`: ein Stand-in, das das echte `/bin/ps` aufruft.
  - `QuitScriptTest`, `SubprocessTest`: Stand-ins, aber ganz um Prozesslisten gebaut.
  - `SteamBackgroundTest`: `DockHider.runningSteamLibraries`.

  Ausgewählt habe ich so: Gesucht habe ich die Quellfunktionen, die Prozesse auflisten (`ProcessList`,
  `ownProcesses`, `GameProcesses.table`, `runningDownloads`), und die Reihen, die sie direkt oder über die
  Store-Abfragen aufrufen. Der Rest lief mit Zeitgrenze.

## Zweite Runde (3.11., nachgezogen)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 13 | `claude/signed-updates-dda700` | 29b9f7f | 109519f | `tests/ProfileFilesTest/main.swift`, siehe unten | 0 |
| 13b | `claude/signed-updates-dda700`, neuer Kopf | 700fd70 | 9a3dc17 | keine | 0 |
| 14 | `claude/quit-always-1a4e06` | 02dd718 | eb4ffbe | `App.swift`, `CompleteRemoval.swift`, `tests/CompleteRemovalTest/main.swift`, siehe unten | 0 |
| 15 | `claude/steam-programm` | dbc0504 | d75fdb3 | `Launcher.swift`, `LibraryModel.swift`, siehe unten | 0 |
| 16 | `claude/audit-low` und `claude/audit-sicherheit`, neue Köpfe | 6e309f7, 20f0acc | 8a44b6e, e6ec798 | keine | 0 |

Konflikte:
- **13, `tests/ProfileFilesTest/main.swift`:** Nur der Kopfkommentar. audit-low hat „die Speicherordner, die eine Regel
  nennen darf“ ergänzt, signed-updates „signiert mit einem Schlüssel des Tests“. Beides übernommen.
  - `scripts/install.sh` ging von selbst zusammen und ist von Hand geprüft. signed-updates prüft die Signatur nur auf
    dem Download-Weg, ein `NIGHTFORGE_ZIP` gilt, wie es ist. Die Wahl des Zielordners und `NIGHTFORGE_NO_QUIT` aus
    Merge 1 bleiben.
  - `tests/test_signing_scripts.py` ersetzt `pgrep`, `osascript` und `open` und setzt `NIGHTFORGE_NO_QUIT`, beendet also
    kein laufendes Nightforge.
  - `ci.yml` hat jetzt den Schritt der Signier-Skripte neben `scripts/run-tests.sh`.
- **14, `App.swift`:** Am Ende von `applicationDidFinishLaunching` hängen jetzt beide Ergänzungen: der Schlüssel für
  ältere Spiel-Apps (audit-low) und der Handler für das Beenden per Apple Event (quit-always). Danach folgen die neuen
  Methoden aus quit-always.
- **14, `CompleteRemoval.swift`:** h1-h3 hat `run()` als `run(phase:)` neu geschrieben. quit-always ändert darin nur
  zwei Dinge: Es setzt für die Dauer des Laufs `isRunning`, und es beendet mit `Quit.now(by: "the removal")` statt mit
  `NSApp.terminate`. Beides ist auf h1-h3s Fassung übertragen. Damit gehen alle drei Beenden-Wege (Entfernen, Update,
  Spielstart) über `Quit.now`.
- **14, `tests/CompleteRemovalTest/main.swift`:** h1-h3s neuer Testblock bleibt, quit-alwayss `quit()` wird
  zusätzlich aufgerufen. Die Reihe kann vor dem Neustart nicht laufen (ps). Gerade diese Lösung sollte sie danach
  zuerst prüfen.
- **15, `Launcher.swift`:** Vor dem Start von Steam steht beides. engine-env schreibt die Wine-Schalter des Spiels ins
  Log, steam-programm ruft `SteamProgram.prepare` auf. Der Kommentar ist der von steam-programm, mit den
  LaunchOptions.
- **15, `LibraryModel.swift`:** Der Aufruf `prepareLaunchEnvironment` hat jetzt beides: engine-envs Argument
  `environment:` und steam-programms `|| programChanged`.

Den Audit-Commit 783921d habe ich vor dem Merge noch einmal geändert (jetzt 20f0acc). Er nennt bei M1 und N9 jetzt die
neuen Commits von signed-updates (b1c26c9, 700fd70), als „noch nicht geprüft“.

## Tests der zweiten Runde (auf e6ec798)

- **pytest:** 108 von 108.
- **Swift-Reihen ohne echte Prozessliste:** 50 von 50 grün, jede mit rc=0: die 48 aus der ersten Runde,
  dazu die neuen `SignatureTest` und `SteamProgramTest`.
- Offen wegen ps sind dieselben neun Reihen wie oben, jetzt mit den Lösungen aus Merge 14 in `CompleteRemovalTest`.
- Während des Laufs entstanden in `~/Library/Preferences` zwar `nightforge.engine-rollback-test-<UUID>` (sieben),
  `engine-rollback-test`, `launch-health-test` und `nightforge.launch-phase-test`, aber nicht durch Staging. Dessen
  `EngineRollbackTest` hat keine solche Suite mehr. Die Dateien kamen paarweise etwa alle acht Minuten und meist nach
  dem Ende der beiden Staging-Reihen (02:13 und 02:17), also aus den alten Reihen einer anderen Sitzung.

## Für die echten Merges

- Noch in Arbeit und später nachzuziehen: `claude/game-test-fixes`, compat-db M3/N7 und der zweite angekündigte
  Commit von h1-h3.
- Der Stand je Befund steht jetzt in `docs/AUDIT-SICHERHEIT.md` (Merge 16).
- Mit N1 (audit-low) startet ein `nightforge://play`-Link nur noch mit dem Schlüssel der eigenen Spiel-Apps. Eigene
  Kurzbefehle des Nutzers mit solchen Links zeigen danach die Spielseite (für den Nutzer in `docs/TODO.md`).
- Die vor Merge 1 liegengebliebenen Test-Plists räumt der Nutzer auf (Liste in `docs/TODO.md`, Wartung und
  Community).
