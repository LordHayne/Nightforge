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
- **Ein belegter Logikfehler bleibt offen** (E4, Komponenten nach dem Aufwachen): Die saubere Lösung reicht in
  `Engine.swift`, das gerade eine andere Session bearbeitet. Vorschlag unten.
- **Ein Fund in einer gesperrten Datei** (E8, Update unter einem laufenden Spiel) und **zwei Punkte fürs Board** (E9, E10).
- Die Texte sind sauber: 1100+ Schlüssel, alle über `L10n.t`, kein fest eingetragener sichtbarer Text ohne Übersetzung
  gefunden (zwei `grep`-Läufe über alle `Text(`, `Button(`, `Label(`, `.help(`, `errorMessage =`).

## Testergebnis

`scripts/run-tests.sh -P 2` auf `157e754` (alle sechs Fixes): **117 von 117 Reihen grün.** Gezählt an
`build/test-logs/*.rc`: 117 Dateien, jede mit `0`, so viele wie es `tests/*Test` gibt. Die Python-Tests liefen nicht
(das Python der Command Line Tools hat kein pytest); keine Änderung betrifft sie. Rot ohne Fix und grün mit ihm ist für
E5 nachgestellt; die übrigen Tests prüfen Regeln, die es vor dem Fix nicht gab.

## Funde, nach Wirkung aufs Erlebnis

| Nr. | Wirkung | Fund | Stelle | Stand |
|---|---|---|---|---|
| E1 | mittel | Die Hinweisleiste sagt „Spielen“, wo A herunterlädt oder nichts tut | `LibraryView.swift:2251`, `:2285`, `:2331` | behoben, `d92a1c8` |
| E2 | mittel | Bildschirmtastatur bleibt offen, wenn ihr Controller ausgeht; kein Pad schließt sie dann | `InputRouter.swift:109`, `:723`, `PadRules.swift:86` | behoben, `157e754`; ob es heute so hängt: **Vermutung** |
| E3 | mittel | Die Overlay-Leiste bleibt über Nightforge stehen, wenn das Spiel darunter von selbst endet | `GameOverlay.swift:81`, `OverlayTiles.swift:138` | behoben, `4936204` |
| E4 | mittel | Nach dem Aufwachen sucht Nightforge laut Protokoll nach Komponenten, fragt die Liste aber nie neu | `Components.swift:136`, `:140`, `IdleRest.swift:91` | **vorgeschlagen**, per Probe belegt |
| E5 | mittel bis niedrig | Eine Meldung bleibt für immer stehen, nachdem der Knopf der vorigen mit der Maus geklickt wurde | `Toast.swift:32`, `:53` | behoben, `b29f421` |
| E6 | niedrig | „Willkommen zurück“ nach einem Battle.net-Spiel: „Dein Spielstand wird zu Battle.net hochgeladen …“ | `SessionSummary.swift:220`, `CloudSaves.swift:24` | behoben, `d214a4f` |
| E7 | niedrig | Bei offenem Download-Feld oder offener Filterliste wirken Pfeile und Return auf die Spiele dahinter | `InputRouter.swift:189`, `:267`, `PadRules.swift:94` | behoben, `a30ae4a` |
| E8 | niedrig | Das App-Update lässt sich unter einem laufenden Spiel einspielen | `LibraryModel.swift:2939` | **vorgeschlagen** (gesperrte Datei) |
| E9 | niedrig | A auf dem Suchfeld setzt mit dem Pad nur einen Textcursor | `LibraryGrid.swift:400` | **Board / Vorschlag** |
| E10 | niedrig | A auf einem laufenden Download auf der Startseite tut nichts | `LibraryModel.swift:2859` | **Board** |
| E11 | Frage | Der eigene Lade-Kreis zeichnet mit Bildschirmfrequenz neu | `Glass.swift:473` | **Frage**, nicht gemessen |

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

### E4 · Komponenten nach dem Aufwachen (vorgeschlagen)

