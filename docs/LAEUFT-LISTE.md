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
| Start-Evidenz (`start-evidence.jsonl`, `StartEvidence.swift`) | je Start: Spiel, Weg, winecx-Stand, Chip und macOS, Ausgang (`worked`, `failed`, `ended`, `gaveUp`); seit dem 14.11.2026 dazu Nightforge-Version mit Baudatum (`nightforge`, `built`), alle Engine-Teile (`parts`) und der Name des Spiels (`name`) | Mac-Fassungen, Messwerte; Zeilen von vor dem 14.11. nennen weder Version noch Namen |
| Spieletest (`GameTests/<Datum>/report.json`, `GameTest*.swift`) | je Spiel: Bild ja/nein, Sekunden bis zum Bild, Wege, Messwerte im Spielfenster; je Lauf: Nightforge-Version, alle Engine-Teile, Last | bestätigt keinen Weg (siehe Stufen) |

Nicht benutzt: `wine.log` (rotiert bei 8 MB, keine dauerhafte Quelle – der Spieletest liest seinen Abschnitt daraus,
solange er frisch ist) und die bestätigten Wege in den Einstellungen der App (`LaunchHealth.confirmedWays`: ohne Datum
und Engine-Stand; die Evidenz hält dasselbe als `known` fest).

## 2. Stufen

Ein Eintrag gilt für **ein Spiel, eine Fassung (Windows oder Mac) und einen Mac** (Chip und macOS).

| Stufe | Bedingung in den Daten | Bedeutet |
|---|---|---|
| **läuft** | Die Evidenz hat für den Weg ein `worked` – das ist `LaunchHealth.verdict`: gemessene Frames oder 180 s mit Bild – oder einen Start mit `known: true` (der Weg war schon bestätigt, bevor die Aufzeichnung am 9.11.2026 begann). Und: Kein späterer Start desselben Wegs war wieder unbestätigt. | Nightforge startet das Spiel auf Automatik, es zeichnet, und Nightforge selbst hält den Weg für bewährt. |
| **startet** | Kein bestätigter Weg, aber ein Bild: Ein Spieletest-Lauf des Spiels endete mit `picture`, oder die Evidenz hat ein `ended` mit `picture: true`. Es zählt das jüngste Bild, mit seinem Datum. | Es kam ins Bild. Ob es dabei bleibt, ist nicht belegt. |
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
- **Kein Bild danach** (`noPictureSince`): Starts ohne Bild nach dem jüngsten Bild eines „startet“-Eintrags. Der
  Eintrag und sein Messwert bleiben, der Hinweis sagt, wie oft und wann zuletzt. Ein Bild nimmt kein späterer Lauf
  zurück, so wenig wie ein neuerer Build einen Wert.
- **Was der aktuelle Build gesehen hat** (`onCurrentBuild`): der jüngste Start des Spiels auf dem Build, der zuletzt
  lief – mit Bild, ohne Bild oder „noch nichts“. Das ist die Angabe für „läuft auf dem aktuellen Stand“; die Stufe und
  die Messwerte hängen nicht daran.
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
| Engine | `engine` des Starts (`winecx@…`), seit dem 14.11. alle Teile (`parts`) | alle Teile (`winecx@…`, `graphics@…`, `d3dmetal@…` …), dazu `runsOn` |
| Nightforge-Version | `nightforge` und `built` des Starts, seit dem 14.11.; bei älteren Zeilen **nicht aufgezeichnet** | `nightforge`, seit Format 2 mit `built` |
| Datum | `at` | Start des Spiels im Lauf |

Tage stehen in UTC, damit dieselben Daten auf jedem Mac dieselbe Liste geben.

## 3. Messwerte: was heute messbar ist

Stand 14.11.2026, Engine winecx 4.7.3. Geprüft am Code der Schichten, an Apples Dokumentation, an den Logs dieses Macs
und mit einem eigenen kleinen Metal-Programm (unten: „Probe“).

