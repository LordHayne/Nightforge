# Die Läuft-Liste: was sie behauptet und wie gemessen wird

Idee vom 14.11.2026: eine Liste der Spiele, die unter Nightforge eindeutig starten und laufen, mit Messwerten – als
Referenz für die Community und die Landingpage. Dieses Dokument legt fest, was ein Eintrag behauptet, woher er kommt
und was seine Zahlen bedeuten. Die Liste selbst erzeugt `scripts/laeuft-liste.py` nach `docs/laeuft/`
(`laeuft.json` für Werkzeuge, `LAEUFT.md` für Menschen). Niemand trägt von Hand ein.

Zweiter Zweck (Nachtrag vom 14.11.): Die Liste ist zugleich **Benchmark-Liste und Abhakliste**. Der Nutzer will geladene
Spiele deinstallieren können, um Platz für neue zu schaffen – aber erst, wenn er von einem Spiel „einen 100%igen Start“
gesehen und „einen FPS-Wert für unsere Benchmark-Liste“ hat. Das regelt Abschnitt 4; die FPS-Werte sollen offen auf die
Landingpage (Abschnitt 7).

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
  Prefix: In einem Messlauf sind sie tabu (Abschnitt 6).
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
| Nightforge-Version | **nicht aufgezeichnet** (Lücke, Abschnitt 9) | `nightforge`, seit Format 2 mit `built` |
| Datum | `at` | Start des Spiels im Lauf |

Tage stehen in UTC, damit dieselben Daten auf jedem Mac dieselbe Liste geben.

## 3. Messwerte: was heute messbar ist

Stand 14.11.2026, Engine winecx 4.7.3. Geprüft am Code der Schichten, an Apples Dokumentation und an den Logs dieses Macs.

| Weg | Eigene Zählung der Schicht (FPS Ø, tiefste Periode, langsamster Frame je Periode) | Apples Metal-HUD-Protokoll (jeder Frame: 1-%-Tief, GPU-Zeit) | Gezeichnete Auflösung |
|---|---|---|---|
| DXMT | **ja**, immer: `[nightforge-dxmt]` alle 10 s, nach zwei Minuten jede Minute | **ja, belegt:** 538 Zeilen im `wine.log` vom 7.11. (Overwatch, ABZU) | nein; der Anzeigemodus, wenn das Spiel einen setzt |
| DXVK auf KosmicKrisp (Direct3D 9), Vulkan-Spiele | **ja**, immer: `[nightforge-vulkan]`, gleiches Format | wahrscheinlich (zeichnet über Metal), nicht gesehen | **ja:** Swapchain in Pixeln und MetalFX-Ziel |
| DXVK auf MoltenVK (Direct3D 10/11) | nein | wahrscheinlich: Die Anzeige hängt sich laut Log an, Protokollzeilen nicht gesehen | nein |
| D3DMetal | nein | wahrscheinlich: wie oben | nein |
| WineD3D (OpenGL) | nein | **offen:** nicht belegt, dass die Anzeige an OpenGL-Bilder kommt | nein |
| Mac-Fassung | nein | **heute nein:** Die Ausgabe landet beim Spiel, nicht im `wine.log`; ein Schalter fürs Protokoll ohne Umgebungsvariable ist nicht dokumentiert | nein |
| alle | Sekunden bis zum Bild; Fenstergröße und Bildschirm in Punkten (Zeile des Vorhangs); Frame-Limit, Bildwiederholrate, MetalFX an/aus und ob das Limit gedrosselt war (nur Windows-Fassungen); Last, Akku, Stromsparmodus; Größe auf der Platte | | |

### FPS auf jedem Weg: Apples Metal-Leistungsanzeige

Was Apple dokumentiert („Monitoring your Metal app's graphics performance“ und „Customizing Metal Performance HUD“,
developer.apple.com/documentation/xcode, gelesen am 14.11.2026):

