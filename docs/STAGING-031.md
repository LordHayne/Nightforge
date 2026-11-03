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

## Dritte Runde (3.11., auf b2ee5e5 aufgesetzt, nichts davor umgeschrieben)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 17 | `claude/h1-h3-031` bis 85ff930 | 85ff930 | 4e6d0e6 | keine | 0 |
| 18 | `claude/steam-tray-1a4e06` | 9813c84 | 5151b23 | keine | 0 |
| 19 | `claude/engine-rueckfall-33` | d52f08c | 285dd99 | `Engine.swift`, `Launcher.swift`, `docs/TODO.md`, siehe unten | 0 |

`claude/signed-updates-dda700` war mit 13b (700fd70) schon ganz drin.

- **17:** `ProcessList.source` und `tests/Shared/FakeProcesses.swift`. Die Reihen geben `ProcessList` ihre eigene
  Liste, statt `ps -ax` zu fragen. `ci.yml` hat dafür einen Schritt `tests/ProcessListLive/run.sh`, die einzige
  Prüfung mit dem echten `ps`. Sie liegt außerhalb von `tests/*Test` und lief hier nicht.
- **18:** `SteamBackgroundTest` prüft auch das Tray-Symbol. Dazu startet die Reihe eine kleine Probe mit eigener
  Defaults-Domäne `nightforge-tray-probe` und räumt sie im `trap` wieder weg, nicht die der App.
- **19, `Engine.swift` (`startSteam`):** Im Zweig „Steam läuft noch nicht“ steht jetzt beides. Zuerst
  `SteamProgram.apply` (steam-programm), danach `wine = steamEngine(wine)` und `lastSteamStart` (engine-rueckfall).
  Dafür wird `wine` zu `var`. Der Loader der Sandbox nimmt danach die gewählte Engine.
- **19, `Launcher.swift`:** Hier stehen `SteamProgram.apply` und `Engine.lastSteamStart = (runner, Date())`
  hintereinander.
- **19, `docs/TODO.md`:** Übernommen sind engine-rueckfalls neu geschriebene Punkte zum Rückfall („erledigt“, „gebaut“,
  „behoben“). Der Punkt zur Speicher-Anzeige fehlt, weil storage-fixes ihn als behoben gestrichen hat.
- `EngineRollbackTest` hat auch mit den Ergänzungen aus 19 keine Suite mit echtem Namen.

## Tests der dritten Runde (auf 285dd99)

- **pytest:** 108 von 108.
- **Alle 59 Swift-Reihen grün, jede mit rc=0**, auch die neun bisher wegen ps offenen. Jede lief mit Zeitgrenze,
  keine hing:
  - `CompleteRemovalTest`, darin die Lösung aus Merge 14;
  - `DetachedProcessTest`, `EpicTest`, `GOGTest`, `GameOverlayTest` und `SteamBackgroundTest` mit `FakeProcesses`;
  - `SubprocessTest`, das `ProcessList.source` selbst setzt;
  - `QuitScriptTest` mit den Stand-ins für `pgrep` und `lsof` im PATH des Skripts;
  - `MacVersionTest`, das kein `ps` mehr aufruft.
- Nicht gelaufen ist nur `tests/ProcessListLive/run.sh`, die Prüfung mit dem echten `ps`. Sie gehört nach den
  Neustart.
- In `~/Library/Preferences` entstanden in dieser Zeit Test-Plists mit den alten Namen (`mvt-<UUID>`,
  `ProfileFilesTest-<UUID>`, `nightforge.game-audio-test.<PID>` und andere). Staging schreibt keine solchen Suites
  mehr. Das neue `mvt-<UUID>` kam um 02:57, zehn Minuten nach dem Ende von Stagings `MacVersionTest` (02:47). Es stammt
  also aus den alten Reihen einer anderen Sitzung.

## Vierte Runde (3.11., auf 6d9ecb1 aufgesetzt)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 20 | `claude/audit-low` (Review M10) | 9ba69ab | c5a1d36 | keine | 0 |
| 21 | `claude/steam-program-m4` (Review M4) | d92494f | 3e23000 | keine | 0 |
| 22 | `claude/signed-updates-dda700` (Review M2, M9, `docs/SIGNIEREN.md`) | 593e80e | fb13369 | `docs/TODO.md` | 0 |
| 23 | `claude/wine-sandbox` (Sandbox H1) | 01e234d | 7b6eeea | `Engine.swift` | 0 |
| 24 | `claude/quit-always-1a4e06` (Review M7) | 38b4418 | 440499f | keine | 0 |
| 25 | `claude/system-prompt-curtain-1a4e06` (Review M8) | a9a7b5e | a4c4713 | keine | 0 |
| 26 | `claude/h1-h3-031` (Review M3) | 69ad783 | 56635ff, dazu 49e249d | `Engine.swift` (zweimal), `Launcher.swift`, `LibraryModel.swift` | 0 |
| 27 | `claude/wine-sandbox` (Sandbox H2) | a4d0cdd | 8157ca4, dazu 897b94a | keine; eine Anpassung des Tests | 0 |

Konflikte und Anpassungen:
- **22, `docs/TODO.md`:** signed-updates hat den Punkt „Nur geprüfte Komponenten“ neu geschrieben, der gilt. Die Zeile zu
  den Tests in der CI nennt jetzt, was `ci.yml` wirklich ausführt.
- **23, `Engine.startSteam`:** Der Block für „Steam läuft nicht“ bleibt. `let process = DetachedProcess()` fällt weg,
  weil die Sandbox den Prozess nach dem Loader mit `WineSandbox.process` baut. Zur Kontrolle: Programmstarts mit
  `DetachedProcess()` gibt es auf Staging genauso viele wie auf dem Sandbox-Zweig.
- **26, `Engine.ensureEngine`:** Beide Änderungen bleiben. Unbenutzte Komponenten gehen nur nach einer signierten Liste
  (signed-updates M9), und eine gehaltene Engine gilt als benutzt, solange es keine Prozessliste gibt
  (`ownProcessesKnown`, M3).
- **26, `Engine.startSteam` und `Launcher`:** Guide-Knopf, LaunchOptions, Wahl der Engine und Startnotiz kommen nur
  noch, wenn bekannt ist, dass Steam nicht läuft (`steamRunningKnown == false`, M3). Im Launcher stehen davor
  engine-envs Notiz und `SteamProgram.prepare`.
- **26, Vorhang in `LibraryModel.swift`:** M3s `GameProcesses.curtainLook` gilt (ohne Liste wird nichts entschieden).
  Die Fragesteller von macOS (M8) kommen in derselben Aufgabe aus demselben, zwischengespeicherten
  `GameProcesses.lookup`. Ohne Liste gibt es keine.
- **49e249d (Staging-Commit):** `SteamProgram.steamIsDown` heißt jetzt `Engine.steamRunningKnown == false`. Der
  M4-Zweig hatte noch keinen M3 und behalf sich mit „die Liste enthält Nightforge selbst“.
- **897b94a (Staging-Commit):** `WineSandboxTest` prüft, dass jeder Programmstart über `WineSandbox.process` läuft
  oder bekannt ist, dass er kein Wine startet. h1-h3s `Subprocess.run` (`Subprocess.swift:33`) kannte der Test noch
  nicht. Seine Aufrufer starten Systemprogramme und `wineserver -k`, deshalb steht er jetzt auf der Liste. Was ein
  `Subprocess.run`-Aufruf selbst startet, prüft der Test nicht. Das sollten die Sandbox- und die h1-h3-Seite klären.

## Tests der vierten Runde (auf 8157ca4, WineSandboxTest auf 897b94a)

