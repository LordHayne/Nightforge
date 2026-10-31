# Testabdeckung

Stand 31.10.2026. Gemessen auf `claude/ux-roadmap-next` 159acfa (GOG gemergt), dem Stand, auf dem dieser Zweig
aufsetzt. Zum Vergleich steht auch 001a3e0 da, der Stand vor dem GOG-Merge. Die Prozentzahlen sind Zeilenabdeckung
laut `llvm-cov`.

## Messen

```bash
scripts/coverage.sh
```

Das Skript lässt jede Testreihe `tests/*Test` laufen, vier gleichzeitig, wie im Gesamtlauf. Mit `--html` schreibt
es zusätzlich jede Datei annotiert als Seite, mit `--files` als Text. Dort findet
`grep -E '^ *[0-9]+\| *0\|' build/coverage/files/Datei.swift.txt` die Zeilen, die kein Test ausführt. Nennt man
Reihen (`scripts/coverage.sh VDFTest EpicTest`), laufen nur diese. Ein Lauf über alle dauert etwa 6 Minuten. Die
Tabelle landet in `build/coverage/report.txt`, die Ausgaben jeder Reihe in `build/coverage/logs/`.

So funktioniert es: Ein `swiftc` vorn im `PATH` fügt `-profile-generate -profile-coverage-mapping` hinzu und hebt
jede Testbinary auf (manche `run.sh` löschen ihre am Ende). Jede Reihe schreibt ihre Profile unter eigenem Namen.
`llvm-profdata merge` und `llvm-cov report` über alle Binaries rechnen dann jede Datei unter `Sources/Nightforge/`
zusammen. Beide Werkzeuge kommen per `xcrun` aus den Command Line Tools; Xcode braucht es nicht. Die `run.sh` der
Tests bleiben, wie sie sind.

## Ergebnis

Die Logik, die für den Nutzer entscheidet (die 13 Dateien unten), ist von **72,1 % auf 80,1 %** der Zeilen
gestiegen. Was dort noch fehlt, sind SwiftUI-Ansichten, Netzwerk, echte Steam- und legendary-Prozesse sowie die echten
Dateien des Nutzers; die Liste unter der Tabelle nennt es pro Datei. Über die ganze App stieg die Abdeckung nur von 27,8 % auf
28,7 %, weil die großen Ansichten und `LibraryModel` die Summe bestimmen.

| Datei | Zeilen | 001a3e0 | vorher (159acfa) | nachher | Δ |
|---|---|---|---|---|---|
| `Compatibility.swift` | 150 | 64,0 % | 64,0 % | 81,3 % | +17,3 |
| `LibraryFilters.swift` | 85 | 83,5 % | 83,5 % | 100,0 % | +16,5 |
| `GameID.swift` | 54 | 84,8 % | 98,1 % | 100,0 % | +1,9 |
| `VDF.swift` | 169 | 94,1 % | 94,1 % | 100,0 % | +5,9 |
| `Library.swift` | 643 | 83,1 % | 83,4 % | 96,9 % | +13,5 |
| `StoreFacts.swift` | 139 | 84,2 % | 84,2 % | 84,2 % |  |
| `SteamSwitch.swift` | 189 | 52,4 % | 52,4 % | 52,4 % |  |
| `Legendary.swift` | 378 | 57,7 % | 74,3 % | 82,5 % | +8,2 |
| `EpicStore.swift` | 902 | 50,9 % | 50,9 % | 51,6 % | +0,7 |
| `EngineRollback.swift` | 272 | 95,6 % | 95,6 % | 95,6 % |  |
| `FramePacing.swift` | 105 | 76,0 % | 77,1 % | 91,4 % | +14,3 |
| `Profiles.swift` | 166 | 63,3 % | 63,3 % | 92,2 % | +28,9 |
| `GameAnalysis.swift` | 265 | 82,3 % | 82,3 % | 99,2 % | +17,0 |

Was in diesen Dateien bewusst ungetestet bleibt:

- `Compatibility`: nur noch `CompatibilityBadge` (SwiftUI). Die Bewertung selbst ist vollständig abgedeckt.
- `StoreFacts`: `Metascores.score(for:)` fragt den Steam-Store im Netz, dazu gehört der Zwischenspeicher in den
  Standard-Defaults. Die Namenstabellen sind jetzt ganz geprüft (Regionen 26 % → 89 %).
