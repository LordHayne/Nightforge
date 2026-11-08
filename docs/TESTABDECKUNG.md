# Testabdeckung

Stand 31.10.2026. Gemessen auf `claude/ux-roadmap-next` 159acfa (GOG gemergt), dem Stand, auf dem dieser Zweig
aufsetzt. Zum Vergleich steht auch 001a3e0 da, der Stand vor dem GOG-Merge. Die Prozentzahlen sind Zeilenabdeckung
laut `llvm-cov`.

## Stand 8.11.2026, dritte Runde (0.3.3, auf `claude/staging-033` 365f393)

| | vorher | nachher |
|---|---|---|
| Zeilen | 34,47 % | 36,72 % |
| Funktionen | 46,49 % | 49,97 % |
| Regionen | 43,70 % | 46,99 % |

Gemessen wie in der zweiten Runde: 23 betroffene Reihen, zusammengeführt mit den älteren Profilen. Funktionen, die sich
seither geändert haben, verlieren die alten Zähler, die absoluten Zahlen liegen also eher zu niedrig. Zwei kleine
Testfälle kamen nach der Messung dazu.

Neu abgedeckt: `PadKeyboard` 100 %, `TouchpadPointer` 99 %, `HomeSources` 99 %, `Navigation` 99 %, `ControllerNotices` 97 %,
`CurtainEscape` 93 %, `BattleNetStart` 76 %, `PlayerSlots` 63 %, `SteamOnDemand` 42 %, `D3DMetalFlow` 0,4 → 15 %.

### Gefundene Fehler, alle behoben

| Commit | Fehler | Ursprungszweig |
|---|---|---|
| 12c6c39 | Steam schläft, ein Mac-Spiel startet ohne Nightforge im Vordergrund (Dock-Menü, Link): Das Nach-vorn-Kommen verbrauchte das Aufwecken, der Start wurde wegen des Mac-Spiels verweigert, und niemand holte das Windows-Steam zurück. Das nächste Windows-Spiel wartete dann 45 s aufs Anmelden | `claude/steam-on-demand-033` (fff859f) |
| ac054bc | Battle.net: Das Log wurde erst nach dem Senden des Befehls mitgelesen, die Antwort des Clients ging verloren; ein angenommener Start wurde bei 12 s erneut gesendet, bei 30 s kam sein Fenster nach vorn | `claude/battlenet-start-033` (d900dc5) |
| 61df63e | Vorhang: Die neue Geschwindigkeitszeile stürzte bei einem Wert „unendlich“ aus einem beschädigten legendary- oder gogdl-Log ab | `claude/ruhiger-ladescreen-033` (cb2223c) |

Die Regeln selbst hielten: Touchpad-Zeiger, Pad-Tastatur, Spielernummern, Controller-Meldungen, Ausweg aus dem Vorhang
und Steam nur bei Bedarf liefen über 12 Durchgänge mit Zufallseingaben fehlerfrei. Epic- und GOG-Updates beenden beim
Abbruch wirklich ihren Prozess; ihr Log beginnt bei jedem Start neu.

### Neue Reihen

`PadAndCurtainFuzzTest` (alle Regeln oben unter Zufall, dazu Battle.nets Log und die Zahlen des Vorhangs). `ModelFlowsTest`
kann jetzt auch die Reihenfolge der Pins und die D3DMetal-Frage, `ModelNavigationTest` auch die Quellen der Startseite.

Gegenprobe in einer Kopie: Alle 11 eingebauten Fehler wurden am Ende erkannt. Zwei überlebten zuerst (Tastatur-Limit,
Reihenfolge der Pins, weil der Zufall sie selten traf) und haben deshalb je einen festen Testfall bekommen.

### Beobachtet, nicht geändert

- Beim kurzen Bluetooth-Aussetzer kommt „Controller getrennt“, aber keine Meldung, dass er wieder da ist
  (`ControllerNoticesTest` will das so). Ob die Meldung die 4 s abwarten soll, ist eine Entscheidung.
- `nightforge://show/…` und der Klick auf eine Mitteilung wählen das Spiel nur aus. Der Kommentar in `GameShortcut` spricht
  von der Spielseite.