- **Was der Spieler merkt:** nichts sofort, aber das Versprechen der Ruhe im Leerlauf stimmt nicht: „Updates laufen beim
  nächsten Aufwachen“ (`docs/TODO.md`, Mac mini als Konsole). Ein Nightforge, das wochenlang offen bleibt, bekommt neue
  Engine-, Grafik- und Controller-Pakete erst nach dem Beenden. Im `wine.log` steht trotzdem jedes Mal „The Mac woke:
  Nightforge looks for updates“. App-Update, Profilliste und AppleGamingWiki werden dabei wirklich neu gefragt.
- **Ursache:** `Engine.fetchComponents` ruft `ComponentStore.manifest()`. Das gibt die Liste vom Programmstart zurück
  (`if let fetched { return fetched }`), und die Online-Liste wird je Lauf nur einmal gefragt (`triedRemote`). Einen Weg,
  noch einmal zu fragen, hat `ComponentStore` nicht.
- **Beleg:** Probe im Notizordner, `erlebnis-audit-komponentenliste-probe.swift` (nicht Teil der Suite): erste Frage
  ohne Online-Liste, dann liegt eine da, zweite Frage. Ausgabe: „the online list was NOT asked again in this run“.
- **Warum nicht behoben:** Einfach neu fragen würde die neue Liste sofort zur gültigen machen. Drückt der Spieler dann
  „Spielen“, wartet `ensureEngine` auf den Download der neuen Engine, gegen „ein Spielstart hat Vorrang“.
  **Vorschlag:** `ComponentStore` holt die Liste nach dem Aufwachen getrennt, `fetchComponents` lädt ihre Pakete, und
  erst wenn alle da sind, wird sie die gültige (dann `applyFetchedComponents`). Dazu muss `removeUnusedComponents`
  (`Engine.swift:898`) die schon geladenen neuen Versionen stehen lassen, sonst räumt ein Start dazwischen sie wieder
  weg. Braucht einen Live-Test mit einem echten Paketwechsel.

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

### E8 · Update unter einem laufenden Spiel (vorgeschlagen)

- **Was passiert:** `installUpdate()` prüft nur `!updating`. Unter einem laufenden oder startenden Spiel tauscht es die
  App und beendet Nightforge. Das Spiel läuft weiter, aber das neue Nightforge hat es nicht gestartet (`startedHere`
  leer): beim Spielende kein Vorhang, kein Zurück zu Nightforge, kein „Willkommen zurück“. „Nightforge neu starten“ ist
  genau deshalb gesperrt („Beende zuerst das Spiel …“, `LibraryModel.swift:2363`).
- **Vorschlag:** dieselbe Sperre in `installUpdate()` (`running.isEmpty`, `launchingID == nil`, `move == nil`) mit dem
  Satz „Beende zuerst das Spiel, dann aktualisiere Nightforge.“ Ein neuer Text, eine Zeile, eine Regel fürs
  `UpdateStateTest`. Datei gehört gerade der Session diagnose-start.

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

## Die fünf nächsten Verbesserungen

1. **Komponenten nach dem Aufwachen wirklich holen (E4).** Der Mac mini als Konsole bleibt wochenlang offen; ohne das
   kommen Engine-Fixes dort nie an.
2. **A auf dem Suchfeld öffnet die Bildschirmtastatur (E9).** Der eine Ort, an dem das Pad heute in etwas landet, das es
   nicht bedienen kann.
3. **Die Hinweisleiste ganz als Regel, mit einer Matrix-Reihe.** E1 konnte entstehen, weil die Wörter in der Ansicht
   stehen und die Taten in `InputRouter`. Eine Regel „Seite und Zustand → Hinweise“ neben `PadRules`, und ein Test, der
   jeden Hinweis gegen die Tat prüft (wie `GameMenuMatrixTest`), hält beide zusammen.
4. **A auf einem laufenden Download zeigt die Downloads (E10, Board).** Auf der Startseite ist das die einzige Kachel,
   auf der A nichts tut.
5. **Eine Regel für Tastatur und Pad: was offen ist, hat die Eingabe.** `handleKey` bildet `PadRules.back` von Hand
   nach; G1 (Vorhang) und E7 (Felder) waren dieselbe Lücke, der große Screenshot ist die nächste. Dazu gehört die
   Update-Sperre unter einem Spiel (E8).

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