- `MTL_HUD_ENABLED=1` schaltet die Anzeige ein; `MTL_HUD_LOG_ENABLED=1` „Enables logging of per-frame statistics. Requires
  MTL_HUD_ENABLED=1.“
- Das Protokoll schreibt **einmal pro Sekunde** eine Zeile „to the console“:
  `metal-HUD: <erste Frame-Nummer>,<Grafikspeicher>,<Prozessspeicher>,<Present-Intervall>,<GPU-Zeit>,…` – ein Paar je Frame.
  Einheiten nennt Apple nicht; im Log sind es Millisekunden (16,67 bei 60 FPS). macOS-Versionen nennen die Seiten nicht.
- `MTL_HUD_OPACITY` (0.0 bis 1.0) regelt die Deckkraft: ein Weg, zu protokollieren, ohne dass die Anzeige im Bild steht.
  Nicht geprüft.
- Ohne Umgebungsvariable: der Menüpunkt „Enable Logging“ (⌘F8) im Spiel, wenn die Anzeige an ist. Einen
  `defaults`-Schlüssel fürs Protokoll dokumentiert Apple nicht.

Was auf diesem Mac belegt ist: Unter Wine landen die Zeilen im `wine.log` (`… wine[18259:…] metal-HUD: 48,335.58,…`). Aus
den 538 Zeilen vom 7.11. lassen sich für Overwatch 23 197 Frames über 414 s lesen (Ø 56 FPS, 99. Perzentil 33 ms), für
ABZU 7 505 Frames über 135 s. Das ist die eine Zählung, die nicht an der Schicht hängt.

Gebaut ist die **Leseseite**: `GameTest.hudSample` liest die Zeilen des Prozesses mit den meisten Frames, und der Bericht
bekommt daraus Ø, tiefste 10-Sekunden-Strecke, langsamsten Frame, **1-%-Tief** (Bildrate am 99. Perzentil der
Frame-Zeit) und die GPU-Zeit je Frame (`source: metal-hud`). Stehen keine solchen Zeilen im Log, bleibt es bei der
Zählung der Schicht.

Was fehlt, ist das **Einschalten** – in Dateien, die diese Session nur lesen durfte (Abschnitt 9, Punkt 1). Bis dahin gilt:

- **Heute ohne Eingriff messbar:** DXMT und die Vulkan-Schicht. Auf diesem Mac sind das 6 der 23 geladenen Spiele
  (193,7 GB): Overwatch, Just Cause 4, Metal Gear Solid V, REANIMAL, The Forest, ABZU.
- **Heute nicht messbar:** D3DMetal (5 Spiele, 261,1 GB), WineD3D (5 mit Batman, 58,9 GB), Mac-Fassungen (5 mit Dying
  Light, 64,0 GB), DXVK ohne Zeilen im Log (OxyRail, 7,4 GB; vermutlich MoltenVK). Für D3DMetal und MoltenVK reicht
  voraussichtlich das Protokoll der Leistungsanzeige; für WineD3D und Mac-Fassungen ist das offen.
- **Von Hand heute schon:** Leistungsanzeige in den Einstellungen an, im Spiel ⌘F8. Dann liest der Spieletest die Zeilen.
  Für einen unbeaufsichtigten Lauf taugt das nicht.

Der Spieletest schreibt seit Berichtsformat 2 je Spiel (`GameTestMeasure.swift`): `frames` mit `average`, `low`,
`periods`, `seconds`, `slowestFrame`, `slowestTypical`, `source`, `onePercentLow`, `gpuTime`; `measure` mit `window`,
`screen`, `swapchain`, `upscaledTo`, `displayMode`, `frameLimit`, `refreshRate`, `metalFX`, `throttled` und `noFrames`
(`wayReportsNone` oder `noneInLog`); `check` (Abschnitt 4) und `sizeBytes`; je Lauf `built` (das Datum des Programms:
Testbuilds zwischen zwei Versionen tragen dieselbe Versionsnummer), `onBattery`, `lowPower`. Berichte im Format 1 liest
der Generator weiter; ihnen fehlen diese Felder, und die Liste sagt dann „nicht gemessen“.