| Weg | Eigene Zählung der Schicht (FPS Ø, tiefste Periode, langsamster Frame je Periode) | Apples Metal-HUD-Protokoll (jeder Frame: 1-%-Tief, GPU-Zeit) – im Spieletest eingeschaltet | Gezeichnete Auflösung |
|---|---|---|---|
| DXMT | **ja**, immer: `[nightforge-dxmt]` alle 10 s, nach zwei Minuten jede Minute | **ja, belegt:** 538 Zeilen im `wine.log` vom 7.11. (Overwatch, ABZU) | nein; der Anzeigemodus, wenn das Spiel einen setzt |
| DXVK auf KosmicKrisp (Direct3D 9), Vulkan-Spiele | **ja**, immer: `[nightforge-vulkan]`, gleiches Format | erwartet (zeichnet über einen Metal-Layer), unter Wine noch nicht gesehen | **ja:** Swapchain in Pixeln und MetalFX-Ziel |
| DXVK auf MoltenVK (Direct3D 10/11) | nein | erwartet: Die Anzeige hängt sich laut Log an; Protokollzeilen unter Wine noch nicht gesehen | nein |
| D3DMetal | nein | erwartet: wie oben | nein |
| WineD3D (OpenGL) | nein | **nein:** Ein OpenGL-Fenster bekommt weder Anzeige noch Zeilen (Probe) | nein |
| Mac-Fassung | nein | **nicht im Spieletest:** Das Spiel startet Steam für Mac, die Umgebungsvariable erreicht es nicht, und die Zeilen gingen an seine eigene Fehlerausgabe (Abschnitt 9, Punkt 4) | nein |
| alle | Sekunden bis zum Bild; Fenstergröße und Bildschirm in Punkten (Zeile des Vorhangs); Frame-Limit, Bildwiederholrate, MetalFX an/aus und ob das Limit gedrosselt war (Zeile des Starts, nur Windows-Fassungen); Last, Akku, Stromsparmodus; Größe auf der Platte | | |

### FPS auf jedem Weg: Apples Metal-Leistungsanzeige

Was Apple dokumentiert („Monitoring your Metal app's graphics performance“ und „Customizing Metal Performance HUD“,
developer.apple.com/documentation/xcode, gelesen am 14.11.2026):

- `MTL_HUD_ENABLED=1` schaltet die Anzeige ein; `MTL_HUD_LOG_ENABLED=1` „Enables logging of per-frame statistics. Requires
  MTL_HUD_ENABLED=1.“
- Das Protokoll schreibt **einmal pro Sekunde** eine Zeile „to the console“:
  `metal-HUD: <erste Frame-Nummer>,<Grafikspeicher>,<Prozessspeicher>,<Present-Intervall>,<GPU-Zeit>,…` – ein Paar je Frame.
  Einheiten nennt Apple nicht; im Log sind es Millisekunden (16,67 bei 60 FPS). macOS-Versionen nennen die Seiten nicht.
- `MTL_HUD_OPACITY` (0.0 bis 1.0) regelt die Deckkraft: ein Weg, zu protokollieren, ohne dass die Anzeige im Bild steht
  (belegt, siehe Probe).
- Ohne Umgebungsvariable: der Menüpunkt „Enable Logging“ (⌘F8) im Spiel, wenn die Anzeige an ist. Einen
  `defaults`-Schlüssel fürs Protokoll dokumentiert Apple nicht.

Was auf diesem Mac belegt ist: Unter Wine landen die Zeilen im `wine.log` (`… wine[18259:…] metal-HUD: 48,335.58,…`). Aus
den 538 Zeilen vom 7.11. lassen sich für Overwatch 23 197 Frames über 414 s lesen (Ø 56 FPS, 99. Perzentil 33 ms), für
ABZU 7 505 Frames über 135 s. Das ist die eine Zählung, die nicht an der Schicht hängt.

**Probe am 14.11.2026** (M5, macOS 27.0): ein eigenes kleines Programm, das fünf Sekunden lang Frames in ein Fenster
zeichnet – kein Wine, kein Nightforge. Ergebnis:

| Gestartet mit | `metal-HUD:`-Zeilen auf der Fehlerausgabe | Anzeige im Fensterbild |
|---|---|---|
| `MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1` (Metal) | 4 in 5 s | zu sehen |
| dazu `MTL_HUD_OPACITY=0` (Metal) | 4 in 5 s | **nicht zu sehen** |
| nur `MTL_HUD_LOG_ENABLED=1` (Metal) | keine | keine |
| `MetalForceHudEnabled` in den Einstellungen des Programms, `MTL_HUD_LOG_ENABLED=1 MTL_HUD_OPACITY=0` (Metal) | 3 in 4 s | nicht zu sehen |
| `MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1` (**OpenGL**) | **keine** | keine |

Die Zeilen stehen nur auf der Fehlerausgabe des Programms; im einheitlichen Log von macOS (`log show`) fand sich keine.

**Im Spieletest eingeschaltet** (`Engine.setFrameLog`, `GameTest.logsFrames`): Jeder Start eines Spieletests bekommt
`MTL_HUD_ENABLED=1` und `MTL_HUD_LOG_ENABLED=1`; ist die Leistungsanzeige in den Einstellungen aus, dazu
`MTL_HUD_OPACITY=0`, sie bleibt also unsichtbar. Ein Start über „Spielen“ bekommt nichts davon. Ein Spiel über Steam erbt
die Umgebung des Windows-Steams, das es startet: Das Protokoll steht deshalb in Steams Signatur
(`steamConfigSignature`), Steam startet beim ersten Steam-Spiel des Tests einmal neu und nach dem Test noch einmal,
zurück in die Umgebung von vorher (am Ende des Laufs, `LibraryModel.endFrameLog`, oder beim nächsten Start über
„Spielen“). Ein Spiel von Epic oder GOG hat die Variablen aus seinem eigenen Start und lässt Steams Stand, wie er war.
Die „Sekunden bis zum Bild“ des ersten Steam-Spiels eines Laufs enthalten diesen Neustart. Ausschalten:
`defaults write io.github.lordhayne.nightforge gameTest.frameLog -bool false`.

`GameTest.hudSample` liest die Zeilen der Prozesse des Spiels (Steams eigene Fenster zeichnen auch über Metal), und der
Bericht bekommt daraus Ø, tiefste 10-Sekunden-Strecke, langsamsten Frame, **1-%-Tief** (Bildrate am 99. Perzentil der
Frame-Zeit) und die GPU-Zeit je Frame (`source: metal-hud`). Stehen keine solchen Zeilen im Log, bleibt es bei der
Zählung der Schicht. Der Bericht sagt mit `frameLog`, dass das Protokoll an war; ein Bild ohne Zeilen auf D3DMetal
oder DXVK heißt dann „keine im Log“, nicht mehr „der Weg meldet keine“.

- **Mit dem Protokoll messbar (erwartet):** alles, was über Metal zeichnet – DXMT, DXVK auf MoltenVK und KosmicKrisp,
  D3DMetal. Unter Wine gesehen ist es bisher nur auf DXMT (7.11.); D3DMetal und MoltenVK zeigt der erste Messlauf.
- **Weiter nicht messbar:** WineD3D (OpenGL: auf diesem Mac Dishonored, Left 4 Dead 2, Alan Wake, Mafia II, Batman –
  58,9 GB) und Mac-Fassungen (Tomb Raider, Asphalt Legends, Valheim, Drawful 2, Dying Light – 64,0 GB). Was es dafür
  bräuchte, steht in Abschnitt 9.

Der Spieletest schreibt seit Berichtsformat 2 je Spiel (`GameTestMeasure.swift`): `frames` mit `average`, `low`,
`periods`, `seconds`, `slowestFrame`, `slowestTypical`, `source`, `onePercentLow`, `gpuTime`; `measure` mit `window`,
`screen`, `swapchain`, `upscaledTo`, `displayMode`, `frameLimit`, `refreshRate`, `metalFX`, `throttled` und `noFrames`
(`wayReportsNone` oder `noneInLog`); `check` (Abschnitt 4) und `sizeBytes`; je Lauf `built` (das Datum des Programms:
Testbuilds zwischen zwei Versionen tragen dieselbe Versionsnummer), `onBattery`, `lowPower`, `frameLog`. Berichte im Format 1 liest
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
  (`frameLimit: 0`). Ist das Limit nicht aufgezeichnet (Format 1), ist der Wert keines von beiden. Jeder Start
  schreibt, was für ihn gilt, als Zeile ins Protokoll („Frame limit of <Spiel>: 60 FPS at 120 Hz, MetalFX on“, bei
  Drosselung mit „throttled by battery“ oder „lowPower“); der Spieletest liest sie und rechnet nichts nach. WineD3D
  nimmt weder Limit noch MetalFX: Dort steht „none“ und „MetalFX off“.
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
öffentlich: Alle stammen aus Berichten im Format 1, ohne Limit, Größe und Messdauer; der erste Lauf im Format 2
(14.11., nur Batman auf WineD3D) hat keinen FPS-Wert.