- Der Stopp von „Steam schläft“ prüft nach dem Einreihen nicht erneut, ob inzwischen ein Start läuft. Das Fenster ist
  Millisekunden groß.
- Laufende Updates installierter Spiele zählen für „Steam schläft“ nicht als Download; Steam macht beim Aufwachen weiter.

Weiter ungetestet: die echten Startabläufe (`launch`, `watchCurtain`, `start`, `launchMac`), `InputRouter`, `SettingsView`,
`GameBackdrop`.

## Stand 8.11.2026, zweite Runde (nach 0.3.2)

Neu ist eine Testumgebung für das echte `LibraryModel` ([tests/Shared/ModelWorld.swift](../tests/Shared/ModelWorld.swift)):
erfundenes Home mit Steam-Ordnern und GOG-Bibliothek, kein Fenster, kein Netz. Bricht ab, wenn es das echte Home wäre.
Nie von dort aus: `launch`, `startInput`, eine Store-Anmeldung, irgendetwas mit Steam für Mac; das Modell ginge sonst an
die echten Prozesse dieses Macs.

| | vorher | nachher |
|---|---|---|
| Zeilen | 32,36 % | 35,98 % |
| Funktionen | 43,57 % | 48,76 % |
| Regionen | 42,00 % | 46,19 % |

Gemessen wurden nur die fünf betroffenen Reihen, ihre Profile sind mit denen des Laufs von 6698647 zusammengeführt,
beide gegen die heutigen Quellen. Funktionen, die sich seit jenem Lauf geändert haben, verlieren dabei die alten
Zähler. Deshalb liegt „vorher“ unter den 33,52 %, die der volle Lauf auf dem Release ergab. Der Zuwachs ist das
Verlässliche: 3,6 Punkte Zeilen, 5,2 Punkte Funktionen.

Am meisten bewegt: `LibraryModel` 2,0 → 23,9 %, `DriveMoves` 0 → 22,1 %, `Updater` 56,1 → 88,3 %, `SteamSwitch`
48,9 → 63,0 %, `Launchers` 32,3 → 53,4 %, `GameInfoStore` 19,6 → 56,4 %, `Stores` 10,7 → 52,4 %.

### Gefundene Fehler, alle behoben

| Commit | Fehler | Trifft Spieler? |
|---|---|---|
| 7205e95 | `takeTurnsDownloading` verglich die Summe aller Mac-Downloads: Ein fertiger Download nahm seinen Anteil mit, der nächste galt bis zum Ende der Sitzung als hängend | ja, mehrere Mac-Downloads nacheinander |
| 7205e95 | Epic- und GOG-Spiele liegen in der eingebauten Flasche und zählten als Downloads des Windows-Steam: Sie hielten den Zug von Steam für Mac auf | ja, Epic/GOG neben einem Mac-Download |
| ac82b01 | „Fortsetzen“ nach Platzmangel fragte `steamapps/common` nach freiem Platz; fehlt der Ordner (erster Download einer Bibliothek), hieß es „– frei“, egal wie viel da war | ja, frische Bibliothek auf einer Platte |
| b2115fa | Beschädigtes Manifest mit riesiger Größe: Absturz bei jedem Download-Druck und in Einstellungen › Speicher (die Grenze lag bei `Int64.max`, Addieren läuft über) | nur mit kaputter Datei |
| 4be9315 | Zahlen in Steams und legendarys Logs jenseits von `Int64`: Absturz beim Blick auf einen Download | nur mit kaputter Datei |
| ceff372 | Ein erfolgreiches Update ließ sein Zip im Temp-Ordner (das `defer` kam wegen des Beendens nie dran; hier lagen zwei Ordner à 6 MB) | ja, klein |
| bac2a4e | `fallBackToWindows` scannte neben einem laufenden Scan vorbei, gegen die Regel „ein Scan zur Zeit“ | selten |
| 2078afe | Epics Anmeldeseite: `}` vor `{` ergab einen ungültigen Bereich und damit einen Absturz | kaum |

