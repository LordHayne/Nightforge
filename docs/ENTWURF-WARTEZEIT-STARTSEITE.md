# Entwurf: Wartezeit beim ersten Start und Startseite für Neue

Stand 29.10.2026. Umsetzung erst nach dem OK des Nutzers und nach dem Merge von 6.1
(`claude/first-start-6-1-18d92f`), denn beide Teile hängen an `SetupView.swift` und `LibraryView.swift`.

- **Entwurf zum Anklicken:** https://claude.ai/artifact/Hg1m1YCMvxdowvHwp8c7rp (privat, in 1512 × 853 pt, mit
  Umschaltern für jeden Zustand). Tabs: Einrichtung, Startseite A · Bühne, B · Drei für heute, C · Wand und der
  erste Entwurf.
- **MagicPath:** Das Kontingent für externe Agenten war aufgebraucht (`EXTERNAL_AGENT_API_QUOTA_EXCEEDED`).
  Der Nutzer hat am 29.10. entschieden: kein Upgrade, der Entwurf bleibt auf der Seite oben.
- Wie bei `solidly-valley-2097` gilt: Der Entwurf ist React/Tailwind und nur Vorlage. In SwiftUI nachbauen,
  mit `GlassBackground`, `GlassTextButtonStyle`, `Theme` und den vorhandenen Bausteinen.

## 1. Einrichtung: die rechte Hälfte („Steam wird verbunden“)

Ziel des Nutzers: Die Einrichtung soll „lebendiger“ wirken, und „wenn man viel machen kann am Anfang, wird die
Einrichtung nicht so lange“. Gemessen sind etwa 4 Minuten bis zu Steams Anmeldefenster, bald etwa 2:40.

Links bleibt `ChecklistPage` wie in 6.1, mit QR-Hinweis und „Steam-Fenster wieder zeigen“. Darunter kommt die
Detailzeile unter dem laufenden Schritt, die die Sitzung first-start-6-1 baut, z. B. „Wine 4.7.3 (CrossOver) ·
142 von 380 MB · 15 MB/s“ oder „Steam lädt sein Update: 210 von 336 MB“. Fertige Schritte sagen „in 25 s“. Im
Entwurf ist sie grau, 12,5 pt, eine Zeile unter dem Fortschrittsbalken. Die Texte sind die Beispiele dieser
Sitzung, für „Windows-Umgebung“ steht ein Platzhalter. Rechts kommen, untereinander und mittig, ein
Controller-Test und eine Tipp-Karte.

**Views.** In `ChecklistPage` ein `HStack` mit zwei gleich breiten Spalten. Neu ist `SetupSidePanel.swift`:

- `SetupSidePanel` enthält die Überschrift, `ControllerTestView` und `SetupTipCarousel`.
- `PadDrawing` zeichnet das Pad mit `Shape`s, nicht als Bild, damit jede Taste einzeln leuchten kann.
  Den Umriss, den Body-Pfad und die Lage der Tasten gibt es im Entwurf für zwei Layouts (`LAYOUT.ps`,
  `LAYOUT.xbox` in `ControllerTest.tsx`). Die Koordinaten beziehen sich auf eine 520 × 330 große Fläche.
- Ohne Controller ist das Pad nur ein Umriss mit 26 % Weiß, der langsam atmet (Deckkraft 0,45 bis 0,8, 3,6 s).
  Darüber stehen „Schließ deinen Controller an“, ein Satz und „Controller koppeln …“. Der Text existiert schon in
  `Strings.swift` und öffnet wie in den Einstellungen die Bluetooth-Einstellungen.
- Mit Controller sind Körper und Tasten aus Glas. Gedrückte Teile leuchten in `Theme.sodium` mit Schein.
  L2/R2 füllen sich mit `value`, die Sticks bewegen ihre Kappe um bis zu 10 pt, und L3/R3 färben sie ein.
  Beim DualSense leuchtet die Lichtleiste am Touchpad.

**Daten.**

- **Name und Akku:** `InputRouter.refreshBattery()` liefert `ControllerStatus(name:battery:)` schon für die
  HintBar, dieselbe Quelle nutzen. Die Überschrift kürzt den Namen: „DualSense Wireless Controller“ wird
  „DualSense“, und „Wireless“ fällt weg, aus „Xbox Wireless Controller“ wird also „Xbox Controller“.
- **Layout:** PlayStation oder Xbox wie bei den Glyphen (`model.padSymbols` / `PadSymbols`, beachtet
  `Prefs.padGlyphs`). Die PlayStation-Form gilt für DualSense und DualShock 4, die Xbox-Form für alles andere.