## 4. Die Abhakliste: fertig, darf weg

`docs/laeuft/ABHAKLISTE.md` und `abhakliste.json`: jedes geladene Spiel (Steam für Windows und für Mac, Epic, GOG) mit
seiner Größe auf der Platte und der Antwort, ob es fertig ist. **Deinstalliert wird nie vom Generator und nie vom
Spieletest: Das macht der Nutzer selbst.**

**Fertig** ist ein Spiel, sobald beides einmal **auf demselben Build** aufgezeichnet war – und es bleibt fertig, auch
wenn seither ein neuerer Build läuft. Der Zweck ist das Deinstallieren: Ein Spiel, das weg ist, kann auf einem
späteren Build nicht neu gemessen werden. Der Build, auf dem beides vorlag (Version, Baudatum, Engine-Teile), steht am
Eintrag.

**(a) Ein 100%iger Start.** Ein Start ist sauber, wenn alles gilt:

1. Bild auf dem ersten und einzigen Weg – kein `failed`, kein zweiter Weg, auch kein stiller zweiter Anlauf.
2. Nicht von selbst beendet.
3. Als laufend bestätigt nach Nightforges eigener Regel (`LaunchHealth`): Frames gezählt oder 180 s mit Bild. In der
   Evidenz ist das ein `worked`, bei einem schon bestätigten Weg ein `ended` mit Bild nach mindestens 180 s; im
   Spieletest ein Bild mit gezählten Frames oder ein Spielfenster von mindestens 180 s.
4. Ohne Handgriff. Im Spieletest ist das so gebaut: Braucht ein Start den Spieler, bricht der Test ab (das gilt als
   „klärt nichts“, auch für die eine Lizenzfrage, die der Nutzer dann von Hand beantwortet). Bei Starts von Hand sind
   Handgriffe nicht aufgezeichnet; die Liste nennt deshalb die Quelle („Spieletest“ oder „Evidenz“).

**Ein sauberer Start bleibt einer.** Geht ein späterer Start schief (Fehlstart, mehrere Wege, kein Bild, von selbst
beendet) – auf demselben oder einem neueren Build –, steht das als Hinweis am Eintrag („danach ein Start ging schief,
zuletzt …“) und nimmt nichts zurück. Einer, der nichts klärt (unter 180 s beobachtet, Ausgang nicht aufgezeichnet,
brauchte den Spieler), ist kein Hinweis. Gibt es auf einem Build keinen sauberen Start, sagt die Liste, was sein
jüngster Start war.

**(b) Ein FPS-Wert mit seinen Bedingungen:** aus einem Spieletest auf demselben Build wie der saubere Start, gemessen,
mit aufgezeichnetem Limit (Format 2), am Netz, ungedrosselt, bei niedriger Last.

**Auf welchem Build etwas lief:** Ein Spieletest-Lauf trägt den Build seines Berichts, ein Start der Evidenz den, den
er nennt (seit dem 14.11.). Ältere Zeilen der Evidenz gehören zu dem Build, der zuletzt vor ihnen genannt wurde, wenn
ihr winecx-Stand dazu passt – oder zum aktuellen ab `--since`. **Aktueller Build** ist der, auf dem zuletzt etwas
aufgezeichnet wurde; die Abhakliste nennt ihn oben und markiert Einträge, die auf ihm stehen.

**Welchen Build ein Eintrag zeigt:** bei einem fertigen Spiel den jüngsten, auf dem beides vorlag. Bei einem offenen
den, auf dem es am weitesten kam (ein sauberer Start oder ein zählender FPS-Wert), sonst den jüngsten mit einer
Aufzeichnung. Ein sauberer Start auf einem Build und ein FPS-Wert auf einem anderen ergeben kein „fertig“; ein
Spieletest-Lauf mit FPS-Wert bringt in aller Regel beides zugleich.