Gefunden hat sie das Lesen der Abläufe mit der Frage „was, wenn das nicht stimmt?“. Die 3000 Zufallsschritte über Seiten
und Auswahl liefen dagegen ohne Fehler durch.

### Neue Reihen

`ModelNavigationTest` (3000 Zufallsschritte, Regeln nach jedem Schritt), `ModelFlowsTest` (Downloads, Markierungen und
Undo, ein Spiel aus zwei Stores, Moves, Fragen, abgesteckte Platten, riesige Größen, Deinstallieren, Download Again,
Spielstände vor dem Steam-Wechsel), `UpdaterInstallTest` (Updater gegen ein erfundenes GitHub, Zips mit eigenem
Schlüssel), `BugDownloadTurnsTest` (512 Zustände). Jedes Zip der Updater-Reihe fordert ein macOS, das es nicht gibt:
Auch mit kaputten Prüfungen kann die Reihe weder tauschen noch neu starten.

Gegenprobe in einer Kopie: Jede der 15 eingebauten Änderungen ließ die zuständige Reihe fehlschlagen (Auswahl und Seite
nach einem Scan, Panel, Pin beim Ausblenden, Fortsetzen, zweite Kopie auf abgesteckter Platte, Größengrenze,
Summenvergleich, Epic/GOG, Epics Seite, jede Updater-Prüfung einzeln).

### Was bleibt

Nicht ohne echte Steams testbar sind `launch` (359 Zeilen), `watchCurtain` (322), `start` (147), `launchMac` (113),
`waitForMacStart`, `performMove` und `watchForGameEnd`. Für `watchForGameEnd` wäre der kleinste Schritt ein Werttyp, der
`startedHere`, `playing`, `goneFor` und `sessionStarts` hält und je Blick sagt, was geschehen soll; die Aufrufe von
`GameBackdrop` und `MacSteam` blieben im Modell. `Updater.install` ist bis zum letzten Tor geprüft, der Tausch selbst
nicht.

## Stand 8.11.2026 (0.3.2)

Gemessen auf `claude/staging-032` 6698647. Vorher sind die 66 Reihen von staging, nachher alle 84. Beide Zahlen
kommen aus demselben Lauf, jeweils mit `llvm-cov` über die Profile der einen oder der anderen Menge, sie sind also
direkt vergleichbar. Gemessen mit einer Kopie von `scripts/coverage.sh` mit `-P 2`: das Skript fährt fest vier
Reihen gleichzeitig (Vorschlag unten).

| Gesamt | vorher | nachher |
|---|---|---|
| Zeilen | 33,36 % | **33,49 %** |
| Regionen | 43,28 % | **43,54 %** |
| Funktionen | 45,02 % | **45,19 %** |

Die Gesamtzahl bewegt sich wenig, das ist erwartbar. Die großen Blöcke (`LibraryModel`, `LibraryView`, `InputRouter`,
`SettingsView`, `Setup`) lassen sich ohne Umbau nicht testen, und die neuen Reihen sollten Fehler finden, keine Zeilen
abhaken. Viele prüfen Code, der schon lief, mit schlimmeren Eingaben, oder Regeln, die keine Zeilen messen (Skript,
Übersetzungen, Controller). Gestiegen sind vor allem:

| Datei | Zeilen | vorher | nachher |
|---|---|---|---|
| `LaunchPhase.swift` | 70 | 54,3 % | 90,0 % |
| `ProfileOrigin.swift` | 36 | 0,0 % | 44,4 % |
| `Downloads.swift` | 484 | 1,0 % | 3,7 % |
| `SaveTransfer.swift` | 217 | 96,8 % | 99,1 % |
| `SteamStartCheck.swift` | 51 | 94,1 % | 98,0 % |
| `BattleNetLibrary.swift` | 133 | 98,5 % | 99,3 % |

### Befunde

Alle acht sind auf `claude/staging-032` behoben (d98cb64 und 4990b22); die zugehörigen Reihen waren vorher rot und
sind jetzt grün. Sie bleiben als Regressionstests. Die Zeilen nennen den Stand beim Fund (c475580).

