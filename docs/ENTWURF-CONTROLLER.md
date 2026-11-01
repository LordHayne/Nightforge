# Entwurf: Die Controller-Steuerung als Ganzes

Stand 1.11.2026. Nur Analyse und Vorschlag. Am Code der Steuerung ist nichts geändert. Gebaut wird erst nach dem OK
des Nutzers und nach dem Merge des TV-Zweigs.

**Anlass:** Beim TV-Test am 1.11. öffnete ↓ auf der Startseite die Bibliothek. Der Nutzer wünscht: „die ganze
Controllersteuerung in Nightforge nochmal überprüfen und schauen, ob sie logisch ist“.

**Gelesen auf:** `claude/ux-roadmap-next` (7f0ac95) mit `claude/tv-fullscreen-61ab1e` (9319ca3) und
`claude/game-metadata-a2cee0` (4aa23d2), lokal zusammengeführt (7c24277). Der einzige Konflikt lag in
`InputRouter.swift`. Der rechte Stick und sein Timer scrollen dort nur bei `reach == .app`. Der Build
(`swift build`) läuft durch.
Quellen: `InputRouter.swift`, `PadFocus.swift`, `LibraryModel.swift` (`move`, `moveRow`, `jump`, `activate`,
`back`, Route), `Navigation.swift`, `PadDrawing.swift` (Controller-Test), `GameOverlay.swift`, die `HintBar` in
`LibraryView.swift`, alle `.padFocus`-Stellen, `docs/ROADMAP.md` (Phase 0 und 5) und `docs/TODO.md` (Controller).

**Tasten:** Xbox-Namen, DualSense in Klammern: A (✕), B (○), X (□), Y (△), LB/RB (L1/R1), LT/RT (L2/R2),
LS/RS (L3/R3), ☰ (Options), ⧉ Ansicht (Create), Xbox-Taste (PS). „Rahmen“ ist die Pad-Markierung von `PadFocus`.

## Kurz

- Die Grundidee trägt: A bestätigt, B geht zurück, L1/R1 wechseln fest zwischen Startseite und Bibliothek, Sheets
  und das Overlay sind sauber abgeschottet (`reach`, `dialog`), die sichere Antwort ist immer die Standardantwort.
- Das Hauptfenster hat kein klares Oben und Unten. Auf der Startseite führt ↑ zu den Knöpfen unten links, ↓ öffnet
  die Bibliothek, und von der oberen Leiste geht ↓ an den Spielen vorbei zu den Knöpfen. `PadFocus` kennt nur
  die Lage auf dem Bildschirm, keine Bereiche.
- **Ein echter Fehler, in einer Sonde bestätigt:** Die Bibliothek bleibt unsichtbar hinter einer Spielseite stehen,
  die aus ihr geöffnet wurde, und ihre Chips bleiben für das Pad erreichbar. Dann markiert das Pad einen
  unsichtbaren Chip, und A stellt unsichtbar Store oder Sortierung um.
- B braucht oft zwei Drücke: Auf der Spielseite und im Download-Panel nimmt der erste nur den Rahmen weg.
- Das Download-Panel ist keine eigene Ebene. X, Y, ☰ und L2/R2 wirken auf die Spiele dahinter.
- ☰ macht dasselbe wie L1/R1. Konsolen nutzen ☰ für die Optionen eines Spiels.
- Der Vorschlag: feste Bedeutungen je Taste, drei Bereiche im Hauptfenster (obere Leiste, Spiele, Knöpfe bzw.
  Filterzeile), Panels als eigene Ebenen, B immer genau eine Ebene. Dazu fünf Fragen an den Nutzer (Abschnitt 7).

---

## 1. Bestandsaufnahme

Steuerkreuz und linker Stick tun überall dasselbe. Gehalten wiederholen sie: erster Schritt sofort, nach 0,38 s
alle 0,11 s. Die stärkere Achse gewinnt. Ohne Rahmen bewegt das Pad die Spiele (`LibraryModel.move`/`moveRow`).
Mit Rahmen springt `PadFocus.move` zum nächsten Bedienelement in der Richtung, nur nach der Lage auf dem Bildschirm.

### 1.1 Hauptfenster

