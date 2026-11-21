# Erlebnis-Audit 0.3.3 (14.11.2026)

Geprüft: Zweig `claude/erlebnis-audit-033-0f5292`, Basis `0c2f78a` (`claude/staging-033`, Testbuild `4d7806c` plus Doku).
Auftrag: Fehler und raue Stellen in Oberfläche und Logik, alles, was das Erlebnis weniger rund macht. Nur Code gelesen und
Tests gebaut; keine Nightforge-GUI, kein Wine, kein Steam, nichts installiert, nichts gepusht. Was in `docs/AUDIT-0.3.2.md`,
`docs/AUDIT-0.3.3.md`, `docs/TESTABDECKUNG.md` und `docs/TODO.md` schon steht, ist hier nicht wiederholt.

„Belegt“ heißt: am Code nachvollzogen und, wo es ohne Oberfläche geht, mit einem Test gezeigt. **Vermutung** steht, wo nur
der echte Bildschirm entscheidet. Zeilen gelten für die Spitze dieses Zweigs.

## Ergebnis

- **Sechs Fehler behoben**, je ein Commit mit Test (E1, E2, E3, E5, E6, E7). Die Tests stehen in einer neuen Reihe,
  `tests/ExperienceAuditTest`.
- **Nachtrag vom Abend** (unten): E4 und E8 sind behoben, dazu zwei Funde aus der Live-Prüfung des Koordinators:
  Beenden bei offenem Blatt (E12) und Testreihen, die ins echte Protokoll schreiben (E13).
- **Zwei Punkte fürs Board** (E9, E10) und eine Frage (E11) bleiben.
- Die Texte sind sauber: 1100+ Schlüssel, alle über `L10n.t`, kein fest eingetragener sichtbarer Text ohne Übersetzung
  gefunden (zwei `grep`-Läufe über alle `Text(`, `Button(`, `Label(`, `.help(`, `errorMessage =`).

## Testergebnis

**Nach dem Nachtrag:** `scripts/run-tests.sh -P 2` auf `8ee00e2`: **118 von 118 Reihen grün.** Gezählt an
`build/test-logs/*.rc`: 118 Dateien, jede mit `0`, so viele wie es `tests/*Test` gibt. Ein Lauf davor (auf `a7b9cfc`)
hatte 117 von 118: `ModelFlowsTest` war einmal rot an einer festen Wartezeit von 80 ms, die keine der Änderungen
berührt; die Reihe wartet jetzt auf das Ereignis. Die Python-Tests liefen nicht (das Python der Command Line Tools hat
kein pytest); von den Änderungen betrifft sie keine.

**Erste Runde:** auf `157e754` 117 von 117 Reihen grün, ebenso gezählt.

Rot ohne Fix und grün mit ihm ist nachgestellt für E5 (Meldung), E12 (`closeAllSheets` am alten Stand: zwei Prüfungen
rot; neue Beenden-Prüfungen gegen das alte `Quit.swift`: neun rot) und E4 (Probe im Notizordner). Die übrigen Tests
prüfen Regeln, die es vor dem Fix nicht gab.

## Funde, nach Wirkung aufs Erlebnis