### Was die Zahlen bedeuten

- **Messfenster:** vom ersten Frame bis zum Ende des Spielfensters (`playSeconds` nach dem ersten Bild). Das sind die
  ersten Minuten nach dem Start: Logos, Intro, Menü, vielleicht die erste Szene. **Keine feste Szene**, kein Benchmark.
- **Einstellungen:** die das Spiel mitbringt. Niemand stellt Grafik ein.
- **FPS Ø** ist nach Periodenlänge gewichtet. **Tiefste Periode** ist der schlechteste 10-Sekunden-Schnitt, kein
  1-%-Tief.
- **Unter Limit oder frei – nie vermischt.** „Scharf & flüssig“ hält ein Spiel auf 120 Hz bei 60 FPS. Ein Wert unter
  Limit (`kind: holdsLimit`) sagt „hält 60 FPS“ oder „hält sie nicht“ (`holds`: Ø mindestens 95 % des Limits, wie
  `FramePacing`), nicht „schafft nur 59“. Eine freie Zahl (`kind: free`) gibt es nur aus einem Lauf ohne Limit
  (`frameLimit: 0`). Ist das Limit nicht aufgezeichnet (Format 1), ist der Wert keines von beiden. Der Spieletest
  rechnet das Limit so aus, wie der Start es tut, und liest es nicht aus dem Start selbst (Abschnitt 9).
- **Was das Limit senkt:** „Akku sparen“ (30 FPS) und der Stromsparmodus stehen als `throttled`; solche Werte sind
  nicht öffentlich. Ein von `FramePacing` gelerntes niedrigeres Limit (40 statt 60) ist Nightforges eigene Wahl und
  steht als Limit da. Das V-Sync des Spiels selbst ist nicht aufgezeichnet: Auch eine freie Zahl kann daran hängen.
- **1-%-Tief und GPU-Zeit** gibt es nur aus dem Protokoll der Leistungsanzeige. Die GPU-Zeit je Frame zeigt unter Limit,
  wie viel Luft bleibt (10 ms bei 60 FPS heißt: Die Grafik wäre nicht die Grenze).
- **Langsamster Frame:** „schlimmster“ ist der eine langsamste im ganzen Fenster, meist ein Lade-Ruckler. „Üblich“ ist
  der Median der langsamsten Frames je Periode und sagt mehr über das Spielgefühl.
- **Größe:** Die Fenstergröße in Punkten ist nicht die gezeichnete Auflösung (Retina und MetalFX liegen dazwischen).
  Pixel nennt nur die Vulkan-Schicht.
- **Vergleichbar** sind dieselben Spiele über Nightforge- und Engine-Stände auf demselben Mac, grob. Nicht vergleichbar:
  Spiele untereinander, und Läufe mit hoher Last, auf Akku oder im Stromsparmodus (alle drei werden markiert).

### Was öffentlich standhält

Ein FPS-Wert ist `public`, wenn seine Bedingungen vollständig im Datensatz stehen: Mac und macOS, Nightforge-Version
(seit Format 2 mit Baudatum) und Engine-Teile, Grafikweg, Größe, Datum, Messdauer, Limit und MetalFX – und wenn er am
Netz, außerhalb des Stromsparmodus, ohne gedrosseltes Limit und bei niedriger Last gemessen ist. Sonst nennt
`notPublic` die Gründe, und die Tabelle sagt „FPS nicht für die öffentliche Liste: …“. Am 14.11. ist **kein** Wert
öffentlich: Alle stammen aus Berichten im Format 1, ohne Limit, Größe und Messdauer.

## 4. Die Abhakliste: fertig, darf weg

