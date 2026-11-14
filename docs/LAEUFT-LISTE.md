# Die Läuft-Liste: was sie behauptet und wie gemessen wird

Idee vom 14.11.2026: eine Liste der Spiele, die unter Nightforge eindeutig starten und laufen, mit Messwerten – als
Referenz für die Community und die Landingpage. Dieses Dokument legt fest, was ein Eintrag behauptet, woher er kommt
und was seine Zahlen bedeuten. Die Liste selbst erzeugt `scripts/laeuft-liste.py` nach `docs/laeuft/`
(`laeuft.json` für Werkzeuge, `LAEUFT.md` für Menschen). Niemand trägt von Hand ein.

Leitsatz: Eine Zahl ohne ihre Bedingungen ist keine Referenz. Was keine Aufzeichnung hergibt, heißt „nicht gemessen“.

## 1. Quellen

Nur Nightforges eigene Aufzeichnungen. Nichts aus AppleGamingWiki, PCGamingWiki, CodeWeavers, ProtonDB oder Highball.

| Quelle | Was sie belegt | Was ihr fehlt |
|---|---|---|
| Start-Evidenz (`start-evidence.jsonl`, `StartEvidence.swift`) | je Start: Spiel, Weg, winecx-Stand, Chip und macOS, Ausgang (`worked`, `failed`, `ended`, `gaveUp`) | Nightforge-Version, Spielname, Mac-Fassungen, Messwerte |
| Spieletest (`GameTests/<Datum>/report.json`, `GameTest*.swift`) | je Spiel: Bild ja/nein, Sekunden bis zum Bild, Wege, Messwerte im Spielfenster; je Lauf: Nightforge-Version, alle Engine-Teile, Last | bestätigt keinen Weg (siehe Stufen) |

Nicht benutzt: `wine.log` (rotiert bei 8 MB, keine dauerhafte Quelle – der Spieletest liest seinen Abschnitt daraus,
solange er frisch ist) und die bestätigten Wege in den Einstellungen der App (`LaunchHealth.confirmedWays`: ohne Datum
und Engine-Stand; die Evidenz hält dasselbe als `known` fest).

## 2. Stufen

Ein Eintrag gilt für **ein Spiel, eine Fassung (Windows oder Mac) und einen Mac** (Chip und macOS).

| Stufe | Bedingung in den Daten | Bedeutet |
|---|---|---|
| **läuft** | Die Evidenz hat für den Weg ein `worked` – das ist `LaunchHealth.verdict`: gemessene Frames oder 180 s mit Bild – oder einen Start mit `known: true` (der Weg war schon bestätigt, bevor die Aufzeichnung am 9.11.2026 begann). Und: Kein späterer Start desselben Wegs war wieder unbestätigt. | Nightforge startet das Spiel auf Automatik, es zeichnet, und Nightforge selbst hält den Weg für bewährt. |
| **startet** | Kein bestätigter Weg, aber ein Bild: Der jüngste Spieletest-Lauf des Spiels endete mit `picture`, oder die Evidenz hat ein `ended` mit `picture: true`, das jünger ist. | Es kam ins Bild. Ob es dabei bleibt, ist nicht belegt. |
| **Anti-Cheat** | Der jüngste Spieletest hat es mit `antiCheat` übersprungen. | Nightforge startet es nicht. Mehr sagt die Liste dazu nicht. |
| *versucht, bisher ohne Bild* | Starts oder Läufe ohne Bild. | Gehört nicht zur Liste. Steht in `LAEUFT.md` unten, damit die Liste nicht nur Erfolge zeigt; die Landingpage lässt es weg. |

Zu jeder Stufe gehört, **wie** sie erreicht wurde:

- **Beim wievielten Start, nach wie vielen Wegen** (`confirmed.starts`, `confirmed.ways`): gezählt bis zum ersten
  `worked`, nur für Spiele, die die Evidenz von ihrem ersten Start an kennt. „1. Start“ ist die Quote, um die es der
  Startlogik geht.
