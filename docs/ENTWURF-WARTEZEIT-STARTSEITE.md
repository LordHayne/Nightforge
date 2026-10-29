# Entwurf: Wartezeit beim ersten Start und Startseite für Neue

Stand 29.10.2026. Umsetzung erst nach dem OK des Nutzers und nach dem Merge von 6.1
(`claude/first-start-6-1-18d92f`), denn beide Teile hängen an `SetupView.swift` und `LibraryView.swift`.

- **Entwurf zum Anklicken:** https://claude.ai/artifact/Hg1m1YCMvxdowvHwp8c7rp (privat, in 1512 × 853 pt, mit
  Umschaltern für jeden Zustand). Tabs: 1 · Einrichtung, 2a · Ruhig (der erste Entwurf), 2b · Wand, 2c · Kino,
  2d · Bühne, 2e · Drei für heute.
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
- **Echte Umrisse:** Der DualSense ist zweifarbig, mit einer hellen Schale samt langen Griffen und einem dunklen
  Kern (`PS_BODY`, `PS_CORE`), dazu das große Touchpad (`PS_TOUCHPAD`) und die Lichtleiste an beiden Seiten.
  Der Xbox Wireless Controller ist rundlicher, mit kürzeren Griffen und versetzten Sticks, einer zur Xbox-Taste
  ansteigenden Oberkante und der Share-Taste in der Mitte (`XB_BODY`). Keine Logos.
- **Schultertasten: Tasten-Chips** (Entscheid des Nutzers, 29.10.: „sieht am besten aus“). Vier Glas-Chips
  „L1 L2 · R1 R2“ (Xbox: „LB LT · RB RT“) sitzen direkt über der Oberkante des Pads, links und rechts über den
  Griffen, im Stil der Tasten-Chips der Hinweisleiste (`Key`, 24 pt hoch, Glas). Gedrückt leuchten sie in Sodium.
  L2/R2 füllen sich vorher von links mit dem Druck (`leftTrigger.value`). Am Pad selbst gibt es dann keine
  Schulterformen, also braucht die App kein eigenes Grafik-Asset, Pfade für Körper und Tasten reichen.
  - Verworfen (bleiben im Entwurf nur zum Vergleich): „Lichtkanten“ (L1/R1 als leuchtendes Stück der Oberkante,
    L2/R2 als Balken neben den Griffen) und „Gekippt“ (Pad um 16° geneigt, mit sichtbarer Oberseite; hätte ein
    SVG/PDF-Asset gebraucht). Davor schon verworfen: „Bügel“, „Mit Abstand“, „Seitlich“ (Pad von vorn, Schultern
    wie von oben).
- Entschieden (29.10.): Die Startseite wird **2d · Bühne** in der überarbeiteten Fassung (Version 5 des Entwurfs,
  „das ist auch eleganter“), die Schultertasten werden **Tasten-Chips**.
- **Akku nur einmal:** „Akku 80 %“ steht unter dem Pad. Der Chip „DualSense · 80 %“ unten links fällt im
  ersten Start weg (`HintBar` ohne Controller-Chip), auf der Startseite bleibt er.

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

## 2. Startseite für Neue: fünf Richtungen

Das Urteil des Nutzers über die heutige Startseite nach dem ersten Start: „sieht langweilig aus“, „zu leer“.
Deshalb gibt es neben der ruhigen Variante (2a) vier mutige Richtungen, jede vor und nach dem ersten Spiel. Welche es wird, entscheidet der
Nutzer. Für alle gelten dieselbe Wahl, dieselben Daten und dieselbe Regel nach dem ersten Spiel (unten unter
„Erster Entwurf“).

- **2c · Kino** (`HomeKino.tsx`): Das ganze Fenster ist das Bild des Spiels und bewegt sich langsam wie die
  erste Einstellung eines Films. Dazu gehören eine Kamerafahrt (Ken Burns, 26 s), Horizonte, die gegeneinander
  gleiten, Staub, Lichtstrahlen und Filmkorn. Der Titel steht groß in 86 pt, darunter ein Band aus breiten
  Standbildern (220 × 124 pt). Die guten Starts wechseln sich alle 9 s als Hauptbild ab, eine Linie im gewählten
  Bild zeigt die Zeit, und eine Berührung hält es 15 s an. Nach dem ersten Spiel bleibt das gespielte Spiel stehen.
  In der App wird die gezeichnete Landschaft zu Steams `library_hero.jpg` und der Titel zu `logo.png`. Beides
  lädt `Artwork.swift` schon (`ArtworkKind.hero`, `.logo`). Die Kamerafahrt ist dann ein langsames
  `scaleEffect`/`offset` auf dem Bild, ohne Hero-Bild braucht es einen Ersatz (z. B. das Cover groß und
  weichgezeichnet).