| # | Fehler | Ablauf | Test | trifft 0.3.2 |
|---|---|---|---|---|
| 1 | `Engine.steamShutdownScript` kannte nur die erste Bibliothek jeder Steam (`$STEAMAPPS`, `$MAC_STEAMAPPS`). | Mac-Spiel aus einer Bibliothek auf externer Platte läuft, Nightforge wird beendet: `osascript … quit` für Steam for Mac unter dem laufenden Spiel. Ein Download in eine Bibliothek auf der Platte zählte nicht: Steam endet, der Download stoppt. | `BugQuitExternalLibrariesTest` | ja (nicht neu), mit externer Platte |
| 2 | `GameMenu.swift:85`: Das Schnellmenü bot „Herunterladen“ für ein Spiel auf abgesteckter Platte. | Eintrag tut nichts (`primaryAction` kehrt zurück); `Game.missingDrive` verbietet das sogar. | `BugMenuMissingDriveTest` | ja, neu |
| 3 | `BattleNetLibrary.games`: `progress` aus product.db ungeprüft. | inf oder 1e300 erreicht `Int(fraction * 100)` in `LibraryView.swift:1845` und `Downloads.swift:219`: Absturz. | `BugBattleNetProgressTest` | neu, braucht kaputte Datei |
| 4 | `UpdateState.pending` (`Library.swift:818`): `Int64(Double)` ohne Grenze. | Zahl über Int64 in einem Manifest: Absturz beim Einlesen, bei jedem Start. | `BugManifestNumbersTest` (Exit 133) | alt, braucht kaputte Datei |
| 5 | `Downloads.swift:78`: Schließen-Knopf nur mit `.help`, ohne `accessibilityLabel`. | VoiceOver hat keinen Namen dafür; alle anderen solchen Knöpfe haben beides. | `AccessibilityRulesTest` | ja, klein |
| 6 | `SaveTransfer.takeNewer`: `Set(ours).subtracting(theirs)` vergleicht Namen exakt. | Mac `Save1.dat`, Windows `SAVE1.DAT` auf case-insensitivem APFS: der rename ersetzt die Datei, das Entfernen löscht sie wieder. Der Ordner ist leer. Die Kopie der anderen Version und das Backup bleiben. | `BugSaveNamesTest` | ja, wenn ein Port die Namen anders schreibt |
| 7 | `SaveTransfer.files`: Muster `*` trifft Finders `.DS_Store`. | Ein Ordner mit nur `.DS_Store` gilt als „hat Spielstände“, `carryOver` überträgt nichts. | `BugSaveNamesTest` | selten |
| 8 | `LaunchWatcher.poll`: Offset rückt auch hinter eine halbe Zeile. | Steam schreibt eine Zeile in zwei Teilen: Die Zeile ist verloren, etwa „waiting for user response“. | `BugLaunchWatcherPartialLineTest` | theoretisch |

Nur notiert, nicht als Test: `ProfileStore.decode` nutzt `Dictionary(uniqueKeysWithValues:)` mit `Int(key)`. „570“ und
„0570“ in einer Liste wären ein Absturz, nur über eine signierte Liste erreichbar (Fehler des Maintainers).

### Neue Reihen

In eigenen Reihen, damit der Merge mit den Audits keine Konflikte bringt:

- `QuitDrivesTest` (Spiele auf externen Platten aus allen Stores, Pfade mit Leerzeichen und Umlauten, kaputte
  Manifeste; Helfer `tests/Shared/QuitWorld.swift`)
- `GameMenuMatrixTest` (jede Kombination aus Spielzustand, Anti-Cheat und Menüzustand gegen die Regeln, beide
  Sprachen, Platzierung über viele Fenstergrößen)
- `BattleNetDamageTest` (product.db an jedem Byte abgeschnitten, 6000 Bitfehler mit festem Seed, Dateiarten,
  Pfade, Logs mit Bytes, die kein Text sind)
- `LauncherStatesMatrixTest`, `LaunchEdgeTest`, `StoreCardsEdgeTest`, `SaveTransferEdgeTest` (Hilfe
  `tests/Shared/SaveWorld.swift`), `SmallLogicTest`