- **Eingabe:** Auf keinen Fall eigene `pressedChangedHandler`/`valueChangedHandler` setzen. Die gehören
  `InputRouter`, und ein zweiter Handler ersetzt den ersten, dann geht die Navigation kaputt. Stattdessen den
  Zustand lesen, solange die Ansicht sichtbar ist, in einer `TimelineView(.animation)`:
  `pad.buttonA.isPressed`, `leftTrigger.value`, `leftThumbstick.xAxis.value`, `dpad.up.isPressed` usw.
  Das Touchpad liest man über `(pad as? GCDualSenseGamepad)?.touchpadButton`, die Home-Taste über `buttonHome`
  (optional, macOS kann sie für sich behalten).
- **Was die Taste macht:** Die Zeile unter dem Pad („In Nightforge: …“) folgt der Belegung in `InputRouter`:
  A wählt aus (auf Home: spielen), B geht zurück, X öffnet die Spielseite, Y die Optionen, ☰ wechselt Home ↔
  Bibliothek, L1/R1 springen 5 Spiele, L2/R2 zum ersten/letzten, Steuerkreuz/linker Stick bewegen (runter auf
  Home = Bibliothek). Was Nightforge nicht belegt, sagt „Funktioniert – Nightforge braucht sie nicht“. Die
  Tabelle gehört direkt neben die Belegung in `InputRouter.swift` (z. B. `enum PadPart` mit `meaning`), damit
  beides nicht auseinanderläuft.
- **Zähler:** „8 von 20 ausprobiert“ (DualSense 20 Teile mit Touchpad, Xbox 19), am Ende „Alles
  funktioniert“ in `Theme.runsGreat`. Ein neuer Controller beginnt von vorn.

**Tipps.** `SetupTipCarousel` zeigt eine Glas-Karte mit Symbol-Kachel (60 pt), Titel, einer Zeile, Punkten
und einer Zeitleiste unten. Alle 7 s kommt die nächste Karte, unter dem Mauszeiger (`onHover`) hält sie an.
Bei „Bewegung reduzieren“ wird nur überblendet. Die Texte stehen im Entwurf in `TipCarousel.tsx` und kommen
als L10n-Schlüssel in `Strings.swift` (Englisch als Schlüssel, Deutsch als Wert). Tipp 4 nimmt die Glyphen des
angeschlossenen Pads (△/○ oder Y/B). Jeder Tipp ist eine echte Funktion:

| # | Label (Englisch) | Wo im Code |
|---|---|---|
| 1 | Mac versions first | `MacVersion.swift` |
| 2 | Sharp & smooth by itself | `FramePacing.swift`, MetalFX |
| 3 | Anti-cheat via GeForce Now | `Compatibility.swift`, `Launcher.swift` |
| 4 | Menu button switches views | `InputRouter.swift` (☰, Y, B) |
| 5 | Swipe back, pinch for covers | `Trackpad.swift` |
| 6 | Welcome back after a session | `SessionSummary.swift` |
| 7 | Downloads keep the Mac awake | `Downloads.swift` |
| 8 | TV mode follows an external screen | `GameDisplay.swift` (mit Monitor getestet, mit Fernseher noch nicht) |
| 9 | Weak charger warning | `PowerSource.swift` (`ChargerCheck`) |
| 10 | Engine rollback after a crash | `EngineRollback.swift` |
| 11 | Recent games in the Dock menu | `MacIntegration.swift` |

**Wenn Steam auf die Anmeldung wartet** (`SetupModel.phase == .waitingForSignIn`): Die rechte Hälfte geht auf
22 % Deckkraft und Graustufen, die Tipps halten an. Dazu kommen `allowsHitTesting(false)` und
`accessibilityHidden(true)`. Oben steht eine Zeile „Pausiert, solange Steam auf deine Anmeldung wartet“. In der
Phase davor (`steamStarting`, QR-Hinweis „Gleich öffnet sich …“) läuft rechts alles normal.

**Kleinere Fenster.** Der Entwurf ist für 1512 pt gebaut. Unter etwa 1100 pt Fensterbreite die rechte Spalte
weglassen und nur die Tipp-Karte unter die Checkliste stellen.

**Der Lampenschein.** Ein schwacher radialer Schein (`Theme.sodium`, 8,5 %) hinter dem Pad, nur mit
Controller. Das ist kein Deko-Leuchten wie das gestrichene Lampenlicht aus 6.1: Es zeigt, dass ein Pad da ist.
Wenn das nicht gewollt ist, einfach weglassen.