`docs/laeuft/ABHAKLISTE.md` und `abhakliste.json`: jedes geladene Spiel (Steam für Windows und für Mac, Epic, GOG) mit
seiner Größe auf der Platte und der Antwort, ob es fertig ist. **Deinstalliert wird nie vom Generator und nie vom
Spieletest: Das macht der Nutzer selbst.**

**Fertig** ist ein Spiel, wenn auf dem aktuellen Build beides aufgezeichnet ist:

**(a) Ein 100%iger Start.** Ein Start ist sauber, wenn alles gilt:

1. Bild auf dem ersten und einzigen Weg – kein `failed`, kein zweiter Weg, auch kein stiller zweiter Anlauf.
2. Nicht von selbst beendet.
3. Als laufend bestätigt nach Nightforges eigener Regel (`LaunchHealth`): Frames gezählt oder 180 s mit Bild. In der
   Evidenz ist das ein `worked`, bei einem schon bestätigten Weg ein `ended` mit Bild nach mindestens 180 s; im
   Spieletest ein Bild mit gezählten Frames oder ein Spielfenster von mindestens 180 s.
4. Ohne Handgriff. Im Spieletest ist das so gebaut: Braucht ein Start den Spieler, bricht der Test ab (das gilt als
   „klärt nichts“, auch für die eine Lizenzfrage, die der Nutzer dann von Hand beantwortet). Bei Starts von Hand sind
   Handgriffe nicht aufgezeichnet; die Liste nennt deshalb die Quelle („Spieletest“ oder „Evidenz“).

Es entscheidet der **jüngste** Start. Einer, der nichts klärt (unter 180 s beobachtet, Ausgang nicht aufgezeichnet,
brauchte den Spieler), lässt einen sauberen Start davor stehen – nach einem unsauberen ist er selbst die Antwort.

**(b) Ein FPS-Wert mit seinen Bedingungen:** aus einem Spieletest auf dem aktuellen Build, gemessen, mit
aufgezeichnetem Limit (Format 2), am Netz, ungedrosselt, bei niedriger Last.

**Aktueller Build** ist der des jüngsten Spieletest-Berichts: Version, Baudatum (Format 2) und Engine-Teile. Gezählt
wird ab dessen erstem Spieletest – oder ab `--since`, wenn auf einem neuen Build noch kein Spieletest lief. Die Evidenz
kennt den Build nicht (Abschnitt 9, Punkt 2): Ihre Starts zählen nach Datum und winecx-Stand.

| Status | Bedeutet |
|---|---|
| **fertig – darf weg** | (a) und (b) liegen vor. |
| **offen** | Die Liste sagt, was fehlt: „Start fehlt: brauchte mehrere Wege“, „FPS fehlt: D3DMetal meldet keine“ … Ließ der jüngste Spieletest das Spiel aus (Update, Laufzeiten, Anmeldung), steht das dabei. |
| **von Hand zu prüfen** | Kein Spieletest wird es je starten: Anti-Cheat, nur VR, CrossOver-Flasche, Battle.net – und der erste Start der anderen Fassung (`versionSwitch`), bis der Nutzer ihn einmal von Hand gemacht hat. Anti-Cheat-Spiele werden nicht geprüft; über sie entscheidet der Nutzer ohne Messung. |

Stand 14.11.: 23 geladene Spiele, 594,8 GB; **0 fertig**. 11 haben einen sauberen Start auf Rekord, keines einen
FPS-Wert, der zählt: 6 haben einen Wert ohne aufgezeichnetes Limit, 14 liegen auf Wegen, die nichts melden oder
nichts im Log hatten, 3 wurden auf diesem Build nie gemessen.

Der Spieletest schreibt dieselbe Prüfung selbst: `check` je Spiel (`GameTest.check`) und in `report.md` den Abschnitt
„Abhakliste“ mit Größe, Start, FPS und Fazit für **jedes** geladene Spiel. Ein Lauf über alle Spiele endet also mit der
Antwort, was jetzt vorliegt.

