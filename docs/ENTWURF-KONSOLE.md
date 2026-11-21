# Entwurf: Das Konsolen-Gefühl

Stand 8.11.2026, gelesen auf f30d255 (`claude/staging-032` samt TODO-Commits). Ein Bericht, nichts ist gebaut.
Für die Zeit nach 0.3.2. Oberflächen sind hier nur beschrieben: Sobald der Nutzer gewählt hat, kommen zuerst Boards
auf die Zeichenfläche.

**Ziel:** Einschalten, Controller in die Hand, spielen, ohne Maus, Tastatur, Mac-Fenster oder sichtbare Technik. Am
MacBook und am Fernseher. „Nightforge erkennt nicht nur, welche Hardware angeschlossen ist. Es erkennt, wie der
Nutzer gerade spielen möchte.“

**Wie die Aussagen belegt sind:**
- **[Code]** Datei und Zeile im Stand oben. **[Log]** `wine.log` oder `pmset -g log` auf dem Mac des Nutzers.
- **[SDK]** Header aus `MacOSX26.5.sdk` oder `MacOSX27.0.sdk`. **[Quelle]** siehe Quellenliste am Ende, mit Nummer.
- **[Vermutung]** nicht belegt. **Live:** nur am Gerät zu beurteilen, dazu steht die kurze Testanweisung.

## Die fünf Dinge mit der größten Wirkung

### 1. Aufwachen mit dem Controller

**Heute:** Nightforge startet nur von Hand. Es gibt keinen Autostart (`SMAppService`, Anmeldeobjekte: kein Treffer im
Code). Das Wecken per Pad (`InputRouter.wakeIfIdle`, `InputRouter.swift:650`) wirkt nur, wenn Nightforge schon läuft.
Die PS-/Xbox-Taste, das stärkste Konsolen-Muster, gehört macOS.

**Was fehlt zum „einschalten“:** drei kleine Stücke, die zusammen eine Kette ergeben.

1. **Autostart als Schalter** (`SMAppService.mainApp`, [SDK], macOS 13). Aus, bis der Nutzer ihn setzt.
2. **Bildschirm und Fernseher an per Pad.** Der Weg ist teils schon offen:
   - **[Log]** Ein DualSense zählt für macOS als Nutzeraktivität: `pmset -g log` zeigt `UserIsActive … IOHIDUserDevice
     product:DualSense Wireless Controller` mit `DeclUser` (1.–7.11., 11 Einträge).
   - **[SDK]** `IOPMAssertionDeclareUserActivity` schaltet den Bildschirm ein und braucht keine Rechte, falls das Pad
     allein nicht reicht.
   - **[Quelle 2]** HDMI-CEC weckt den Fernseher mit dem Mac und legt ihn mit dem Mac schlafen, ohne Zutun einer App.
     Eingebautes HDMI nennt Apple für M4, M3/M4/M5 Pro und Max; das einfache M5 des Nutzers (Mac17,2) steht in der
     gelesenen Liste nicht. Mit Apples oder Belkins USB-C-HDMI-Adapter geht es auf jedem Apple-Silicon-Mac ab 14.4.
   - Dazu gehört, dass der Mac wach bleibt, während der Bildschirm aus ist: `PreventUserIdleSystemSleep` nur bei
     Netzteil, Fernseher und laufendem Nightforge (wie `Downloads.swift:18`, dort für Downloads). Ein Konsolen-Ruhemodus.
3. **Die Home-Taste führt zu Nightforge.** Neu in macOS 27 **[SDK]**: `GCControllerHomeButtonSettingsManager` sagt, der
   Nutzer könne dem langen Druck der Home-Taste eine App zuweisen. Eine App darf den Stand lesen und die richtige
   Seite der Systemeinstellungen öffnen (`openControllerHomeButtonSettingsForActivity:`), setzen darf sie ihn nicht.
   Nightforge kann also genau einen Weg anbieten: „PS-Taste lange drücken öffnet Nightforge“, ein Knopf, einmal am Mac.
   Im Bau steht SDK 26.5 (`build.sh:7`, mit SDK 27 fehlt ohne Xcode das `@State`-Makro), der Zugriff muss daher zur
   Laufzeit über `NSClassFromString` laufen. Mit `GCControllerHomeButtonSettingInAppActionDefer` könnte die kurze
   PS-Taste in Nightforge auch die Startseite sein; das hatte der Nutzer am 1.11. anders entschieden (Frage unten).

**Grenzen, ehrlich:**
- **Aus dem echten Ruhezustand** ist Wecken per Controller nicht dokumentiert. Apple nennt Taste, Klick und Deckel
  **[Quelle 3]**. Im aufbewahrten `pmset`-Log kamen alle 13 vollen Wachphasen vom Deckel oder Einschaltknopf,
  Bluetooth nur als `DarkWake` **[Log]**. Ein Versuch mit dem Pad ist darin nicht erkennbar.
- **Sperrbildschirm:** Fordert macOS nach dem Bildschirm-Aus ein Passwort **[Quelle 4]**, kommt man ohne Tastatur oder
  Touch ID nicht weiter. Das ändert keine App.

