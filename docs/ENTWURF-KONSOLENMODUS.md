# Entwurf: Die Anfrage „Konsolenmodus“ (0.4 „Wie eine Konsole“)

Stand 22.11.2026, Worker A für den Koordinator, Zweig `claude/konsolenmodus-035`. **Nur Entwurf, nichts gebaut.**
Thomas wählt die Variante. Canvas: `docs/entwuerfe/konsolenmodus/` (Heute, A, B, C).

Grundlagen: Thomas' Entscheidungen vom 22.11. (Controller-only ist hart; eine Anfrage „Konsolenmodus“, sobald ein
Controller erkannt wird, statt der heutigen Vollbild-Anfrage; im Konsolenmodus nie ein Dock; Lichtnaht auf dem
Ladescreen), `docs/ENTWURF-KONSOLE.md` (K5, TV, Fragen fürs Sofa), `docs/ENTWURF-LADESCREEN-KONSOLE.md` §6 und
`DockAutoHide` (Worker B, `claude/ladescreen-konsole-035`), `FullScreen.swift`, `FullScreenOffer.swift`,
`GameDisplay.swift`, `PadFocus`.

## 1. Heute (Vorher)

- **Wann:** `FullScreenOffer.offers` (LibraryModel `offerFullScreenIfDue`): Pad verbunden, Nightforge vorne, nicht im
  Vollbild, **nur am eingebauten Bildschirm**, nicht beim ersten Start, kein Spiel, nichts offen. **Einmal je
  Programmstart**: Nach jedem Neustart von Nightforge kommt die Frage wieder.
- **Was:** ein Blatt „Vollbild für den Controller?“ / „Nightforge füllt den Bildschirm, und der Schreibtisch des Macs
  geht aus dem Weg. ⌃⌘F schaltet zurück.“, Knöpfe „Nicht jetzt“ und „Vollbild“ (vorgewählt).
- **Ja** schaltet nur `FullScreen` ein. Das merkt sich `GameDisplay` je Bildschirm (`TVSettings.setFullScreen`).
- **Dock:** Im Vollbild ist es nur weg, solange Nightforge vorne ist. Auf Worker Bs Zweig schaltet `DockAutoHide` beim
  Spielstart macOS' „Dock automatisch ausblenden“ ein, **solange `FullScreen.isOn`** (LibraryModel, Spielstart), und
  stellt es zurück, wenn das Vollbild endet (`FullScreen.set(false)`), beim Beenden und nach einem Absturz.
- **Fernseher:** `GameDisplay` legt das Fenster auf den Fernseher und schaltet dort von selbst Vollbild
  (`wantsFullScreen`, Standard: bei einem TV). Beim Abstecken verlässt es ein Vollbild, das es selbst eingeschaltet hat.
- **Heraus:** grüner Knopf (im Vollbild ohne Titelleiste nicht zu sehen), ⌃⌘F, Ansicht › Vollbild und **Esc auf der
  Tastatur ganz oben** (InputRouter, Taste 53). Ⓑ auf dem Pad geht nur zurück und verlässt das Vollbild nie.

## 2. Wann die Anfrage kommt

**Vorschlag:** einmal überhaupt, nicht einmal je Programmstart.

- Ein Controller ist verbunden **und** Nightforge ist vorne, es läuft kein Spiel, nichts ist offen (Blatt, Menü,
  Tastatur), die Ersteinrichtung ist vorbei. Jeder Bildschirm zählt, auch der Fernseher; heute zählt nur der eingebaute.
- Ist bei der Ersteinrichtung schon ein Controller verbunden, kommt die Anfrage direkt nach „Los geht's“, nicht mitten
  in der Einrichtung.
- **Ja:** Der Konsolenmodus geht an und bleibt an, auch nach einem Neustart von Nightforge oder des Macs.
- **Nicht jetzt:** Nightforge fragt **nicht wieder von selbst**. Der Modus liegt danach im kleinen Menü oben rechts (⧉, dort
  wo Ein/Aus steht) und unter Einstellungen › Controller. Ob Nightforge nach einer Weile noch einmal fragt (etwa beim ersten Fernseher), ist eine
  offene Frage.
- Wer heute schon „Vollbild“ gewählt hat, wird einmal gefragt; das Vollbild je Bildschirm bleibt, wie es war.
- Ohne Controller gibt es keine Anfrage. Wer nur Maus und Tastatur nutzt, sieht nichts davon.

## 3. Was der Modus schaltet

Ein Schalter, `ConsoleMode.isOn` (gemerkt in den Einstellungen):