## 5. Der Generator

```bash
python3 scripts/laeuft-liste.py
```

Ohne Argumente liest er die Evidenz, alle Spieletest-Berichte und den Bestand der Läden dieses Macs (nur lesend) und
schreibt `laeuft.json`, `LAEUFT.md`, `abhakliste.json` und `ABHAKLISTE.md` nach `docs/laeuft/`. Mit `--evidence DATEI`
(mehrfach möglich), `--names DATEI`, `--out ORDNER`, `--since ZEITPUNKT` und Berichten oder Ordnern als Argumenten geht
es auch anders. `--no-stock` liest keinen Bestand und schreibt keine Abhakliste (für Daten anderer Macs).

- **Bestand:** Steam aus `libraryfolders.vdf` und den `appmanifest`-Dateien (Windows-Steam im Prefix samt Bibliotheken
  auf anderen Laufwerken, Steam für Mac), Epic aus legendarys `installed.json` (Add-ons zählen zur Größe ihres Spiels),
  GOG aus Nightforges `installed.json`. Größen sind die der Läden. Pfade und Laufwerksnamen verlassen den Leser nicht:
  Die Liste sagt nur „intern“ oder „extern“. Battle.net liest er nicht.

- **Deterministisch:** Gleiche Eingaben geben byte-gleiche Dateien. Kein Erzeugungsdatum; `dataUntil` ist der jüngste
  Zeitstempel der Eingaben. Derselbe Lauf zählt einmal, auch wenn er zusätzlich in `docs/spieletest` liegt.
- **Namen:** Die Evidenz kennt nur Schlüssel (`steam.35140`). Der Name kommt aus dem jüngsten Spieletest-Bericht, der
  das Spiel nennt (`nameFrom: report`); sonst aus `docs/laeuft/namen.json` (`nameFrom: names`, von Hand gepflegt,
  heute ein Eintrag: Batman); sonst aus dem Bestand des Ladens, solange das Spiel geladen ist (`nameFrom: stock`);
  sonst steht der Schlüssel da, und der Generator meldet ihn. Wer ein Spiel deinstalliert, das nie im Spieletest war,
  trägt seinen Namen vorher in `namen.json` ein.
- **Messung je Eintrag:** der jüngste Lauf mit Bild auf dem gelisteten Weg; gibt es keinen, der jüngste mit Bild
  überhaupt, mit dem Hinweis „Messung auf …“.
- **Datenschutz:** In die Liste gehen nur feste Felder – keine Notizen, Fehlerzeilen oder Gründe aus den Berichten.
  Vor dem Schreiben prüft der Generator beide Dateien auf Home-Ordner, Kontonamen und Laufwerke und schreibt sonst
  nichts. Was drinsteht: Spielnamen und Laden-IDs der getesteten Spiele, Chip, macOS, Wege, Zahlen, Tage.
- **Format:** `laeuft.json` hat `formatVersion: 1`, `dataUntil`, `sources` und `entries`. Je Eintrag: `key`, `store`,
  `storeID`, `name`, `platform`, `mac`, `level` (`laeuft`, `startet`, `anti-cheat`, `kein-bild`), `way`, `antiCheat`
  (wahr, falsch oder `null` für „nicht aufgezeichnet“), `confirmed`, `withdrawn`, `seen`, `evidence`, `gameTest`,
  `gameEngine`, `measured`, `notes`. Tests: `tests/test_laeuft_liste.py`.

## 6. Ein Messlauf über alle geladenen Spiele

Damit Zahlen von heute und von in vier Wochen nebeneinander stehen können und die Abhakliste danach stimmt:

1. **Mac:** am Netzteil, kein Stromsparmodus, interner Bildschirm (oder der Bildschirm wird genannt), keine anderen
   Apps, kein Build nebenher. Der Test wartet bis zu fünf Minuten auf niedrige Last und markiert den Rest.