**Einordnung:** Autostart und Wachbleiben klein für 0.3.3, Home-Taste klein bis mittel. **Risiko:** Der lange Druck holt
Nightforge über ein laufendes Spiel. Ein Windows-Spiel im Vollbild, das die Tasten verliert, kann sich minimieren
(Befund vom 7.11., `GameStage`).

**Live:**
- Bildschirm aus (`pmset displaysleepnow` oder warten), Mac wach, Pad drücken: kommt das Bild? Am Fernseher: kommt er an?
- Pad einschalten, während Nightforge hinten liegt: Kommt `GCControllerDidConnect` an, geht der Bildschirm an?
- Mac in den echten Ruhezustand, dann PS-Taste: wacht er auf? Am Netzteil und auf Akku je einmal.
- Systemeinstellungen › Game Controller: langen Druck auf Nightforge stellen, im Spiel lange drücken. Was passiert mit dem Spiel?

### 2. Eine Tastatur für den Controller

**Heute:** Die einzige Sackgasse auf dem täglichen Weg. Y steht als „Suchen“ in der Hinweisleiste (`LibraryView.swift`,
Bibliothek) und setzt nur den Textcursor (`InputRouter.swift:487`, `LibraryGrid.swift:392`). Dann geht es ohne Tastatur
nicht weiter, auch nicht in die Store-Suche, die seit 0.3.2 der Weg zu Spielen ist, die man noch nicht hat. Die Idee steht
seit dem 31.10. in `docs/TODO.md:972`.

**Vorbild:** Big Picture hat eine eigene Bildschirmtastatur, und Valve hat sie am 13.10.2026 weiter gepflegt
**[Quelle 8]**. Sie klappt bei Mausklick bewusst nicht auf, das passt zur Erkennung von Pad oder Maus hier
(`PadRules.padUsedLast`).

**Vorschlag (nur beschrieben):** Ein Tastatur-Feld aus den vorhandenen `padFocus`-Bausteinen. A tippt, B löscht, Y
schließt, die Treffer laufen live mit; „rdr2“ und „bg3“ gehen schon, meist reichen 2 bis 3 Buchstaben. Als zweiter
Schritt dieselbe Tastatur für Epics und GOGs Anmeldeseite im `WKWebView`, die sich heute nicht bedienen lässt
(`InputRouter.swift:919`). Passwörter bleiben auch dann nur auf der Seite des Stores; das braucht aber eine eigene Prüfung.
schließt, die Treffer laufen live mit; „rdr2“ und „bg3“ gehen schon, meist reichen 2 bis 3 Buchstaben. Auf Anmeldeseiten
kommt die Pad-Tastatur nicht: Das Passwort liefe durch Nightforge (Beschluss 8.11., `docs/ENTWURF-ANMELDEN.md`).

**Einordnung:** größeres Stück, zuerst Boards. Kein laufender Effekt, also kein Strompreis. **Risiko:** gering; die
Tastatur liegt als Ebene über dem Hauptfenster wie die Panels.

### 3. Am Fernseher lesbar

**Heute:** Der Fernseher zeigt das MacBook-Layout. Am TV des Nutzers läuft 1920×1080, Punkte gleich Pixel (TV-Test vom 31.10.).
Von 305 festen Schriftgrößen im Code sind 223 höchstens 13 pt **[Code]** (nicht alle davon am Fernseher zu sehen):

| Was | Nightforge am 1080p-TV | Richtwert |
|---|---|---|
| Hinweisleiste | 13 pt (`LibraryView.swift`, `Hint`) | tvOS Standard 29 pt, Minimum 23 pt **[Quelle 5]** |
| Controller-Akku | 12 pt | Xbox: Nebentext 12 epx = 24 px **[Quelle 6]** |
| Fließtext, Knöpfe | 13–16 pt | Xbox: Haupttext 15 epx = 30 px **[Quelle 6]** |
| Rand oben / unten | 36 / 22 pt | 54 px, 5 % **[Quelle 6, 7]** |
| Rand seitlich | 56 pt (`Theme.gutter`) | 96 px, 5 % **[Quelle 6, 7]** |
| Fokusrahmen | 3 pt (`PadFocus.swift:235`) | Xbox: Rahmen um das Element, tvOS: das Element wächst **[Quelle 5, 6]** |

„Größere Schrift“ gibt +18 % (`Accessibility.swift`) und nur von Hand: 13 pt werden 15,3 pt, die Hälfte des Richtwerts.
Obere Leiste und Hinweisleiste liegen damit im äußeren 5-%-Rand, den manche Fernseher abschneiden.

**Vorschlag:**
- **Klein, 0.3.3:** Am Fernseher (`Candidate.isTV`) „Größere Schrift“ von selbst an, Ränder auf 5 %, Rahmen dicker.
- **Größeres Stück:** eine richtige TV-Stufe, etwa 1,5-fach, mit weniger auf einmal (Hinweisleiste höchstens
  vier Einträge, Bühne ohne Nebenspalte).