- **pytest:** 108 von 108.
- **Alle 59 Swift-Reihen grün:** 58 auf 8157ca4. `WineSandboxTest` schlug dort mit dem Fund oben fehl und ist nach
  897b94a grün. `tests/ProcessListLive` (echtes `ps`) lief wieder nicht.

## Nicht in der vierten Runde

signed-updates' drei neuere Commits, engine-env und profile-guide sind in der fünften Runde nachgezogen (28–30).

## Nach dem Neustart: das echte `ps` (auf 51662a5)

`ps -ax` antwortet seit etwa 06:30 wieder.

- **`tests/ProcessListLive/run.sh`:** grün. `ProcessList.ps`, `Engine.processTable` und `GameProcesses.table`
  finden das Prüfprogramm in der echten Liste, die Spalten kommen wie verlangt.
- **Die neun früheren ps-Reihen:** alle mit rc=0, zwei gleichzeitig und mit Zeitgrenze, keine hing. Einen Schalter
  für das echte `ps` bietet keine der Reihen:
  - `CompleteRemovalTest`, `DetachedProcessTest`, `EpicTest`, `GOGTest`, `GameOverlayTest` und
    `SteamBackgroundTest` setzen `FakeProcesses` fest. Die Prozesse, die sie selbst starten, lesen sie einzeln
    über ihre PID.
  - `SubprocessTest` nimmt ein Stand-in als `ProcessList.program`, `QuitScriptTest` Stand-ins für `pgrep` und
    `lsof`. `MacVersionTest` ruft kein `ps` mehr auf.
  - Auf die echte Liste umgebaut habe ich die Reihen nicht. Dann entschieden `CompleteRemovalTest` und
    `DetachedProcessTest` über das, was gerade läuft, und in der App lief der Spieletest. Das echte `ps` prüft
    `ProcessListLive`.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** alle 59 Reihen grün (1550 s). **pytest:** 108 von 108.
- In `~/Library/Preferences` änderten sich in dieser Zeit Test-Plists: `ProfileFilesTest-<UUID>` paarweise um
  06:56 und 07:05, dazu `mvt-<UUID>`, `io.github.lordhayne.nightforge.gametest-<UUID>`, `engine-layout-test`,
  `engine-rollback-test`, `io.github.lordhayne.nightforge.removal-test` und andere.
  - Von Staging kommen sie nicht. Stagings `ProfileFilesTest` endete um 07:02, `EngineLayoutTest` um 06:50.
    Ausnahme ist `nightforge.wine-sandbox-test-<UUID>` (07:11), siehe die Tests der fünften Runde.
  - Gleichzeitig lief im Worktree `angry-heisenberg-1f2283` (`claude/game-test-fixes`) eine eigene Testreihe mit
    `xargs -P 2`. Dieser Zweig hat `tests/Shared/TestDefaults.swift` noch nicht.
  - Gelöscht habe ich nichts.

## Fünfte Runde (3.11., auf 51662a5)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 28 | `claude/signed-updates-dda700` (Review M1, M5, M6) | 435e399 | bc83342 | `.github/workflows/wrapper.yml` | 0 |
| 29 | `claude/engine-env-0f3a` | 5c8edd0 | 5564e29 | `Launcher.swift`, `LibraryModel.swift`, `tests/CompleteRemovalTest/run.sh`, `tests/EngineLayoutTest/main.swift` | 0 |
| 30 | `claude/profile-guide-1a4e06` | bf214f5 | d8b4d9c | keine | 0 |

Die Merges entstanden in einem zweiten Worktree, während die Reihen auf 51662a5 liefen. `claude/staging-031` ist
danach per Fast-Forward auf d8b4d9c gegangen. Jeder der drei Merges ist für sich gebaut.

Konflikte und Anpassungen:
- **28, `.github/workflows/wrapper.yml`:** signed-updates baut den Wrapper jetzt in einem Job und schlägt ihn in
  einem zweiten als Pull Request vor (Zweig `bot/wrapper`), statt auf main zu pushen. Staging hatte dazu die Zeile mit
  der SHA-256 (audit-low, Merge 4). Beides gilt:
  - Das Artefakt trägt `steamwebhelper.exe` und `steamwebhelper.exe.sha256`.
  - Der Vorschlag vergleicht und committet beide Dateien. Mit dem `.exe` allein käme ein neues Programm ohne
    passende Zeile, und `build.sh` lehnte es ab.
  - `tests/test_wrapper_checksum.py` prüft genau diese Zeilen.
- **29, `Launcher.swift`:** Zuerst kommt engine-envs Notiz zum Vulkan-Loader, dann `SteamProgram.prepare`, dann M3s
  `steamRunningKnown == false` mit steam-programms Kommentar.
- **29, `LibraryModel.swift`:** Der Aufruf hat engine-envs Argument `vulkan:` und steam-programms
  `|| programChanged`.
- **29, `tests/CompleteRemovalTest/run.sh`:** Stagings Zeile mit `FakeProcesses` (h1-h3) bleibt.
- **29, `tests/EngineLayoutTest/main.swift`:** engine-envs neue Prüfungen (Registry, Vulkan-Loader) stehen hinter
  dem Block der Spiel-Schalter.
- **29, ohne Konflikt:** 4e02fbf entspricht Stagings 8b5314d und cb18659 kleinkrams 85f6a1f. Beide gingen ohne
  Änderung durch. 5c8edd0 nimmt `applyGameEnvironment` heraus, auf Staging ruft es danach niemand mehr auf.

## Tests der fünften Runde (auf d8b4d9c)

- **`tests/ProcessListLive/run.sh`:** grün, das echte `ps`.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** alle 59 Reihen grün (1440 s), jede Reihe für sich mit rc=0.
- **pytest:** 112 von 112. Die vier neuen kommen mit signed-updates (28): Perl gegen CryptoKit mit RFC 8032, der
  Stempel einer neueren Liste und zwei zu `sign-release.sh`.
- **Ein Fund, 7374066 (Staging-Commit):** `WineSandboxTest` legte bei jedem Lauf eine Suite
  `nightforge.wine-sandbox-test-<UUID>` im echten `~/Library/Preferences` an. Sie kam mit Sandbox H1 (01e234d, Merge
  23). Die Reihe leerte die Suite am Ende nur, die Datei blieb.
  - Vier solche Dateien stammen aus Stagings Läufen (04:55, 04:57, 07:11, 07:42).
  - Jetzt kompiliert die Reihe `tests/Shared/TestDefaults.swift` und nimmt `TestDefaults.suite("wine-sandbox")`.
  - Danach ist sie grün und hinterlässt keine Datei mehr.
- Die übrigen Test-Plists, die sich während des Laufs änderten (`ProfileFilesTest-<UUID>` um 07:21, `mvt-<UUID>`,
  `…gametest-<UUID>`, `engine-layout-test` und andere), passen wieder nicht zu Stagings Reihen. Sie passen zur Reihe
  in `angry-heisenberg-1f2283`, die noch lief, als Stagings Lauf schon zu Ende war.

## Nicht in der fünften Runde (in der sechsten nachgezogen oder entschieden)

game-test-fixes bis ee28d32, compat-db M3/N7 und die Wahl der Anleitung kamen in der sechsten Runde (31–33).

- **`claude/game-test-fixes`, jetzt 1ec9167 (07:30, davor a34e251 und ee28d32):** nicht fertig gemeldet, die
  Sitzung arbeitet noch. Ein Probe-Merge (`git merge-tree`) zeigt zwei Konflikte, die von Hand zusammengeführt werden
  müssen:
  - `GameTestRun.swift`, in der Schleife des Spieletests. M3 zählt dort Blicke ohne Prozessliste, game-test-fixes
    verfolgt jetzt mehrere PIDs, Steams Fragen und wer den Vordergrund nimmt.
  - `tests/GameOverlayTest/main.swift`, wo beide Seiten an derselben Stelle einen Testblock anfügen.