| Nr. | Wirkung | Fund | Stelle | Stand |
|---|---|---|---|---|
| E1 | mittel | Die Hinweisleiste sagt „Spielen“, wo A herunterlädt oder nichts tut | `LibraryView.swift:2251`, `:2285`, `:2331` | behoben, `d92a1c8` |
| E2 | mittel | Bildschirmtastatur bleibt offen, wenn ihr Controller ausgeht; kein Pad schließt sie dann | `InputRouter.swift:109`, `:723`, `PadRules.swift:86` | behoben, `157e754`; ob es heute so hängt: **Vermutung** |
| E3 | mittel | Die Overlay-Leiste bleibt über Nightforge stehen, wenn das Spiel darunter von selbst endet | `GameOverlay.swift:81`, `OverlayTiles.swift:138` | behoben, `4936204` |
| E4 | mittel | Nach dem Aufwachen sucht Nightforge laut Protokoll nach Komponenten, fragt die Liste aber nie neu | `Components.swift:193`, `:220`, `:321`, `IdleRest.swift:95` | behoben, `af8cdb9` (Nachtrag); der echte Paketwechsel ist live offen |
| E5 | mittel bis niedrig | Eine Meldung bleibt für immer stehen, nachdem der Knopf der vorigen mit der Maus geklickt wurde | `Toast.swift:32`, `:53` | behoben, `b29f421` |
| E6 | niedrig | „Willkommen zurück“ nach einem Battle.net-Spiel: „Dein Spielstand wird zu Battle.net hochgeladen …“ | `SessionSummary.swift:220`, `CloudSaves.swift:24` | behoben, `d214a4f` |
| E7 | niedrig | Bei offenem Download-Feld oder offener Filterliste wirken Pfeile und Return auf die Spiele dahinter | `InputRouter.swift:189`, `:267`, `PadRules.swift:94` | behoben, `a30ae4a` |
| E8 | niedrig | Das App-Update lässt sich unter einem laufenden Spiel einspielen | `Updater.swift:146`, `LibraryModel.swift:2956` | behoben, `1d62554` (Nachtrag) |
| E9 | niedrig | A auf dem Suchfeld setzt mit dem Pad nur einen Textcursor | `LibraryGrid.swift:400` | **Board / Vorschlag** |
| E10 | niedrig | A auf einem laufenden Download auf der Startseite tut nichts | `LibraryModel.swift:2859` | **Board** |
| E11 | Frage | Der eigene Lade-Kreis zeichnet mit Bildschirmfrequenz neu | `Glass.swift:473` | **Frage**, nicht gemessen |
| E12 | hoch | Beenden bleibt an einem offenen Blatt hängen, Nightforge läuft weiter (⌘Q, Dock, `osascript`) | `LibraryModel.swift:3341`, `:3348`, `Quit.swift:78` | behoben, `307d432` und der Commit danach (Nachtrag) |
| E13 | niedrig | Testreihen schreiben Zeilen ins echte `wine.log` | `GameLog.swift:16`, `:44`, `:69` | behoben, `a7b9cfc` (Nachtrag) |

### E1 · Die Hinweisleiste nennt, was A wirklich tut (behoben)