| Status | Bedeutet |
|---|---|
| **fertig – darf weg** | (a) und (b) lagen einmal auf demselben Build vor. Bleibt, auch auf neueren Builds. |
| **offen** | Die Liste sagt, was fehlt: „Start fehlt: brauchte mehrere Wege“, „FPS fehlt: D3DMetal meldet keine“ … Ließ der jüngste Spieletest das Spiel aus (Update, Laufzeiten, Anmeldung), steht das dabei. |
| **von Hand zu prüfen** | Kein Spieletest wird es je starten: Anti-Cheat, nur VR, CrossOver-Flasche, Battle.net – und der erste Start der anderen Fassung (`versionSwitch`), bis der Nutzer ihn einmal von Hand gemacht hat. Anti-Cheat-Spiele werden nicht geprüft; über sie entscheidet der Nutzer ohne Messung. |

Stand 14.11. abends: 23 geladene Spiele, 594,8 GB; **0 fertig**. Am 14.11. liefen zwei Testbuilds (gebaut 14:40 und
17:41 UTC); die Einträge stehen mit dem Build, auf dem sie entstanden sind, die meisten mit dem vom 9.11. Kein Spiel hat einen FPS-Wert, der
zählt: Die Werte von DXMT und der Vulkan-Schicht stammen aus Berichten ohne aufgezeichnetes Limit, die übrigen Wege
meldeten nichts. Ein Messlauf mit dem HUD-Protokoll (Abschnitt 6) ist der Weg dahin.

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
- **Namen:** Der Name kommt aus dem jüngsten Spieletest-Bericht, der das Spiel nennt (`nameFrom: report`); sonst aus
  einem Start der Evidenz, der ihn nennt (`nameFrom: evidence`, Zeilen seit dem 14.11.); sonst aus
  `docs/laeuft/namen.json` (`nameFrom: names`, von Hand gepflegt, heute ein Eintrag: Batman); sonst aus dem Bestand
  des Ladens, solange das Spiel geladen ist (`nameFrom: stock`); sonst steht der Schlüssel da, und der Generator
  meldet ihn. `namen.json` braucht nur noch, was vor dem 14.11. gestartet, nie im Spieletest gespielt und inzwischen
  deinstalliert wurde.
- **Messung je Eintrag:** von den Läufen mit Bild auf dem gelisteten Weg der jüngste, dessen FPS-Wert öffentlich
  standhält; sonst der jüngste mit einem FPS-Wert; sonst der jüngste mit Bild. Gibt es auf dem Weg keinen, dasselbe
  über alle Wege, mit dem Hinweis „Messung auf …“. Ein Wert trägt den Build, auf dem er gemessen ist, und bleibt, wenn
  ein neuerer Build läuft oder ein neuerer Lauf keinen Wert bringt.
- **Datenschutz:** In die Liste gehen nur feste Felder – keine Notizen, Fehlerzeilen oder Gründe aus den Berichten.
  Vor dem Schreiben prüft der Generator beide Dateien auf Home-Ordner, Kontonamen und Laufwerke und schreibt sonst
  nichts. Was drinsteht: Spielnamen und Laden-IDs der getesteten Spiele, Chip, macOS, Wege, Zahlen, Tage.
- **Format:** `laeuft.json` hat `formatVersion: 1`, `dataUntil`, `sources` und `entries`. Je Eintrag: `key`, `store`,
  `storeID`, `name`, `platform`, `mac`, `level` (`laeuft`, `startet`, `anti-cheat`, `kein-bild`), `way`, `antiCheat`
  (wahr, falsch oder `null` für „nicht aufgezeichnet“), `confirmed` (mit `nightforge`, `built` und `parts` des Starts,
  wo die Zeile sie nennt), `withdrawn`, `seen`, `noPictureSince`, `evidence`, `gameTest`, `gameEngine`, `measured`,
  `onCurrentBuild`, `notes`; dazu oben `currentBuilds` je Mac. `abhakliste.json`: `build` (der aktuelle), `builds`
  (die Builds, auf denen Einträge stehen) und je Spiel `status`, `missing`, `start`, `fps`, `build` (mit `current`),
  `later` (Starts, die nach dem sauberen schiefgingen). Tests: `tests/test_laeuft_liste.py`.