- **compat-db M3 und N7:** stehen auf `claude/report-url-m3` (ce91765 06:39, b87dee7 06:51). Nicht fertig
  gemeldet, die Sitzung arbeitet noch. Ein Probe-Merge geht ohne Konflikt.
- **KosmicKrisp:** `claude/wine-sandbox` hat nach a4d0cdd nichts Neues, H1 bis H3 sind seit Merge 27 da.
  `claude/quirky-clarke-81fd65` (DirectX 9) stand nicht auf der Liste.
- **`claude/tested-on-mac`, 1a35913 (06:40):** eine zweite Anleitung für Profile, neben der von profile-guide.
  - tested-on-mac schreibt `docs/CONTRIBUTING.md` und `.github/pull_request_template.md`, profile-guide (30)
    `docs/PROFILE.md` und `.github/PULL_REQUEST_TEMPLATE/profile.md`.
  - Beide ändern dieselbe Zeile im README.
  - Nicht gemergt. Es sollte nur eine der beiden gelten.

## Sechste Runde (3.11., auf 056184e)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 31 | `claude/game-test-fixes` bis ee28d32 | ee28d32 | 25da571 | `GameTestRun.swift`, `tests/GameOverlayTest/main.swift` | 0 |
| 32 | `claude/report-url-m3` (compat-db, Audit M3 und N7) | b87dee7 | 9ea5350 | keine | 0 |
| 33 | `claude/tested-on-mac` (Anleitung für Profile), davor 30 zurückgenommen | 1a35913 | 5720a1d, 7c13864 | keine | 0 |

Schon da und nicht noch einmal gemergt: engine-env bis 5c8edd0 (29) und wine-sandboxs d493cd4 (H3, mit 27).

Konflikte und Anpassungen:
- **31, `GameTestRun.swift`:** Beide Absichten gelten. game-test-fixes rechnet mit der Liste, wenn es eine gibt, und
  ohne Liste wird nichts entschieden wie bei h1-h3.
  - game-test-fixes bringt `pids`, die Verfolgung von Steams Fragen (`asking`) und wer den Vordergrund nimmt
    (`foreignSince`, `frontTakers`). M3 bringt `blind`, die Zahl der Blicke ohne Prozessliste.
  - Ein Blick ohne Liste wird wie bisher nicht bewertet. Nach zwei Minuten davon endet der Test des Spiels mit einer
    Notiz. Mit Liste ist sie das `pids` von game-test-fixes.
  - Die neuen Aufrufer von `processes(of:)` aus game-test-fixes, `clearStage` und `endLateStart`, beenden ohne Liste
    nichts (`?.isEmpty == false`), wie `quit(_:)`.
  - `GameProcesses.biggest`, `question` und `windowList` arbeiten über die PID (libproc, CGWindowList), ohne
    Prozessliste.
- **31, `tests/GameOverlayTest/main.swift`:** M8s Prüfungen der Fragesteller von macOS und game-test-fixes'
  `biggest(_:)` bleiben beide.
- **33:** Die Hauptsitzung nimmt vorerst die Anleitung von tested-on-mac. Weil vor dem Kopf nichts umgeschrieben wird,
  nimmt 5720a1d Merge 30 zurück (`git revert -m 1 d8b4d9c`). Danach kommt tested-on-mac (7c13864). Wer
  profile-guides Fassung (bf214f5) später doch nimmt, muss zuerst 5720a1d zurücknehmen.

## Tests der sechsten Runde (auf 7c13864)

- **`tests/ProcessListLive/run.sh`:** grün, das echte `ps`.
- **pytest:** 113 von 113.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** 58 von 59 grün. `SubprocessTest` schlug mit drei Prüfungen fehl, und
  zwar wegen der Last, nicht wegen der Merges:
  - Es geht um die Prüfungen der Prozessliste mit einem Stand-in für `ps`: „the list is what ps printed: nil“, „asked
    again … (0 calls)“, „an old list is marked as old“.
  - Das Stand-in kam in der Grenze von 0,5 s (`ProcessList.timeout` im Test) nicht einmal bis zu seiner ersten Zeile.
  - 31 bis 33 ändern weder `Subprocess.swift` noch die Reihe, und in der fünften Runde war sie grün.
  - Allein noch dreimal gelaufen: einmal derselbe Fehler, zweimal grün. Die Last lag dabei bei 6 bis 7, weil
    gleichzeitig die Reihen in `angry-heisenberg-1f2283` und der Spieletest liefen.
  - Für die h1-h3-Seite: Die 0,5 s sind auf einem belasteten Mac zu knapp, in der CI womöglich auch.
- Test-Plists in `~/Library/Preferences` (`removal-test`, `duplicate-games-test`, `nightforge.test.oldgame` und
  andere) änderten sich um 08:12 bis 08:14. Stagings `CompleteRemovalTest` und `DuplicateGamesTest` waren da schon seit
  07:54 und 07:56 fertig. Sie stammen also wieder aus der Reihe in `angry-heisenberg-1f2283`.

## Nicht in der sechsten Runde

- **`claude/game-test-fixes` a34e251 (07:05) und 1ec9167 (07:30):** nach ee28d32 dazugekommen, nicht aufgeführt, die
  Sitzung arbeitet noch.
  - Ein Probe-Merge auf 7c13864 geht ohne Konflikt.
  - 1ec9167 liest das Spiel-Log, nicht die Prozessliste.
- **`claude/engine-env-0f3a` 03e7843 (07:15):** nur `docs/TODO.md` (Overwatch-Test E), nach 5c8edd0.
- **`claude/profile-guide-1a4e06` bf214f5:** notiert, siehe 33.
- **`claude/quirky-clarke-81fd65` (KosmicKrisp DirectX 9):** stand nicht auf der Liste.

## Siebte Runde (3.11., auf a3245b4)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 34 | `claude/system-prompt-curtain-1a4e06` (Vorhang unter macOS-Fragen) | c696a64 | 85e89eb | `LibraryModel.swift`, `tests/GameOverlayTest/main.swift` | 0 |
| 35 | `claude/game-test-fixes` bis 1ec9167 | 1ec9167 | b74875a | keine | 0 |
| 36 | `claude/h1-h3-031` (`SubprocessTest` unter Last) | a097ccb | 2ab3cb1 | keine | 0 |

engine-env bis 5c8edd0 war mit 29 schon da.

Konflikte und Anpassungen:
- **34, `LibraryModel.swift`, der Blick des Vorhangs:** M3s `GameProcesses.curtainLook` bleibt (ohne Liste wird nichts
  entschieden, `blindLooks`). Dazu kommt das neue `macOSQuestions` des Zweigs, also alle Fragen von macOS statt nur
  der vordersten, aus denselben Fragestellern wie bisher. Die Fragen werden wie bisher erst nach der Prüfung „keine
  Liste“ behandelt.
- **34, `tests/GameOverlayTest/main.swift`:** Die neue Prüfung von `macOSQuestions` steht im Block der Fragesteller,
  danach game-test-fixes' `biggest(_:)`.
- **35, ohne Konflikt:** `GameTest.macOSAsking` liest im Log die Zeile des Vorhangs „Curtain under a question of
  macOS's for <Spiel>: …“. Seit 34 kommt sie nur für eine Frage, die während des Starts aufkam. Die neue Zeile für eine
  Frage von vorher passt nicht darauf. Eine alte Frage bricht also auch im Spieletest keinen Start ab.