2. **Nightforge:** der Stand, der gemessen werden soll, frisch gestartet. Alle Spiele auf Automatik, „Scharf & flüssig“
   wie ausgeliefert. Keine versteckten Engine-Schalter, kein Eingriff in den Prefix.
3. **Spiele:** unverändert, mit ihren eigenen Einstellungen. Der Test spielt alle geladenen Spiele; was er auslässt,
   nennt die Abhakliste mit dem Grund.
4. **Spieldauer: `gameTest.playSeconds` mindestens 190.** Die Bestätigung braucht gezählte Frames oder 180 s mit Bild;
   bei 60 s (Standard) bleibt jedes Spiel auf D3DMetal, WineD3D und als Mac-Fassung „unter 180 s beobachtet“. 190 s
   geben DXMT zwölf 10-Sekunden-Perioden und eine Minutenperiode.

   ```bash
   defaults write io.github.lordhayne.nightforge gameTest.playSeconds -int 190
   ```

   ```bash
   defaults write io.github.lordhayne.nightforge gameTest -bool true
   ```

   Je Spiel sind das bis zu 120 s Warten aufs Bild, 190 s Spiel und 10 bis 120 s Ruhe danach: vier bis sieben Minuten.
   Für die 23 Spiele dieses Macs also anderthalb bis knapp drei Stunden.
5. **Zweimal, wenn es um Zahlen geht.** Der erste Lauf nach einem Engine-Wechsel übersetzt Shader und ist langsamer.
   Für die Abhakliste zählt der jüngste Start, für die Messung der jüngste Lauf mit Bild.
6. **Freie Zahlen** (ohne Limit) brauchen einen eigenen Durchgang: „Scharf & flüssig“ in den Einstellungen aus, dann
   hält Nightforge kein Limit, und der Bericht zeigt `frameLimit: 0`. Nicht live geprüft; MetalFX steht als `metalFX` dabei.
7. **Danach:** `scripts/import-game-test.py` (Bericht ins Repository, mit Leck-Prüfung), `scripts/laeuft-liste.py`,
   beide Tabellen ansehen, committen. Deinstallieren ist Sache des Nutzers.

Nicht automatisch möglich ist dieselbe Szene. Wer die braucht, misst von Hand und trägt es **nicht** in diese Liste ein.

## 7. Vorschlag: Landingpage

Kein Eingriff in `site/` von hier aus; Gestaltung über ein Board und die Wahl des Nutzers. Der Nutzer will die
FPS-Werte offen zeigen, als Übersicht für alle.

- **Datei:** `docs/laeuft/laeuft.json`, beim Bau der Seite eingelesen. Nur `level` `laeuft` und `startet`. Die
  Abhakliste gehört nicht auf die Seite: Sie ist das Arbeitsblatt dieses Macs.
- **Zwei Arten von Zahl, sichtbar getrennt:**
  - *Unter Limit* (`measured.kind: holdsLimit`): „hält 60 FPS“ oder „hält 60 FPS nicht (Ø 47)“, daneben „langsamstes
    Bild üblich 24 ms“ (`fps.slowestTypical`) und, wo vorhanden, „1-%-Tief 56“ und „GPU 10 ms je Bild“. Keine große
    FPS-Zahl: Sie wäre immer 60.
  - *Frei gemessen* (`kind: free`): „Ø 87 FPS, 1-%-Tief 61“, mit dem Wort „ohne Limit“.
- **Nur `measured.public: true`.** Alles andere zeigt die Stufe ohne Zahl. Akku, Stromsparmodus, gedrosseltes Limit,
  hohe Last oder eine fehlende Bedingung schließen einen Wert aus; `notPublic` sagt, warum.