| Taste | Startseite: Spiele | Startseite: Knöpfe, obere Leiste (Rahmen) | Bibliothek: Raster | Bibliothek: Kopf, Filterzeile, Leiste (Rahmen) | Filter-Panel offen | Spielseite | Großbild | Download-Panel offen |
|---|---|---|---|---|---|---|---|---|
| A | Spielen (oder Laden); auf „Alle Spiele“: Bibliothek | drückt den Knopf | Spielseite | Store-Chip: nächster Store; Sortier-Chip: nächste Sortierung; Filter-Chip: Panel auf; Suchfeld: Textcursor | Schalter um | ohne Rahmen: Spielen/Laden; mit Rahmen: der Knopf | schließt | der Knopf (×, Abbrechen mit Rückfrage) |
| B | nichts (während ein Start wartet: abbrechen) | Rahmen weg, zurück zu den Spielen | Suche leeren, dann Ausgeblendete aus, dann Startseite | Rahmen weg, zurück ins Raster | Panel zu, Rahmen zurück auf den Chip | mit Rahmen: **erst nur Rahmen weg**, dann zurück | schließt | mit Rahmen: **erst nur Rahmen weg**, dann Panel zu |
| X | Spielseite | Spielseite | Spielseite (wie A) | Spielseite, **der Rahmen bleibt auf dem nun unsichtbaren Chip** | Spielseite, Panel zu | nichts | nichts | Spielseite hinter dem Panel |
| Y | Optionen | Optionen | Optionen | Optionen | Optionen über dem Panel | Optionen | Optionen über dem Großbild | Optionen über dem Panel |
| ☰ | Bibliothek | Bibliothek | Startseite | Startseite | Startseite, Panel zu | wechselt zur jeweils anderen Ebene | wechselt die Ebene | wechselt die Ebene, Panel bleibt offen |
| L1 / R1 | nichts / Bibliothek | nichts / Bibliothek | Startseite / nichts | Startseite / nichts | Startseite, Panel zu / nichts | Startseite / Bibliothek | Ebene, Großbild zu | nichts |
| L2 / R2 | erstes Spiel / „Alle Spiele“ | Auswahl springt hinter dem Rahmen | erstes / letztes Spiel | Auswahl springt hinter dem Rahmen | Auswahl springt im Raster dahinter | nichts | nichts | Auswahl springt dahinter |
| ← → | Spiel wechseln | zwischen den Knöpfen | nächstes Spiel, über Zeilenenden | zwischen den Chips | nichts | erster Druck: Rahmen auf „Spielen“, dann zwischen den Knöpfen | voriges / nächstes Bild | mit Rahmen im Panel, ohne: die Spiele dahinter |
| ↑ | Rahmen auf „Spielen“ **unten links**, oder auf den Knopf einer Meldung, falls eine da ist | nach oben bis zur oberen Leiste | eine Reihe hoch; aus der obersten: Filterzeile | Kopfzeile, dann obere Leiste | Zeile hoch, dann Chip, dann Leiste (Panel bleibt offen) | erster Druck: „Spielen“; dann aufwärts, oben die Leiste, dann scrollt die Seite hoch | nichts | mit Rahmen im Panel, ohne: „Spielen“ |
| ↓ | **öffnet die Bibliothek** | unter dem untersten Knopf: Rahmen weg, zurück zu den Spielen | eine Reihe runter | unter der Zeile: Rahmen weg, zurück ins Raster | Zeile runter; nach der letzten: Rahmen weg, Panel bleibt offen | abwärts; nach dem letzten Knopf scrollt die Seite | nichts | im Panel |
| Rechter Stick | nichts | nichts | scrollt das Raster, die Auswahl bleibt | scrollt das Raster | scrollt das Raster hinter dem Panel | scrollt die Seite | nichts | wie ohne Panel |

In allen Spalten gleich:
- **L3 + R3, 2 s halten** (ohne Stick-Tasten: ☰ + ⧉): Läuft ein Spiel im Hintergrund, kommt das Overlay über das Spiel,
  sonst passiert nichts.
- **⧉ (Ansicht/Create), Touchpad, L3 oder R3 allein:** nichts.
- **Xbox- bzw. PS-Taste:** gehört macOS (Game Overlay, Spiele-App).

„Spielseite“ meint auch „Über das Spiel“ und die Screenshot-Leiste. Dort drückt A „Über das Spiel ⌄“ (scrollt
hin) oder einen Screenshot (Großbild).

### 1.2 Sheets, Overlay und außerhalb

