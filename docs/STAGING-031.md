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

## Nicht in dieser Runde

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

## Für die echten Merges

- Noch in Arbeit und später nachzuziehen: `claude/game-test-fixes` und compat-db M3/N7 (`claude/report-url-m3`).
- Die zwei Anleitungen für Profile: nur eine sollte gelten (siehe oben).
- Nur auf Staging stehen:
  - 8b5314d. engine-env hat dasselbe jetzt als 4e02fbf.
  - 49e249d, M4s „Steam ist aus“ über M3. Gehört in den M4-Zweig, sobald der M3 hat.
  - 897b94a, `WineSandboxTest` kennt `Subprocess.run`. Sollten die Sandbox- und die h1-h3-Seite übernehmen.
  - 7374066, `WineSandboxTest` legt seine Suite im Arbeitsordner an. Für `claude/wine-sandbox`.
- Der Stand je Befund steht jetzt in `docs/AUDIT-SICHERHEIT.md` (Merge 16).
- Mit N1 (audit-low) startet ein `nightforge://play`-Link nur noch mit dem Schlüssel der eigenen Spiel-Apps. Eigene
  Kurzbefehle des Nutzers mit solchen Links zeigen danach die Spielseite (für den Nutzer in `docs/TODO.md`).
- Die vor Merge 1 liegengebliebenen Test-Plists räumt der Nutzer auf (Liste in `docs/TODO.md`, Wartung und
  Community). Dazu kommen die aus Läufen anderer Zweige ohne `TestDefaults`, etwa der Reihe auf `claude/game-test-fixes`.