- **Was der Spieler sieht:** Auf der Startseite steht unten „Ⓐ Spielen“ unter jedem Spiel. Der große Knopf darüber sagt
  aber „Herunterladen“, wenn das Spiel noch nicht auf dem Mac ist, und A lädt es dann herunter. Bei einem laufenden
  Download, einem Spiel auf einem abgezogenen Laufwerk oder einem von Anti-Cheat gestoppten tut A gar nichts, „Spielen“
  stand trotzdem da. Das trifft gerade den ersten Abend: Eine neue Bibliothek zeigt auf der Startseite die Vorschläge
  „Zum Einstieg“ (`StarterPicks`, auch nicht geladene Spiele), dazu kommt die Liste „Später spielen“ (`HomeRail.pick`:
  „also shows what isn't downloaded yet“). Die Spielseite hatte dieselbe Lücke kleiner: „Spielen“ unter einem laufenden
  Download, „Herunterladen“ bei abgezogenem Laufwerk und bei „Nur VR“.
- **Ursache:** Die Startseite schrieb das Wort fest hin; die Spielseite kannte nur „nicht installiert“ und Anti-Cheat.
- **Fix:** `PrimaryHint.word` bildet `LibraryModel.primaryAction` nach: Spielen, Herunterladen, „Weiter laden“ (Download
  wartet auf Platz), „Zum Spiel wechseln“ (läuft), sonst kein Hinweis. Alle Texte gab es schon.
- **Beleg:** `tests/ExperienceAuditTest`, `hintWords` (zwölf Zustände). Vor dem Fix gab es die Regel nicht; die alte
  Zeile stand in `0c2f78a` bei `LibraryView.swift:2250`.

### E2 · Bildschirmtastatur ohne ihren Controller (behoben, abgesichert)

- **Was der Spieler sehen könnte:** Suche mit Y geöffnet, der Controller geht aus (Akku leer, oder er schläft nach einer
  Weile auf dem Sofa ein). Die Tastatur bleibt stehen. Der wieder eingeschaltete Controller ist für macOS ein neuer:
  A, B, Y, ☰ und die Sticks werden alle verschluckt, weil die Tastatur „das Pad hat“ (`keyboardHasPad`,
  `panelOpen`), gelesen wird aber nur der alte. Hinaus führt nur Esc auf einer echten Tastatur oder die Maus.
- **Ursache:** `lookAtKeyboardPad` schloss nur, wenn das schwach gehaltene Pad-Objekt verschwunden war, und das Trennen
  eines Controllers rief `closeKeyboard` nicht auf. Ob macOS das Objekt beim Trennen freigibt, sagt der Code nicht.
- **Fix:** Die Tastatur schließt mit ihrem Controller (beim Trennen und bei jedem Blick: steht er noch in
  `GCController.controllers()`?). Der getippte Text bleibt.
- **Beleg:** Regel `PadRules.keyboardStays`, Test `keyboardWithoutItsPad`. **Vermutung:** dass es im Build `4d7806c`
  wirklich hängt. Das zeigt nur ein Controller (Live-Prüfung 6, mit Gegenprobe im alten Build).

### E3 · Overlay über einem Spiel, das von selbst endet (behoben)

- **Was der Spieler sieht:** Die Seitenleiste ist offen, das Spiel endet darunter: ein Spiel, das unter dem Overlay
  weiterläuft (nur online spielbar, `OverlayRules.stillness`, `runsOnIfSilent`), fliegt vom Server oder stürzt ab; oder
  ein angehaltenes wird von außen beendet. Nightforge kommt nach vorn, „Willkommen zurück“ erscheint, aber darüber
  steht weiter die Leiste mit „Weiterspielen“ und „Spiel beenden“ für ein Spiel, das es nicht mehr gibt. Sie behält das
  Pad (`reach == .overlay`), „Willkommen zurück“ lässt sich erst bedienen, wenn man die Leiste wegdrückt.
- **Ursache:** `watchForGameEnd` rief nur `GameOverlay.gameEnded()`, und das löschte nur den Hinweis zum späten
  Controller (`LibraryModel.swift:965`).
- **Fix:** `gameEnded()` schließt die Leiste (`OverlayRules.goesWithGame`). Nicht die Frage „Startet nicht?“ (die nimmt
  die Vorhang-Wache weg) und nicht auf dem Weg „Zu Nightforge“.
- **Beleg:** Test `overlayAfterItsGame` (Regel, und der Aufruf bleibt ohne offenes Overlay, was er war).
  `GameOverlayTest` weiter grün.

### E4 · Komponenten nach dem Aufwachen (behoben im Nachtrag)

- **Was der Spieler merkt:** nichts sofort, aber das Versprechen der Ruhe im Leerlauf stimmt nicht: „Updates laufen beim
  nächsten Aufwachen“ (`docs/TODO.md`, Mac mini als Konsole). Ein Nightforge, das wochenlang offen bleibt, bekommt neue
  Engine-, Grafik- und Controller-Pakete erst nach dem Beenden. Im `wine.log` steht trotzdem jedes Mal „The Mac woke:
  Nightforge looks for updates“. App-Update, Profilliste und AppleGamingWiki werden dabei wirklich neu gefragt.
- **Ursache:** `Engine.fetchComponents` ruft `ComponentStore.manifest()`. Das gibt die Liste vom Programmstart zurück
  (`if let fetched { return fetched }`), und die Online-Liste wird je Lauf nur einmal gefragt (`triedRemote`). Einen Weg,
  noch einmal zu fragen, hat `ComponentStore` nicht.
- **Beleg:** Probe im Notizordner, `erlebnis-audit-komponentenliste-probe.swift` (nicht Teil der Suite): erste Frage
  ohne Online-Liste, dann liegt eine da, zweite Frage. Ausgabe: „the online list was NOT asked again in this run“.
- **Fix (Nachtrag, `af8cdb9`):** Nach dem Aufwachen fragt `ComponentStore.askAgain()` die Online-Liste noch einmal, mit
  denselben Prüfungen wie beim Start (signiert, nicht älter als die behaltene und die eigene). Eine neuere Liste gilt
  nicht sofort: Sonst wartete ein Spielstart dazwischen auf ihre Downloads, gegen „ein Spielstart hat Vorrang“. Ihre
  Pakete werden vorab geholt und warten in `Components/.ahead`. Dort sieht sie weder die Suche nach dem neuesten
  Engine-Ordner (`Engine.installedWineNow`, `installedComponentNow`) noch das Aufräumen unbenutzter Versionen
  (`removeUnusedComponents` übergeht Namen mit Punkt), `Engine.swift` blieb deshalb unberührt. Sind alle da, übernimmt
  `applyFetchedComponents` die Liste direkt vor `ensureEngine`, und `install` schiebt die Ordner nur noch an ihren
  Platz. Bricht „Spielen“ das Holen ab, startet das Spiel mit der bisherigen Liste; beim nächsten Programmstart nimmt
  `install` das schon Geholte, ohne zweiten Download.
- **Beleg:** `tests/ComponentsSmokeTest`, 16 neue Prüfungen mit eigener Signatur und Dateien statt Netz: neu fragen,
  nichts Neues, neuere Liste wartet und gilt noch nicht, vorab Geholtes liegt nicht bei den installierten, Übernahme,
  kein zweiter Download, ältere und unsignierte Liste abgewiesen, ohne Netz bleibt die wartende Liste.
- **Nicht belegt:** der echte Wechsel einer Engine im laufenden Nightforge (`ensureEngine` beendet die alte
  Wine-Sitzung und startet Steam neu). Das ist derselbe Weg wie beim Programmstart mit neuer Liste, aber nach dem
  Aufwachen lief er noch nie mit einem neuen Paket, weil die Liste nie neu kam. Live-Prüfung 7.

### E5 · Meldung bleibt stehen (behoben)

- **Was der Spieler sieht:** Spiel verstecken, mit der Maus auf „Rückgängig“ klicken. Die nächste Meldung („… ist auf
  deiner Liste Später spielen“) geht nicht mehr weg, bis der Zeiger einmal auf einer Meldung war und sie wieder verlässt.
- **Ursache:** Der Klick nimmt die Meldung unter dem Zeiger weg, und SwiftUI meldet für eine entfernte Ansicht kein
  „Zeiger weg“. `hovering` blieb wahr, `scheduleHide` wartete jede Sekunde weiter. Dasselbe, wenn eine Meldung unter dem
  Zeiger durch eine neue ersetzt wird.
- **Fix:** Eine Meldung, die geht oder ersetzt wird, nimmt den Zeiger-Zustand mit.
- **Beleg:** Test `messageAfterAClick`: ohne den Fix rot („still stands after 3.4 s“, zweimal), mit ihm grün; der Zeiger
  auf einer Meldung hält sie weiter. Dass SwiftUI das „weg“ wirklich nicht meldet, ist **Vermutung** aus bekanntem
  Verhalten; der Fix schadet auch dann nicht.

### E6 · Battle.net in „Willkommen zurück“ (behoben)

- **Was der Spieler sieht:** Nach einer Battle.net-Sitzung dreht 90 Sekunden „Dein Spielstand wird zu Battle.net
  hochgeladen …“, danach steht „Dein Spielstand wird im Hintergrund zu Battle.net hochgeladen.“ Nightforge lädt dort
  nichts hoch und liest keinen Stand.
- **Ursache:** `followCloud` behandelte jeden Store außer Steam wie Epic und GOG; für Battle.net setzt nichts
  `storeSaves` (`LibraryModel.swift:486`, `:542` sind die einzigen Stellen).
- **Fix:** `CloudSaves.watch(for:)`: Steam liest seinen Eintrag, Epic und GOG den eigenen Upload, Battle.net bekommt
  keine Zeile. Beleg: Test `saveLine`.

### E7 · Tasten unter einem offenen Feld (behoben)

- **Was der Spieler sieht:** Download-Feld offen (D oder Klick), Return gedrückt: Auf der Startseite startet oder lädt
  das markierte Spiel dahinter. Filterliste in der Bibliothek offen: ↑/↓ verschieben die Auswahl im Raster darunter,
  Return öffnet eine Spielseite. Mit dem Pad passierte das nie (`perform` hält das Pad im Feld).
- **Fix:** Wie beim Schnellmenü: Pfeile zwischen den Knöpfen des Felds, Return auf dem markierten, Esc und D schließen.
  Regel `PadRules.panelHasKeys`, Test `keysUnderAPanel`.
- **Nicht angefasst:** Unter dem großen Screenshot wirken die Buchstaben (L, O, H, P, M, D) weiter auf die Seite
  dahinter. Selten und harmlos; gehört zur fünften Verbesserung unten.

### E8 · Update unter einem laufenden Spiel (behoben im Nachtrag)

- **Was passiert:** `installUpdate()` prüft nur `!updating`. Unter einem laufenden oder startenden Spiel tauscht es die
  App und beendet Nightforge. Das Spiel läuft weiter, aber das neue Nightforge hat es nicht gestartet (`startedHere`
  leer): beim Spielende kein Vorhang, kein Zurück zu Nightforge, kein „Willkommen zurück“. „Nightforge neu starten“ ist
  genau deshalb gesperrt („Beende zuerst das Spiel …“, `LibraryModel.swift:2363`).
- **Fix (Nachtrag, `1d62554`):** `Updater.hold` hält das Update zurück, solange ein Spiel läuft oder startet
  (`gameUnderWay`) oder ein Spiel auf ein anderes Laufwerk zieht. Der Druck auf den Knopf sagt es, wie „Nightforge neu
  starten“: „Beende zuerst das Spiel, dann aktualisiere Nightforge.“ bzw. „Warte, bis das Spiel verschoben ist, …“.
  Beleg: Test `updateUnderAGame`.

### E9 · A auf dem Suchfeld (Board oder kleiner Vorschlag)

Mit dem Pad kommt man über ↑ auf das Suchfeld, die Leiste sagt „Ⓐ Auswählen“. A setzt einen Textcursor, den das Pad
nicht bedienen kann; die Bildschirmtastatur liegt auf Y. Naheliegend: A öffnet mit dem Pad die Bildschirmtastatur. Der
Weg dorthin (`InputRouter.openKeyboard`) hängt am Modell, daher nicht gebaut.

### E10 · A auf einem laufenden Download (Board)

Auf der Startseite stehen laufende Downloads in der Reihe. A tut dort nichts (`primaryAction`, Fall `.downloading`),
seit E1 steht auch kein Hinweis mehr. Rund wäre: A öffnet das Download-Feld. Das ändert, was ein Knopf tut, also Board.

### E11 · Der Lade-Kreis (Frage)

`GlassSpinner` zeichnet über `TimelineView(.animation)` mit Bildschirmfrequenz neu, solange er zu sehen ist (120 Mal
pro Sekunde am MacBook): beim Einlesen in der oberen Leiste, in „Willkommen zurück“ bis zu 90 s, in der
Ersteinrichtung über Minuten. Klein, aber das Gegenteil von „billige Transformationen“. Nicht gemessen. Frage: mit
Instruments ansehen, bevor jemand es umbaut?

### Kleines, nur notiert

- „Mac schlafen legen“: Scheitert `pmset sleepnow`, steht es nur im `wine.log` (`LibraryModel.swift:5725`). Der Spieler
  sieht nichts. Praktisch scheitert es nicht.
- „Spiel neu starten“ im Overlay wartet höchstens 30 s auf das Ende und startet dann trotzdem
  (`startAgainWhenEnded`). Hängt ein Spiel beim Beenden länger, ist unklar, was der Spieler sieht. **Vermutung**, nicht
  nachgestellt.

## Nachtrag vom Abend (14.11.): E12 und E13

Aufgesetzt auf `claude/laeuft-liste-033-c4dd4a` (`5cf8e12`). Die Startschleife in `LibraryModel.swift` ist nicht berührt.

### E12 · Beenden bei offenem Blatt (behoben)

- **Was passierte:** Zweimal nach einem Spieletest ließ `osascript … quit` Nightforge laufen. Im `wine.log`: „Quit by
  an Apple Event from osascript didn't go through: a sheet is still open (SheetPresentationWindow)“. Beim zweiten Mal
  zweimal hintereinander, der dritte Versuch schrieb nur „Quit by …“ und hing, der vierte ging durch.
- **Trifft es den Spieler?** Ja. ⌘Q, „Beenden“ im Menü und im Dock, Abmelden und das Update gehen alle durch
  `Quit.now`.
- **Ursache 1, belegt:** `closeAllSheets()` kannte zwei Blätter nicht: die Vollbild-Frage für den Controller
  (`offersFullScreen`) und die Rückfrage des kleinen Menüs (`pendingPower`, „Nightforge beenden?“ und „Mac schlafen
  legen?“). Bleibt so ein Zustand stehen, beendet AppKit das Blatt nach einer Sekunde, SwiftUI zeigt es beim nächsten
  Zeichnen wieder, und `NSApp.terminate` tut unter einem Blatt nichts. Test `quitClosesEverySheet` in `ModelFlowsTest`
  war am alten Stand rot (beide Prüfungen).
- **Ursache 2, belegt:** Die Blätter wurden genau einmal geschlossen. Eins, das danach kommt, blieb: „Willkommen
  zurück“ erscheint erst, wenn der Vorhang weg ist; die Vollbild-Frage kommt aus der Sekunden-Schleife in dem Moment, in
  dem nichts anderes mehr offen ist, also gerade nachdem das Beenden die anderen Blätter geschlossen hat.
- **Ursache 3, belegt:** Nach zwei Sekunden wurde einmal versucht, unter dem offenen Blatt, und dann nie wieder. Ging
  das Blatt später weg, blieb Nightforge trotzdem stehen.
- **Welches Blatt war es?** Das sagt das Protokoll nicht, alle SwiftUI-Blätter heißen dort gleich. Am besten passt die
  Vollbild-Frage: Sie ist das eine Blatt, das zwei Versuche im Abstand von zwölf Sekunden übersteht, und sie kommt
  genau dann, wenn nach einem Spiel mit verbundenem Controller am MacBook-Bildschirm nichts mehr offen ist.
  **Vermutung**, solange niemand sagt, ob ein Controller verbunden und das Fenster nicht im Vollbild war. Vom Spieletest
  selbst kommt kein Blatt (`GameTestRun` räumt „Willkommen zurück“, Fehlstart und Meldung selbst weg).
- **Der dritte Versuch:** „Quit by …“ ohne Folgezeile, 24 s später ging der vierte sofort durch. Der vierte wurde also
  bearbeitet, während der dritte noch in `NSApp.terminate` steckte. **Vermutung:** AppKit wartete dort auf das Blatt,
  das es selbst beendet hatte und das SwiftUI noch für offen hielt. Nicht nachstellbar ohne das Programm.
- **Fix:** (1) `closeAllSheets()` schließt alle 17 Blätter, und ein Test liest die `.sheet`s von `LibraryView` gegen das,
  was ein Beenden schließt und was das Protokoll benennen kann: Das nächste neue Blatt kann nicht vergessen werden.
  (2) Solange ein Blatt steht, schließt das Beenden alle halbe Sekunde noch einmal. (3) Es geht in dem Moment, in dem
  keins mehr da ist, zehn Sekunden lang; wer per Apple Event fragte, hört das Ja erst dann. Nach zwei Sekunden steht
  im Protokoll, worauf gewartet wird, jetzt mit dem Namen des Zustands („SheetPresentationWindow: offersFullScreen“).
  (4) Die Schleife beginnt vor dem ersten Versuch: Hängt der in AppKit, folgt der nächste von selbst nach einer halben
  Sekunde, wenn die Bitte aus der Ereignisschleife kam (Taste, Menü, Apple Event).
- **Beleg:** `CompleteRemovalTest`, `quitOrder`: Blatt kommt nach dem Schließen, Blatt geht erst nach drei Sekunden,
  Blatt geht nie, AppKit nimmt das Beenden zweimal nicht an, erster Versuch hängt. Gegen das alte `Quit.swift` neun
  Prüfungen rot, darunter wörtlich die Zeile vom Nachmittag („didn't go through: a sheet is still open (Welcome back)“).
- **Nebenbei:** Hängt Nightforge nach „Quit by …“ noch bis zu 30 s in der Prozessliste, kann das auch das Übergeben des
  Beenden-Skripts an den Helfer sein (`DetachedProcess.run` wartet bis 10 s auf `open` und bis 20 s auf den Helfer).
  Dauert es zwei Sekunden oder länger, steht jetzt „Quit: handing Steam's shutdown to its script took … s“ im Protokoll.

### E13 · Testreihen und das echte Protokoll (behoben)

- **Was passierte:** `tests/SteamSwitchTest` läuft absichtlich im echten Zuhause („the real home isn't a test home“)
  und ruft dort einen zurückgehaltenen Steam-Start. `GameLog.note` schrieb die Zeile „Steam switch: the Windows Steam
  waits …“ ins echte `wine.log`, um 15:59:30 mitten in einem echten Start. Im Protokoll stehen 43 solche Zeilen,
  echte und die der Testläufe gemischt.
- **Andere Reihen:** 98 von 118 Reihen laufen ohne eigenes Zuhause, 74 davon mit der ganzen App. Jede, die über
  irgendeinen Weg `GameLog.note` erreicht, schrieb mit. `GameLog.handleForSteam` hätte bei einem Start mit
  Stellvertreter-Steam sogar ein über 8 MB großes echtes Protokoll beiseitegeschoben.
- **Fix:** an der einen Stelle, die alle trifft. `GameLog.writes`: Nightforge schreibt sein Protokoll; ein Programm
  ohne App-Bündel (eine Testreihe) nur in einem eigenen Zuhause. `SteamSwitchTest` prüft das an der Stelle des Vorfalls
  (und, wenn kein Nightforge läuft, dass das echte Protokoll so lang ist wie vorher).
- **Andere Dateien im echten Ordner:** Die Reihen, die unter `Engine.supportDir` schreiben, geben eigene Pfade mit
  (`SteamProgramTest`, `ComponentsSmokeTest`) oder brechen im echten Zuhause ab (`ProfileFilesTest`,
  `EngineLayoutTest`). Gegenprobe am echten Ordner (nur gelesen): Während des letzten Suite-Laufs, 19:00:55 bis
  19:03:42 bei laufendem, ruhendem Nightforge, hat sich in `~/Library/Application Support/Nightforge` außerhalb von
  `Prefix` und `Components` keine Datei geändert, auch `wine.log` nicht. `Prefix` und `Components` ließen sich so nicht
  prüfen: Dort schreibt das laufende Steam.

## Geprüft, ohne Fund

- **Texte:** kein sichtbarer Text ohne `L10n.t`; `StringsTest` deckt alle 1100+ Schlüssel. Zähltexte haben ihre
  Einzahl („1 Spiel“, „1 Download“, „%ld von 1 Spiel“).
- **Hinweise gegen Tasten:** Bibliothek, Spielseite (außer E1), Launcher-Karten, kleines Menü, Anmelde-Bühne und Overlay
  nennen, was A, B, X, Y, ☰ und ⧉ in `InputRouter` wirklich tun.
- **Zustände ohne Ende:** „Größe wird geprüft …“ (endet mit dem Zeitlimit von legendary und gogdl, 120 s),
  Abgleich-Banner der Stores, „Zu Nightforge“ aus dem Overlay (`leaveGame` ist begrenzt), Komponenten-Download (nach
  URLSessions Standard brechen 60 s ohne Daten ab, kein Netz sofort; nicht nachgestellt).
- **Dauerläufer:** fünf wiederholende Timer, alle enden mit ihrem Anlass (Stick losgelassen, Tastatur zu, Test zu).
- **Fehler ohne Wort:** Download, Verschieben, Verknüpfung, Update, Store-Abgleich sagen ihre Fehler.

## Live prüfen (für die Fixes dieses Zweigs)

1. **Hinweisleiste:** Startseite mit einem Spiel aus „Später spielen“, das nicht geladen ist: unten „Herunterladen“,
   A lädt. Laufender Download markiert: kein A-Hinweis. Spiel läuft, zurück in Nightforge: „Zum Spiel wechseln“.
   Dasselbe auf der Spielseite. Am Fernseher: Passen „Zum Spiel wechseln“ und „Weiter laden“ in die Leiste?
2. **Battle.net:** nach einer Sitzung über einer Minute „Willkommen zurück“ ohne Zeile zum Spielstand.
3. **Meldung:** Spiel verstecken (H auf der Spielseite), mit der Maus „Rückgängig“ klicken, dann „Später spielen“
   setzen: Die Meldung geht nach rund drei Sekunden.
4. **Overlay:** Ein Spiel, das unter dem Overlay weiterläuft (Overwatch auf diesem Mac), Overlay öffnen, das Spiel von
   außen beenden (Aktivitätsanzeige). Die Leiste geht, „Willkommen zurück“ nimmt das Pad. Im `wine.log`:
   `Overlay: … ended under it, the panel goes with it`. Gegenprobe: „Spiel beenden“ und „Zu Nightforge“ wie bisher.
5. **Tasten im Feld:** Download-Feld mit D öffnen, Pfeile: Die Markierung wandert im Feld, Return auf „Abbrechen“ fragt
   nach, das Spiel dahinter startet nicht, D und Esc schließen. Filterliste per Klick öffnen: ↑/↓ und Return wählen
   in der Liste.
6. **Bildschirmtastatur:** Y, ein paar Buchstaben, Controller ausschalten: Die Tastatur geht, der Text bleibt.
   Controller an, Y: Sie kommt wieder. Gegenprobe im Build `4d7806c`: Bleibt sie dort offen, und reagiert danach noch
   ein Knopf?

7. **Komponenten nach dem Aufwachen (E4):** Braucht eine neue signierte Komponentenliste, während Nightforge schon
   läuft. Mac mindestens sechs Stunden schlafen lassen (oder `WakeCatchUp.every` für den Test klein setzen), wecken,
   20 s warten: `wine.log` „The Mac woke: Nightforge looks for updates“, in `Components/.ahead` erscheinen die neuen
   Versionen, danach „The component list fetched after the wake is in use now“, `.ahead` ist leer, Steam kommt neu
   hoch, ein Spiel startet. Gegenprobe: gleich nach dem Wecken „Spielen“ drücken: Der Start wartet auf keinen
   Download und läuft mit der alten Engine.
8. **Update-Sperre (E8):** Mit einem angebotenen Update ein Spiel starten, über das Overlay zu Nightforge, auf „Update
   auf …“ drücken: Meldung „Beende zuerst das Spiel …“, nichts wird geladen. Ohne Spiel: Update wie bisher.
9. **Beenden (E12):** (a) Controller verbinden, Fenster nicht im Vollbild, warten bis „Vollbild für den Controller?“
   steht, ⌘Q: Nightforge geht. (b) Kleines Menü, „Nightforge beenden“, bei offener Rückfrage ⌘Q: geht. (c) Nach einem
   Spieletest oder einer Sitzung über einer Minute sofort `osascript -e 'tell application "Nightforge" to quit'`: geht
   innerhalb einer Sekunde, im `wine.log` nur „Quit by …“. (d) Einstellungen › Speicher, „Nightforge komplett
   entfernen …“ bis zur Rückfrage (nicht bestätigen), dann ⌘Q: Geht es nicht, steht nach zwei Sekunden „waits: a sheet
   is still open (…)“ mit Namen im Protokoll, und nach „Abbrechen“ geht Nightforge von selbst.
10. **Protokoll (E13):** `scripts/run-tests.sh -P 2 SteamSwitchTest` ohne laufendes Nightforge: Danach steht keine neue
    Zeile „Steam switch: the Windows Steam waits …“ im echten `wine.log`.

## Die nächsten Verbesserungen

1. **A auf dem Suchfeld öffnet die Bildschirmtastatur (E9).** Der eine Ort, an dem das Pad heute in etwas landet, das es
   nicht bedienen kann.
2. **Die Hinweisleiste ganz als Regel, mit einer Matrix-Reihe.** E1 konnte entstehen, weil die Wörter in der Ansicht
   stehen und die Taten in `InputRouter`. Eine Regel „Seite und Zustand → Hinweise“ neben `PadRules`, und ein Test, der
   jeden Hinweis gegen die Tat prüft (wie `GameMenuMatrixTest`), hält beide zusammen.
3. **A auf einem laufenden Download zeigt die Downloads (E10, Board).** Auf der Startseite ist das die einzige Kachel,
   auf der A nichts tut.
4. **Eine Regel für Tastatur und Pad: was offen ist, hat die Eingabe.** `handleKey` bildet `PadRules.back` von Hand
   nach; G1 (Vorhang) und E7 (Felder) waren dieselbe Lücke, der große Screenshot ist die nächste.
5. **Blätter aus einer Liste.** E12 kam, weil jedes Blatt an drei Stellen steht (Ansicht, Schließen, Name). Der Test
   hält sie jetzt zusammen; eine Liste der Blätter im Modell, aus der alle drei kommen, bräuchte ihn nicht mehr.
6. **Jede Testreihe in einem eigenen Zuhause.** E13 ist für das Protokoll zu; `CFFIXED_USER_HOME` für alle Reihen
   machte lokale Läufe wie die der CI. `SteamSwitchTest` will im ersten Durchlauf das echte Zuhause, das wäre die Ausnahme.

## Nicht prüfbar ohne laufendes Programm

- Ob E2 heute wirklich hängt, und wie macOS einen wieder eingeschalteten Controller meldet.
- Ob SwiftUI beim Entfernen einer Ansicht unter dem Zeiger „Zeiger weg“ meldet (E5).
- Fokus-Sprünge, die erst das Layout zeigt: `PadFocus.move` rechnet mit echten Rahmen. Geprüft sind nur die Regeln.
- Alles am Fernseher (Größen, Überscan, ob die längeren Hinweiswörter passen).
- Schlaf und Aufwachen, Bildschirm an- und abgesteckt: gelesen sind nur die Regeln (`DarkWatch`, `WakeCatchUp`,
  `GameOverlay.followDisplay`), deren Live-Prüfungen in `docs/TODO.md` schon stehen.
- Download-Wege mit echtem Store (Pause, kein Netz, volle Platte, Laufwerk abgezogen): Die Regeln haben eigene Reihen
  (`BugDownloadTurnsTest`, `SpaceCheckTest`, `ExternalDriveTest`, `DownloadHintsTest`), der echte Ablauf nicht.
- Der Weg Spielen → Vorhang → Spiel → Beenden liegt in den gesperrten Dateien und ist in `docs/AUDIT-LADESCREEN.md` und
  `docs/AUDIT-0.3.3.md` schon geprüft; hier nur an den Rändern berührt (E3).
