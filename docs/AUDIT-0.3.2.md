# Audit 0.3.2 (8.11.2026)

Geprüft: alles seit 0.3.1, Diff `97a8056...f30d255` (47 Commits). Die Zeilenangaben gelten für f30d255, vor den Korrekturen.
Nicht geändert: alles rund um den Ladescreen (`GameBackdrop`, `GameStage`, `raiseCurtain`, `watchCurtain`, `waitForMacStart`), das liegt bei der Session ladescreen-audit.

„Belegt“ heißt: im Code nachvollzogen oder gemessen. „Vermutung“ heißt: nur live zu entscheiden.

## Testergebnis

Stand f30d255, vor den Korrekturen (`scripts/run-tests.sh -P 2`, Exit-Code je Reihe aus `build/test-logs/*.rc`):

- Swift-Reihen: **65 von 66 grün.** Rot: `TextScaleTest` (A14, ein echter Fehler).
- `python3 -m pytest tests -q`: 158 bestanden.
- `tests/ProcessListLive/run.sh`: bestanden.

Nach den Korrekturen erneut grün: `TextScaleTest`, `StringsTest`, `D3DMetalTest`, `StoreHitsTest`, `GameOverlayTest`, `DetachedProcessTest`, `QuitScriptTest`, `WineSandboxTest`, `MacVersionTest`, `EngineLayoutTest`, `FirstStartTest`, `LaunchHealthTest`. `./build.sh` läuft durch (für den Lauf ohne Aufsicht ad hoc signiert), `codesign --verify --deep --strict` ist in Ordnung. Die volle Reihe lief nach den Korrekturen nicht noch einmal.

## Blocker

### A1. Overwatch hängt auf jedem Mac ohne D3DMetal weiter beim Start (behoben)