- **Vor der Aufzeichnung bestätigt** (`basis: known`): ohne Datum der Bestätigung und ohne Zählung. Die Tabelle sagt
  das wörtlich.
- **Bestätigung zurückgezogen** (`withdrawn`): Startet Nightforge einen bestätigten Weg wieder als unbestätigt
  (`LaunchHealth.unconfirm` nach zwei kurzen Enden, oder eine geänderte Wegeliste), fällt der Eintrag auf „startet“
  oder ganz heraus, bis ein neues `worked` kommt. So steht ABZU am 14.11. unter „startet“.
- **Fehlstarts danach** (`failedSince`): `failed` auf dem bestätigten Weg nach der Bestätigung. Der Eintrag bleibt
  „läuft“ (so hält es auch `StartEvidence.proofs`), der Hinweis steht dabei.
- **Spieletest-Quote** („Bild in 3 von 5“): alle Läufe, in denen das Spiel wirklich gestartet wurde. Sie steht auch bei
  „läuft“: Ein bestätigter Weg mit „Bild in 1 von 7“ ist ein ehrlicher Eintrag, kein glatter.

### Was nie zählt

- **Ein von Hand geformter Start.** Die Evidenz zeichnet nur Starts auf Automatik auf; wer in den Spieloptionen einen
  Grafikweg wählt, hinterlässt keinen Eintrag. Unsichtbar bleiben versteckte Engine-Schalter und Eingriffe in den
  Prefix: An einem Messabend sind sie tabu (Abschnitt 5).
- **Der Online-Teil eines Anti-Cheat-Spiels.** Solche Spiele werden nicht geprüft. Steht eines mit Anti-Cheat in der
  Evidenz (`kind.antiCheat`), trägt der Eintrag den Hinweis „nur der Start ist belegt, der Online-Teil nicht“.
- **Was ein Profil geformt hat, als Beweis für andere Spiele.** Für das Spiel selbst zählt es (Hinweis „mit Profil“).
- **Fremde Daten** und alles, was ein Mensch „gesehen hat“, ohne dass es aufgezeichnet wurde.
- **Mac-Fassungen als „läuft“:** Für sie gibt es keine Evidenz. Sie erreichen höchstens „startet“.

### Was jeder Eintrag nennt

| Angabe | Bei „läuft“ aus der Evidenz | Bei Messwerten aus dem Spieletest |
|---|---|---|
| Mac und macOS | `mac` des Starts | `mac` des Laufs |
| Engine | `engine` des Starts (nur `winecx@…`) | alle Teile (`winecx@…`, `graphics@…`, `d3dmetal@…` …), dazu `runsOn` |
| Nightforge-Version | **nicht aufgezeichnet** (Lücke, Abschnitt 8) | `nightforge` |
| Datum | `at` | Start des Spiels im Lauf |

Tage stehen in UTC, damit dieselben Daten auf jedem Mac dieselbe Liste geben.

## 3. Messwerte: was heute messbar ist

Stand 14.11.2026, Engine winecx 4.7.3. Geprüft am Code der Schichten und an den Logs dieses Macs.

| Weg | FPS Ø, tiefste Periode | Langsamster Frame | 1-%-Tief | Gezeichnete Auflösung |
|---|---|---|---|---|
| DXMT | ja: `[nightforge-dxmt]`-Zeile alle 10 s, nach zwei Minuten jede Minute | ja, einer je Periode | nein | nein; der Anzeigemodus, wenn das Spiel einen setzt |
| DXVK auf KosmicKrisp (Direct3D 9) und Vulkan-Spiele: Nightforges Vulkan-Schicht | ja: `[nightforge-vulkan]`, gleiches Format | ja, einer je Periode | nein | ja: Swapchain in Pixeln und MetalFX-Ziel |
| DXVK auf MoltenVK (Direct3D 10/11 unter winecx) | nein | nein | nein | nein |
| D3DMetal | nein | nein | nein | nein |
| WineD3D | nein | nein | nein | nein |
| Mac-Fassung | nein | nein | nein | nein |
| alle | Sekunden bis zum Bild; Fenstergröße und Bildschirm in Punkten (Zeile des Vorhangs); Frame-Limit, Bildwiederholrate, MetalFX an/aus (nur Windows-Fassungen); Last, Akku, Stromsparmodus | | | |