- Regeln über alle Quellen, gebaut wie `TextScaleTest` (Skripte `check.py`, Scanner `tests/Shared/swift_views.py`):
  `StringRulesTest` (Platzhalter und Argumente aller `L10n.t`, Deutsch gegen Englisch, keine rohen englischen Texte),
  `ControllerRulesTest` (jede Schaltfläche hat `.padFocus` oder steht mit Begründung in der Liste, keine doppelten
  Pad-Namen), `AccessibilityRulesTest`, `BuildLayoutTest` (`build.sh`, `codesign-app.sh` und `Detached.swift` sagen
  dasselbe über die Helper-App, Release Notes zur Version in `Info.plist`)

### Gegenprobe

In einer Kopie im Scratchpad, die eingebauten Fehler dort sind wieder weg. Alle Reihen schlugen an:

| Eingebauter Fehler | Reihe |
|---|---|
| `grep` im Skript unterscheidet Groß/klein (`\Steam\steam.exe` nicht mehr gefunden) | `QuitDrivesTest` |
| Menü zeigt Play auch während das Spiel läuft | `GameMenuMatrixTest` |
| `..` in Pfaden wird gefolgt | `BattleNetDamageTest` |
| Deutsch: `%ld` durch `%@` ersetzt | `StringRulesTest` (mit diesem Fehler stürzt sogar `LauncherStatesMatrixTest` ab: die Crash-Klasse, die die Regel verhindern soll) |
| `.padFocus` der Download-Liste entfernt | `ControllerRulesTest` |
| Anmeldung läuft: Button statt keiner | `LauncherStatesMatrixTest` |
| Neues, kürzeres Log wird nicht von vorn gelesen | `LaunchEdgeTest` |
| Store-Treffer unsortiert | `StoreCardsEdgeTest` |

Und umgekehrt: Mit den passenden kleinen Fixes in der Kopie wurden `BugMenuMissingDriveTest`, `BugManifestNumbersTest`
und `BugBattleNetProgressTest` grün.

### Lücken und kleinster Umbau

- `LibraryModel.swift` (5374 Zeilen, 2 %): Startablauf, wer gerade laden darf, Neustart, Ende einer Sitzung. Hängt an
  einem `ObservableObject` mit echten Steams. Kleinster Schritt: die Entscheidungen als `static func` über
  `Facts`-Structs herausziehen, wie bei `SteamSwitch`, zuerst `takeTurnsDownloading` und `otherSteamFree`.
- `DriveMoves.swift` (412 Zeilen, 0 %) und `SteamSwitch.swift` (51 %, `makeWayForMac`, `makeWayForWindows`,
  `stopWindowsForMacDownload`): rufen echte Steams. Die Aufrufe als Closures hereinreichen, wie `restartWindows` es tut.
- `InputRouter.swift` (5 %): Controller-Abläufe. Die Regel oben prüft nur, dass jede Schaltfläche erreichbar ist.
- `D3DMetalFlow.swift` (555 Zeilen, 0 %): der Ablauf auf einem frischen Mac ohne D3DMetal; bräuchte seine
  Download- und Installationsschritte als Closures.
- `Setup.swift` (17 %), `MacSteam.swift` (22 %), `Launchers.swift` (32 %): die Teile, die echte Clients ansprechen.
- SwiftUI-Ansichten: bewusst nur über die Regeln oben.
- Vorschlag für `scripts/coverage.sh`: `-P` wie in `run-tests.sh`, weil vier Reihen gleichzeitig über dem liegen, was
  auf dem Rechner des Nutzers erlaubt ist.

Die Abschnitte darunter sind der Stand vom 31.10.

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