- **Bedingungen an jeder Zahl** (als zweite Zeile oder aufklappbar): Mac und macOS (`mac`), Nightforge-Version und
  Baudatum, Engine-Teile, Grafikweg, Größe (`swapchain` in Pixeln, sonst Anzeigemodus, sonst „Fenster … Punkte“),
  MetalFX, Datum, Messdauer (`fps.seconds`).
- **Weitere Spalten:** Spiel, Laden, Stufe als Marke, „bestätigt am … beim 1. Start“, Bild nach.
- **Immer dabei:** der Satz „Die ersten Minuten nach dem Start, mit den Einstellungen des Spiels, kein Benchmark“ und
  ein Link auf dieses Dokument. Hinweise (`notes`) als Fußnote, nie versteckt.

## 8. Vorschlag: Beiträge aus der Community

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

## 9. Lücken und was dafür nötig wäre

Diese Stellen liegen in Dateien, die am 14.11. eine andere Session bearbeitet, und sind hier nur beschrieben:

1. **Protokoll der Leistungsanzeige einschalten** (`Engine.swift` bei `MTL_HUD_ENABLED`, Zeile 92; `Launcher.swift`,
   Zeilen 614 und 726): Während eines Spieletests – oder über einen eigenen Schalter – zusätzlich
   `MTL_HUD_LOG_ENABLED=1` setzen, zusammen mit `MTL_HUD_ENABLED=1`; ist die Anzeige beim Spieler aus, mit
   `MTL_HUD_OPACITY=0`. Die Umgebung bekommt das Spiel von der Steam-Sitzung: Der Schalter muss also gelten, wenn sie
   startet. Live zu prüfen, je einmal: Kommen die Zeilen auf D3DMetal, auf DXVK/MoltenVK, auf WineD3D? Protokolliert die
   Anzeige auch bei Deckkraft 0? Kostet sie Frames?
2. **Evidenz ohne Nightforge-Version, Engine-Teile und Namen** (`StartEvidence.swift`, Aufruf in
   `LibraryModel.swift`): `started` sollte `nightforge` (mit Baudatum), die Teile (`graphics@…`, `d3dmetal@…`) und den
   Namen tragen. Der Generator liest `nightforge` schon, wenn es da ist. Solange es fehlt, zählt die Abhakliste Starts
   von Hand nur nach Datum.
3. **Frame-Limit im Log** (`LibraryModel.launch`): eine Zeile „held to 60 FPS, MetalFX on“ je Start. Heute rechnet
   `GameTestRun.held` es nach.
4. **Mac-Fassungen:** Das Protokoll der Anzeige geht an die Konsole des Spiels. Nötig wäre, es von dort zu lesen
   (einheitliches Log) und es ohne Umgebungsvariable einzuschalten – beides offen, nichts davon dokumentiert Apple
   auf den gelesenen Seiten.
5. **WineD3D,** falls die Anzeige dort nichts liefert: eine eigene Zählung wie die von DXMT in Wines OpenGL-Weg.
   Braucht einen Engine-Build.
6. **Gezeichnete Auflösung unter DXMT und D3DMetal** (`engine/patches/dxmt-0.80-frame-log.patch`): eine Zeile zur
   Backbuffer-Größe. Braucht einen Engine-Build. Das 1-%-Tief käme mit Punkt 1 ohne Build.
7. **Der Spieletest bestätigt bei 60 s keinen Weg** (steht schon in `docs/TODO.md`); am 10.11. blieb ABZU nach vier
   Läufen mit Bild und Frames ohne `worked`.
8. **Von Hand geformte Starts erkennen:** `started` könnte sagen, ob ein versteckter Engine-Schalter gesetzt war.
9. **Die Notiz „Start of <Spiel>: it ended at a question of its own …“** (`LibraryModel.swift`) sieht aus wie eine
   Wege-Zeile. `GameTest.starts` liest sie seit dem 14.11. nicht mehr als Weg; ein anderer Wortlaut wäre sauberer.