Der Spieletest schreibt das seit Berichtsformat 2 je Spiel mit Bild (`GameTestMeasure.swift`): `frames` mit `average`,
`low`, `periods`, `seconds`, `slowestFrame`, `slowestTypical`, `source`; `measure` mit `window`, `screen`, `swapchain`,
`upscaledTo`, `displayMode`, `frameLimit`, `refreshRate`, `metalFX` und `noFrames` (`wayReportsNone` oder `noneInLog`).
Berichte im Format 1 liest der Generator weiter; ihnen fehlen diese Felder, und die Liste sagt dann „nicht gemessen“.

### Was die Zahlen bedeuten

- **Messfenster:** vom ersten Frame bis zum Ende des Spielfensters (`playSeconds` nach dem ersten Bild). Das sind die
  ersten Minuten nach dem Start: Logos, Intro, Menü, vielleicht die erste Szene. **Keine feste Szene**, kein Benchmark.
- **Einstellungen:** die das Spiel mitbringt. Niemand stellt Grafik ein.
- **FPS Ø** ist nach Periodenlänge gewichtet. **Tiefste Periode** ist der schlechteste 10-Sekunden-Schnitt, kein
  1-%-Tief.
- **Frame-Limit:** „Scharf & flüssig“ hält ein Spiel auf 120 Hz bei 60 FPS. „59 FPS“ heißt dann „hält das Limit“,
  nicht „schafft nur 59“. Darum steht das Limit in jeder Zeile. Der Spieletest rechnet es so aus, wie der Start es
  tut, und liest es nicht aus dem Start selbst (Abschnitt 8).
- **Langsamster Frame:** „schlimmster“ ist der eine langsamste im ganzen Fenster, meist ein Lade-Ruckler. „Üblich“ ist
  der Median der langsamsten Frames je Periode und sagt mehr über das Spielgefühl.
- **Größe:** Die Fenstergröße in Punkten ist nicht die gezeichnete Auflösung (Retina und MetalFX liegen dazwischen).
  Pixel nennt nur die Vulkan-Schicht.
- **Vergleichbar** sind dieselben Spiele über Nightforge- und Engine-Stände auf demselben Mac, grob. Nicht vergleichbar:
  Spiele untereinander, und Läufe mit hoher Last, auf Akku oder im Stromsparmodus (alle drei werden markiert).

## 4. Der Generator

```bash
python3 scripts/laeuft-liste.py
```

Ohne Argumente liest er die Evidenz und alle Spieletest-Berichte dieses Macs (nur lesend) und schreibt
`docs/laeuft/laeuft.json` und `docs/laeuft/LAEUFT.md`. Mit `--evidence DATEI` (mehrfach möglich), `--names DATEI`,
`--out ORDNER` und Berichten oder Ordnern als Argumenten geht es auch anders, etwa mit `docs/spieletest`.

- **Deterministisch:** Gleiche Eingaben geben byte-gleiche Dateien. Kein Erzeugungsdatum; `dataUntil` ist der jüngste
  Zeitstempel der Eingaben. Derselbe Lauf zählt einmal, auch wenn er zusätzlich in `docs/spieletest` liegt.
- **Namen:** Die Evidenz kennt nur Schlüssel (`steam.35140`). Der Name kommt aus dem jüngsten Spieletest-Bericht, der
  das Spiel nennt (`nameFrom: report`); sonst aus `docs/laeuft/namen.json` (`nameFrom: names`, von Hand gepflegt,
  heute ein Eintrag: Batman); sonst steht der Schlüssel da, und der Generator meldet ihn.