Die Logik, die für den Nutzer entscheidet (die 19 Dateien unten, mit GOG, LaunchHealth und GameLog), ist von
**72,2 % auf 79,1 %** der Zeilen gestiegen. Was dort noch fehlt, sind SwiftUI-Ansichten, Netzwerk, echte Steam-,
legendary- und gogdl-Prozesse sowie die echten Dateien des Nutzers; die Liste unter der Tabelle nennt es pro Datei.
Über die ganze App stieg die Abdeckung nur von 27,8 % auf 29,1 %, weil die großen Ansichten und `LibraryModel` die
Summe bestimmen.

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
| `LaunchHealth.swift` | 256 | 91,5 % | 93,0 % | 99,2 % | +6,2 |
| `GameLog.swift` | 166 | 82,1 % | 82,5 % | 98,2 % | +15,7 |
| `GOGDL.swift` | 198 | – | 69,7 % | 78,3 % | +8,6 |
| `GOGLibrary.swift` | 368 | – | 92,4 % | 92,4 % |  |
| `GOGRedist.swift` | 328 | – | 79,3 % | 82,9 % | +3,7 |
| `GOGStore.swift` | 785 | – | 52,4 % | 56,6 % | +4,2 |

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
- `LaunchHealth`: `proof`, `earlyEnd` und `afterFirstSeconds` waren vom GOG-Zweig schon vollständig geprüft. Jetzt
  sind auch die gelernten Laufzeiten und die Log-Markierung dabei (`LearnedFixes`).
- `GameLog`: Es fehlen nur noch drei Zeilen.
- `GOGDL`, `GOGRedist` und `GOGStore`: Anmelden, Download, Update, Deinstallieren, Mac-Start, Spielstände und das
  Einrichten der Windows-Teile laufen über das echte gogdl bzw. Wine. Das Einlesen ist abgedeckt; dazu kommen jetzt
  die Sync-Zustände, die Spielzeit, die Start- und Setup-Infos und das Anmelde-Log. `GOGLibrary` lag schon bei 92 %.
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
- `GOGTest`: Aktualisierungen, die nicht durchkommen (abgemeldet, gogdl startet nicht, GOG antwortet nicht).
  Außerdem die Spielzeit, die Setup-Infos für die Windows-Teile, ein Start ohne GOGs Info-Datei oder ohne ihr
  Programm, installierte Spiele außerhalb der Liste, das Anmelde-Log ohne den Code, `GOGError` und
  `GOGRedist.Needs`.
- `LaunchHealthTest`: Laufzeiten, die ein Spiel gebraucht hat, die Log-Markierung des letzten Starts, Namen der
  Startwege.
- `EngineLayoutTest`: Die Reihe bekommt ein eigenes Home (siehe Beobachtungen). Dort wird die Datei-Seite von
  GameLog geprüft: die Markierung, das Lesen ab einem Start, ein frisches Log ab 8 MB und die `since:`-Leser.

Am Produktionscode hat sich nichts geändert. In `scripts/coverage.sh --files` markiert `^0` zusätzlich die Teile
einer Zeile, die kein Test ausgeführt hat.

Laufzeit des Gesamtlaufs (`ls -d tests/*Test | xargs -P 4 …`), direkt nacheinander gemessen:
**159acfa 453 s mit 41 Reihen, dieser Zweig 439 s mit 43 Reihen**, alle grün. Der Unterschied liegt im Rauschen.
Ein späterer Lauf mit allen Ergänzungen, darunter GOG, brauchte 347 s; die Maschine war da weniger belastet.

Alle Tests arbeiten in eigenen temporären Ordnern mit UUID und brauchen kein Netz. Sie lesen keine echte Steam und
nicht den Prefix des Nutzers. Wo Code UserDefaults braucht, nehmen sie eine Spiel-ID, die kein Store vergibt, und
entfernen den Schlüssel wieder. Die Reihen, die ich angefasst habe, laufen auch auf dem Stand mit dem gemergten
TV-Zweig grün (`claude/tv-fullscreen-61ab1e`). Dieser Zweig lässt sich ohne Konflikte mit dem TV- und dem
Spieldaten-Zweig mergen.

## Verbleibende Lücken, nach Risiko