- `SteamSwitch`: `makeWayForMac`, `makeWayForWindows`, `afterMacGame` und `stopWindowsForMacDownload` stoppen und
  starten die echten Steams (`Engine.stopSteam`, `MacSteam.quit`) und lesen `Engine.isSteamRunning`. Ein Test
  könnte die Steam des Nutzers beenden. Testbar würden sie, wenn diese Aufrufe als Closures hereinkämen, wie
  `restartWindows` es schon tut. Die Regeln (`switchesBackAfterMac` usw.) sind vollständig abgedeckt.
- `EpicStore` und `Legendary`: Anmelden, Download, Update, Deinstallieren und Spielstände laufen über die echte
  legendary-Binary (`ComponentStore.install` lädt sie notfalls aus dem Netz). Das Einlesen (Liste, installed.json,
  assets.json, Größen, Fortschritt, Startbefehl, gepackte App) ist abgedeckt. Als Nächstes böte sich ein
  Stand-in-legendary als Shell-Skript im Test-Home an, wie es der PackedApp-Test schon macht.
- `Library`: `defaultBottlesRoot` (der echte CrossOver-Ordner), die Standardwerte von `merge` (echte Defaults) und der
  Download-Anteil aus `MacSteamProgress` in `scanMac`.
- `FramePacing.learn` liest Nightforges echtes wine.log. Seine Bausteine (`rates`, `next`) sind getestet.
- `ProfileStore.refresh` lädt die Liste aus dem Netz. Ohne App-Bundle gibt es keine Adresse, also bleibt es aus.
- `EngineRollback` lag schon bei 95,6 %. Es fehlen `heldEngineFolders()` und der Abbruch, wenn das Kopieren
  scheitert.

## Was dazukam

Neue Testreihen. Beide übersetzen nur ihre eine Quelldatei und laufen damit in etwa einer Sekunde:

- `tests/VDFTest`: Groß- und Kleinschreibung, Escapes, Kommentare, `[$OSX]`-Bedingungen, abgeschnittene und kaputte
  Dateien, `libraryfolders.vdf`, das unverändert zurückgeschrieben und geändert wieder gelesen wird.
- `tests/GameAnalysisTest`: Spielordner aus kleinen Windows-Programmen, die der Test selbst schreibt (PE32 und PE32+,
  Imports und Delay-Loads, auch die Adressen alter Linker). Geprüft werden Direct3D 7 bis 12, Vulkan, OpenGL, Unity,
  Unreal und Source. Dazu die großen Engine-Bibliotheken ohne Upscaler und SDKs, das Programm hinter einem Launcher,
  Anti-Cheat, .NET, WebView2 und fremde Launcher. Außerdem, was draußen bleibt: Installer, Crash-Reporter und
  Dateien, die zu tief liegen.

Erweiterte Reihen. Jede davon hat ihre Übersetzung ohnehin, die neuen Prüfungen kosten Millisekunden:

- `UpdateStateTest`: `LibraryScanner` liest eine ausgedachte Flasche. Darin liegen Manifeste in allen Zuständen
  (installiert, lädt, entpackt, Platte voll, Update wartet) sowie Redistributables, Runtimes, Proton und kaputte
  Manifeste, die draußen bleiben. Weitere Bibliotheken kommen über Laufwerksbuchstaben, das alte Format und
  Mac-Pfade dazu. Geprüft werden außerdem eine zweite Steam, zwei Konten mit Spielzeiten, die Reihenfolge,
  `updateState(of:)`, Windows-Pfade, abgesteckte Laufwerke und welcher Anti-Cheat welche Version stoppt.
- `CompatibilityTest`: das eigene Urteil des Spielers, jede Art von Fix, `fromNightforge`, Chip-Namen und
  `Compatibility.of`.
- `StoreFactsTest`: alle Genre- und Tag-Namen, jeder kommt nur einmal vor.
- `LibraryFiltersTest`: was eingrenzt, die Beschriftungen, ein Spiel aus zwei Stores, Gleichstand und Zahlen in Namen.
- `ProfileFilesTest`: `ProfileStore` mit seiner Liste in Application Support. Die Reihe bekommt dafür ein eigenes
  `HOME` und `CFFIXED_USER_HOME` und verweigert die Arbeit, wenn das nicht greift. Dazu kommen seltsame Einträge,
  eine zu neue oder kaputte Liste und GeForce-Now-Links.
- `GraphicsPresetTest`: Das gelernte Bildlimit gilt beim nächsten Start, ein anderer Bildschirm fängt neu an, und
  `recordStart` wird geprüft.
- `GameIDTest`: GOG-Schlüssel, was eine ID enthalten darf, Store-Namen und Abzeichen.
- `EpicTest`: die Umgebung, in der legendary läuft, seine Fehlerzeilen, `EpicError`, installierte Spiele außerhalb
  der Liste und Spiele auf abgesteckten Laufwerken.