- **Sonde dazu (8.11., außerhalb des Bildschirms, ohne Nightforge):** Das ganze Fenster mit `scaleEffect` zu skalieren geht
  nicht, der Text wird unscharf. Maß ist der Anteil weicher Randpixel an den vollen Pixeln: 19,5 pt direkt gezeichnet 0,26,
  13 pt mit `scaleEffect` 1,5 dagegen 0,61 und damit auf die Stelle genau wie die gestreckten Pixel von 13 pt (Kontrolle).
  Lage und Treffer stimmen dabei: Die Rahmen der AppKit-Ansichten kommen skaliert an, Klicks treffen, `PadFocus` würde also
  richtig rechnen. `drawingGroup` macht den Text wieder scharf (0,27), taugt aber nicht fürs Ganze: Es zeichnet keine
  AppKit-Ansichten (Rollflächen, Textfelder, `PadAnchor`) und wäre ein Vollbild-Effekt gegen das Budget. Eine auf 1280×720
  gesetzte `NSView`-Bounds-Fläche zeigt die Rahmen richtig, Klicks treffen aber nicht. **Also:** die TV-Stufe über die
  Schriftgröße (`TextScale`, alle Größen laufen schon durch `.font(size:)`), etwa 1,5-fach. Dagegen stehen 107 feste
  Rahmenmaße im Code, von denen nur vier die Schrift mitrechnen: Die Boards müssen zeigen, was am Fernseher wegfällt, und
  dann die Layouts folgen. **Live, eine Minute:** ob der Fernseher die Unschärfe auch so zeigt, entscheidet die Sonde nicht.

**macOS-Grenze:** Die Overscan-Stellung des Fernsehers lässt sich nicht verlässlich abfragen. In IOKit stehen nur Schlüssel,
keine App-Schnittstelle **[SDK]**. Also feste Ränder.

**Live:** Am TV aus 3 m Abstand: Hinweisleiste, Spieltitel und Akku lesen. Liegt die Hinweisleiste ganz im Bild, oben auch die Uhr?

### 4. Keine Fragen fürs Sofa

**Heute:** Der Vorhang sagt in drei Fällen, dass man aufstehen muss (`Strings.swift:773,806,807`):
„Steam fragt … antworte in seinem Fenster“, „Das Spiel fragt etwas – antworte mit Maus oder Trackpad“, „macOS fragt um
Erlaubnis – antworte mit Maus oder Trackpad“. Teile sind schon gelöst: Unitys Startfenster drückt ein Helfer ohne
Bedienungshilfen-Recht (`docs/TODO.md:622`), Steams Frage nach der Startoption bei Mac-Spielen ist weg (c72e31e).

**Vorschlag, in dieser Reihenfolge:**
1. **Fragen vermeiden.** Jede neue Art wie beim Unity-Helfer als Kategorie abfangen. Wo möglich vor dem Sofa: erste
   Erlaubnisse gesammelt im Erststart stellen. Ein kleines Beispiel: Die Mitteilungs-Frage kommt heute genau dann, wenn
   ein Download endet und ein Spiel vorne ist (`MacIntegration.swift:103`).
2. **A und B in Windows-Fragen.** Der Weg des Unity-Helfers (`BM_CLICK` in der Wine-Sitzung) braucht keine macOS-Rechte
   und ginge für klassische Dialoge (`#32770`). Steams Chromium-Fenster sind keine solchen; ob Tastendrücke dort ankommen, ist **[Vermutung]**.
3. **Stick als Zeiger**, als letzter Ausweg. Für Wine-Fenster reicht `SendInput` in der Sitzung
   **[Vermutung]**, für Mac-Fenster bräuchte es einmal die Bedienungshilfen-Freigabe. Der Nutzer entscheidet, ob das sein soll.

**Einordnung:** Punkt 1 klein und laufend, 2 und 3 größeres Stück mit offenem Ausgang.

**Live:** Ein Spiel mit Steam-Frage (Wukong-Benchmark, EULA) nur mit dem Pad; mitzählen, wie oft man zur Maus greift. Dasselbe am TV.