- **36:** ein Commit auf `claude/h1-h3-031`, gebaut und geprüft in einem eigenen Worktree. Der Zweig ist im Worktree
  `code-review-plan-2f9ae5` (sauber) per `--ff-only` auf a097ccb gegangen.
  - Das Stand-in-`ps` hat jetzt 3 s statt 0,5 s. Bei 0,5 s kam es unter Last manchmal nicht einmal bis zu seiner ersten
    Zeile, und alle Prüfungen danach schlugen fehl.
  - Damit der Test nicht zahnlos wird, wird gegen diese Grenze gemessen. Ein hängendes `ps` muss an der Grenze
    zurückkommen (3 bis 6 s) statt nur unter 4 s, also nicht nach den 30 s des Stand-ins. In der Pause wartet niemand
    länger als ein Drittel davon.
  - Die Shell, die vor ihrer Grenze schreibt, hat ebenfalls 3 s statt 1 s.

## Tests der siebten Runde (auf 2ab3cb1)

- **`tests/ProcessListLive/run.sh`:** grün, das echte `ps`.
- **pytest:** 113 von 113.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** 58 von 59. `SubprocessTest` ist grün.
- **Der Vergleich unter Last:** Während des vollen Laufs lief der alte und der neue `SubprocessTest` je zwölfmal im
  Wechsel, bei einer Last von 6,4 bis 8,9. Der alte schlug einmal fehl (bei 8,9), der neue keinmal. Ein Lauf des neuen
  dauert etwa 10 s statt 5 s.
- **`PadFocusTest` schlug fehl, mit 6 Prüfungen, und zwar wegen des ausgeschalteten Bildschirms, nicht wegen der
  Merges:**
  - Betroffen sind die Prüfungen des weichen Scrollens („the control below shows with room under it: 0.0“ und die
    folgenden). Sie geben der Animation 0,5 s (`RunLoop.main.run`) und erwarten dann das Ziel. Die Seite hatte sich gar
    nicht bewegt.
  - Laut `pmset -g log` ist der Bildschirm seit 08:08:55 aus, der Nutzer ist weg. In der sechsten Runde war die Reihe um
    08:05 noch grün.
  - Allein lief sie danach dreimal mit demselben Fehler. Auf dem alten Kopf a3245b4 schlägt sie jetzt genauso fehl.
  - 34 bis 36 ändern weder `PadFocus.swift` noch `PageScroll` noch die Reihe.
  - Für die Controller-Seite: Die Reihe braucht einen eingeschalteten Bildschirm, ein Lauf über Nacht oder mit
    zugeklapptem Mac scheitert daran.
- Die Test-Plists, die sich in dieser Zeit änderten (`ProfileFilesTest-<UUID>` um 08:23, 08:48 und 08:50,
  `engine-layout-test` und andere), passen wieder nicht zu Stagings Reihen. Stagings `ProfileFilesTest` endete um
  08:43, `EngineLayoutTest` um 08:32.

## Nicht in der siebten Runde

- `claude/engine-env-0f3a` 03e7843: nur `docs/TODO.md`, nach 5c8edd0.
- `claude/profile-guide-1a4e06` bf214f5: notiert, siehe 33.
- `claude/quirky-clarke-81fd65` (KosmicKrisp DirectX 9): stand nicht auf der Liste.

## Achte Runde (3.11., auf 4497792)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 37 | `claude/unity-play` („Play!“ in Unitys Fenster, Schalter aus) | 5b03c67 | 60e24d5 | `Profiles.swift`, `docs/TODO.md` | 0 |
| 38 | `claude/game-test-fixes` bis 9e32feb | 9e32feb | 57730a2, dazu 78205cf | keine | 0 |
| 39 | `claude/padfocus-test-1a4e06` | 88f0cb8 | 529ca66 | keine | 0 |
| 40 | `claude/live-findings-0748` (ABZU, The Forest) | 65e2983 | 4cc8d42 | `docs/TODO.md` | 0 |
| 41 | `claude/stable-codesign` | b32a8ac | f068346 | `release.yml`, `docs/TODO.md` | 0 |
| 42 | `claude/engine-env-0f3a` bis 946c202 (nur TODO) | 946c202 | cd122f8 | keine | – |
| 43 | `claude/release-notes-031` (Entwurf) | b03f715 | d3269e3, dazu 5dd6d71 | keine | 0 |

Nicht gemergt: profile-guides bf214f5 (nicht gewählt). Der KosmicKrisp-Zweig ist noch offen, siehe unten.

Konflikte und Anpassungen:
- **37, `Profiles.swift`:** engine-envs `environment` und unity-plays `skipUnityDialog` stehen beide in den Feldern,
  den Schlüsseln und beim Lesen. **`docs/TODO.md`:** Der Schalter `unityDialogPlay` steht in der Liste der
  Testschalter nach dem von wine-sandbox, danach folgt engine-envs Abschnitt. So steht es auch in
  `unity-play-staging-merge.diff` im Notizordner.
- **37 und 38, der Name des Schalters:** Beide nennen ihn gleich, `unityDialogPlay`. game-test-fixes hatte dafür eine
  eigene Konstante (`GameTest.Keys.unityDialogPlay`), weil `UnityDialog` auf seinem Zweig fehlte. Der Staging-Commit
  78205cf macht daraus `UnityDialog.switchKey`, und `GameTestTest` prüft beides. `GameTestTest` ist grün.
- **40, `docs/TODO.md`:** report-url-m3s Abschnitt zum Problembericht und live-findings' Abschnitt zum Spieletest
  stehen hintereinander. Dessen Vorschlag für einen Play!-Helfer ist mit 37 und 38 gebaut.
- **41, `release.yml`:** signed-updates' Entwurf eines Releases und stable-codesigns Signaturidentität laufen jetzt
  nacheinander: zuerst die Identität, dann der Build, dann der Entwurf, danach wird der Schlüsselbund entfernt.
  **`docs/TODO.md`:** Der Punkt zur Codesignatur steht vor signed-updates' Abschnitt. Dieser hatte den alten Punkt
  „Updates sind nicht echt signiert“ ersetzt, der deshalb wegfällt.
- **41, ad hoc ohne Zertifikat:** Ohne die Identität „Nightforge Code Signing“ im Schlüsselbund (`security
  find-identity` findet keine) signiert `build.sh` wie bisher ad hoc. `codesign -dv` zeigt `Signature=adhoc`,
  `codesign --verify --deep --strict` geht durch.
- **43:** Der Entwurf liegt in `docs/RELEASE-NOTES-0.3.1.md`. `release.yml` nimmt für den Tag aber
  `docs/release-notes/v0.3.1.md`, das mit 41 kam und bisher nur den Absatz zur Codesignatur enthält. Das sagt der
  Entwurf selbst im Kopfkommentar. Vor dem Tag gehört sein Text dorthin.
- **5dd6d71 (Staging-Commit), ein Fund des vollen Laufs:** `WineSandboxTest` meldete `UnityDialog.swift:112`.
  unity-play startete Wine für seinen Helfer mit `DetachedProcess`, also an `WineSandbox.process` vorbei. Mit
  eingeschalteter Sandbox wäre der Helfer in der Sitzung des Spiels außerhalb gelaufen (Review H1). Jetzt geht er über
  `WineSandbox.process` wie die Spielstarts im Launcher. Fehlt bei eingeschalteter Sandbox ihr Helfer, startet er
  nicht. Danach sind `WineSandboxTest` und `UnityDialogTest` grün. Der Commit gehört in `claude/unity-play`.