- **Messung je Eintrag:** der jüngste Lauf mit Bild auf dem gelisteten Weg; gibt es keinen, der jüngste mit Bild
  überhaupt, mit dem Hinweis „Messung auf …“.
- **Datenschutz:** In die Liste gehen nur feste Felder – keine Notizen, Fehlerzeilen oder Gründe aus den Berichten.
  Vor dem Schreiben prüft der Generator beide Dateien auf Home-Ordner, Kontonamen und Laufwerke und schreibt sonst
  nichts. Was drinsteht: Spielnamen und Laden-IDs der getesteten Spiele, Chip, macOS, Wege, Zahlen, Tage.
- **Format:** `laeuft.json` hat `formatVersion: 1`, `dataUntil`, `sources` und `entries`. Je Eintrag: `key`, `store`,
  `storeID`, `name`, `platform`, `mac`, `level` (`laeuft`, `startet`, `anti-cheat`, `kein-bild`), `way`, `antiCheat`
  (wahr, falsch oder `null` für „nicht aufgezeichnet“), `confirmed`, `withdrawn`, `seen`, `evidence`, `gameTest`,
  `gameEngine`, `measured`, `notes`. Tests: `tests/test_laeuft_liste.py`.

## 5. Ein Messabend

Damit Zahlen von heute und von in vier Wochen nebeneinander stehen können:

1. **Mac:** am Netzteil, kein Stromsparmodus, interner Bildschirm (oder der Bildschirm wird genannt), keine anderen
   Apps, kein Build nebenher. Der Test wartet bis zu fünf Minuten auf niedrige Last und markiert den Rest.
2. **Nightforge:** der Stand, der gemessen werden soll, frisch gestartet. Alle Spiele auf Automatik, „Scharf & flüssig“
   wie ausgeliefert. Keine versteckten Engine-Schalter, kein Eingriff in den Prefix.
3. **Spiele:** unverändert, mit ihren eigenen Einstellungen. Zuerst die, die in der Liste fehlen oder nie im Spieletest
   waren (heute: Batman).
4. **Lauf:** `playSeconds` auf 200. Dann ist das Fenster lang genug für 180 s mit Bild – ein Erststart auf D3DMetal oder
   WineD3D kann so überhaupt bestätigt werden – und DXMT liefert etwa zwölf Perioden.

   ```bash
   defaults write io.github.lordhayne.nightforge gameTest.playSeconds -int 200
   ```

   ```bash
   defaults write io.github.lordhayne.nightforge gameTest -bool true
   ```

5. **Zweimal.** Der erste Lauf nach einem Engine-Wechsel übersetzt Shader und ist langsamer. Gewertet wird der zweite;
   der Generator nimmt ohnehin den jüngsten Lauf mit Bild.
6. **Danach:** `scripts/import-game-test.py` (Bericht ins Repository, mit Leck-Prüfung), `scripts/laeuft-liste.py`,
   die Tabelle ansehen, committen.

Nicht automatisch möglich ist dieselbe Szene. Wer die braucht, misst von Hand und trägt es **nicht** in diese Liste ein.

## 6. Vorschlag: Landingpage

Kein Eingriff in `site/` von hier aus; Gestaltung über ein Board und die Wahl des Nutzers.

- **Datei:** `docs/laeuft/laeuft.json`, beim Bau der Seite eingelesen. Nur `level` `laeuft` und `startet`.
- **Spalten:** Spiel (`name`), Laden (`store`), Stufe (`level` als Marke), Grafikweg (`way` in Klartext), „bestätigt
  am“ mit „beim 1. Start“ (`confirmed.at`, `confirmed.starts`), Bild nach (`measured.secondsToPicture`), FPS Ø mit dem
  Limit daneben (`measured.fps.average`, `measured.frameLimit`), „gemessen auf“ (`mac`, `measured.nightforge`,
  `measured.at`).
- **Immer dabei:** der Satz „Die ersten Minuten nach dem Start, mit den Einstellungen des Spiels, kein Benchmark“ und
  ein Link auf dieses Dokument. Hinweise (`notes`) als Fußnote, nie versteckt.