- **Stellen:** `Engine.swift:2316-2321`, `D3DMetalSupply.swift:203-206`, `D3DMetalFlow.swift:53-61`, `profiles/mac.json` (2357570).
- **Ablauf:** Frischer Mac, oder ein Update von 0.3.1 ohne eingerichtetes D3DMetal. Der Spieler drückt bei Overwatch auf Spielen. Das Profil sagt DXMT, also ist `D3DMetalSupply.needed` falsch und es kommt keine Frage. `CX_APPLEGPTK_LIBD3DSHARED_PATH` wird nur gesetzt, wenn `lib/external/libd3dshared.dylib` da ist, und die Datei kommt erst mit D3DMetal. Overwatch hängt ohne Fenster, wie vor dem Fix.
- **Beleg:** `D3DMetalSupply.swift:3` („It isn't fetched with the engine“), `Engine.swift:2312` („It comes with D3DMetal“), Notiz vom 7.11. in `nightforge-engine-04` („Needs D3DMetal set up“, nur diese eine Variable zählt). Auf dem Test-Mac ist D3DMetal eingerichtet, deshalb fiel es dort nicht auf.
- **Zweite Hälfte:** Wird D3DMetal eingerichtet, während das Hintergrund-Steam läuft, behält Steam seine alte Umgebung, und `steamConfigSignature` kennt die Variable nicht. Der erste Start nach der Einrichtung hätte trotzdem gehangen.
- **Korrektur:** `D3DMetalSupply.needed(…, game:)` kennt die Spiele, die Apples Bibliothek brauchen (`needsRosettaLibrary`, bisher nur Overwatch über Steam). Nightforge fragt jetzt vor dem Start wie bei einem DirectX-12-Spiel. Die Signatur enthält nun, ob die Bibliothek da ist, und `finishD3DMetal` startet Steam dafür neu, bevor das Spiel startet.
- **Für 0.3.3:** Ein Profilfeld statt der festen Liste. Das ist neu und blieb deshalb draußen.

## Hoch

### A2. „Nightforge neu starten“ kann für immer hängen, genau wenn etwas hängt (behoben)

- **Stellen:** `Engine.swift:1152` (`steam.exe -shutdown` ohne Zeitlimit), `Engine.swift:1141` (`osascript`, bis zu 120 s), `Engine.swift:1142-1144`.
- **Ablauf:** Steam antwortet nicht mehr, der Spieler wählt „Nightforge neu starten“. Nightforge beendet sich, das Skript bleibt in `steam.exe -shutdown` stehen. Bis zu `wineserver -k` und `open` kommt es nie: Nightforge ist weg und kommt nicht wieder. Bei einem hängenden Steam für Mac wartet es bis zu 120 s auf `osascript`, dann 20 s, und lässt Steam danach weiterlaufen. Die Release Notes versprechen das Gegenteil („Das hilft, wenn etwas hängt“).
- **Beleg:** Skripttext; der neue Fall in `QuitScriptTest` mit einem hängenden Stellvertreter.
- **Korrektur:** `limited` beendet beide Aufrufe nach 30 s (`NIGHTFORGE_HANG_LIMIT`). Beim Neustart wird Steam für Mac nach 20 s Wartezeit beendet (erst TERM, nach 5 s KILL). Das normale Beenden lässt Steam für Mac wie bisher in Ruhe.

## Mittel

### A3. „Spiel neu starten“ im Overlay läuft dem Spielende in die Quere (behoben)

- **Stellen:** `LibraryModel.swift:1661-1665`, `LibraryModel.swift:743-773`.
- **Ablauf:** Nach „Spiel neu starten“ startet `startAgainWhenEnded` das Spiel, sobald `running` leer ist. `watchForGameEnd` braucht aber einen Blick mehr. Es sieht das Ende also erst, wenn der neue Start schon läuft, und ruft `comeBack`: Der Vorhang geht weg, Nightforge kommt nach vorn, und bei mindestens einer Minute Spielzeit erscheint „Willkommen zurück“ über dem neuen Start.
- **Beleg:** am Code nachvollzogen. Live noch nicht gesehen, die Funktion ist auch nur mit spätem Controller erreichbar.
- **Korrektur:** `restartAfterEnd`. Das Spielende übergibt direkt an den neuen Start, ohne Rückweg und ohne „Willkommen zurück“. Berührt `watchForGameEnd` an einer Stelle; wer die Session ladescreen-audit mergt, sollte darauf achten.

### A4. Der Hinweis „Controller zu spät“ wandert zum nächsten Spiel (behoben)

- **Stellen:** `GameOverlay.swift:50-52`, `GameOverlay.swift:260`, `LibraryModel.swift:1641`.
- **Ablauf:** Windows-Spiel ohne Controller starten, Controller einschalten, das Spiel im eigenen Menü beenden, ohne das Overlay zu öffnen. `lateController` bleibt gesetzt, denn nur `close()` löscht es. Das Overlay des nächsten Spiels bietet „Spiel neu starten“ zuerst an und sagt, der Controller sei zu spät gekommen.
- **Korrektur:** Das Spielende setzt den Hinweis zurück (`GameOverlay.gameEnded`).

### A5. Der signierte Helper bleibt nach einer anderen Version ad hoc (behoben)

- **Stellen:** `Detached.swift:280-282`, `Detached.swift:286`.
- **Ablauf:** Eine ältere Nightforge-Kopie läuft einmal (die 0.3.1 in `/Applications`, über einen `nightforge://`-Link) und baut ihren Ad-hoc-Helper über den signierten. 0.3.2 vergleicht nur die Datei `.helper.sha256`, und die stimmt noch: Der Ad-hoc-Helper bleibt, macOS fragt wieder nach externen Laufwerken. Außerdem legt `copyShippedHelper` den Datenordner nicht an: Fehlt er beim ersten Start, baut Nightforge einmal den Ad-hoc-Helper und ersetzt ihn beim nächsten Start. Das wären zwei Fragen statt einer.
- **Korrektur:** Verglichen werden jetzt Programm und Siegel der Kopie selbst, der Ordner wird angelegt.

## Niedrig

| | Befund | Stelle | Stand |
|---|---|---|---|
| A6 | GOG-Suche fragt immer in Euro. Außerhalb des Euro-Raums liefert GOG dann keinen Preis (gemessen: US+EUR `null`, US+USD `$79.99`, GB+GBP, CH+CHF richtig). | `GOGSearch.swift:93` | behoben, Währung aus dem Locale |
| A7 | Release Notes: Die Leistungsanzeige kommt aus den Einstellungen, nicht aus den Optionen. Die Optionen haben den Schalter nur für CrossOver-Flaschen. | `v0.3.2.md:10`, `:53` | behoben |
| A8 | Ein „Startet nicht“ aus 0.3.1 hat kein `profileNote`. Hat das Spiel ein Profil mit Notiz, verfällt die Bewertung schon beim Update. Folge nur: Das Zeichen zeigt wieder die Einschätzung des Profils. | `Compatibility.swift:87` | kann warten |
| A9 | `codesign --deep` signiert den Helper noch einmal, das `-r` geht verloren. Installiert steht `certificate root` statt `certificate leaf`. Bei einem selbstsignierten Zertifikat ist das dasselbe. Der Kommentar in `codesign-app.sh` stimmt aber nicht. | `codesign-app.sh:41-49` | kann warten |
| A10 | Die Karte „Dieses Spiel“ zeigt für Mac-Versionen beim HUD „–“, obwohl es jetzt dort läuft. | `ThisGameCard.swift:110` | kann warten |
| A11 | Neustart innerhalb von fünf Minuten nach einem Spiel: 30 s Wartezeit für die Cloud-Spielstände, ohne Anzeige. Wer in der Zeit Nightforge selbst öffnet, bricht den Neustart ab. | `Engine.swift:1134` | kann warten; eine Anzeige wäre neu |
| A12 | Der D3DMetal-Dialog sagt bei Overwatch „zeichnet mit DirectX 12“. Stimmt nur halb (das Profil nimmt DXMT), der Weg ist aber richtig. | `D3DMetalFlow.swift:347` | kann warten |
| A14 | `TypoCover` setzt seine Schrift fest, „Größerer Text“ erreicht sie nicht; deshalb war `TextScaleTest` rot. | `TypoCover.swift:35`, `:44` | behoben |
| A13 | Liefert Epics letzte Seite keinen Code oder scheitert eine Seite nach dem Laden (`didFail`), dreht die Bühne weiter. B und Esc führen hinaus. | `EpicSignIn.swift`, `SignInStage.swift` | kann warten |

## Release Notes und Version

Jede Zeile gegen den Code geprüft, `Resources/Info.plist` sagt 0.3.2.

- **Left 4 Dead 2 („lädt seine Karten wieder“) stimmt bisher nicht.** Aus dem Menü hängt das Spiel weiter (`docs/TODO.md`). Der Live-Test läuft. Klappt er nicht, muss die Zeile raus oder unter „Bekannt“.
- **Overwatch:** Der Satz gilt erst mit A1. Ergänzt: Beim ersten Start richtet Nightforge dafür Apples D3DMetal ein.
- HUD korrigiert (A7). Die übrigen Zeilen stimmen.

## Strings und Bedienung

- Deutsch vollständig, kein doppelter Schlüssel (`StringsTest`). Alle Platzhalter im Deutschen passen zum Englischen (1100 Paare, zwei nutzen korrekt `%1$@`/`%2$@`).
- Mit dem Controller erreichbar: Karten, kleines Menü (⧉), Schnellmenü (☰ gehalten), „Verwalten“, „Neu starten“ in den Einstellungen, Overlay. Nur mit Maus oder Tastatur: Anmelden bei Epic und GOG und das Suchen (steht in den Notes), der Epic-Link unter dem Suchraster (`padReachable(false)`, Absicht) und „Neu starten“ im App-Menü (mit dem Controller über die Einstellungen).

## Geprüft, ohne Fehler

Kein Befund bei: `-nofriendsui -nochatui`, `macLaunchType`, `MacSteam.show/ask/bringForward` (kurze Lesezugriffe auf dem Main-Thread, 32 KB Log), `MacGameHUD`, `ShaderCaches`, `cachedAppInfo` (unter Sperre; `appinfo.vdf` hier 1 MB, der Speicher ist kein Thema), `HomeRemovals`, „Später spielen“, Store-Suche (Abbruch und veraltete Antworten), Battle.net-Erkennung und `ProductDB` (Längenprüfungen, kein Lesen über das Ende), Update-Weg von 0.3.1 (`--verify --deep` deckt `Contents/Helpers`, `sign-release.sh` signiert den Helper mit), Quoting in `build.sh`, `codesign-app.sh` und dem Beenden-Skript (Pfade mit Leerzeichen).

## Live zu prüfen

1. **Overwatch ohne D3DMetal:** D3DMetal in den Einstellungen entfernen, dann Spielen. Die Frage muss kommen, danach muss Overwatch über die Hänge hinaus starten.
2. **Neustart mit hängendem Steam für Mac** (Drawful-Dialog offen) und einmal direkt nach einem Spiel.
3. **Controller spät**, dann „Spiel neu starten“: kein „Willkommen zurück“, ein durchgehender Vorhang.
4. **Gegenprobe der Rosetta-Variable** (Vermutung, nur live zu klären): Control, Wukong-Benchmark, OxyRail, ABZU. Macs ohne D3DMetal bekommen sie nicht, sie verhalten sich wie 0.3.1.
5. **Left 4 Dead 2** mit `-condebug +host_writeconfig`.
6. Offene Punkte aus der Checkliste in `docs/RELEASE-0.3.2-ENTWURF.md` (HUD mit Valheim, Launcher-Bühne, Bühnenwache).