## 6. Ein Messlauf über alle geladenen Spiele

Damit Zahlen von heute und von in vier Wochen nebeneinander stehen können und die Abhakliste danach stimmt:

1. **Mac:** am Netzteil, kein Stromsparmodus, interner Bildschirm (oder der Bildschirm wird genannt), keine anderen
   Apps, kein Build nebenher. Der Test wartet bis zu fünf Minuten auf niedrige Last und markiert den Rest.
2. **Nightforge:** der Stand, der gemessen werden soll – am besten ein Build für den ganzen Abend: Start und FPS-Wert
   zählen zusammen nur auf demselben Build (was schon fertig ist, bleibt es). Alle Spiele auf Automatik, „Scharf & flüssig“ wie ausgeliefert. Keine versteckten
   Engine-Schalter, kein Eingriff in den Prefix. Nightforge ist beendet, wenn die Schalter unten gesetzt werden.
3. **Spiele:** unverändert, mit ihren eigenen Einstellungen. Der Test spielt alle geladenen Spiele; was er auslässt,
   nennt die Abhakliste mit dem Grund.
4. **Spieldauer: `gameTest.playSeconds` mindestens 190.** Die Bestätigung braucht gezählte Frames oder 180 s mit Bild;
   bei 60 s (Standard) bleibt jedes Spiel ohne gezählte Frames „unter 180 s beobachtet“. 190 s geben DXMT zwölf
   10-Sekunden-Perioden und eine Minutenperiode, dem HUD-Protokoll rund 190 Zeilen.

   ```bash
   defaults write io.github.lordhayne.nightforge gameTest.playSeconds -int 190
   ```

   ```bash
   defaults write io.github.lordhayne.nightforge gameTest -bool true
   ```

   Dann Nightforge starten (den Build, der gemessen wird – über seinen Pfad, nicht über die Bundle-ID). Der Lauf beginnt
   von selbst, sobald die Bibliothek gelesen ist, und der Schalter `gameTest` ist danach wieder weg. Das HUD-Protokoll
   ist im Lauf von selbst an (unsichtbar, wenn die Leistungsanzeige aus ist); Steam startet dafür beim ersten
   Steam-Spiel einmal neu und nach dem Lauf noch einmal.

   Nur einzelne Spiele (Schlüssel oder Namen, mit Komma getrennt), und anhalten nach dem laufenden Spiel:

   ```bash
   defaults write io.github.lordhayne.nightforge gameTest.only -string "steam.287700,epic.Curry"
   ```

   ```bash
   defaults write io.github.lordhayne.nightforge gameTest.stop -bool true
   ```

   Nach dem Abend `gameTest.only` wieder löschen (`defaults delete io.github.lordhayne.nightforge gameTest.only`); die
   Spieldauer darf stehen bleiben.

   Je Spiel sind das bis zu 120 s Warten aufs Bild (`gameTest.pictureWait`), 190 s Spiel und 10 bis 120 s Ruhe danach:
   vier bis sieben Minuten. Für die 23 Spiele dieses Macs also anderthalb bis knapp drei Stunden. Der Bildschirm bleibt
   im Lauf von selbst wach; gesperrt sein darf er nicht.
5. **Zweimal, wenn es um Zahlen geht.** Der erste Lauf nach einem Engine-Wechsel übersetzt Shader und ist langsamer.
   Für die Abhakliste reicht ein Lauf, in dem beides vorliegt; für die Messung zählt der jüngste Wert, der öffentlich
   standhält.
6. **Freie Zahlen** (ohne Limit) brauchen einen eigenen Durchgang: „Scharf & flüssig“ in den Einstellungen aus, dann
   hält Nightforge kein Limit, und der Bericht zeigt `frameLimit: 0`. Nicht live geprüft; MetalFX steht als `metalFX` dabei.