- `tests/UnityDialogTest/dialog.sh` startet den Helfer unter winecx in einem eigenen Prefix. `run-tests.sh` ruft es
  nicht auf, und ich habe es nicht laufen lassen (keine Wine-Prozesse).

## Tests der achten Runde (auf d3269e3, danach 5dd6d71)

- **`tests/ProcessListLive/run.sh`:** grün.
- **pytest:** 123 von 123. Dazu kommen `test_codesign_app.py` (41) und die Prüfsumme von `unity-play.exe` (37).
- **Voller Lauf `scripts/run-tests.sh -P 2` auf d3269e3:** 59 von 60 grün, neu ist `UnityDialogTest`.
  `WineSandboxTest` schlug mit dem Fund oben fehl.
  - Auf 5dd6d71 sind `WineSandboxTest` und `UnityDialogTest` grün, der Build geht durch.
  - 5dd6d71 ändert nur `UnityDialog.start`, die übrigen Reihen sind dafür nicht noch einmal gelaufen.
- **`PadFocusTest` ist mit 88f0cb8 grün, bei schlafendem Bildschirm und gesperrter Sitzung.** Der Bildschirm ist
  seit 08:08:55 aus. Die Reihe lief allein zweimal grün und im vollen Lauf einmal. Mit „Reduce motion“ im
  Argument-Bereich, also nur im Speicher, landet `PageScroll.show` sofort. Nichts davon wird geschrieben.
- Die Test-Plists, die sich in dieser Zeit änderten (`removal-test` und `nightforge.wine-sandbox-test-<UUID>` um 09:21,
  `engine-layout-test` um 09:22), entstanden, bevor Stagings Reihen dieser Namen liefen. Deren Ende: 09:23,
  09:44 und 09:25. Sie stammen also aus dem Lauf einer anderen Sitzung.

## Achte Runde, Nachtrag: KosmicKrisp DirectX 9 (Merge 44)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 44 | `claude/quirky-clarke-81fd65` bis 763efd2 | 763efd2 | fbeab53 | `Engine.swift` (vier Stellen), `LibraryModel.swift` | 0 |

Die Lösung in `kosmickrisp-staging-merge.diff` (02:36) ist älter als engine-envs 4aaf428. Den Teil, den sie nicht
abdeckt, habe ich mit der KosmicKrisp-Sitzung abgestimmt (Frage 09:21, ihre Antwort danach).

- **Zwei Wege für Direct3D 9 auf DXVK unter winecx, ein Aufruf:** `prepareLaunchEnvironment` nimmt KosmicKrisps
  `vulkan: VulkanDriver?` und engine-envs Loader als `vulkanLoader: [String: String]`.
  - Zuerst kommt KosmicKrisps Weiche. `.kosmicKrisp` setzt seine Variablen und nimmt `VK_ADD_IMPLICIT_LAYER_PATH`
    weg. `.moltenVK` nimmt alle weg, nur das Backend eines Profils bleibt. `nil` lässt Steams Treiber stehen.
  - Danach kommt der Loader, aber nur, wenn er Werte hat. Vorher schrieb engine-env seine Variablen bei jedem Start,
    ohne Loader leer. Das hätte KosmicKrisps Werte gelöscht und nach Mafia II einen Neustart von Steam gekostet.
  - Meine Ergänzung: `nil` behält auch „wined3d“, solange ein `CX_LIBVULKAN` gesetzt ist und das Profil kein eigenes
    Backend hat. engine-envs Schleife über die Schalter des Spiels setzt `CX_ACTIVE_GRAPHICS_BACKEND` sonst bei jedem
    Start zurück. Ein DXMT-Spiel nach Mafia II hätte dann doch einen Neustart gekostet, und KosmicKrisps eigene
    Prüfung dazu wäre rot gewesen. Der KosmicKrisp-Sitzung ist das zum Übernehmen gemeldet.
- **Beide Schalter an:** Der Loader gewinnt. `LibraryModel` wählt KosmicKrisp nur bei `kosmicKrispReady`, und das ist
  bei eingeschaltetem Loader über `vulkanLayerLoads` falsch. Die Direktstarts (Epic, GOG) bekommen dieselbe Wahl.
- **Aus der Notiz:**
  - Mesas Shader-Ordner steht neben engine-envs Registry-Aufräumen.
  - `preparePrefix` hat kein `applyGameEnvironment` mehr (5c8edd0), aber `d3d9From`.
  - `ensureEngine` und `useHeld` nehmen auch upstream-DXVKs Direct3D 9 mit.
- **`EngineLayoutTest`:**
  - Der Fall des Loaders steht unter dem neuen Namen.
  - Ein DXMT-Spiel nach dem Loader kostet keinen Neustart, das war vorher „Steam startet ohne sie neu“.
  - KosmicKrisp nach dem Loader hat seine Variablen und keine des Loaders.
  - Der Loader wieder: KosmicKrisps Cache-Ordner fällt weg.
  - Ein DirectX-11-Spiel auf DXVK räumt alles ab.
- **KosmicKrisp bleibt aus.** Die Komponentenliste nennt nur upstream-DXVK 3.1.1, nicht `kosmickrisp`. Das steht
  erst als optionaler Eintrag in `components/sources.json`, bis es ein Release gibt. Ohne Komponente ist
  `kosmicKrispNow` nil, und upstream-DXVK wird nur zusammen mit KosmicKrisp eingerichtet.
- Neu, nicht von `run-tests.sh` ausgeführt und nicht gelaufen: `tests/kosmickrisp/` (D3D9-Probe, Live-Test-Skript)
  und `.github/workflows/kosmickrisp.yml`.

## Tests nach Merge 44 (auf fbeab53)

- **`tests/ProcessListLive/run.sh`:** grün.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** alle 60 Reihen grün (1291 s), auch `PadFocusTest` bei gesperrtem
  Bildschirm und `WineSandboxTest`. **pytest:** 123 von 123.
- Vorab allein: `EngineLayoutTest` und `LaunchHealthTest` grün.
- Neue Test-Plists in dieser Zeit (`nightforge.wine-sandbox-test-<UUID>` um 10:12 und 10:15, `com.example.other`)
  kommen nicht von Staging. Stagings `WineSandboxTest` legt seine Suite seit 7374066 im Arbeitsordner an, und keine
  Staging-Reihe nennt `com.example.other`.

## Neunte Runde (3.11., auf c869b59)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 45 | `claude/signed-updates-dda700` (Review N5, N6) | 9f7c5ec | c596eb8 | keine | 0 |
| 46 | `claude/wine-sandbox` bis 5300f05 (Review N2, N8) | 5300f05 | 2e77f71 | keine | 0 |
| 47 | `claude/release-notes-031` bis 28d9498 | 28d9498 | 6dc2826 | keine | – (nur Doku) |
| 48 | `claude/review-n-031` (N1, N3, N4, N7, N12, Zusatz 1–4) | 49f721f | e9f2459 | keine | 0 |

- **46:** Der Schalter der Sandbox bleibt aus. Nach 5300f05 kamen 3d257f1 (das Beenden-Skript startet Steams
  `-shutdown` auch in der Sandbox) und 77e0bba (Nightforges Steuerdateien und seine Einstellungen sind von innen
  nicht änderbar). Beide sind nicht drin, weil die Runde bis 5300f05 verlangte.
- **46, N8 neben M3:** `Engine.stopSessionNow` fragt das schlichte `isSteamRunning`. Erreicht wird es nur über
  `WineSandbox.settleSession`, das unter einem laufenden Spiel nichts beendet. Seit M3 gilt `windowsGameRunning` ohne
  Prozessliste als wahr. Ohne Liste endet also keine Sitzung, und eine Anpassung ist nicht nötig.