| Taste | Optionen eines Spiels | Einstellungen (alle Tabs) | Dialoge und Sheets | Ersteinrichtung mit Controller-Test | Overlay im Spiel | Spiel vorne | Nightforge nicht vorne, kein Spiel |
|---|---|---|---|---|---|---|---|
| A | erster Druck: Rahmen auf die gewählte Voreinstellung; dann drückt er | erster Druck: Rahmen auf **„ד oben rechts**; dann drückt er | erster Druck: Rahmen auf die sichere Standardantwort (ohne eine: auf „ד); dann drückt er | Hauptaktion der Seite (Loslegen, Rosetta installieren, Steam-Fenster wieder zeigen, Erneut versuchen, Los geht's), auch mitten im Controller-Test | die markierte Wahl (der Rahmen steht sofort) | dem Spiel | holt Nightforge nach vorne (der Druck wirkt sonst nicht) |
| B | Abbrechen, ohne Speichern | schließt | Esc, also Abbrechen bzw. × | Überspringen bzw. „Los geht's“ je Schritt, in der Checkliste nichts; mit Rahmen erst Rahmen weg | Menü: Weiterspielen; Frage: zurück zum Menü; beim Beenden nichts | dem Spiel | wie A |
| X | nichts | nichts | nichts | nichts | nichts | dem Spiel | wie A |
| Y | **schließt, ohne zu speichern** | nichts | nichts | nichts | nichts | dem Spiel | wie A |
| ☰ | nichts | nichts | nichts | nichts | nichts | dem Spiel | wie A |
| L1 / R1 | nichts | **nichts** (Tabs nur über ↑, ← →, A) | nichts | nichts | nichts | dem Spiel | nichts |
| L2 / R2 | nichts | nichts | nichts | Auswahl springt unsichtbar, sobald es Spiele gibt | nichts | dem Spiel | nichts |
| Steuerkreuz, linker Stick | nach Lage; ← → schalten Schalter | nach Lage; ← → ändern Schalter und Auswahlen (Sprache, Nach dem Start) | zwischen den Antworten | ↑: Rahmen auf die Knöpfe; ← → ↓ ohne Rahmen nichts | zwischen den Wahlen | dem Spiel | Steuerkreuz wie A, der Stick nicht |
| Rechter Stick | scrollt die Mitte | scrollt das Formular | scrollt die Mitte, wo sie scrollt | scrollt die Seite (kleines Fenster) | nichts | dem Spiel | nichts |
| L3 + R3, 2 s | – | – | – | – | Weiterspielen | Overlay auf | nichts |

Zu „Nightforge nicht vorne“: Es weckt nur ein frischer Druck, höchstens alle 2 s, und nur wenn die App vorne kein
Spiel ist (`LSApplicationCategoryType` games). Das gilt auch für Wines „Nightforge Game“, also auch für Steams
Anmeldefenster und Steam-Fragen unter Wine. Steam für Mac (ohne Kategorie) zählt nicht als Spiel.

Im Overlay bekommt das Spiel dieselben Drücke mit. Windows-Spiele sind darum angehalten.

### 1.3 Hinweise unten und andere Tastenhinweise

| Wo | Was heute dasteht (mit Pad) | Passt? |
|---|---|---|
| Startseite | A Spielen · X Details · ☰ Bibliothek · Stick Auswählen (auf „Alle Spiele“: A Öffnen) | ☰ ist der dritte Weg zur Bibliothek, das ☰-Symbol ist fest eingetragen und kommt nicht vom Pad. Y Optionen fehlt. |
| Bibliothek | A Öffnen · Stick Auswählen · B Startseite / Suche löschen / Alle Spiele | ja |
| Spielseite | A Spielen bzw. Herunterladen · Y Optionen · B Startseite bzw. Bibliothek | ja; der rechte Stick (Scrollen) fehlt |
| Mit Rahmen, überall im Hauptfenster | A Auswählen · Stick Bewegen · B Zurück | B „Zurück“ nimmt nur den Rahmen weg; auf der Spielseite geht es erst beim zweiten Druck zurück |
| Meldung mit Knopf | Stick-Symbol + „Rückgängig“, „Spielen“, „Download abbrechen“ oder „Zeigen“ | Es gibt keinen bestimmten Weg zum Knopf (siehe M2) |
| Ersteinrichtung | A + Aktion der Seite · B + Zurück-Aktion | ja |
| Großbild | keine; die Leiste liegt unter dem fast deckenden Großbild | ← → und B stehen nirgends |
| Filter-Panel | „B schließt“ im Panel | fest „B“, auf dem DualSense heißt die Taste ○ |
| Download-Panel | die Hinweise der Ebene dahinter | nein |
| Overlay | ○/B Weiterspielen · L3 R3 Halten: dieses Menü | ja |
| Controller-Test (`PadPart.meaning`) | ↓ „auf der Startseite geht’s nach unten in die Bibliothek“, rechter Stick „in Spielen meist die Kamera“, ☰ „Wechselt zwischen Startseite und Bibliothek“ | ↓ und ☰ passen nach dem Umbau nicht mehr. Der rechte Stick scrollt schon heute. |
| Einstellungen › Controller | „Im Spiel“: L3 + R3 | ja |
| Chips neben „Startseite \| Bibliothek“ | LB/RB bzw. L1/R1, nur mit Pad | ja |

### 1.4 Wege nur mit Maus oder Tastatur

- **Suche:** A aufs Suchfeld setzt nur den Textcursor. Ohne Tastatur kommt man nicht weiter (bekannt, TODO
  „Suche mit dem Controller“).
- **Listen der Chips „Alle Stores ▾“ und „Zuletzt gespielt ▾“:** Mit dem Pad schaltet A blind weiter. Die Listen mit
  den Zahlen öffnet nur die Maus.
- **Downloads:** nur über ↑ bis zur oberen Leiste, dann zum Ring. Das ist in Ordnung, Konsolen haben das auch oben.
- **Textfelder** (eigenes Wine, Startoptionen) und **macOS-Dialoge** (Ordner wählen): nur Tastatur und Maus.
  Das sind Expertenwege, die bleiben so.

---

## 2. Unstimmigkeiten, nach Schwere

### Schwer: Fehler, Sackgassen, Überraschungen

**S1. Unsichtbare Bibliotheks-Knöpfe auf der Spielseite (Fehler).**
Eine Spielseite aus der Bibliothek liegt über der Bibliothek. Die Bibliothek steht dahinter mit Deckkraft 0
(`SwipeLevel`, `keepsLibrary`), damit die Scrollposition bleibt. `PadFocus.entries` prüft aber nur `isHidden` und
`visibleRect`, nicht die Deckkraft. Eine Sonde im Scratchpad bestätigt das: In einem `NSHostingView` landete ↑ von
„Spielen“ auf einem Knopf unter `.opacity(0)`, der näher lag als die sichtbare Zurück-Pille. Zwei Wege führen dahin:
- *Sicher (Code-Pfad):* In der Filterzeile steht der Rahmen auf einem Chip, dann X. Die Spielseite öffnet sich, der
  Rahmen bleibt auf dem nun unsichtbaren Chip. Die Hinweise zeigen „A Auswählen“, und A stellt unsichtbar die
  Sortierung oder den Store um, statt zu spielen. Beim Suchfeld bekommt das unsichtbare Feld den Textcursor.
  Dann leert Esc die Suche, statt zurückzugehen.
- *Sehr wahrscheinlich:* ↑ von „Spielen“ auf der Spielseite. Die Filterzeile der Bibliothek liegt näher an
  „Spielen“ als die Zurück-Pille.

**S2. ↓ auf der Startseite öffnet die Bibliothek.**
Der Fund des Nutzers (`perform`: „Down on Home opens the library“). Das stammt aus der Zeit vor L1/R1 und ist heute
der dritte Weg zur Bibliothek. Die Tastatur macht es anders: ↓ tut auf der Startseite nichts. Der Controller-Test
erklärt das alte Verhalten noch.

**S3. Oben und unten sind auf der Startseite vertauscht.**
Die Bühne mit den Covern liegt in der Mitte rechts, die Knöpfe des Spiels liegen unten links, darüber ist die obere
Leiste. Das Pad geht aber so: Von den Covern führt ↑ zu „Spielen“ unten links, also nach unten. Ein zweites ↑ führt
zur oberen Leiste. Von dort führt ↓ an den Covern vorbei wieder zu „Spielen“, und ↓ unter „Spielen“ springt zurück
zu den Covern, also nach oben. Ist eine Meldung mit Knopf da, fängt diese das erste ↑ ab, weil sie das unterste
Bedienelement ist.

**S4. B braucht zwei Drücke.**
Im Hauptfenster nimmt B zuerst den Rahmen weg (`PadFocus.shared.clear()`), bevor es eine Ebene zurückgeht.
- *Spielseite:* Der Rahmen erscheint schon beim ersten Steuerkreuz-Druck. Danach ist der erste B-Druck nur „Rahmen
  weg“, ohne sichtbare Folge, obwohl der Hinweis „Zurück“ sagt. Erst der zweite geht zurück.
- *Download-Panel:* Das Wegnehmen des Rahmens kommt in der Reihenfolge vor dem Schließen des Panels. Dazwischen
  bewegt das Pad die Spiele hinter dem offenen Panel.

**S5. Das Download-Panel ist keine eigene Ebene.**
L1/R1 sind gesperrt, X, Y, ☰ und L2/R2 aber nicht. X öffnet die Spielseite hinter dem Panel. ☰ wechselt die Ebene,
und das Panel bleibt offen. Y legt die Optionen darüber. Ohne Rahmen führt ↑ zu „Spielen“, nicht ins Panel.
In das Panel kommt man nur über ↑↑ zum Ring und dann ↓.

### Mittel: Unlogisch oder unvollständig

**M1. ☰ ist doppelt belegt.** ☰ wechselt zwischen Startseite und Bibliothek, das tun schon L1/R1. Der Hinweis auf
der Startseite zeigt „☰ Bibliothek“, oben stehen die Chips L1/R1. Xbox und PlayStation öffnen mit ☰ bzw. Options das
Menü des gewählten Spiels.

**M2. Meldungen mit Knopf** („Rückgängig“ nach dem Ausblenden, „Spielen“ nach einem Download, „Download abbrechen“,
„Zeigen“). Der Hinweis zeigt das Stick-Symbol, aber erreichbar ist der Knopf nur zufällig: als unterstes
Bedienelement beim Einstieg mit ↑. Mitten im Raster der Bibliothek kommt man in den 5 Sekunden nicht hin. Auf der
Startseite und in der obersten Rasterzeile fängt die Meldung dafür das ↑ ab, das zu „Spielen“ bzw. zur Filterzeile
führen sollte.

**M3. Einstellungen ohne L1/R1, Einstieg auf „ד.** Die Tabs erreicht man nur über ↑ zur Tab-Reihe, dann ← → und A.
Der erste A-Druck setzt den Rahmen auf das oberste Bedienelement, das ist der Schließen-Knopf. Zweimal A schließt
also die Einstellungen. Ein `preferred` fehlt dort.

**M4. Die Chips der Bibliothek verhalten sich verschieden.** A schaltet beim Store- und beim Sortier-Chip blind
weiter, beim Filter-Chip öffnet A ein Panel. Panel und Listen halten den Rahmen nicht: ↓ nach der letzten Zeile
lässt ihn fallen, das Panel bleibt offen, und das Pad bewegt dann das Raster darunter. ↑ führt aus dem offenen Panel
bis in die obere Leiste.

**M5. Suche ohne Tastatur ist eine Sackgasse** (siehe 1.4).

**M6. Das Großbild ist halb eine Ebene.** ← → und B gehen. Y öffnet aber die Optionen darüber, und Hinweise gibt es
keine. A schließt, das ist harmlos, aber eine dritte Bedeutung von A.

**M7. Hinweise und Beschriftungen passen nicht überall** (Tabelle 1.3):
- „B schließt“ ist fest eingetragen.
- Das ☰-Symbol ist fest eingetragen.
- Auf der Spielseite fehlt der Hinweis zum rechten Stick.
- Mit Rahmen steht „B Zurück“ da, obwohl B nur den Rahmen wegnimmt.
- Der Controller-Test beschreibt ↓, ☰ und den rechten Stick falsch oder veraltet.
- `PadPart.name` kennt kein Nintendo-Layout. Auf einem Switch-Pad stehen dann A und B vertauscht, die Hinweisleiste
  selbst nimmt aber die richtigen Symbole vom Pad.

**M8. Der rechte Stick scrollt in der Bibliothek von der Auswahl weg.** Das Raster scrollt, die Auswahl bleibt, wo
sie war. Der nächste Steuerkreuz-Druck springt zurück dorthin.

**M9. Im Controller-Test lösen Tasten echte Aktionen aus.** Der Test sagt „Drück eine Taste“. A löst dabei auch die
Hauptaktion der Seite aus, je nach Schritt „Rosetta installieren“ oder „Steam-Fenster zeigen“ (Steam kommt nach
vorne). Für die Einrichtung ist das gewollt, im Test überrascht es.

### Klein

- **K1.** X in der Bibliothek tut dasselbe wie A. Das ist harmlos, die Bedeutung „Spielseite“ ist dieselbe.
- **K2.** L2/R2 bewegen die Auswahl hinter einem Rahmen oder Panel, und in der Ersteinrichtung bewegen sie sie
  unsichtbar. Auf der Spielseite tun sie nichts.
- **K3.** Y in den Optionen schließt ohne Speichern, also wie Abbrechen. Das kommt daher, dass Y ein Umschalter ist.
- **K4.** Wecken: L1/R1 wecken nicht, A/B/X/Y/☰/Steuerkreuz schon. Steams Fenster unter Wine zählen als Spiel, dort
  weckt das Pad nicht. Steams eigene Fragen bedient man aber ohnehin nicht mit dem Pad.
- **K5.** L3 + R3 halten, während Nightforge vorne ist und ein Spiel dahinter läuft: Das Overlay geht auf dem
  Spielbildschirm auf, nicht dort, wo man gerade schaut.
- **K6.** In `PadSymbols` heißt das X-Symbol `library`, gemeint ist „Details“. Das ist ein Überbleibsel.
- **K7.** In Dialogen zeigt der erste A-Druck nur, wo man ist. Das Overlay setzt den Rahmen dagegen sofort.
  Beides ist bewusst so, aber nicht einheitlich.

---

## 3. Das Regelwerk

### 3.1 Jede Taste hat eine Bedeutung

| Taste | Bedeutung, überall gleich |
|---|---|
| **A** | Drückt, was markiert ist. Ohne Rahmen: die Hauptaktion des gewählten Spiels (Startseite Spielen/Laden, Bibliothek Spielseite, Spielseite Spielen/Laden). Das ist so bestätigt (Phase 0) und bleibt. |
| **B** | Genau eine Ebene zurück, mit einem Druck und immer mit sichtbarer Folge (3.3). |
| **X** | Spielseite des gewählten Spiels. Auf der Spielseite und in Ebenen nichts. |
| **Y** | Suchen (Frage 2). |
| **☰** | Optionen des gewählten Spiels, wie das Menü eines Spiels auf Xbox und PlayStation (Frage 1). Ohne Spiel (Alle Spiele, Store-Treffer, Ersteinrichtung) und in Ebenen nichts. |
| **L1 / R1** | Tabs. Im Hauptfenster L1 Startseite, R1 Bibliothek, fest wie heute. In den Einstellungen voriger/nächster Tab. Sonst nichts. |
| **L2 / R2** | Anfang/Ende dessen, worin man gerade ist: Startseite erstes Spiel / „Alle Spiele“, Bibliothek erstes/letztes Spiel, Spielseite Seitenanfang/-ende. Sie holen einen Rahmen zurück zu den Spielen. In Ebenen nichts. |
| **Steuerkreuz, linker Stick** | Bewegen den Rahmen bzw. die Auswahl. Sie wechseln nie die Ebene (kein ↓ in die Bibliothek mehr). |
| **Rechter Stick** | Scrollt, wo etwas scrollt. Er bewegt nie den Rahmen. In der Bibliothek folgt die Auswahl (Frage 5). |
| **L3 + R3, 2 s** | Overlay über dem laufenden Spiel (ohne Stick-Tasten ☰ + ⧉). Wie heute. |
| **Xbox-/PS-Taste** | Bleibt bei macOS. Nightforge fasst sie nicht an, wie heute. Für die Startseite gibt es L1. |
| **⧉, Touchpad, L3/R3 allein** | In Nightforge frei. Create trägt unter macOS 27 die Bildschirmfoto-Gesten. |

### 3.2 Bereiche im Hauptfenster

Jede Ebene teilt sich in Bereiche, von oben nach unten. ↑/↓ wechseln den Bereich erst, wenn im Bereich nichts mehr
in dieser Richtung liegt. Innerhalb eines Bereichs bleibt es bei der Lage auf dem Bildschirm (`PadFocus.move`).

| Ebene | Bereiche von oben nach unten | Einstieg |
|---|---|---|
| Startseite | obere Leiste → **Spiele** (Bühne, ohne Rahmen) → Knöpfe des Spiels (Spielen, Details, Optionen, ggf. Akku-Einstellungen) | Spiele. ↑ führt zur Leiste (auf „Startseite“), ↓ auf „Spielen“. |
| Bibliothek | obere Leiste → Kopf (Suche, Ausgeblendet, Filterzeile, Store-Hinweis) → **Raster** | Raster. ↑ aus der obersten Reihe führt in den Kopf, auf den ersten Chip. |
| Spielseite | obere Leiste → **Seite** (alles von der Zurück-Pille bis zu den Karten unten) | Seite. Der erste Druck setzt den Rahmen auf „Spielen“. ↓ nach dem letzten Knopf scrollt weiter (wie heute). |

Unsichtbares gehört zu keinem Bereich. Das behebt S1 an der Wurzel. Meldungen gehören auch zu keinem (Frage 4).
Ein Ebenenwechsel nimmt den Rahmen mit. Der Rahmen springt nur dann mit, wenn die neue Ebene denselben Knopf hat
(„Spielen“ von der Startseite auf die Spielseite).

### 3.3 Ebenen für B

Von innen nach außen. B schließt immer die innerste Ebene:

1. Großbild
2. offene Liste oder offenes Panel (Filter, Stores, Sortierung, Downloads)
3. Sheet oder Dialog (Optionen, Einstellungen, Fragen), wie heute über Esc
4. ein Rahmen in einem Bereich der Startseite oder der Bibliothek, zurück zu den Spielen (auf der Spielseite gibt
   es diese Stufe nicht, dort geht B sofort zurück)
5. Suche, dann Ausgeblendete (Bibliothek)
6. Ebene: Spielseite zurück dorthin, woher sie kam; Bibliothek zur Startseite
7. Startseite: nichts. Wartet ein Start auf Steam, bricht B ihn ab (wie heute).

Ebenen 1 bis 3 sind abgeschottet. Steuerkreuz und rechter Stick bleiben darin, A und B gelten. L1/R1 gelten nur, wo
die Ebene Tabs hat. X, Y, ☰ und L2/R2 tun dort nichts. Beim Öffnen per Pad steht der Rahmen sofort auf der sicheren
Standardantwort, wie im Overlay. Diese Antwort ist nach der Regel in `GlassQuestion` nie die zerstörerische, also
kann A gleich wirken. Das löst K7 einheitlich.

### 3.4 Hinweise unten

Unten stehen höchstens vier Hinweise. Es stehen nur Tasten da, die hier etwas tun, alle mit dem Symbol des Pads
(`PadSymbols`, nie fest eingetragen). Ebenen 1 und 2 zeigen eigene Hinweise in der Ebene (Großbild:
„← → Weiter · B Schließen“; Panel: „B Schließen“).

---

## 4. Je Ort: was sich ändert und warum

| Ort | Soll | Warum |
|---|---|---|
| **Startseite, Spiele** | ↓: Rahmen auf „Spielen“ des gewählten Spiels. ↑: obere Leiste. ☰: Optionen. Y: Suchen. Hinweise: A Spielen · X Details · ☰ Optionen · Stick Auswählen. | Behebt S2 und S3. Oben ist oben, unten ist unten. Die Bibliothek bleibt bei R1 (und Kachel „Alle Spiele“). |
| **Startseite, Knöpfe** | ← → zwischen den Knöpfen; ↑ oder B: zurück zu den Spielen; ↓ nichts. | Der Bereich ist eine Zeile unter dem Spiel, wie der Spiel-Hub einer Konsole. |
| **Startseite, obere Leiste** | ← → durch die Leiste; ↓ oder B: zurück zu den Spielen, nicht an ihnen vorbei. | S3 |
| **Bibliothek, Raster** | wie heute; ☰: Optionen; Y: Suchen; rechter Stick: scrollt, Auswahl folgt. | M1, M8 |
| **Bibliothek, Kopf** | A auf allen drei Chips öffnet die Liste. In der Liste wählt A und schließt sie. Aktive Filter-Chips nehmen mit A den Filter weg (wie heute). ↓ aus dem Kopf: Raster. Eine Meldung fängt das ↑ nicht mehr ab. | M4: einheitlich, die Zahlen werden sichtbar. Blindes Weiterschalten zeigt nicht, was es noch gibt. |
| **Filter-Panel, Listen** | Eigene Ebene: Der Rahmen startet auf der gewählten Zeile und bleibt im Panel. ↓ nach der letzten Zeile tut nichts. B schließt. Unten steht „○ Schließen“ mit Pad-Symbol. | M4, M7 |
| **Spielseite** | B geht sofort zurück, auch mit Rahmen. Die unsichtbare Bibliothek ist nicht erreichbar. L2/R2: Seitenanfang/-ende. Hinweise: A Spielen · ☰ Optionen · rechter Stick Scrollen · B Zurück. | S1, S4, M7 |
| **Großbild** | ← → Bilder, A und B schließen, sonst nichts (kein Y). Eigene Hinweiszeile im Großbild. | M6 |
| **Download-Panel** | Eigene Ebene: per Pad geöffnet, steht der Rahmen im Panel. B schließt mit einem Druck. X, Y, ☰ und L2/R2 tun nichts. | S4, S5 |
| **Optionen eines Spiels** | Öffnen mit ☰. Darin: B Abbrechen, A, Steuerkreuz. ☰ oder Y schließen nicht mehr. | K3: Schließen ohne Speichern nur über B, das ist einheitlich mit allen Sheets. |
| **Einstellungen** | L1/R1 wechseln die Tabs. Der Rahmen startet auf dem aktiven Tab, nicht auf „ד. | M3 |
| **Dialoge und Sheets** | Der Rahmen steht sofort auf der Standardantwort. Sonst wie heute. | K7 |
| **Ersteinrichtung** | wie heute. Der Controller-Test erklärt A ehrlich: „Drückt den markierten Knopf – ohne Rahmen die Hauptaktion der Seite“. | M9, die kleinste Lösung |
| **Overlay im Spiel** | bleibt. Es folgt den Regeln schon (A, B eine Ebene, nur Steuerkreuz). | – |
| **Spiel vorne** | bleibt. | – |
| **Nightforge nicht vorne** | L1/R1 wecken auch. Die Sticks wecken nicht (sie werden leicht angestoßen). | K4 |
| **Meldungen mit Knopf** | Mit dem Pad nicht erreichbar, kein Pad-Hinweis. Das Angebot gibt es am Ort: Spielen über die Startseite, Ausgeblendete über „Ausgeblendet“, Abbrechen über das Download-Panel (Frage 4). | M2, ohne Fehlgriffe |

**Tastatur:** Die Tastatur bekommt keine Bereiche. Durch den Umbau stimmen Pad und Tastatur wieder überein:
↓ wechselt auf der Startseite nie die Ebene. Esc schließt das Download-Panel schon heute vor einer offenen Liste.
Die Reihenfolge von B gleicht sich daran an.

---

## 5. Änderungsliste je Datei

| Datei | Änderung |
|---|---|
| `Sources/Nightforge/PadRules.swift` (neu) | Das Regelwerk als reine Funktion, wie heute schon `InputRouter.section(for:…)` und `wakes(…)`: Eingabe (Ebene, Route, Bereich, Taste bzw. Schritt), Ergebnis (Rahmen bewegen, Bereich wechseln, Route, Ebene schließen, nichts). Dann ist die Tabelle aus Abschnitt 3 testbar. Heute ist `perform` privat und nicht testbar. |
| `InputRouter.swift` | `perform`: Startseite ↓ in den Knöpfe-Bereich statt `goLibrary()`, ↑ in die Leiste, Bereichswechsel über `PadRules`; Kommentar „Down on Home opens the library“ weg. B-Handler in der Reihenfolge aus 3.3, ohne „Rahmen weg“ auf der Spielseite, Download-Panel vor dem Rahmen. ☰ → Optionen (nur öffnen). Y → Suchen (Frage 2), schließt die Optionen nicht mehr. `goSection`: in den Einstellungen Tab-Schritt, sonst in Ebenen nichts. X/Y/☰/L2/R2 nur ohne offene Ebene (Download-Panel, Liste, Großbild dazu). L2/R2 auf der Spielseite: Seitenanfang/-ende. Rechter Stick in der Bibliothek: Auswahl folgt (Frage 5). `wakeIfIdle`: L1/R1 dazu. `PadSymbols`: `library` → `details`, neu `menu` (aus `buttonMenu.sfSymbolsName`) und `scroll` (rechter Stick), auch im Stil „PlayStation“. |
| `PadFocus.swift` | `Item.zone` und `Item.reachable` über zwei Modifier für ganze Teilbäume (`.padZone(_:)`, `.padReachable(_:)`, per Environment an `PadAnchor`). `entries` überspringt Unerreichbares (S1). `move(…, zone:)` bleibt im Bereich. `enter(zone:)` setzt den Einstieg: `preferred` des Bereichs, sonst die Regel von heute. Der Einstieg mit ↑ nimmt nie die Meldung und nie ein `*.close`, solange es anderes gibt. `page(toEnd:)` für L2/R2. |
| `LibraryView.swift` | `LibraryLevel`: `.padReachable(model.showingLibrary)` (S1). Bereiche: `TopBar` `.top`, `GameDetail(compact: true)` `.game`, `DetailLevel` `.page`, `DownloadsPanel` `.panel`, `ToastHost` unerreichbar. `HintBar` nach 3.4 und Abschnitt 4: Startseite mit ☰ Optionen statt Bibliothek, Spielseite mit Scrollen; im Rahmen-Modus sagt B, wohin es geht („Zu den Spielen“ bzw. „Startseite“/„Bibliothek“); bei offenem Panel „Schließen“; kein Pad-Hinweis für Meldungen; alle Symbole aus `PadSymbols`. |
| `LibraryFilterRow.swift` | `ChoiceChip`: A öffnet bei allen drei die Liste. Liste und Panel als Bereich `.panel` mit `preferred` auf dem gewählten Wert. „B closes“ → Pad-Symbol + „Schließen“. |
| `LibraryGrid.swift` | `Segmented` bekommt `preferred` für das gewählte Segment (Einstieg in den Einstellungen). Das Suchfeld bleibt, bis es eine Pad-Tastatur gibt. |
| `SettingsView.swift` | Tab-Schritt von L1/R1 annehmen (z. B. `model.settingsTabStep`). Einstieg auf dem aktiven Tab. |
| `Downloads.swift` | Panel als Bereich `.panel`. Per Pad geöffnet, steht der Rahmen darin. |
| `GameAbout.swift` | `ScreenshotLightbox`: eigene Hinweiszeile (← → Weiter, B Schließen) mit Pad-Symbolen. |
| `Glass.swift` | Nichts Neues nötig. `GlassCloseButton` ist nach der `PadFocus`-Regel kein Einstieg mehr. |
| `PadDrawing.swift` | `PadPart.meaning` neu: A („Drückt den markierten Knopf – ohne Rahmen spielt es auf der Startseite“), ↓ („auf der Startseite zu den Knöpfen des Spiels“), ☰ („Optionen für das gewählte Spiel“), Y („Suchen“), rechter Stick („Scrollt Seiten und Listen – in Spielen meist die Kamera“), L2/R2 („Springt an den Anfang/ans Ende“). `name(_:)`: das Nintendo-Layout (klein). |
| `LibraryModel.swift` | `settingsTabStep`; `openOptions()` für ☰ (dieselben Bedingungen wie heute `toggleOptions`); bei Frage 5 eine Auswahl, die dem Scrollen folgt (`selectNearestVisible`). |
| `Strings.swift` | Neue und geänderte Texte, Englisch und Deutsch. |
| `GameOverlay.swift`, `ControllerTest.swift`, `Toast.swift` | Keine Änderung an der Logik. In `Toast.swift` bleibt nur die Maus/⌘↩. |
| `docs/ROADMAP.md`, `docs/TODO.md` | Phase 0 nennt noch „☰ Home ↔ Bibliothek, Y Optionen“; die TODO beim Eintrag L1/R1 „L2/R2 und ☰ bleiben“. Nach dem Umbau anpassen. |

**Tests:**
- `tests/PadFocusTest`: Bereiche; ein Teilbaum unter `.padReachable(false)` ist nicht erreichbar, die Sonde aus
  dieser Analyse wird Testfall; der Einstieg mit ↑ überspringt Meldung und ×.
- neu `tests/PadRulesTest`: die Tabelle aus Abschnitt 3 und 4 als Fälle (Startseite ↓ wechselt die Route nicht,
  B auf der Spielseite mit Rahmen geht zurück, im Download-Panel tun X/Y/☰ nichts, L1/R1 in den Einstellungen …).
- `tests/StringsTest`: die neuen Texte auf Deutsch.
- **Live mit Pad** (DualSense und Xbox), nach dem Bau: jede Zeile aus Abschnitt 4 einmal. Dazu die Spielseite aus
  der Bibliothek mit ↑ von „Spielen“ und mit X aus der Filterzeile (S1).

**Reihenfolge und Aufwand:** Erst nach dem TV-Merge, weil die TV-Session gerade an `InputRouter` baut.
- **Schritt 1 (klein, ~½ Tag, unabhängig von den Fragen):** S1, die Reihenfolge von B (S4) und das Download-Panel
  als Ebene (S5). Das sind Fehler, die könnten noch in 0.3.0.
- **Schritt 2 (~1½ Tage, nach den Antworten):** Bereiche, neue Belegung von ☰/Y, Einstellungs-Tabs, Chips und Listen,
  Hinweise, Controller-Test-Texte, `PadRules` mit Tests.

---

## 6. Was bleibt, wie es ist

- L1/R1 im Hauptfenster: feste Richtung, auch von der Spielseite. Sie sind live bestätigt.
- A ohne Rahmen ist die Hauptaktion: Spielen auf der Startseite, die Spielseite in der Bibliothek. Das ist so
  entschieden (Phase 0), sicher für nicht geladene Spiele.
- X = Spielseite.
- `reach`: Im Spiel gehören die Tasten dem Spiel. Das Overlay, das Wecken, und die Xbox-/PS-Taste bei macOS.
- Rechter Stick: Tempo und Totzone (`stickSpeed`), nur bei `reach == .app`.
- Sheets über Esc, sichere Standardantworten, Schalter und Auswahlen mit ← →.

---

## 7. Offene Fragen an den Nutzer

1. **☰ öffnet die Optionen des gewählten Spiels** (statt zwischen Startseite und Bibliothek zu wechseln, das machen
   L1/R1)? *Empfehlung: ja.* So machen es Xbox und PlayStation, und ☰ ist heute doppelt belegt.
2. **Y wird „Suchen“**: Y springt in der Bibliothek ins Suchfeld. Die Glas-Tastatur fürs Pad aus der TODO-Idee kommt
  als eigener Schritt danach. *Empfehlung: ja.* Sonst wäre Y neben ☰ ein zweiter Weg zu den Optionen. Alternative:
  Y bleibt vorerst Optionen, bis die Tastatur da ist.
3. **↓ auf der Startseite führt zu den Knöpfen des gewählten Spiels** (Spielen, Details, Optionen), ↑ zur oberen
  Leiste mit Downloads und Einstellungen? *Empfehlung: ja*, so liegen die Bereiche auch auf dem Bildschirm.
4. **Meldungen mit Knopf** („Rückgängig“, „Spielen“): (a) mit dem Pad nicht erreichbar, das Angebot gibt es am Ort;
  (b) als unterster Bereich über ↓ erreichbar. *Empfehlung: (a)*, weil (b) beim Raster lange dauert und eine feste
  Taste mit „Spielen“ zu Fehlstarts führen kann.
5. **Rechter Stick in der Bibliothek:** (a) scrollen, die Auswahl folgt auf das Cover an derselben Stelle;
  (b) nur scrollen wie heute; (c) nichts. *Empfehlung: (a)*. Sonst zeigt das Raster etwas anderes, als A öffnet.