| | Konsolenmodus an | aus (wie heute) |
|---|---|---|
| **Vollbild** | Nightforge im Vollbild auf dem Bildschirm, auf dem es ist, auf jedem Bildschirm, auch nach dem Abstecken eines Fernsehers | je Bildschirm gemerkt, TV von selbst |
| **Dock** | nie zu sehen: Nightforges Vollbild hält es fern, solange Nightforge vorne ist; beim ersten Spielstart setzt `DockAutoHide` macOS' Einstellung (unter dem Vorhang, Wert gemerkt) | beim Spielen sichtbar, wenn das Spiel im Fenster läuft oder Steam vorne ist |
| **Menüleiste** | weg; kommt mit dem Zeiger am oberen Rand wie heute im Vollbild | wie heute |
| **Pad-Fokus** | der Rahmen steht sofort, auch ohne ersten Tastendruck | wie heute (`PadFocus`) |
| **Zeiger** | verschwindet, sobald das Pad benutzt wird (heutiges „Zeiger parken“); der Pad-Zeiger bleibt für Fenster, die eine Maus brauchen (Steam-Fragen) | wie heute, nach den Einstellungen |
| **Ladescreen** | Lichtnaht im Vollbild über allem | gleich (Lichtnaht), das Dock darf zu sehen sein |

Die Einstellungen des Spielers („Zeiger parken“, „Pad als Zeiger“) überschreibt der Modus nicht. Er schaltet nur
Vollbild und Dock. Der sofort sichtbare Fokusrahmen ist das Einzige, was er neu bringt.

## 4. Wie man herauskommt

- **Kleines Menü (⧉, oben rechts bei Ein/Aus) › „Konsolenmodus beenden“**: mit dem Pad, zwei Drücke.
- **Einstellungen › Controller › Konsolenmodus**: Schalter.
- **⌃⌘F, Ansicht › Vollbild**: Am Schreibtisch mit Tastatur beendet das den Konsolenmodus, nicht nur das Vollbild. Es
  bleibt ein Schalter, kein Vollbild ohne Konsolenmodus darunter.
- **Esc ganz oben:** beendet ihn **nicht** (eine Tastatur auf dem Sofa, ein versehentlicher Druck). Offene Frage.
- **Ⓑ** beendet ihn nie.
- Beim Beenden: Vollbild aus, Fenster in der alten Größe, das Dock nach `DockAutoHide.restore` wieder wie vorher.
  Eine Zeile: „Konsolenmodus aus.“

## 5. Fernseher, zweiter Bildschirm, Mac-Bildschirm

- **Fernseher angesteckt:** `GameDisplay` legt Nightforge wie heute auf den Fernseher. Im Konsolenmodus ist es dort
  sowieso im Vollbild.
- **Fernseher abgesteckt:** Nightforge kommt auf den Mac-Bildschirm und **bleibt im Vollbild**. Heute verlässt
  `leaveFullScreenOffTV` ein selbst eingeschaltetes Vollbild; im Konsolenmodus nicht (`GameDisplay.leavesFullScreen`
  fragt `ConsoleMode.isOn`).
- **Zweiter Bildschirm am Schreibtisch:** Der Modus gilt für den Bildschirm, auf dem Nightforge steht. Schiebt der
  Spieler das Fenster (nur ohne Vollbild möglich, also nach dem Beenden), gilt die heutige Regel. Die Dock-Einstellung
  gilt für alle Bildschirme: macOS kennt sie nur für den ganzen Mac. Ein Grund mehr, sie beim Verlassen zurückzustellen.
- **Mac-Bildschirm mit Notch:** Inhalt unter der Notch wie heute (`FullScreen.fit`).
- **Zugeklapptes MacBook am Fernseher:** wie „Fernseher angesteckt“.

## 6. Wo es an DockAutoHide hängt: eine Stelle

`DockAutoHide` bleibt, wie Worker B es baut. Es ändert sich nur, **wer** es anstößt:

- **Spielstart** (Worker B: LibraryModel, `if FullScreen.isOn { DockAutoHide.run({ DockAutoHide.engage($0) }) }`) wird
  `if ConsoleMode.isOn { … }`. Das ist die eine Stelle.
- **Zurückstellen:** von `FullScreen.set(false)` nach `ConsoleMode.set(false)` verschoben. Das Zurückstellen beim
  Beenden von Nightforge und nach einem Absturz (App.swift) bleibt.
- `ConsoleMode` (neu, klein): `isOn` (gemerkt), `set(_:)` schaltet `FullScreen` und beim Verlassen
  `DockAutoHide.restore`. `FullScreen.toggle()` ruft im Konsolenmodus `ConsoleMode.set(false)`.