Am Produktionscode hat sich nichts geändert.

Laufzeit des Gesamtlaufs (`ls -d tests/*Test | xargs -P 4 …`), direkt nacheinander gemessen:
**159acfa 453 s mit 41 Reihen, dieser Zweig 439 s mit 43 Reihen**, alle grün. Der Unterschied liegt im Rauschen.

Alle Tests arbeiten in eigenen temporären Ordnern mit UUID und brauchen kein Netz. Sie lesen keine echte Steam und
nicht den Prefix des Nutzers. Wo Code UserDefaults braucht, nehmen sie eine Spiel-ID, die kein Store vergibt, und
entfernen den Schlüssel wieder. Die Reihen, die ich angefasst habe, laufen auch auf dem Stand mit dem gemergten
TV-Zweig grün (`claude/tv-fullscreen-61ab1e`). Dieser Zweig lässt sich ohne Konflikte mit dem TV- und dem
Spieldaten-Zweig mergen.

## Verbleibende Lücken, nach Risiko

1. **`LibraryModel.swift`**: 3431 Zeilen, 0 %. Hier steckt viel Entscheidungslogik, etwa wer gerade herunterladen
   darf (`takeTurnsDownloading`), ob die andere Steam frei ist (`otherSteamFree`) und der Startablauf. Alles hängt
   an einem `ObservableObject` mit echten Steams. Der TV-Zweig ändert die Datei. Danach sollten die Entscheidungen
   als statische Funktionen über `Facts`-Structs herausgezogen werden, wie bei `SteamSwitch`.
2. **Abläufe, die echte Prozesse anfassen**: `SteamSwitch` (52 %), `Engine` (45 %), `Launcher` (44 %), `MacSteam`
   (27 %), `MacSteamPrep` (18 %), `Setup` (17 %), `Downloads` (1 %, Wachhalten und Download-Ansicht) und
   `DriveMoves` (0 %, Spiele auf andere Laufwerke verschieben). Sicher testen lassen sie sich nur, wenn die Aktionen als
   Closures hereinkommen oder Stand-in-Programme im Test-Home laufen.
3. **Store-Abläufe**: `EpicStore` (52 %), `GOGStore` (52 %), `GOGDL` (70 %). Ein Stand-in für legendary und gogdl
   wäre der Weg.
4. **`InputRouter`** (1 %): die Navigation mit Tastatur, Trackpad und Controller. Ein Teil der Logik steckt schon in
   `PadFocus` und `Navigation`, die beide getestet sind.
5. **Dateien des TV-Zweigs**: `GameDisplay` (8 %), `GameAudio`, `GameResolution`. Ihre Tests kommen mit dem Zweig;
   nach dem Merge neu messen.
6. **SwiftUI-Ansichten** (`LibraryView`, `SettingsView`, `SettingsViews`, `SetupView`, `Glass`, `HomeStage`,
   `ControllerTest`, `PadDrawing`, `DriveViews`, `SetupTips`, `ThisGameCard`, `Toast`, `MacSteamSetup`, große
   Teile von `LibraryGrid`): 0 bis 6 %. Bewusst ungetestet; Tests lohnen erst, wenn sich Logik herausziehen lässt.

## Beobachtungen nebenbei

- **HOME und CFFIXED_USER_HOME schützen UserDefaults nicht.** `cfprefsd` schreibt Suites und die Standard-Domain
  einer Testbinary trotzdem in das `~/Library/Preferences` des echten Nutzers. Das zeigt sich etwa an
  `nightforge.engine-rollback-test-<UUID>.plist`, das frisch entsteht, obwohl `EngineRollbackTest` HOME umlenkt.
  Dort liegen etwa 525 Reste alter Läufe: 215× `mvt-<UUID>`, 198× `ProfileFilesTest-<UUID>`,
  112× `nightforge.engine-rollback-test-<UUID>`, dazu `store-facts-test.plist` und andere mit dem Namen einer
  Testbinary. Das sind keine Nightforge-Daten, sie liegen aber im echten Home. Abhilfe wäre, dass die Tests ihre
  Suite am Ende entfernen (`removePersistentDomain` und die Datei löschen) oder Speicher übergeben bekommen.
  Meine neuen Prüfungen legen dort nichts an.
- **HOME allein lenkt den FileManager nicht um**: `Application Support` bleibt im echten Home. Erst mit
  `CFFIXED_USER_HOME` landet `Engine.supportDir` im Test-Home. Geprüft habe ich das mit einer kleinen Binary.
