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

## Offen in der achten Runde: KosmicKrisp DirectX 9 (`claude/quirky-clarke-81fd65` bis 763efd2)

- Die Lösung in `kosmickrisp-staging-merge.diff` stammt von 02:36, aus der Zeit vor engine-envs 4aaf428. Heute gibt
  es fünf Konfliktstellen statt drei.
- Drei sind klar und in einem eigenen Worktree schon gelöst:
  - Mesas Shader-Ordner neben engine-envs Registry-Aufräumen. KosmicKrisp hat `applyGameEnvironment` selbst nicht
    geändert, 5c8edd0 hat es entfernt.
  - `preparePrefix` ohne `applyGameEnvironment`, mit `d3d9From`.
  - `ensureEngine` und `useHeld` wie in der Notiz.
- **Unklar ist der Parameter `vulkan:` von `prepareLaunchEnvironment`.**
  - engine-env (4aaf428) hat einen eigenen Weg für Direct3D 9 auf DXVK unter winecx: Gcenx' Khronos-Loader, MoltenVK
    und Nightforges Layer, hinter dem Schalter `vulkanLoader` (aus), mit `vulkan: [String: String]`.
  - KosmicKrisp hat `vulkan: VulkanDriver?`. Beide setzen `CX_ACTIVE_GRAPHICS_BACKEND=wined3d`, `CX_LIBVULKAN` und
    `VK_DRIVER_FILES`.
  - engine-env schreibt die Loader-Variablen bei jedem Start, ohne Loader leer, also weg. KosmicKrisps `nil` lässt
    dagegen Steams Treiber stehen, damit ein Wechsel zwischen Mafia II und einem DXMT-Spiel keinen Neustart von Steam
    kostet.
  - Welcher Weg bei beiden Schaltern gilt, ist eine Entscheidung. Gefragt ist die KosmicKrisp-Sitzung (09:21), mit
    einem Vorschlag: KosmicKrisp nur bei `kosmicKrispReady`, sonst der Loader. Eine Antwort steht noch aus.

## Für die echten Merges

- Für Profile gilt vorerst die Anleitung von tested-on-mac (33). profile-guides Fassung bräuchte zuerst die Rücknahme
  von 5720a1d.
- `SubprocessTest` ist auf h1-h3 behoben (a097ccb, Merge 36).
- `PadFocusTest` braucht seit 88f0cb8 (Merge 39) keinen eingeschalteten Bildschirm mehr.
- Vor dem Tag v0.3.1: den Entwurf aus `docs/RELEASE-NOTES-0.3.1.md` nach `docs/release-notes/v0.3.1.md` (43).
- Nur auf Staging stehen:
  - 8b5314d. engine-env hat dasselbe jetzt als 4e02fbf.
  - 49e249d, M4s „Steam ist aus“ über M3. Gehört in den M4-Zweig, sobald der M3 hat.
  - 897b94a, `WineSandboxTest` kennt `Subprocess.run`. Sollten die Sandbox- und die h1-h3-Seite übernehmen.
  - 7374066, `WineSandboxTest` legt seine Suite im Arbeitsordner an. Für `claude/wine-sandbox`.
  - 78205cf, der Schalter des Play!-Helfers im Spieletest heißt `UnityDialog.switchKey`. Erst sinnvoll, wenn
    unity-play und game-test-fixes zusammenkommen.
  - 5dd6d71, Unitys Play!-Helfer startet über `WineSandbox.process`. Für `claude/unity-play`.
- Der Stand je Befund steht jetzt in `docs/AUDIT-SICHERHEIT.md` (Merge 16).
- Mit N1 (audit-low) startet ein `nightforge://play`-Link nur noch mit dem Schlüssel der eigenen Spiel-Apps. Eigene
  Kurzbefehle des Nutzers mit solchen Links zeigen danach die Spielseite (für den Nutzer in `docs/TODO.md`).
- Die vor Merge 1 liegengebliebenen Test-Plists räumt der Nutzer auf (Liste in `docs/TODO.md`, Wartung und
  Community). Dazu kommen die aus Läufen anderer Zweige ohne `TestDefaults`, etwa der Reihe auf `claude/game-test-fixes`.