- **48, warum schon in dieser Runde:** Eine Meldung „fertig“ habe ich nicht gesehen. Die Sitzung code-review ist seit
  10:45 untätig, ihr Worktree ist sauber auf 49f721f (letzter Commit 10:18), und der Probe-Merge geht ohne Konflikt.
  Soll 48 doch erst in die zehnte Runde, ist 6dc2826 der voll getestete Stand davor.
- **48 und der Vorhang (34):** N4 holt die Fragesteller von macOS in `curtainLook`, aus derselben Liste wie die
  Prozesse des Spiels. review-n-031 baut schon auf `macOSQuestions` auf. Ohne Liste wird wie bisher nichts
  entschieden.

## Tests der neunten Runde

- **Auf 6dc2826 (45 bis 47):**
  - `ProcessListLive` grün.
  - Voller Lauf `-P 2`: alle 60 Reihen grün (1556 s), auch `CompleteRemovalTest` und `WineSandboxTest` mit der
    Seatbelt-Probe von N2.
  - pytest: 124 von 124.
- **Auf e9f2459 (dazu 48):**
  - `ProcessListLive` grün.
  - Voller Lauf `-P 2`: alle 60 Reihen grün (1208 s).
  - pytest: 124 von 124.
- **Test-Plists:** Während des zweiten Laufs änderte sich in `~/Library/Preferences` keine. Im ersten Lauf änderten
  sich `removal-test` und `engine-layout-test` um 10:30 und 10:31. Die beiden Staging-Reihen waren da schon fertig
  (10:23, 10:26), die Plists stammen also aus einer anderen Sitzung.

## Neunte Runde, Nachtrag (auf a847623)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 49 | `claude/wine-sandbox` bis 77e0bba (3d257f1, 77e0bba) | 77e0bba | b7d7056, dazu 2a7b285 | `Engine.swift`, `tests/WineSandboxTest/main.swift` | 0 (mit 50) |
| 50 | `claude/engine-env-0f3a` bis 67a4da4 | 67a4da4 | c90d1d0 | `LibraryModel.swift` | 0 |

`claude/review-n-031` steht unverändert auf 49f721f, das ist mit 48 schon drin. Weitere Commits dort kämen als
Nachtrag dazu.

- **49, `steam-shutdown.sh`, die Nummern der Argumente:** h1-h3 gibt dem Skript als `$8` mit, wann zuletzt ein Spiel
  lief. wine-sandbox wollte `$8` und `$9` für Helfer und Profil der Sandbox. `$8` bleibt, wie es ist. Helfer und
  Profil kommen als `$9` und `${10}`.
  - `QuitScriptTest` und `MacVersionTest` rufen das Skript mit `$8` auf.
  - `WineSandboxTest` holt `wine_program` aus dem Skript und setzt `SANDBOX`/`PROFILE` selbst. Die Zeile in
    `scheduleSteamShutdown`, nach der es sucht, steht unverändert.
- **49, `WineSandboxTest`:** Die Sitzungsprüfung des Zweigs legt ihre Einstellungen jetzt selbst in ihren Testordner.
  Das gilt, Stagings 7374066 ist damit überholt.
- **2a7b285 (Staging-Commit):** 77e0bba schützt `launchoptions-written.json` und `shortcut-key` nach Namen. Diese
  Dateien gibt es nur auf Staging (SteamProgram, GameShortcut).
  - Der Test prüfte bisher nur die Namen als Text. Jetzt prüft er zusätzlich zwei Dinge:
    - `SteamProgram.record` ist diese Datei im Datenordner und steht unter dem, was innen nicht änderbar ist.
    - Die Datei, die `GameShortcut.key` schreibt, ist die, die die Regeln ganz sperren.
  - Eine Umbenennung auf einer Seite fällt damit auf. `WineSandboxTest` ist grün.
- **50, `LibraryModel.startDirect`:** Es nimmt beides, KosmicKrisps `vulkan:` (44) und engine-envs `usesD3D9:`.
  KosmicKrisps Variablen kommen über `directLaunchEnvironment`, die des Loaders darüber in
  `Launcher.directEnvironment`. Damit gewinnt der Loader auch hier, und der Spielordner wird nur einmal gelesen.
- **Am Rand, seit 44 so:** Auf dem Direktweg (Epic, GOG) geht das Profilfeld `CX_ACTIVE_GRAPHICS_BACKEND` über
  KosmicKrisps „wined3d“. Über Steam übernimmt KosmicKrisp das Backend. Das betrifft nur ein DirectX-9-Spiel auf DXVK
  mit eigenem Backend im Profil, solange KosmicKrisp aus ist also nichts.

## Tests nach dem Nachtrag (auf c90d1d0)

- **`tests/ProcessListLive/run.sh`:** grün.
- **pytest:** 124 von 124.
- **Vorab allein:** `WineSandboxTest`, `EngineLayoutTest` und `QuitScriptTest` grün.
- **Voller Lauf `-P 2`:** 59 von 60 (1270 s). `MacVersionTest` schlug mit einer Prüfung fehl: „the quit script brings
  Nightforge back once the game has ended (after 30 s)“. Ich halte es für eine Frage der Zeit unter Last, nicht für
  einen Fehler der Merges:
  - Die Prüfung erwartet das Zurückholen nach 4 bis 20 s. Das Skript fragt dafür in einer Schleife ein Stand-in für
    `ps` ab, ein Bash-Skript über eine Datei.
  - 49 ändert am Skript nur den Start von `steam.exe -shutdown`, über `wine_program`. In dieser Prüfung ist Wine leer
    (`$1 ""`), der Teil läuft also gar nicht.
  - Allein lief die Reihe danach zweimal grün (Last 2), in den vorigen vollen Läufen heute jedes Mal.
  - Für die Seite des Beenden-Skripts: Die 20 s sind unter `-P 2` auf einem beschäftigten Mac knapp, wie zuvor die
    0,5 s in `SubprocessTest`.
- **Test-Plists:** `ProfileFilesTest-<UUID>` um 11:21, vor Stagings `ProfileFilesTest`. Sie stammen also aus einer
  anderen Sitzung.

## Zehnte Runde (3.11., auf 5392523)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 51 | `claude/signed-updates-dda700` bis 83d10d2 (externes Review der Signierkette, A bis H) | 83d10d2 | d39a28a | `docs/TODO.md` | 0 |
| 52 | `claude/game-test-fixes` bis c5f4b07 (Spieletest ohne Prozessliste) | c5f4b07 | 41bb13d | `GameTestRun.swift` | 0 |

- **51, A bis H:**
  - A: `sign-lists.sh` baut sein Werkzeug aus dem eigenen Checkout, nie aus dem Zweig, den es signiert.
  - `Profiles` vergleicht mit `SignedLists.isOlder`, Stempel als Datum.
  - Der Updater bindet die Version im ZIP an den Tag.
  - `signatures.yml` prüft mit den Schlüsseln und dem Prüfer von main.
  - Die Eingaben der CI sind über Hashes festgelegt, dmgbuild in `release.yml` mit `--require-hashes`.
- **51, ungeprüft auf GitHub:** Die Änderungen an den Workflows (`components.yml`, `release.yml`,
  `signatures.yml`, `tools.yml`) sind nur lokal geprüft. Auf GitHub ist keiner gelaufen, hier nur das Lesen als YAML
  (geht). In `release.yml` bleiben die Schritte der Codesignatur aus 41 unverändert.