## 7. Die Varianten der Anfrage (Canvas)

Alle drei sind mit dem Pad bedienbar: Ⓐ wählt, Ⓑ ist „Nicht jetzt“, der Fokus steht auf „Konsolenmodus“.

- **A · Die Frage wie heute** (Empfehlung): das bekannte Glasblatt mit neuem Text. Kleinster Bau, bekanntes Muster
  (`GlassQuestion`, `padFocus`).
- **B · Eine eigene Seite:** einmalig über die ganze Seite, Lichtnaht oben, darunter zwei Pad-Knöpfe. Fühlt sich am
  meisten nach Konsole an, ist aber ein eigener Bildschirm zum Bauen und Prüfen.
- **C · Eine leise Leiste:** unten eine Zeile „Controller verbunden – ⧉ für den Konsolenmodus“, nach 12 s weg. Sie
  unterbricht nichts, wird aber leicht übersehen. Nach Thomas' Regel „eine Anfrage“ ist sie die schwächste.

### Texte (Deutsch / Englisch)

⧉ steht hier für die Ansicht-Taste (Create bei DualSense, View bei Xbox). Auf dem Bildschirm zeigt Nightforge das
Zeichen des Controllers in der Hand (`PadGlyph`).


| Stelle | Deutsch | Englisch |
|---|---|---|
| A Titel | Konsolenmodus? | Console mode? |
| A Zeile | Nightforge füllt den Bildschirm und hält das Dock auch beim Spielen fern. | Nightforge fills the screen and keeps the Dock away while you play, too. |
| A, B Knöpfe | Nicht jetzt · Konsolenmodus | Not Now · Console Mode |
| B Titel | Mit dem Controller spielen | Play with the controller |
| B Zeile | Im Konsolenmodus füllt Nightforge den Bildschirm, das Dock bleibt weg. | In console mode Nightforge fills the screen, and the Dock stays away. |
| C Leiste | Controller verbunden – ⧉ für den Konsolenmodus | Controller connected – ⧉ for console mode |
| nach Ja (Hinweis, 4 s) | Konsolenmodus an. Beenden im Menü ⧉. | Console mode on. Leave it from the ⧉ menu. |
| nach dem Beenden | Konsolenmodus aus. | Console mode off. |
| Eintrag im kleinen Menü (⧉) | Konsolenmodus beenden / Konsolenmodus | Leave Console Mode / Console Mode |
| Einstellungen | Konsolenmodus – Vollbild auf jedem Bildschirm, das Dock bleibt beim Spielen weg. | Console mode – full screen on every screen, the Dock stays away while you play. |

„Nicht jetzt“ und „Not Now“ gibt es schon. Die Vollbild-Anfrage („Full screen for the controller?“) entfällt mit ihren
beiden Texten.

## 8. Was ein Bau braucht (zur Einschätzung)

- `ConsoleMode.swift`: Schalter, Regel „wann fragen“ als reine Funktion (ersetzt `FullScreenOffer`), Merker „gefragt“.
- `LibraryView`/`LauncherViews`: Blatt (A), Eintrag im kleinen Menü neben Ein/Aus, Einstellungen › Controller.
- `FullScreen.toggle`, `GameDisplay.leavesFullScreen`, Esc-Regel, die eine Stelle bei `DockAutoHide`.
- Tests: Fragen-Regel (erster Controller, einmal, nicht bei Spiel/Blatt/Einrichtung, jeder Bildschirm), Schalter
  (Vollbild, Dock-Rückstellung, TV abstecken bleibt im Vollbild, ⌃⌘F beendet, Esc nicht).
- Abhängig von Worker Bs Merge (`DockAutoHide`).

## Offene Fragen an Thomas

1. **Variante:** A (Glasblatt, Empfehlung), B (eigene Seite) oder C (leise Leiste)?
2. **Nach „Nicht jetzt“:** nie wieder von selbst fragen (Vorschlag), oder einmal noch, zum Beispiel beim ersten
   Fernseher?
3. **Esc ganz oben auf der Tastatur:** soll es den Konsolenmodus beenden (wie heute das Vollbild) oder nicht (Vorschlag)?
4. **Konsolenmodus nach dem Mac-Neustart:** bleibt er an (Vorschlag) und öffnet Nightforge gleich im Vollbild, auch am
   Schreibtisch ohne Controller?
5. **Fokusrahmen sofort sichtbar** im Konsolenmodus, auch bevor ein Knopf gedrückt wurde: ja?
6. **Ersteinrichtung mit Controller:** Anfrage direkt nach „Los geht's“ (Vorschlag), oder schon als Teil der Einrichtung?