## 2. Startseite für Neue: drei Richtungen

Das Urteil des Nutzers über die heutige Startseite nach dem ersten Start: „sieht langweilig aus“, „zu leer“.
Deshalb gibt es drei mutige Richtungen, jede vor und nach dem ersten Spiel. Welche es wird, entscheidet der
Nutzer. Für alle gelten dieselbe Wahl, dieselben Daten und dieselbe Regel nach dem ersten Spiel (unten unter
„Erster Entwurf“).

- **A · Bühne** (`HomeStage.tsx`): Die guten Starts als Cover-Flow. Das gewählte Cover steht groß vorn
  (250 pt breit), schwebt leicht und spiegelt sich im Boden. Ein Lichtstreif zieht über das Glas. Die nächsten
  Cover drehen sich um 58° weg, abgedunkelt. Das Licht des Spiels füllt den Hintergrund. Links stehen Titel,
  Warum-Satz, Werte und Knopf. In SwiftUI: ein `ZStack` mit `rotation3DEffect`, `offset` und `zIndex` je Abstand
  zur Auswahl, die Spiegelung als gespiegelte Kopie mit Verlaufsmaske.
- **B · Drei für heute** (`HomeThree.tsx`): eine Wahl aus drei großen Covern, jedes mit seinem Grund („Am
  schnellsten bereit“ = kleinster Download, „Gemacht für den Mac“, „Am besten bewertet“ = Metascore). Das gewählte
  tritt vor und neigt sich zum Mauszeiger, seine Farbe leuchtet dahinter. Unten steht eine Leiste „Mehr für den
  Anfang“. Nach dem ersten Spiel steht links „Weiterspielen“. In SwiftUI: `rotation3DEffect` und
  `onContinuousHover` für das Neigen.
- **C · Wand** (`HomeWall.tsx`): die ganze Bibliothek als schräge Cover-Wand, sieben Reihen, die langsam
  gegeneinander gleiten (110–210 s je Durchlauf). Was super läuft, ist hell, der Rest liegt bei 30 % Helligkeit.
  Davor eine Scheibe aus dickem Glas (`Glass.thick`) mit „22 deiner 100 Spiele laufen hier“ und „Fang hiermit an“.
  Glas-Schilder an der Wand öffnen die gefilterte Bibliothek. In SwiftUI muss die Wand eine gezeichnete Ebene
  sein (`Canvas` in `TimelineView` oder `drawingGroup()`), sonst ruckelt sie bei 100 Covern. Bei kleinen
  Bibliotheken wiederholen sich die Cover.
- Alle drei halten bei „Bewegung reduzieren“ still (`Accessibility.swift`): kein Schweben, kein Gleiten.

### Erster Entwurf (die ruhige Variante, Grundlage für alle drei)

**Wann.** Wenn die heutige Leiste nichts zum Weiterspielen hätte: keine angehefteten Spiele, keine Downloads und
kein installiertes Spiel, das in den letzten 90 Tagen gespielt wurde (die ersten drei Teile von
`HomeRail.pick` in `Navigation.swift` sind leer). Heute füllt `HomeRail.minimum` dann mit anderen installierten
Spielen auf, bei null installierten bleibt nur die Kachel „Alle Spiele“.

**Was.** `HomeLevel` in `LibraryView.swift` bekommt einen zweiten Inhalt für die Leiste. Der Held bleibt
`GameDetail(compact: true)`, mit Zusätzen.

- **Die Wahl und die Reihenfolge** (`rank` in `homeData.ts`): installiert, „Läuft super“, volle
  Controller-Unterstützung, Mac-Version, Metascore, kleinerer Download, in dieser Rangfolge. Das erste Spiel ist
  der Held mit dem Chip „Empfohlen zum Start“ (Sodium) vor dem Kompatibilitäts-Abzeichen. Auf seinem Cover in der
  Leiste steht dieselbe Marke als runder Punkt.
- **Daten, alle schon vorhanden:** `Compatibility.of(game, profile:, analysis:)` für die Stufe, die Mac-Version
  aus `MacVersion`, die Controller-Unterstützung wie auf den Covern, der Metascore aus
  `SteamCatalog.storeFacts(appID:)`, die Größe aus `sizeOnDisk`/`downloadSize`, der Zustand aus `Game.install`.