- **`LibraryScanner.libraryFolders`** liefert die zusätzlichen Bibliotheken in Dictionary-Reihenfolge, also bei
  jedem Lauf anders. Liegt ein Spiel in zwei zusätzlichen Bibliotheken, gewinnt zufällig eine der Kopien. Steams
  eigene Bibliothek kommt immer zuerst; der Test prüft deshalb die Menge und nicht die Reihenfolge.

## Alle Dateien

| Datei | Zeilen | 001a3e0 | vorher (159acfa) | nachher | Δ |
|---|---|---|---|---|---|
| `Accessibility.swift` | 31 | 0,0 % | 0,0 % | 0,0 % |  |
| `Artwork.swift` | 211 | 6,6 % | 6,6 % | 6,6 % |  |
| `CloudSaves.swift` | 30 | 90,0 % | 90,0 % | 90,0 % |  |
| `CompleteRemoval.swift` | 115 | 87,9 % | 88,7 % | 88,7 % |  |
| `Components.swift` | 306 | 55,6 % | 55,6 % | 56,2 % | +0,7 |
| `ControllerCompatibility.swift` | 112 | 95,5 % | 95,5 % | 95,5 % |  |
| `ControllerTest.swift` | 368 | 0,0 % | 0,0 % | 0,0 % |  |
| `Demos.swift` | 92 | 0,0 % | 0,0 % | 0,0 % |  |
| `Detached.swift` | 240 | 90,8 % | 90,8 % | 90,8 % |  |
| `DockHider.swift` | 79 | 70,9 % | 70,9 % | 70,9 % |  |
| `DownloadRate.swift` | 37 | 97,3 % | 97,3 % | 97,3 % |  |
| `Downloads.swift` | 468 | 0,0 % | 1,1 % | 1,1 % |  |
| `DriveMoves.swift` | 408 | 0,0 % | 0,0 % | 0,0 % |  |
| `DriveViews.swift` | 360 | 3,1 % | 3,1 % | 3,1 % |  |
| `DuplicateGames.swift` | 135 | 95,5 % | 95,6 % | 95,6 % |  |
| `Engine.swift` | 1806 | 45,5 % | 45,2 % | 45,3 % | +0,1 |
| `EpicSignIn.swift` | 80 | 20,0 % | 20,0 % | 20,0 % |  |
| `ExternalDrives.swift` | 309 | 74,7 % | 74,8 % | 74,8 % |  |
| `FlowRow.swift` | 57 | 28,1 % | 28,1 % | 28,1 % |  |
| `GameDisplay.swift` | 178 | 7,9 % | 7,9 % | 7,9 % |  |
| `GameLog.swift` | 166 | 82,1 % | 82,5 % | 82,5 % |  |
| `GameMarks.swift` | 11 | 100,0 % | 100,0 % | 100,0 % |  |
| `GameMove.swift` | 326 | 96,0 % | 96,0 % | 96,0 % |  |
| `GameShortcut.swift` | 74 | 95,9 % | 95,9 % | 95,9 % |  |
| `Glass.swift` | 472 | 0,0 % | 0,0 % | 0,0 % |  |
| `GOGDL.swift` | 198 | – | 69,7 % | 69,7 % |  |
| `GOGLibrary.swift` | 368 | – | 92,4 % | 92,4 % |  |
| `GOGRedist.swift` | 328 | – | 79,3 % | 79,3 % |  |
| `GOGSignIn.swift` | 82 | – | 28,0 % | 28,0 % |  |
| `GOGStore.swift` | 785 | – | 52,4 % | 52,4 % |  |
| `HomeStage.swift` | 405 | 0,0 % | 0,0 % | 0,0 % |  |
| `InputRouter.swift` | 813 | 1,4 % | 1,4 % | 1,4 % |  |
| `Launcher.swift` | 427 | 44,2 % | 49,4 % | 49,4 % |  |
| `LaunchHealth.swift` | 256 | 91,5 % | 93,0 % | 93,4 % | +0,4 |
| `LaunchPhase.swift` | 67 | 56,1 % | 52,2 % | 52,2 % |  |
| `LibraryGrid.swift` | 1008 | 5,9 % | 5,9 % | 5,9 % |  |
| `LibraryModel.swift` | 3431 | 0,0 % | 0,0 % | 0,0 % |  |
| `LibraryReveal.swift` | 296 | 20,6 % | 20,6 % | 20,6 % |  |
| `LibraryView.swift` | 4430 | 0,0 % | 0,0 % | 0,0 % |  |
| `MacIntegration.swift` | 101 | 7,9 % | 7,9 % | 7,9 % |  |
| `MacSteam.swift` | 408 | 26,7 % | 26,7 % | 26,7 % |  |
| `MacSteamPrep.swift` | 207 | 18,4 % | 18,4 % | 18,4 % |  |
| `MacSteamProgress.swift` | 107 | 56,1 % | 56,1 % | 56,1 % |  |
| `MacSteamSetup.swift` | 211 | 0,0 % | 0,0 % | 0,0 % |  |
| `MacSteamTestHome.swift` | 131 | 72,5 % | 72,5 % | 72,5 % |  |
| `MacVersion.swift` | 32 | 96,9 % | 96,9 % | 96,9 % |  |
| `MetaLine.swift` | 67 | 0,0 % | 0,0 % | 0,0 % |  |
| `Migration.swift` | 91 | 46,2 % | 46,2 % | 46,2 % |  |
| `Navigation.swift` | 97 | 100,0 % | 100,0 % | 100,0 % |  |
| `OfflineReadiness.swift` | 42 | 44,7 % | 45,2 % | 45,2 % |  |
| `PadDrawing.swift` | 360 | 0,0 % | 0,0 % | 0,0 % |  |
| `PadFocus.swift` | 160 | 55,6 % | 55,6 % | 55,6 % |  |
| `PowerSource.swift` | 89 | 52,8 % | 52,8 % | 52,8 % |  |
| `ProblemReport.swift` | 71 | 0,0 % | 0,0 % | 0,0 % |  |
| `ProfileOrigin.swift` | 36 | 0,0 % | 0,0 % | 0,0 % |  |
| `SaveTransfer.swift` | 186 | 97,8 % | 97,8 % | 97,8 % |  |
| `Search.swift` | 34 | 100,0 % | 100,0 % | 100,0 % |  |
| `SessionSummary.swift` | 463 | 1,6 % | 2,4 % | 4,5 % | +2,2 |
| `SettingsView.swift` | 2288 | 0,0 % | 0,0 % | 0,0 % |  |
| `SettingsViews.swift` | 758 | 0,0 % | 0,0 % | 0,0 % |  |
| `Setup.swift` | 668 | 16,8 % | 16,8 % | 16,8 % |  |
| `SetupDetail.swift` | 148 | 98,0 % | 98,0 % | 98,0 % |  |
| `SetupTips.swift` | 332 | 0,0 % | 0,0 % | 0,0 % |  |
| `SetupView.swift` | 613 | 0,0 % | 0,0 % | 0,0 % |  |
| `ShaderCaches.swift` | 43 | 95,3 % | 95,3 % | 95,3 % |  |
| `SpaceCheck.swift` | 45 | 95,6 % | 95,6 % | 95,6 % |  |
| `StarterPicks.swift` | 58 | 98,2 % | 98,3 % | 98,3 % |  |
| `SteamBootstrap.swift` | 259 | 94,2 % | 94,2 % | 94,2 % |  |
| `SteamCatalog.swift` | 633 | 83,9 % | 83,9 % | 85,3 % | +1,4 |
| `SteamGuideButton.swift` | 57 | 100,0 % | 100,0 % | 100,0 % |  |
| `SteamPackages.swift` | 189 | 46,0 % | 46,0 % | 46,0 % |  |
| `SteamPriority.swift` | 44 | 0,0 % | 0,0 % | 0,0 % |  |
| `SteamWindow.swift` | 36 | 36,1 % | 36,1 % | 36,1 % |  |
| `Stores.swift` | 78 | 9,0 % | 9,0 % | 9,0 % |  |
| `StoreSearch.swift` | 122 | 0,0 % | 0,0 % | 0,0 % |  |
| `StoreSyncBanner.swift` | 109 | 11,8 % | 11,9 % | 11,9 % |  |
| `Strings.swift` | 32 | 62,5 % | 62,5 % | 62,5 % |  |
| `Theme.swift` | 54 | 17,3 % | 20,4 % | 20,4 % |  |
| `ThisGameCard.swift` | 210 | 0,0 % | 0,0 % | 0,0 % |  |
| `Toast.swift` | 155 | 0,0 % | 0,0 % | 0,0 % |  |
| `Trackpad.swift` | 172 | 50,6 % | 50,6 % | 50,6 % |  |
| `Updater.swift` | 99 | 0,0 % | 0,0 % | 0,0 % |  |
| **Gesamt** | 32977 | 25,3 % | 27,8 % | 28,7 % | +0,9 |