- **2d · Bühne** (`HomeStage.tsx`), **die Favoritin des Nutzers** („was modernes, was einen nicht erschlägt,
  trotzdem einladend, und etwas, was nicht jede x-beliebige App hat“, 29.10.). Die guten Starts stehen als
  Cover-Flow. Das gewählte Cover steht groß vorn (320 × 480 pt, bei 44 % der Bühnenbreite, also nah an der
  Fenstermitte). Es schwebt leicht, ein Lichtstreif zieht über das Glas, und darunter liegt ein weicher Schimmer
  in der Farbe des Spiels, kein Spiegelbild. Die anderen Cover drehen sich um 56° weg: links bis zu zwei, rechts
  bis zu drei, mit 252/372/492 pt Abstand, Helligkeit 0,40/0,32/0,26, leicht weichgezeichnet und ohne Titel.
  An den Rändern blendet eine Maske sie aus, statt sie abzuschneiden. Hinter allem liegt das Hintergrundbild des
  Spiels (`library_hero.jpg`), 30 pt weichgezeichnet, mit einem kaum merklichen Zoom über 60 s. Darüber kommt das
  Farblicht des Covers. Links stehen Titel, Abzeichen, Warum-Satz, Werte und der Knopf („Herunterladen“ oder
  „Spielen“, ohne Größe, die steht in den Werten). Unter der Bühne steht „Für den Anfang · 2 von 11“ mit
  Pfeilen. In SwiftUI: ein `ZStack` mit `rotation3DEffect`, `offset`, `zIndex` und `blur` je Abstand zur
  Auswahl, der Hintergrund als `Image` mit `.blur(radius: 30)`.
- **2e · Drei für heute** (`HomeThree.tsx`): eine Wahl aus drei großen Covern, jedes mit seinem Grund („Am
  schnellsten bereit“ = kleinster Download, „Gemacht für den Mac“, „Am besten bewertet“ = Metascore). Das gewählte
  tritt vor und neigt sich zum Mauszeiger, seine Farbe leuchtet dahinter. Unten steht eine Leiste „Mehr für den
  Anfang“. Nach dem ersten Spiel steht links „Weiterspielen“. In SwiftUI: `rotation3DEffect` und
  `onContinuousHover` für das Neigen.
- **2b · Wand** (`HomeWall.tsx`): die ganze Bibliothek als schräge Cover-Wand, sieben Reihen, die langsam
  gegeneinander gleiten (110–210 s je Durchlauf). Was super läuft, ist hell, der Rest liegt bei 30 % Helligkeit.
  Davor eine Scheibe aus dickem Glas (`Glass.thick`) mit „22 deiner 100 Spiele laufen hier“ und „Fang hiermit an“.
  Glas-Schilder an der Wand öffnen die gefilterte Bibliothek. In SwiftUI muss die Wand eine gezeichnete Ebene
  sein (`Canvas` in `TimelineView` oder `drawingGroup()`), sonst ruckelt sie bei 100 Covern. Bei kleinen
  Bibliotheken wiederholen sich die Cover.
- Alle halten bei „Bewegung reduzieren“ still (`Accessibility.swift`): kein Schweben, kein Gleiten.

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

## Für die Umsetzung der Bühne (2d)

- **Echte Steam-Cover statt der gezeichneten:** Die Platzhalter im Entwurf sind dunkel. Echte Cover
  (`library_600x900`) können hell sein. Prüfen, dass ein helles Cover die Textspalte links und die Glas-Leiste
  nicht überstrahlt, und wo nötig das Licht dämpfen oder einen Schleier davor legen (z. B. den Verlauf links
  dunkler und den Farbschein schwächer bei hellen Covern). Dasselbe für die hinteren Cover, die ohnehin
  abgedunkelt und entsättigt sind.
- **Der weichgezeichnete Hintergrund ist ein fertiges Bild:** das Hintergrundbild (`library_hero.jpg`) einmal
  je Spiel weichzeichnen (z. B. Core Image, `CIGaussianBlur`, auf etwa Fenstergröße verkleinert) und im Cache
  neben den anderen Bildern ablegen. Nie als lebender Blur-Filter über das ganze Fenster, wegen des Akkus. Der
  langsame Zoom ist nur ein billiges `scaleEffect` auf diesem Bild. Bei „Bewegung reduzieren“ entfällt er.

## Offene Fragen an den Nutzer

1. Startseite: welche von 2a bis 2e, oder eine Mischung (z. B. das Kino-Bild mit der Wahl aus drei davor)?
2. Controller-Test oben, Tipps darunter: passt die Anordnung?
3. Während Steams Anmeldefenster: rechte Hälfte blass und angehalten oder ganz ausblenden?
4. Tipps alle 7 Sekunden?
5. Detailzeilen links: so dezent oder auffälliger?
6. Vorschläge bis drei gespielte Spiele?

Beantwortet: Frage 1 (2d · Bühne). Die Schultertasten sind entschieden (Tasten-Chips). Die übrigen Fragen
sind noch offen.

## Quellcode des Entwurfs

Eine Kopie liegt im Notizordner dieser Sitzungsgruppe unter `design-setup-home/`:

- `mp/setup/src/…` ist die Einrichtung. `mp/home/src/…` enthält die Startseite: `HomeStage.tsx`,
  `HomeThree.tsx`, `HomeWall.tsx`, `HomeKino.tsx`, den ersten Entwurf `NightforgeHome.tsx` und das Gemeinsame in `HomeParts.tsx`
  und `homeData.ts`.
- `mp/shared/` enthält Glas-CSS (nach `Glass.swift`), Icons, Top- und Hinweisleiste, Controller-Test und Tipps.
- `preview/build.sh` und `preview/review.sh` bauen die Seiten (React 18.3.1, Tailwind 4.1.11, esbuild),
  `npm install` vorher in `preview/`.