- **Warum-Satz** unter dem Titel (`why` in `NightforgeHome.tsx`), z. B. „Die Mac-Version läuft ganz ohne
  Windows-Übersetzung, und du spielst es voll mit dem Controller.“ Bei installierten Spielen steht „Schon auf
  deinem Mac.“ davor. Bei teilweiser oder fehlender Controller-Unterstützung sagt der Satz das ehrlich.
- **Werte:** Download/Belegt, Version (Mac/Windows), Controller, Metascore. Der Knopf heißt wie heute
  „Herunterladen · 0,7 GB“ oder „Spielen“. Die Zeile darunter sagt bei Mac-Versionen, dass Steam für Mac beim
  ersten Mal eingerichtet wird (Text aus `MacSteamSetup`), bei Windows-Spielen, dass es im Hintergrund lädt und
  der Mac wach bleibt.
- **Die Leiste heißt „Für den Anfang“** („Ausgesucht aus deinen 100 Spielen – was auf diesem Mac am besten
  läuft“) und hat Gruppen mit kleiner Überschrift: „Bereit zum Spielen“ (nur wenn etwas installiert ist),
  „Mac-Versionen“, „Läuft super“, je bis zu fünf Spiele, und am Ende wie heute „Alle Spiele“. Zwischen den Gruppen
  steht eine Haarlinie. „Alle 6 ›“ / „Alle 21 ›“ öffnen die Bibliothek mit dem Filter aus `LibraryFilters`
  („Mac version“, „Runs great“).
- **Covers** in 138 × 207 pt statt 154 × 231 pt, sonst passt der Held nicht über die Leiste. Hier wird nichts
  ausgegraut, weil anfangs ohnehin nichts geladen ist. Den Pfeil „Nicht geladen“ gibt es nur, wenn in der Leiste
  Geladenes und nicht Geladenes gemischt ist.
- **Bibliotheks-Karte rechts:** „22 von 100 laufen hier“ mit dem Balken und den Zeilen „Läuft super 21 ›“ und
  „Mac-Versionen 6 ›“ (Filter wie oben), dazu ein Satz zu „noch nicht getestet“ und GeForce Now. Die Zahlen sind
  dieselben wie in `LibraryReveal`, aus `model.cards` neu berechnet. Die Karte gibt es nur bis zum ersten Spiel.
- **Pad:** Die Leiste geht wie heute mit Steuerkreuz und Stick. Die Gruppen-Links und die Karte sind
  `padFocus`-Knöpfe, erreichbar mit ↑ aus der Leiste.

**Nach dem ersten Spiel.** Die Leiste heißt wieder „Weiterspielen“. Die gespielten Spiele stehen vorn (Gruppe
„Zuletzt gespielt“), dahinter bleibt „Für den Anfang“ ohne die schon gespielten. Das gilt, solange
`HomeRail.pick` ohne Auffüllen weniger als `HomeRail.minimum` (3) Spiele hätte. „Für den Anfang“ ersetzt also nur
das heutige Auffüllen. Der Held ist das zuletzt gespielte Spiel mit den heutigen Werten (Zuletzt gespielt,
Spielzeit, Belegt, Controller). Den Chip „Empfohlen“ und die Bibliotheks-Karte gibt es dann nicht mehr.

## Offene Fragen an den Nutzer

1. Startseite: A, B oder C, oder eine Mischung (z. B. die Wand als Hintergrund hinter A)?
2. Controller-Test oben, Tipps darunter: passt die Anordnung?
3. Während Steams Anmeldefenster: rechte Hälfte blass und angehalten oder ganz ausblenden?
4. Tipps alle 7 Sekunden?
5. Detailzeilen links: so dezent oder auffälliger?
6. Vorschläge bis drei gespielte Spiele?

Antworten: noch offen.

## Quellcode des Entwurfs

Eine Kopie liegt im Notizordner dieser Sitzungsgruppe unter `design-setup-home/`:

- `mp/setup/src/…` ist die Einrichtung. `mp/home/src/…` enthält die Startseite: `HomeStage.tsx`,
  `HomeThree.tsx`, `HomeWall.tsx`, den ersten Entwurf `NightforgeHome.tsx` und das Gemeinsame in `HomeParts.tsx`
  und `homeData.ts`.
- `mp/shared/` enthält Glas-CSS (nach `Glass.swift`), Icons, Top- und Hinweisleiste, Controller-Test und Tipps.
- `preview/build.sh` und `preview/review.sh` bauen die Seiten (React 18.3.1, Tailwind 4.1.11, esbuild),
  `npm install` vorher in `preview/`.