- **51, `docs/TODO.md`:** Bei den Rechten von `components.yml` gilt signed-updates' „seit dem Review G erledigt“.
  Die Zeile dazu, was die CI ausführt, bleibt die von Staging.
- **52, `GameTestRun.swift`:** Der Zweig hat h1-h3 selbst gemergt (052d9a6) und geht weiter als Stagings Merge 31.
  - `clearStage` und `quit` warten ohne Liste auf eine frische (`knownProcesses`), statt sie zu überspringen.
  - Zwei Minuten ohne Liste heißen „unbekannt“, nicht „startet nicht“.
  - In jeder Stelle gilt seine Seite.
  - `GameTest.macOSQuestion` liest die drei Zeilen des Vorhangs so, wie Stagings `LibraryModel` sie seit 34
    schreibt, auch die Zeile, mit der er aufgibt.
  - `GameTest.Keys.unityDialogPlay` bleibt `UnityDialog.switchKey` (78205cf).

## Tests der zehnten Runde (auf 41bb13d)

- **`tests/ProcessListLive/run.sh`:** grün.
- **Vorab allein:** `GameTestTest` und `GameOverlayTest` grün.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** alle 60 Reihen grün (1225 s). **pytest:** 129 von 129.
- **`MacVersionTest`** ist diesmal im vollen Lauf grün (62 s). In den acht vollen Läufen seit Runde acht schlug er
  einmal fehl, bei c90d1d0 unter Last, und war danach allein zweimal grün. Die drei Läufe allein, die für einen neuen
  Fehler vorgesehen waren, entfallen. Als Kandidat für die Stabilisierung bleibt er wegen des einen Fehlers.
- **Test-Plists:** In `~/Library/Preferences` änderte sich während des Laufs keine.

## Elfte Runde (3.11., auf dfe9fa1)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 53 | `claude/profile-ci` (Profil-CI: fileEdits, iniSettings, resolution, saves, winetricks-Windows-Versionen) | 6ec6878 | b77bee0 | keine | 0 |
| 54 | `claude/wine-sandbox` bis 76f1b50 (Caches der signierten Listen, Spiel-Apps) | 76f1b50 | e89120a | keine | 0 |

- **54:**
  - `profiles.json`, `agw.json` und ihre `.sig` im Datenordner sind innen nur lesbar.
  - `~/Applications/Nightforge Games` ist innen ganz gesperrt, nicht mehr nur lesbar.
  - `WineSandboxTest` ging neben Stagings 2a7b285 von selbst zusammen und ist grün.
- **Angekündigt, aber bis zum Ende der Runde nicht fertig gemeldet.** Alle drei gehen auf e89120a ohne Konflikt
  zusammen (Probe-Merge):
  - `claude/profile-limits` 6e8dc40 (12:35): die Profilregeln in der App.
  - `claude/game-test-fixes` 44f09e8 (12:31): die Schwärzung in den Berichten. Er enthält einen Merge von
    report-url-m3.
  - `claude/review-n-031` b0d6863 (12:31): `BinaryKV.parse` mit höchstens 64 Ebenen und die GameShortcut-Punkte des
    externen Reviews.

## Tests der elften Runde (auf e89120a)

- **`tests/ProcessListLive/run.sh`:** grün.
- **Vorab allein:** `WineSandboxTest` grün, `tests/test_build_profiles.py` 32 von 32.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** alle 60 Reihen grün (1327 s), `MacVersionTest` auch (66 s).
  **pytest:** 137 von 137.
- **Test-Plists:** In `~/Library/Preferences` änderte sich während des Laufs keine.

## Zwölfte Runde (3.11., auf 1291796)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 55 | `claude/profile-limits` (Profilregeln in der App, acht Commits) | 6e8dc40 | dc13f83 | keine | 0 |
| 56 | `claude/game-test-fixes` bis 44f09e8 (Schwärzung in den Berichten) | 44f09e8 | cabff73 | keine | 0 |
| 57 | `claude/review-n-031` bis b0d6863 (BinaryKV, GameShortcut) | b0d6863 | baf57f6 | keine | 0 |

**Regeln der App (55) gegen die der Profil-CI (53), aus dem Quelltext verglichen:**
- **Gleich:**
  - Die winetricks-Verben, die die Windows-Version setzen: 19 auf beiden Seiten, `Engine.windowsVersionVerbs` gegen
    `WINDOWS_VERSION_VERBS`.
  - Die Wurzeln: sechs für Windows (`gameinstall`, `winappdataroaming`, `winappdatalocal`, `winappdatalocallow`,
    `winmydocuments`, `winsavedgames`) und drei für den Mac (`gameinstall`, `macappsupport`, `maccaches`),
    `SaveTransfer.windowsRoot`/`macRoot` gegen `WINDOWS_ROOTS`/`MAC_ROOTS`.
  - Wines Kern-DLLs: 17 auf beiden Seiten.
  - Die Reihenfolgen der Overrides und die Regel für den DLL-Namen (Muster, kein `..`, Kern ohne `.dll`).
  - Die Regel für Argumente: Muster, höchstens 16, keine Laufwerke, kein Pfad ab der Wurzel, höchstens ein `..`.
- **Nur die App ist strenger.** Die CI lässt durch, was die App dann auslässt oder begrenzt:
  - 15 weitere winetricks-Verben, die den ganzen Prefix verstellen (`sharedPrefixUnsafeVerbs`: `dsound`, `sandbox`,
    `isolate_home` und andere). In den heutigen `profiles.json` und `mac.json` steht keins davon.
  - `frameLimit` bis 240 und `vulkanSamplers` bis 128. Die CI prüft keine Grenze.
  - Höchstens 32 DLL-Overrides. In der CI fand ich keine Grenze.
  - Die CI könnte diese Punkte übernehmen, damit nichts still entfällt. Ein Widerspruch ist es nicht.

Weitere Punkte:
- **56:** report-url-m3 ist darin gemergt und steht auf Staging seit 32 schon. Der Merge ging ohne Konflikt.
- **57, der Schlüssel der Spiel-Apps:** `GameShortcut.key` schreibt jetzt zuerst eine eigene Datei,
  `shortcut-key.<UUID>.tmp` im Datenordner. Die wird dann in einem Schritt verlinkt und entfernt.
  - Die Regel der Sandbox (77e0bba) sperrt nur den genauen Namen `shortcut-key`. Die temporäre Datei besteht nur einen
    Augenblick und ist nur für den Spieler lesbar. Wine läuft aber unter demselben Benutzer.
  - Für die Sandbox-Seite: eine Regel für das Präfix `shortcut-key.`, oder die Datei an einen Ort, der schon gesperrt
    ist.
  - Stagings Prüfung 2a7b285 hält weiter, weil danach nur `shortcut-key` übrig bleibt.
- **57:** code-review ließ nur die neun betroffenen Reihen laufen. Den vollen Lauf gibt es unten.

## Tests der zwölften Runde (auf baf57f6)

- **`tests/ProcessListLive/run.sh`:** grün.
- **Vorab allein:** `GameShortcutTest` und `WineSandboxTest` grün.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** alle 60 Reihen grün (1209 s), `MacVersionTest` auch (61 s).
  **pytest:** 138 von 138.
- **Test-Plists:** In `~/Library/Preferences` änderte sich während des Laufs keine.