7. **Danach:** Der Bericht liegt in `~/Library/Application Support/Nightforge/GameTests/<Datum>/report.md` und endet
   mit seiner eigenen Abhakliste. Die Liste über alle Läufe und Starts entsteht mit

   ```bash
   python3 scripts/laeuft-liste.py
   ```

   (liest Evidenz, Berichte und Bestand dieses Macs, schreibt `docs/laeuft/`). Wer den Bericht im Repository haben
   will: `scripts/import-game-test.py` (mit Leck-Prüfung). Beide Tabellen ansehen, committen. Deinstallieren ist Sache
   des Nutzers.

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
- **Werte verschwinden nicht mit einem neuen Build:** Jede Zahl steht mit dem Build, auf dem sie gemessen ist. Was der
  jüngste Build von dem Spiel gesehen hat (`onCurrentBuild`: Bild, kein Bild, noch nichts), kann als eigene, kleine
  Angabe daneben stehen („zuletzt geprüft auf …“).
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

Die Punkte 1 bis 3 sind seit dem 14.11. gebaut; offen ist, was nur ein Lauf zeigt:

1. **Protokoll der Leistungsanzeige** – gebaut (Abschnitt 3). Live zu sehen, je einmal: Kommen die Zeilen unter Wine
   auf D3DMetal und auf DXVK/MoltenVK an (auf DXMT sind sie belegt)? Bleibt die Anzeige bei Deckkraft 0 auch im Spiel
   unsichtbar (im eigenen Fenster der Probe ist sie es)? Startet Steam für den Test neu und danach zurück? Kostet das
   Protokoll Frames (auf DXMT: Zählung der Schicht gegen HUD im selben Lauf vergleichen)?
2. **Evidenz mit Version, Baudatum, Engine-Teilen und Namen** – gebaut. Zeilen von vor dem 14.11. zählen weiter nach
   Datum.
3. **Frame-Limit im Log** – gebaut. Der eine Format-2-Lauf vom 14.11. stammt noch von davor und nennt für Batman auf
   WineD3D „60 FPS, MetalFX an“, obwohl WineD3D beides nicht nimmt: nachgerechnet, nicht gelesen.
4. **Mac-Fassungen:** Die Probe zeigt, dass das Protokoll auch mit `MetalForceHudEnabled` (dem Schalter, den
   `MacGameHUD` schon setzt) läuft, wenn das Spiel `MTL_HUD_LOG_ENABLED=1` in seiner Umgebung hat. Die hat es von
   Steam für Mac, und die Zeilen gehen an die Fehlerausgabe des Spiels, nicht ins einheitliche Log. Nötig wäre also:
   Steam für Mac von Nightforge mit dieser Variable und mit einer lesbaren Fehlerausgabe starten. Einen
   `defaults`-Schalter fürs Protokoll gibt es nicht (Apples Seiten nennen keinen, und in den Systembibliotheken dieses
   Macs stehen nur `MetalForceHudEnabled` und `MetalHudEnabled`).
5. **WineD3D:** Die Anzeige liefert dort nichts (OpenGL, Probe). Bleibt eine eigene Zählung wie die von DXMT in Wines
   OpenGL-Weg – braucht einen Engine-Build – oder das Spiel auf einem Weg über Metal zu messen, wo es einen hat.
6. **Gezeichnete Auflösung unter DXMT und D3DMetal** (`engine/patches/dxmt-0.80-frame-log.patch`): eine Zeile zur
   Backbuffer-Größe. Braucht einen Engine-Build. (Die Anzeige selbst zeigt die Größe, ihr Protokoll nennt sie nicht.)
7. **Der Spieletest bestätigt bei 60 s keinen Weg** (steht schon in `docs/TODO.md`); am 10.11. blieb ABZU nach vier
   Läufen mit Bild und Frames ohne `worked`.
8. **Von Hand geformte Starts erkennen:** `started` könnte sagen, ob ein versteckter Engine-Schalter gesetzt war.
9. **Die Notiz „Start of <Spiel>: it ended at a question of its own …“** (`LibraryModel.swift`) sieht aus wie eine
   Wege-Zeile. `GameTest.starts` liest sie seit dem 14.11. nicht mehr als Weg; ein anderer Wortlaut wäre sauberer.