1. **`LibraryModel.swift`**: 3431 Zeilen, 0 %. Das gilt auch für seinen GOG-Teil: `beforeGOGStart`, `setUpGOG`,
   `launchGOGMac` und `afterGOGSession` sind private Abläufe, die Fenster, Toasts und das Spiel selbst starten.
   Ohne Umbau am Produktionscode gibt es dort nichts zu prüfen, und `launchGOGMac` liegt dort, wo der TV-Zweig
   ändert. Hier steckt viel Entscheidungslogik, etwa wer gerade herunterladen
   darf (`takeTurnsDownloading`), ob die andere Steam frei ist (`otherSteamFree`) und der Startablauf. Alles hängt
   an einem `ObservableObject` mit echten Steams. Der TV-Zweig ändert die Datei. Danach sollten die Entscheidungen
   als statische Funktionen über `Facts`-Structs herausgezogen werden, wie bei `SteamSwitch`.
2. **Abläufe, die echte Prozesse anfassen**: `SteamSwitch` (52 %), `Engine` (45 %), `Launcher` (44 %), `MacSteam`
   (27 %), `MacSteamPrep` (18 %), `Setup` (17 %), `Downloads` (1 %, Wachhalten und Download-Ansicht) und
   `DriveMoves` (0 %, Spiele auf andere Laufwerke verschieben). Sicher testen lassen sie sich nur, wenn die Aktionen als
   Closures hereinkommen oder Stand-in-Programme im Test-Home laufen.
3. **Store-Abläufe**: `EpicStore` (52 %), `GOGStore` (57 %), `GOGDL` (78 %), `GOGSignIn` (28 %, ein
   Web-Fenster). Ein Stand-in für legendary und gogdl
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
  Testbinary. Das sind keine Nightforge-Daten, sie liegen aber im echten Home. `removePersistentDomain` (wie
  `defaults delete`) leert eine Domäne nur, die Datei bleibt. Behoben mit `tests/Shared/TestDefaults.swift`: Eine
  Domäne, deren Name ein absoluter Pfad ist, ist eine Datei an diesem Pfad. `TestDefaults.suite(_:)` legt sie im
  Arbeitsordner der Reihe an, den ihr `run.sh` entfernt, und `TestDefaults.useWorkFolder()` (am Anfang von `main()`)
  macht `UserDefaults.standard` zu einer solchen Domäne. Neue Reihen, die Einstellungen schreiben, kompilieren die
  Datei mit. Die alten Reste stehen in `docs/TODO.md` unter „Wartung und Community“.
- **`EngineLayoutTest` las Nightforges echtes `wine.log`.** Der Aufruf `GameLog.illegalInstruction(since: UInt64.max, …)`
  las ohne eigenes Home die letzten 4 MB von `~/Library/Application Support/Nightforge/Logs/wine.log`. Die Prüfung
  „an older crash report doesn't count“ wäre fehlgeschlagen, sobald dieses Log eine Zeile „illegal instruction“
  enthält. Behoben in 7a0d6e4: Die Reihe läuft jetzt im eigenen Home und bricht ab, wenn das nicht greift.
- **`GOGTest` kopiert das installierte gogdl** aus dem echten `Components/gogdl` ins Test-Home und startet es dort
  mit `--version`. Gelesen wird nur das Programm, keine Nutzerdaten. So hat es der GOG-Zweig angelegt; ich habe es
  so gelassen.
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
| `GameMarks.swift` | 11 | 100,0 % | 100,0 % | 100,0 % |  |
| `GameMove.swift` | 326 | 96,0 % | 96,0 % | 96,0 % |  |
| `GameShortcut.swift` | 74 | 95,9 % | 95,9 % | 95,9 % |  |
| `Glass.swift` | 472 | 0,0 % | 0,0 % | 0,0 % |  |
| `GOGSignIn.swift` | 82 | – | 28,0 % | 28,0 % |  |
| `HomeStage.swift` | 405 | 0,0 % | 0,0 % | 0,0 % |  |
| `InputRouter.swift` | 813 | 1,4 % | 1,4 % | 1,4 % |  |
| `Launcher.swift` | 427 | 44,2 % | 49,4 % | 53,6 % | +4,2 |
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
| **Gesamt** | 32977 | 25,3 % | 27,8 % | 29,1 % | +1,3 |