## Dreizehnte Runde (3.11., auf 4f0d00a)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 58 | `claude/security-status` (code-review) | 0912515 | 9737280 | keine | 0 |
| 59 | `claude/quit-safety` (engine-04) | c5688a4 | 26fb883 | `CompleteRemoval.swift`, `tests/CompleteRemovalTest/main.swift` | 0 |
| 60 | `claude/uninstall-safety` (kosmickrisp-dx9) | 4048a57 | 2f2d622 | keine | 0 |
| 61 | `claude/perf-031` (display-polish) | 1b282d7 | 327d457 | keine | 0 |
| 62 | `claude/wine-sandbox` bis 5cc5402 | 5cc5402 | 37f4f03 | keine | 0 |
| 63 | `claude/signed-updates-dda700` bis b6f340a | b6f340a | 54de5dc | keine | 0 |
| 64 | `claude/release-notes-031` bis ce56a0c | ce56a0c | 764686c | keine | 0 |
| 65 | `claude/kleinkram-031-766fe2` (f50c368, `install.sh`) | f50c368 | 2019741 | `scripts/install.sh` | 0 |

- **59, `CompleteRemoval.endScripts`:** Beide Zweige haben dasselbe behoben. Das Beenden-Skript gilt nur, wenn es das
  erste Argument von bash ist, nicht wo sein Pfad irgendwo im Befehl steht.
  - Es bleibt security-status' `runsScript` (58). Es deckt quit-safetys Prüfung ab und dazu `bash <Skript>`.
  - `CompleteRemovalTest` behält beide Attrappen, eine bash mit dem Pfad als späterem Argument (security-status) und
    eine, deren `-c`-Text ihn nennt (quit-safety). Die Reihe ist grün.
- **59 und 60, das Entfernen eines Spiels:** Kein Textkonflikt. quit-safety ändert `Engine.removeGameFiles` für Steam.
  uninstall-safety ändert die Wege für Epic und GOG und verweist in seinen Kommentaren auf die Steam-Fassung. Die beiden
  ergänzen sich.
- **65, `scripts/install.sh`:** signed-updates' Block bleibt, wo er ist. Der alte Kommentar über `quit_running` weicht
  `app_running` und seinem Kommentar. Das ist dieselbe Lösung, die vorab auf 4f0d00a getestet war: Install- und
  Signier-Tests 47 von 47.
- **62:** `claude/wine-sandbox` 5cc5402 ist jetzt drin. Die Prüfungen von compat-db im Live-Test (L.6) gelten damit für
  den Build von heute Abend.

## Tests der dreizehnten Runde (auf 2019741)

- **`tests/ProcessListLive/run.sh`:** grün.
- **Vorab allein:** `CompleteRemovalTest` grün auf dem gelösten Stand von 59. Dazu Install- und Signier-Tests 47 von 47
  nach 65.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** alle 60 Reihen grün (1239 s), `MacVersionTest` auch (63 s).
  **pytest:** 144 von 144.
- **Test-Plists:** In `~/Library/Preferences` änderte sich während des Laufs keine.

## Vierzehnte Runde (3.11., auf 9c45b18)

| # | Zweig | Kopf | Merge auf Staging | Konflikte | Build |
|---|---|---|---|---|---|
| 66 | `claude/quit-safety` bis e577c5b | e577c5b | 396978c | keine | 0 |
| 67 | `claude/uninstall-safety` bis 0d45261 | 0d45261 | 79ac2c6 | keine | 0 |
| 68 | `claude/game-test-fixes` bis e962125 | e962125 | faa4291 | keine | 0 |
| 69 | `claude/signed-updates-dda700` bis 7143a5c | 7143a5c | cb80381 | keine | 0 |
| 70 | `claude/profile-ci` bis 2ba6006 (`profiles.json` neu, 744 Spiele) | 2ba6006 | 762de45 | keine | 0 |
| 71 | `claude/security-status` bis 468ce3f | 468ce3f | 0b4d80a | keine | 0 |

- **70:** Die neu gebaute `profiles.json` ist unsigniert. Ohne Schlüssel ist das so erwartet.
- **71:** `GameShortcut.key` arbeitet jetzt unter einer Sperre.
  - Offen bleibt die Lücke aus der zwölften Runde: Die temporäre Datei `shortcut-key.<UUID>.tmp` nennt die Regel der
    Sandbox nicht.
  - Seit 62 ist sie innen nur lesbar, nicht unlesbar.

## Tests der vierzehnten Runde (auf 0b4d80a)

- **`tests/ProcessListLive/run.sh`:** grün.
- **Voller Lauf `scripts/run-tests.sh -P 2`:** alle 60 Reihen grün (1202 s), `MacVersionTest` auch (62 s).
- **pytest:** 147 von 147. compat-db sah pytest einmal unter Last scheitern. Hier fiel kein Test aus.
- **Test-Plists:** In `~/Library/Preferences` änderte sich während des Laufs keine.

## Für die echten Merges

- Für Profile gilt vorerst die Anleitung von tested-on-mac (33). profile-guides Fassung bräuchte zuerst die Rücknahme
  von 5720a1d.
- `SubprocessTest` ist auf h1-h3 behoben (a097ccb, Merge 36).
- `PadFocusTest` braucht seit 88f0cb8 (Merge 39) keinen eingeschalteten Bildschirm mehr.
- Profil-CI: die strengeren Regeln der App übernehmen (15 Verben, Grenzen für `frameLimit`, `vulkanSamplers`, Overrides), siehe die zwölfte Runde.
- Sandbox: die temporäre Datei des Schlüssels (`shortcut-key.<UUID>.tmp`) mit sperren, siehe die zwölfte Runde.
- Vor dem Tag v0.3.1: den Entwurf aus `docs/RELEASE-NOTES-0.3.1.md` nach `docs/release-notes/v0.3.1.md` (43).
- `MacVersionTest`: die 20 s für das Zurückholen nach dem Beenden sind unter Last knapp (Nachtrag zur neunten Runde).
- Nur auf Staging stehen:
  - 8b5314d. engine-env hat dasselbe jetzt als 4e02fbf.
  - 49e249d, M4s „Steam ist aus“ über M3. Gehört in den M4-Zweig, sobald der M3 hat.
  - 897b94a, `WineSandboxTest` kennt `Subprocess.run`. Sollten die Sandbox- und die h1-h3-Seite übernehmen.
  - 7374066, `WineSandboxTest` legte seine Suite im Arbeitsordner an. Seit 77e0bba (49) überholt.
  - 2a7b285, `WineSandboxTest` bindet die geschützten Dateien an `SteamProgram.record` und `GameShortcut.key`.
    Gehört in `claude/wine-sandbox`, sobald der Zweig beides hat, sonst bleibt es auf Staging.
  - 78205cf, der Schalter des Play!-Helfers im Spieletest heißt `UnityDialog.switchKey`. Erst sinnvoll, wenn
    unity-play und game-test-fixes zusammenkommen.
  - 5dd6d71, Unitys Play!-Helfer startet über `WineSandbox.process`. Für `claude/unity-play`.
  - fbeab53 ist ein Merge, aber mit eigener Lösung: Was davon in `claude/quirky-clarke-81fd65` gehört, steht im
    Merge-Commit und oben im Nachtrag.
- Der Stand je Befund steht jetzt in `docs/AUDIT-SICHERHEIT.md` (Merge 16).
- Mit N1 (audit-low) startet ein `nightforge://play`-Link nur noch mit dem Schlüssel der eigenen Spiel-Apps. Eigene
  Kurzbefehle des Nutzers mit solchen Links zeigen danach die Spielseite (für den Nutzer in `docs/TODO.md`).
- Die vor Merge 1 liegengebliebenen Test-Plists räumt der Nutzer auf (Liste in `docs/TODO.md`, Wartung und
  Community). Dazu kommen die aus Läufen anderer Zweige ohne `TestDefaults`, etwa der Reihe auf `claude/game-test-fixes`.