**Zeiger über dem Spiel (8.11., gebaut als `PointerParking`):** Versteckt das Spiel den Zeiger nicht selbst, bleibt er stehen. Von außen geht mit öffentlichen Schnittstellen kein echtes Verstecken:
- `NSCursor.setHiddenUntilMouseMoves` wirkt nur für die App vorne, auch mit einem durchlässigen oder ein Punkt großen Panel blieb der Zeiger stehen **[Code, Probe 1.11.]**. Für `CGDisplayHideCursor` aus dem Hintergrund nennen die Quellen ebenfalls keinen öffentlichen Weg (https://developer.apple.com/forums/thread/756199, https://www.raycast.com/Dhaiwat10/mouse-cursor-toggle); selbst probiert habe ich das nicht, um den laufenden Spieler nicht zu stören.
- Ein eigener Zeiger aus einem Panel über dem Spiel scheidet aus: `NSTrackingActiveAlways` ist laut Header „Not supported for NSTrackingCursorUpdate“ **[SDK]**, ohne Hauptfenster gibt es also keinen Cursor-Wechsel.
- Einen Moment die Tasten nehmen geht (so macht es der Vorhang), aber nie über einem sichtbaren Spiel: Unity und Unreal minimieren sich dann (`GameStage`).
- **Privat, nur genannt:** Die Fensterserver-Eigenschaft `SetsCursorInBackground` (`CGSSetConnectionProperty`) erlaubt Hintergrund-Apps das Verstecken, kleine Werkzeuge nutzen sie. Dagegen spricht: undokumentiert, kann mit jedem macOS brechen, Apples DTS nennt das Dock als Hindernis, der Prozess muss dafür laufen bleiben, und der Zählerstand von Verstecken und Zeigen muss stimmen. Bewusst nicht eingebaut.

Öffentlich bleibt: den Zeiger aus dem Bild schieben. `CGWarpMouseCursorPosition` braucht kein Recht und bewegt „without generating events“ **[SDK]**, das Spiel bekommt also weder Fokus- noch Mausereignis. Ziel ist der untere Rand etwas neben der Ecke, dort bleibt nur die Pfeilspitze. Regel: Pad in Benutzung und die Maus seit 2 s still, einmal hinschieben; echte Maus oder Touchpad-Zeiger, er gehört wieder dem Spieler. Nicht bei einer offenen Frage, die den Zeiger braucht. Grenzen: ein bis zwei Pixel bleiben, und ein Spiel, das am Bildrand scrollt, könnte reagieren (Ausweg in `docs/TODO.md`).

### 5. Antwort unter den Fingern: Klang, Haptik, Licht, Akku

**Heute:** Die Oberfläche ist stumm und still. Im ganzen Code keine Treffer für `NSSound`, `AVAudioPlayer`,
`GCDeviceHaptics`, `.light` oder `playerIndex`. Ein Controller, der sich verbindet, löst nichts Sichtbares aus
(`InputRouter.attach`, `InputRouter.swift:393`), einer, der geht, auch nicht (`:82`). Akku wird nur gelesen, solange Nightforge vorne ist
(`LibraryModel.swift:611`), und nur mit Farbe gezeigt (`InputRouter.swift:1149`). Wird das Pad im Spiel leer, erfährt man es, wenn es weg ist.

**Vorbild:** Xbox spielt bei Fokus, Bestätigen, Zurück, Öffnen und Schließen eigene Klänge, die Fokus-Klänge wechseln durch vier
Varianten, und auf der Konsole ist das von selbst an **[Quelle 6, 9]**. PS5 zeigt den Akku unter „Zubehör“ **[Quelle 10]**.

**Vorschlag:**
- **Controller-Rückmeldung, klein:** „DualSense verbunden · 65 %“ als Meldung, im Spiel über `GameHint` (nimmt dem Spiel nie die Tasten).
  Einmal bei 15 % Akku, einmal wenn ein Pad im Spiel wegbricht. Dafür den Akku auch im Spiel lesen, alle paar Minuten.
- **Spielernummer, klein:** `playerIndex` setzen und in der Akku-Kapsel die Nummer zeigen.
- **Klang und Haptik, größeres Stück:** Eigene, kurze Klänge (Nachschlagen, Bestätigen, Zurück, Anschlag am Rand), nur wenn
  zuletzt das Pad benutzt wurde und kein Spiel läuft. Haptik sparsam: Bestätigen, Spielstart, und die zwei Sekunden L3 + R3,
  die heute keinerlei Rückmeldung geben (`OverlayHold`, `GameOverlay.swift:498`). Licht: Farbe des Spiels oder Store-Ton beim Start.
- **Budget:** Kurze Dateien, einmal geladen, keine ständig laufende Audio-Engine; `CHHapticEngine` mit automatischer Abschaltung. Nur Einzelereignisse, nichts Dauerhaftes.
- **Eigenes:** Klänge selbst gestalten, nie von Konsolen übernehmen. Der Nutzer wählt aus zwei bis drei Sätzen.

**Risiko:** Haptik und Licht gehen über `GCController`, Windows-Spiele reden über SDL/HIDAPI mit demselben Pad. Wer gewinnt, zeigt nur der Test.
Am AV-Receiver können kurze Klänge am Anfang abgeschnitten sein **[Vermutung]**.

**Live:**
- Meldet ein DualSense über Bluetooth `haptics` und `light`? (macOS 27, einmal im Scratchpad-Programm ausgeben.)
- Licht setzen, Windows-Spiel starten, beenden: Welche Farbe bleibt?
- Klang am TV über den DENON: Kommt der erste Klang nach einer Pause vollständig?

---

## Der Weg eines Spielers, Station für Station

✅ trägt · ⚠️ Bruch oder fehlende Rückmeldung · ❌ Maus oder Tastatur nötig

| Station | Stand | Beleg | Maßnahme |
|---|---|---|---|
| Mac an, Nightforge startet | ❌ Von Hand, kein Autostart | kein `SMAppService` im Code | K1 |
| Controller als Einschalter | ⚠️ Holt Nightforge nach vorne, wenn es läuft; aus dem Ruhezustand unbelegt | `InputRouter.swift:650` | K2, Live |
| Erststart: Rosetta | ❌ Admin-Passwort, einmal | `Setup.swift:402` | bleibt, ansagen |
| Erststart: Pad koppeln | ❌ Bluetooth-Einstellungen, einmal **[Quelle 11]** | `ControllerTest.swift:181` | später |
| Erststart, Steam | ⚠️ QR mit dem Handy geht, das Fenster bleibt ein Mac-Fenster | `SetupView.swift:124` | bleibt |
| Stores: Epic, GOG | ❌ Tastatur auf der Seite des Stores | `InputRouter.swift:919`, `SignInStage.swift` | G1 Schritt 2 |
| Stores: Battle.net | ❌ Eigenes Fenster des Clients | `SignInStage.swift:82` | bleibt |
| D3DMetal holen | ❌ Browser, Apple-Konto, Dateiauswahl, einmal | `D3DMetalFlow.swift:150,172` | bleibt, ansagen |
| Startseite, Bibliothek | ✅ Bereiche, L1/R1, ☰, B eine Ebene (gebaut 1.11.) | `docs/ENTWURF-CONTROLLER.md` | – |
| Am MacBook mit Pad | ⚠️ Bleibt im Fenster, außer der Spieler wählte Vollbild | `GameDisplay.swift:198` | K5 |
| Suche, Store-Suche | ❌ Y setzt nur den Cursor | `InputRouter.swift:487` | G1 |
| Download | ✅ Panel ist Ebene, Mac bleibt wach | `Downloads.swift:18` | – |
| Download fertig im Spiel | ⚠️ macOS-Mitteilung, beim ersten Mal mit Rückfrage | `MacIntegration.swift:93-105` | K7 |
| Spielstart | ✅ Vorhang, Statuszeile nach 3 s | `GameBackdrop.swift:56` | – |
| Kaltstart von Steam | ⚠️ Oft über eine Minute | `docs/TODO.md:647` | Abhängigkeit unten |
| Fragen vor dem Spiel | ❌ Maus oder Trackpad | `Strings.swift:773,806,807` | G4 |
| Im Spiel: Overlay | ✅ L3 + R3, 2 s; ⚠️ keine Rückmeldung beim Halten | `GameOverlay.swift:498` | G3 |
| Schnellmenü | ✅ ☰ halten, eigene Ebene, B schließt | `PadRules.swift:126` | – |
| Lautstärke im Spiel | ❌ Keine Bedienung am Pad, am MacBook nur Tasten | keine Treffer für Lautstärke-Setzen | G5 |
| Wechsel Spiel ↔ Nightforge | ✅ „Zu Nightforge“, „Zum Spiel wechseln“; ein Fall offen | `[Log]` 12370: „didn't come back“ nach Wechsel zu Claude | – |
| Spielende | ✅ Vorhang, Spielseite, Willkommen zurück | `LibraryModel.swift:714-792` | – |
| Nightforge beenden, Mac schlafen | ❌ Nur Menü, ⌘Q oder Dock | `App.swift:43`, `InputRouter.swift:59` | K6 |
| Zwei Controller | ⚠️ Eine Akku-Kapsel je Pad, keine Nummern; im Spiel ungeprüft | `LibraryView.swift:2169`, `docs/TODO.md:954` | K4, G6 |
| Akku, Benachrichtigungen | ⚠️ Nur vorne und nur als Farbe | `LibraryModel.swift:611` | K4 |
| Ton und Haptik | ❌ Gar nicht vorhanden | keine Treffer | G3 |
| TV: Vollbild, HDMI-Ton | ✅ Live 31.10./1.11. | `GameDisplay.swift`, `GameAudio.swift` | – |
| TV: Erkennung | ⚠️ Nach Namen: Philips, Grundig, Loewe, Yamaha-Receiver fehlen | `GameDisplay.swift:537` | K8 |
| TV: Lesbarkeit, Overscan | ❌ Layout fürs MacBook | Abschnitt 3 oben | K3, G2 |
| Mac schläft ein, wacht auf | ⚠️ Nightforge hört nicht darauf, Verhalten unbekannt | keine `willSleep`/`didWake`-Beobachter | Live |

**Live zu „Mac schläft und wacht“:** Spiel laufen lassen, Deckel zu, Deckel auf: läuft Ton, Pad, Bild weiter? Ist Nightforge noch vorn?

---

## Was Konsolen konkret gut machen

Muster, nie Aussehen, Namen oder Klänge.

| Muster | Bei wem | Beleg | Bei uns |
|---|---|---|---|
| Eine Taste weckt das Gerät | PS5: PS-Taste, auch aus dem Ruhemodus | [Quelle 10] | Teilweise (K1, K2) |
| Eine Taste, immer dieselbe Schnellansicht | PS5 Kontrollzentrum; Big Picture: Steam/Guide-Taste + A | [Quelle 10, 8] | L3 + R3, weil macOS die Home-Taste hat |
| Ein Aus-Knopf im Menü | PS5 „Ein/Aus“ mit Ruhemodus | [Quelle 10] | Fehlt (K6) |
| Fortsetzen, wo man war | Xbox Quick Resume: speichert den Stand des Spiels | [Quelle 12] | Nur RAM-Pause im Overlay (S2) |
| Spieler zuordnen, sichtbar auf dem Pad | Switch: Leuchten zeigen die Nummer, „Griffart/Reihenfolge“ | [Quelle 13] | Fehlt (K4, G6) |
| Text ohne Tastatur | Big Picture Bildschirmtastatur; GFN am TV Code oder QR auf dem Handy | [Quelle 8, 14] | Fehlt (G1); Steam-QR ja |
| Klang bei jeder Bewegung | Xbox-Oberfläche, von selbst an | [Quelle 9] | Fehlt (G3) |
| Bedienung erkennt Pad oder Maus | Big Picture: Hinweise für Tastatur, Tastatur nicht bei Mausklick | [Quelle 8] | Ja (`padUsedLast`, Hinweise) |
| Bild und TV gehen mit dem Gerät an | HDMI-CEC, PS5/Xbox | [Quelle 2, 15] | macOS tut das selbst (siehe oben) |
| Lesbar aus drei Metern | tvOS, Xbox, Android TV | [Quelle 5, 6, 7] | Fehlt (K3, G2) |

Nicht belegt, weil die Seiten nicht lesbar waren: Xbox wecken per Controller, Switch wecken per HOME-Taste, GFN mit dem Pad im Launcher.

---

## Was macOS erlaubt

| Thema | Urteil | Beleg |
|---|---|---|
| Autostart einer App | **Geht.** `SMAppService.mainApp`; macOS zeigt eine Mitteilung, der Nutzer kann es abschalten | [SDK], [Quelle 16] |
| Vollbild ohne Desktop, Dock und Menüleiste aus | **Geht**, solange Nightforge vorne ist (macht `FullScreen` schon) | `FullScreen.swift:127`, [SDK] |
| Desktop beim Autostart nie sichtbar | **Einschränkung.** Den Moment bis zum ersten Fenster bestimmt macOS; die Anmeldung kommt davor | **[Vermutung]**, Live |
| Haptik am DualSense | **Geht laut API**, `GCController.haptics` + CoreHaptics; „falls vorhanden“ | [SDK] `GCDeviceHaptics.h` |
| Lichtleiste, Spieler-LEDs | **Geht laut API**, `GCDeviceLight.color`, `playerIndex`; „nicht garantiert“ | [SDK] `GCController.h:184` |
| Adaptive Trigger | **Geht laut API** in Nightforge; in Windows-Spielen nicht (Xbox-IDs) | [SDK], `docs/TODO.md:877` |
| Pad im Hintergrund hören | **Geht**, `shouldMonitorBackgroundEvents` (nutzt Nightforge) | `InputRouter.swift:399`, [SDK] |
| Home-Taste auf Nightforge | **Einschränkung.** Nur der Nutzer stellt es ein, ab macOS 27; App darf lesen und die Seite öffnen | [SDK 27] |
| Home-Taste im Spiel abfangen | **Geht nicht.** „Overrides“ gelten für die App vorne, das ist das Spiel | [Quelle 11], `docs/TODO.md:901` |
| Bildschirm einschalten | **Geht**, ohne Rechte: `IOPMAssertionDeclareUserActivity` | [SDK] |
| Mac wach halten, Bildschirm aus | **Geht** (`PreventUserIdleSystemSleep`) | `Downloads.swift:18` |
| Bluetooth-Pad weckt Mac aus dem Ruhezustand | **Unbelegt**, nicht dokumentiert | [Quelle 3], [Log], Live |
| Mac schlafen legen | **Geht** wohl: `pmset sleepnow`, Rechte brauchen laut Handbuch nur Einstellungen | `man pmset`, Live |
| Sperrbildschirm umgehen | **Geht nicht** | [Quelle 4] |
| HDMI-CEC steuern (Eingang, Lautstärke) | **Geht nicht** aus einer App, keine Schnittstelle; macOS weckt und legt schlafen von selbst | [Quelle 2], [SDK] ohne Treffer |
| Overscan abfragen oder ändern | **Geht nicht** verlässlich | [SDK], nur IOKit-Schlüssel |
| Game Mode erzwingen | **Einschränkung.** Kommt im macOS-Vollbild von selbst, verdoppelt die Bluetooth-Abtastrate. Fürs Programm: `LSSupportsGameMode` (gesetzt) | [Quelle 1], `Engine.swift:2178` |
| Pad in der App koppeln | **Einschränkung.** Apple sagt Bluetooth-Einstellungen; `startWirelessControllerDiscovery` zu testen | [Quelle 11], [SDK] |

**Eine Sache für Game Mode:** Laut Apple hängt die höhere Abtastrate am Vollbild **[Quelle 1]**. Windows-Spiele laufen mal mit „Game Mode On“,
mal ohne (`docs/TODO.md:931-933`). Für das Pad heißt das: Wo Game Mode fehlt, ist die Eingabe langsamer. Das Thema gehört zur Arbeit an „Direct“ (engine-04).

---

## Alle Maßnahmen, nach Wirkung und Aufwand

Aufwand: S bis ½ Tag, M 1–2 Tage, L mehr. Alle Oberflächen zuerst als Board.

| # | Maßnahme | Wirkung | Aufwand | Einordnung | Risiko | Beleg |
|---|---|---|---|---|---|---|
| K1 | Autostart als Schalter, Bereitschaft im Hintergrund | hoch | S | 0.3.3 | Mitteilung von macOS; mehr RAM dauerhaft | [SDK] |
| K3 | TV: Größere Schrift von selbst, Ränder 5 %, Rahmen dicker | hoch | S | 0.3.3 | Layout mit 18 % ist schon erprobt | Abschnitt 3 |
| K2 | Wachbleiben bei Netzteil + TV, Pad weckt Bild | hoch | S | 0.3.3, nach Live | Mac bleibt an; nur am Netzteil | Abschnitt 1 |
| K4 | Controller verbunden, weg, Akku leer; Spielernummer | mittel | S | 0.3.3 | Hinweis über dem Spiel kostet kurz „Direct“ | `GameHint.swift` |
| K5 | Pad in der Hand am MacBook: Vollbild (oder einmal anbieten) | mittel | S | 0.3.3, Frage | Am Schreibtisch lästig | `GameDisplay.swift:198` |
| K6 | Ein/Aus im Pad-Menü: Nightforge beenden, Mac schlafen | mittel | S | 0.3.3, Board | versehentlich: Rückfrage | `App.swift:43` |
| K7 | Mitteilungs-Frage in den Erststart | klein | S | 0.3.3 | – | `MacIntegration.swift:103` |
| K8 | TV-Erkennung auch nach Größe (`CGDisplayScreenSize` ab etwa 40″) | klein | S | 0.3.3 | Große Monitore, Merken je Schirm hilft | `GameDisplay.swift:537` |
| K9 | Home-Taste auf Nightforge einrichten | hoch | S–M | 0.3.3, nach Live | Spiel verliert Tasten | [SDK 27] |
| G1 | Pad-Tastatur: Suche, Store-Suche, später Anmeldung | hoch | M–L | größeres Stück | gering | Abschnitt 2 |
| G1 | Pad-Tastatur: Suche, Store-Suche | hoch | M–L | größeres Stück | gering | Abschnitt 2 |
| G3 | Klang, Haptik, Licht | hoch | M | größeres Stück, Klangwahl | SDL gegen GC | Abschnitt 5 |
| G2 | Echte TV-Stufe | hoch | L | größeres Stück, Sonde zuerst | Layouts, Fokus | Abschnitt 3 |
| G4 | Fragen per Pad: A/B in Windows-Dialogen, Stick als Zeiger | hoch | L | größeres Stück | offen, teils TCC | Abschnitt 4 |
| G5 | Großes Overlay: Uhr, Akku, Lautstärke, Downloads | mittel | M | größeres Stück, steht in TODO | Panel-Sichtbarkeit bei Game Mode | `docs/TODO.md:952` |
| G6 | Spielerreihenfolge wählen | mittel | L | größeres Stück, nach Test Sonic Mania | SDL/winebus | `docs/TODO.md:954` |
| S1 | Handy-Anmeldung für Epic und GOG (nur der Code, nie das Passwort) | mittel | L | später | Stores ändern Abläufe | [Quelle 14] als Muster |
| S1 | Handy-Anmeldung für GOG (nur der Code, nie das Passwort); Epic sagt ehrlich, dass es eine Tastatur braucht, siehe `docs/ENTWURF-ANMELDEN.md` | mittel | L | später | Stores ändern Abläufe | [Quelle 14] als Muster |
| S2 | Spiel beim Wechsel zu Nightforge pausieren | klein | M | später | Online-Spiele, Wine braucht Lauf für Übergabe | `GameOverlay.swift:297` |
| S3 | Eigene Pad-Kopplung | klein | L | später | einmaliger Vorgang | [Quelle 11] |

**Vorschlag für 0.3.3:** K1, K3, K4, K7, K8 ohne weitere Fragen. K2 und K9 nach ihren Live-Proben. Danach G1 als erstes großes Stück.

**Abhängigkeit:** Punkt 2 der 0.3.3-Liste („Steam nur bei Bedarf, zumindest im Akkubetrieb“) verlängert den Kaltstart auf über eine Minute
(`docs/TODO.md:647`). Für das Konsolen-Gefühl sollte Steam am Netzteil und am Fernseher warm bleiben, wie am 26.10. entschieden: keine Wartezeit ist wichtiger als RAM.

---

## Geprüft, kein Handlungsbedarf

- **Bildschirm schläft beim Spielen mit dem Pad ein:** Ein DualSense hält ihn wach, siehe Beleg oben. Für Xbox-Pads gibt es keinen Eintrag im Log. **Live:** Xbox-Pad, 11 Minuten nur Pad, `pmset -g assertions | grep UserIsActive`.
- **Uhr und Mac-Akku im Vollbild:** stehen in der oberen Leiste (`LibraryView.swift:1126,1160`).
- **Aktualisieren** geht mit dem Pad (`top.update`). **Zeiger** verschwindet bei Pad-Nutzung.

## Bewusst nicht

- Kein dauernd laufender Bildschirmschoner oder Vollbild-Effekt (Budget der Oberfläche, 29.10.). Steam hat einen bekommen **[Quelle 8]**; hier soll einfach der Bildschirm schlafen.
- Keine Kiosk-Optionen (`DisableForceQuit` und Ähnliches): Ein Mac bleibt ein Mac.
- Kein eigener CEC-Adapter als Voraussetzung.

## Fragen an den Nutzer

1. **Autostart:** Soll Nightforge beim Anmelden unsichtbar bereitstehen (RAM dauerhaft belegt)? *Empfehlung: als Schalter, standardmäßig aus.*
2. **PS-/Xbox-Taste in Nightforge:** Am 1.11. „bleibt bei macOS“. Kurz gedrückt zur Startseite, wenn der Nutzer das in den Einstellungen freigibt? *Empfehlung: nochmal ansehen, sobald der lange Druck getestet ist.*
3. **Vollbild am MacBook mit Pad:** von selbst, einmal anbieten oder gar nicht? *Empfehlung: einmal anbieten, dann gemerkt.*
4. **Klänge:** überhaupt, und wie deutlich? *Empfehlung: zwei bis drei Sätze zum Anhören, mit einem Schalter.*
5. **Stick als Zeiger** samt einmaliger Bedienungshilfen-Freigabe: lohnt das? *Empfehlung: erst sehen, wie weit Vermeiden und A/B kommen.*

## Reihenfolge der Live-Proben

Am Stück, etwa 20 Minuten, mit DualSense am MacBook und danach am TV:
1. Bildschirm aus, Pad drücken (Abschnitt 1).
2. Echter Ruhezustand, PS-Taste.
3. Langer Druck auf Nightforge, im Spiel.
4. `haptics`/`light` melden sich? (Probe im Scratchpad, ohne GUI-Kopie von Nightforge.)
5. Lesen aus 3 m am TV.

## Quellen

1. Apple, Use Game Mode: https://support.apple.com/en-us/105118 (auch: Gaming-Fokus beim Verbinden eines Controllers; Home-Taste öffnet Game Overlay, Spiele oder Spotlight).
2. Apple, Connect to HDMI from your Mac: https://support.apple.com/en-us/108928
3. Apple, Mac schlafen legen und wecken: https://support.apple.com/guide/mac-help/put-your-mac-to-sleep-or-wake-it-mh10330/mac
4. Apple, Sperrbildschirm: https://support.apple.com/guide/mac-help/change-lock-screen-settings-mh11784/mac
5. Apple HIG, Typography (tvOS Standard 29 pt, Minimum 23 pt): https://developer.apple.com/design/human-interface-guidelines/typography; Designing for tvOS (Abstand, Fokus): https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos
6. Microsoft, Designing for Xbox and TV (archivierte UWP-Seite): https://learn.microsoft.com/en-us/windows/apps/design/devices/designing-for-tv
7. Android TV, Layouts: https://developer.android.com/design/ui/tv/guides/styles/layouts
8. Steam: Big Picture https://store.steampowered.com/news/posts/?enddate=1667322980; GamingOnLinux zum Update vom 13.10.2026 https://www.gamingonlinux.com/2026/10/a-big-steam-update-brings-the-big-art-mode-screensaver-steam-controller-upgrades-linux-upgrades-and-more/
9. Microsoft, Sound: https://learn.microsoft.com/en-us/windows/apps/design/style/sound (dazu Quelle 6: auf Xbox von selbst an).
10. PlayStation: Kontrollzentrum https://www.playstation.com/en-us/support/games/customize-ps5-control-center/, Tasten https://www.playstation.com/en-us/support/hardware/ps5-button-functions/
11. Apple, Wireless game controller: https://support.apple.com/en-us/111099
12. Xbox, Quick Resume: https://support.xbox.com/en-US/help/games-apps/game-setup-and-play/get-back-to-your-game-instantly-with-quick-resume
13. Nintendo, Controller einrichten: https://www.nintendo.com/my/support/switch/controller/index.html; Pairing https://en-americas-support.nintendo.com/app/answers/detail/a_id/22416/~/how-to-pair-joy-con-controllers
14. GeForce Now am TV: https://nvidia.custhelp.com/app/answers/detail/a_id/5255/; Code-Anmeldung auf Android TV (Fremdquelle): https://beebom.com/run-geforce-now-on-android-tv/
15. HDMI-CEC One Touch Play: https://source.android.com/docs/devices/tv/hdmi-cec
16. Apple, Anmeldeobjekte: https://support.apple.com/guide/mac-help/open-items-automatically-when-you-log-in-mh15189/mac

**Nicht gefunden:** Apples Artikel zum Betrieb mit geschlossenem Deckel war über die bekannten Adressen nicht erreichbar. Was davon abhängt, steht deshalb nur als Live-Test.