- **Weglassen:** langsamster Frame und Größe, solange die meisten Zeilen „nicht gemessen“ sagen.

## 7. Vorschlag: Beiträge aus der Community

Heute sagt `StartEvidence.swift` über die Evidenz: „It stays on this Mac.“ Das zu ändern ist eine Entscheidung des
Nutzers, kein Nebeneffekt dieser Liste.

- **Weg:** ein Export, den der Spieler selbst auslöst (im Problembericht oder als eigener Knopf): eine Datei mit den
  Feldern, die der Generator braucht – Schlüssel, Ereignis, Weg, Engine, Chip und macOS, Sorte, Nightforge-Version,
  Tag statt Uhrzeit. Ohne `reason` und `diagnosis` (Freitext, auch geschwärzt). Der Spieler sieht die Datei, bevor er
  sie abgibt. Nichts geht von selbst hinaus.
- **Annahme:** als Pull Request oder Issue-Anhang nach `docs/laeuft/community/`; der Generator nimmt schon mehrere
  Evidenz-Dateien und hält Macs auseinander.
- **Datenschutz:** nur Chip und macOS, keine Seriennummer, kein Rechnername, kein Konto. Wer meldet, zeigt, welche
  Spiele er besitzt: Das muss beim Export stehen. Epic- und GOG-Schlüssel sind Katalog-IDs, keine Konto-IDs.
- **Vertrauen:** Eine Datei beweist nichts. Darum getrennt ausweisen: „Nightforge-Testmac“ gegen „Community“; ein
  Community-Eintrag zählt erst ab zwei unabhängigen Meldungen für dasselbe Spiel und dieselbe Mac-Klasse; die Seite
  zeigt die Zahl der Meldungen, keine Namen. Messwerte aus der Community erst, wenn der Spieletest ohne Schalter
  auslösbar ist – sonst misst jeder anders.

## 8. Lücken und was dafür nötig wäre

Diese Stellen liegen in Dateien, die am 14.11. eine andere Session bearbeitet, und sind hier nur beschrieben:

1. **Evidenz ohne Nightforge-Version, Engine-Teile und Namen** (`StartEvidence.swift`, Aufruf in
   `LibraryModel.swift`): `started` sollte `nightforge`, die Teile (`graphics@…`, `d3dmetal@…`) und den Namen tragen.
   Der Generator liest `nightforge` schon, wenn es da ist.
2. **Frame-Limit im Log** (`LibraryModel.launch`): eine Zeile „held to 60 FPS, MetalFX on“ je Start. Heute rechnet
   `GameTestRun.held` es nach.
3. **Frames auf D3DMetal, MoltenVK und für Mac-Fassungen** (`Launcher.swift`/`Engine.swift`): Apples Metal-HUD kann
   protokollieren (im Log steht sein Menüpunkt „Enable Logging“). Zu prüfen, ob das unbeaufsichtigt und lesbar geht.
4. **1-%-Tief und gezeichnete Auflösung unter DXMT** (`engine/patches/dxmt-0.80-frame-log.patch`,
   `wrapper/nightforge-vulkan-layer.c`): ein Histogramm je Periode und eine Zeile zur Backbuffer-Größe. Braucht einen
   Engine-Build.
5. **Der Spieletest bestätigt bei 60 s keinen Weg** (steht schon in `docs/TODO.md`); am 10.11. blieb ABZU nach vier
   Läufen mit Bild und Frames ohne `worked`.
6. **Von Hand geformte Starts erkennen:** `started` könnte sagen, ob ein versteckter Engine-Schalter gesetzt war.
7. **Die Notiz „Start of <Spiel>: it ended at a question of its own …“** (`LibraryModel.swift`) sieht aus wie eine
   Wege-Zeile. `GameTest.starts` liest sie seit dem 14.11. nicht mehr als Weg; ein anderer Wortlaut wäre sauberer.
