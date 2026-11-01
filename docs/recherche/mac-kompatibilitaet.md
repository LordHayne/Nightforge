<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHUoXQmY7b9gkDfsf1v (1.11.2026) -->

## Mac-Kompatibilitätsdaten für Nightforge: Quellen, Rechte, Einbau

Stand 1. November 2026. Ich habe nur gelesen und recherchiert, am Repo nichts geändert. Viele Seiten waren von hier aus gesperrt (Liste in Abschnitt 6). Diese Quellen kenne ich nur aus Suchtreffern und aus dem Code anderer Projekte. Unsicheres ist mit *(unsicher)* markiert.

### Kurzfassung

- Keine Quelle kennt genau Nightforges Technik: winecx 4.7.3 (Wine 11.17), DXMT 0.80, D3DMetal 4.0b3, DXVK-macOS 1.10.3 auf MoltenVK 1.4.2.
  - Fremde Bewertungen sind darum nur Hinweise. Sie füllen „Nicht getestet“ und legen die Reihenfolge der Grafikwege fest.
  - Sie überstimmen nie eigene Tests, Anti-Cheat oder das, was der Mac beim Start selbst gelernt hat.

- Drei Quellen haben echte Mac-Daten:
  - AppleGamingWiki ist breit: 1.858 Seiten mit Mac-Tabelle (Stand Juli 2026), mit Steam- und GOG-ID. Nutzbar unter CC BY-NC-SA 3.0, aber ohne Versionsfelder.
  - MacGamingDB ist am genauesten: Jeder Bericht nennt Grafikweg (DXMT, D3DMetal oder DXVK), Chip, FPS und Softwareversion, nach Steam-ID. Rund 1.572 Spiele, meist nur 1–2 Berichte je Spiel. Die Daten sind nicht freigegeben.
  - CodeWeavers ist die größte Datenbank (rund 22.000 Einträge) und bewertet pro CrossOver-Version. Es gibt aber keine API und keine Datenlizenz.

- Für den Abgleich von Steam, GOG und Epic eignet sich Wikidata (CC0, ohne Bedingungen).
- Nachgezählt an den Steam-Top-100 vom 25.10.2026:
  - 54 Spiele sind schon ohne neue Quelle entschieden: 28 haben eine Mac-Version, 22 scheitern am Anti-Cheat, 4 sind keine Spiele.
  - Für etwa 27 der übrigen 46 hat AppleGamingWiki eine CrossOver- oder Wine-Bewertung. Bei reinen DX12-Spielen sind es nur 2 von 9.

- Control läuft laut allen Mac-Quellen über DirectX 12 mit D3DMetal oder als native Mac-Version. Dass es über DX11 mit DXMT oder DXVK läuft, ist nirgends dokumentiert. Das passt zum Absturz am 1.11. (Epic, DX11).

**Empfehlung, in dieser Reihenfolge:**

1. Sofort, ohne Rechtsfrage:
  - Wikidata als ID-Brücke einbauen.
  - In der Spielansicht Links zu AppleGamingWiki, CodeWeavers und MacGamingDB anbieten; Verlinken ist immer erlaubt.
  - Control mit D3DMetal testen (Abschnitt 5).

2. AppleGamingWiki jede Nacht in eine eigene Datei `profiles/agw.json` übernehmen, unter CC BY-NC-SA 3.0 und mit Namensnennung.
  - Vorher das AGW-/PCGW-Team kurz anschreiben. Das klärt die Fragen zu „nicht kommerziell“ und zum Abruf des ganzen Bestands.
  - Heroic, HyperPlay, Bourbon-OSS und Cartouche nutzen AGW schon.

3. MacGamingDB um Erlaubnis bitten (Betreiber auf GitHub: neo773), für einen nächtlichen Export oder die API. Für uns ist das die wertvollste Quelle, weil sie den Grafikweg nennt.
4. CodeWeavers um Zusammenarbeit bitten. Nightforge baut auf ihren Wine-Änderungen auf, und unsere Berichte könnten an sie zurückgehen. Bis dahin nur verlinken, nichts automatisch abrufen.
5. Eigene Berichte („Wie lief es?“) über GitHub-Issue-Formulare und eine Action, parallel beginnen. Auf Dauer ist das die einzige Quelle für genau unsere Version.
6. PCGamingWiki zuletzt und nur bei Bedarf (DirectX-Version, Anti-Cheat und Launcher schon vor dem Download). Seit August 2026 braucht der Abruf ein Bot-Passwort.

**Lohnt sich nicht:** applesilicongames.com, die Whisky-Doku, Mythic, Does It ARM, Porting Kit, die Parallels-Liste und Bottles. ProtonDB taugt nur als schwaches Linux-Signal.

---

### 1. Quellen im Überblick

| Quelle | Was sie über den Mac sagt | Abdeckung, Stand | Zugang | Abgleich | Lizenz | Urteil |
|---|---|---|---|---|---|---|
| **CodeWeavers Compatibility Center** | 1–5 Sterne pro CrossOver- und macOS-Version, getrennt für Mac und Linux | ~22.269 Einträge (Apps und Spiele), viele Bewertungen alt; Bewertungen für 24, 25 und 26 vorhanden | HTML, RSS je App; **keine API, kein Dump** | Slug oder Name; Steam-ID nur in den nicht öffentlichen CrossTie-Dateien | keine Datenlizenz, keine Website-Bedingungen gefunden | **Verlinken ja, Spiegeln nur mit Erlaubnis** |
| **AppleGamingWiki** | Bewertung pro Weg: nativ, Rosetta 2, CrossOver, Wine (inkl. GPTK/Whisky), Parallels; plus Notiz | 1.858 Seiten mit Mac-Tabelle (7.7.2026); **ohne Versions-, Chip- oder Datumsfelder** | MediaWiki-API: Seiten über `embeddedin`, Wikitext über `prop=revisions`; Cargo antwortet anonym nicht mehr *(laut Cartouche, 10/2026)* | Infobox: `steam appid`, `gogcom id`; kein Epic-Feld | CC BY-NC-SA 3.0 *(Fußzeile nicht selbst gesehen)* | **Erlaubt mit Auflagen, getrennte Datei** |
| **MacGamingDB** | Pro Bericht: Weg (Native, CrossOver, Parallels, Other), **Grafikweg (DXVK, DXMT, D3D_METAL)**, 6 Stufen, FPS, Chip und Variante, Auflösung, Softwareversion | ~1.572 Spiele (9/2026); Median 1 Bericht, 78 % haben nur 1–2 | öffentliche tRPC- und REST-API (`/api/rest/games/{id}`) | **Steam-ID**, sonst IGDB | Code MIT; **Daten ausdrücklich nicht freigegeben** (`docs/NOTICE.md`) | **Nur mit Erlaubnis; verlinken ja** |
| **PCGamingWiki** | Keine Mac-Bewertungen. Fakten: Direct3D- und Vulkan-Versionen, 64-bit, Anti-Cheat, DRM und Launcher, Store-IDs | sehr breit | Cargo-API **seit 23.8.2026 nur mit Bot-Passwort**, 60 Anfragen/Min, eigener User-Agent Pflicht; Tabelle `Infobox_game` heißt jetzt `Game` | `Steam_AppID`, `GOGcom_ID`; Epic nur im Wikitext | CC BY-NC-SA 3.0 | **Erlaubt mit Auflagen, aber Konto des Maintainers nötig** |
| **Wikidata** | Nichts zum Mac, nur IDs | breit, Lücken bei Indie-Spielen | SPARQL (`query.wikidata.org`) | P1733 Steam, P12727 GOG-Produkt-ID, P2725 GOG-Slug, P6278 Epic-Slug, P6337 PCGW | **CC0** | **Erlaubt** |
| **applesilicongames.com** | Gerät, „spielbar“, Weg, FPS | Berichte aus der M1-Zeit (2020–21) | kein API; früher Google-Tabelle und -Formular | Name | keine | **Lohnt nicht, Lizenz unklar** |
| **Whisky-Doku** (`whisky-book`) | Platinum bis Garbage | 254 Seiten, 245 mit Steam-ID; archiviert 11/2025; Stand etwa CrossOver 22 + GPTK 1 | Markdown auf GitHub | Steam-ID | keine Lizenzdatei | **Nur verlinken, veraltet** |
| **Mythic-Datenbank** | 1–5 | 106 Spiele, letzter Stand 1/2024 | JSON auf GitHub | Name | keine | **Lohnt nicht** |
| **Does It ARM (Spiele)** | nativ, Rosetta, ~20× CrossOver | ~150 Zeilen, eingefrorene Kopie der applesilicongames-Daten | CSV | Name | CC BY 4.0 | erlaubt mit Nennung, aber veraltet |
| **DXMT** | **keine Spieleliste**; nur 6 Spiel-Profile in `src/util/config/config.cpp` (z. B. Helldivers 2, Shadow of the Tomb Raider); Issues „nur intern“, Berichte gehen über Discord | – | Code | Name der .exe | LGPL-2.1 | Nur als Wissen |
| **Game Porting Toolkit / Apple** | keine offizielle Liste; Community-Tabellen von 2023 | – | Google Sheets (hier gesperrt) | Name | unklar | Lohnt nicht |
| **Porting Kit, Parallels** | Porting Kit: über 1.300 Installer-Rezepte in der App; Parallels verweist auf AGW | – | kein API | – | – | Lohnt nicht |
| **ProtonDB-Dump** | nur Linux/Proton | 395.467 Berichte, 40.587 Apps (Dump vom 1.10.2026) | monatlicher Dump auf GitHub | Steam-ID | ODbL + DbCL | erlaubt, aber kein Mac-Signal |
| **AreWeAntiCheatYet** | Anti-Cheat (schon im Einsatz) | 1.167 Spiele; Epic mit `namespace` + `slug` | JSON | Steam-ID, Epic-Namespace | MIT | erlaubt |

**Einzelheiten zu den wichtigsten Quellen**

- CodeWeavers
  - Skala: „?“ (unbewertet), 1 Will Not Install, 2 Installs Will Not Run, 3 Limited Functionality, 4 Runs Well, 5 Runs Great.
  - Die Übersicht zeigt die Bewertung der neuesten Version und „Last Tested: x.y.z (n)“. Unter …/rating-breakdown/<slug> steht die Aufschlüsselung nach CrossOver-Version.
  - Alte Bewertungen tragen den Hinweis „This rating is from several versions ago, and is considered inaccurate for the latest versions of CrossOver.“
  - Bewerten darf jeder mit einem kostenlosen CodeWeavers-Konto. Die Gewichtung ist (unsicher): Bewertungen von „Advocates“ zählen wohl mehr.
  - Die Datenbank, mit der CrossOver 25+ in „Auto“ den Grafikweg pro Spiel wählt, ist proprietär und steckt in CrossOver.

- AppleGamingWiki
  - Werte: perfect, playable, runs (grobe Fehler, nicht durchspielbar), menu, unplayable, unknown, na.
  - Versionen, Chips und Daten stehen nur als Freitext in {{Refdevice}}-Notizen. Die Daten sind verrauscht, z. B. Freitext im Bewertungsfeld oder Widersprüche: CS2 hat bei AGW „perfect“, bei Whisky „Garbage“.
  - Die Bewertungen gelten pro Seite, nicht pro Store.

- MacGamingDB
  - Konten über Magic Link, Apple oder Steam.
  - Moderation: Meldefunktion (höchstens 10 Meldungen pro Zeitfenster), ausgeblendete Berichte, Prüfung durch ein Sprachmodell.
  - Die robots.txt erlaubt alles. Das ist aber keine Lizenz.

### 2. Dürfen wir das?

| Quelle | Maschinell abrufen | Nächtlich spiegeln | Abgeleitete Daten in Nightforge weitergeben | Namensnennung |
|---|---|---|---|---|
| CodeWeavers | unklar (keine Bedingungen gefunden, robots.txt nicht prüfbar) | **ohne Erlaubnis nein** | **ohne Erlaubnis nein** (keine Lizenz heißt: alle Rechte vorbehalten) | – |
| AppleGamingWiki | erlaubt (öffentliche API, höflich mit User-Agent) | erlaubt mit Auflagen; Abruf des ganzen Bestands *unklar* | erlaubt als **eigene Datei unter CC BY-NC-SA 3.0**, nicht unter GPL | **Pflicht** |
| PCGamingWiki | nur mit Bot-Passwort, 60/Min | wie AGW | wie AGW | **Pflicht** |
| MacGamingDB | technisch offen, Lizenz fehlt: *unklar* | **nein** | **nein** | – |
| Wikidata | erlaubt | erlaubt | erlaubt | keine (freundlich: nennen) |
| ProtonDB-Dump | erlaubt | erlaubt | erlaubt; abgeleitete Datenbank bleibt ODbL | Pflicht |
| Whisky-Doku, Mythic, applesilicongames, Bottles | – | **nein** (keine Lizenz) | **nein** | – |
| Does It ARM | erlaubt | erlaubt | erlaubt (CC BY 4.0) | Pflicht |
| Verlinken auf alle oben | – | – | **immer erlaubt** | – |

**Verträgt sich CC BY-NC-SA mit der GPL? Nein, nicht als gemeinsames Werk.**

- Die FSF stuft NC-Lizenzen als unfrei und GPL-inkompatibel ein. Creative Commons nennt als GPLv3-kompatibel nur CC BY-SA 4.0, und das nur in eine Richtung.
- Erlaubt ist das Nebeneinander: GPLv3 §5 lässt ein „Aggregat“ aus getrennten Werken zu.
  - Der App-Code bleibt GPL.
  - Die AGW-Daten liegen als eigene Datei mit eigener Lizenz daneben, so wie heute LICENSE-areweanticheatyet.
  - Die App lädt die Datei zur Laufzeit von GitHub. Sie wird nicht in die App kompiliert und am besten nicht ins DMG gelegt.

- Folgen von ShareAlike: Auch unsere aus AGW abgeleiteten Stufen pro Steam-ID stehen unter BY-NC-SA. Darum dürfen sie nicht in profiles.json, die heute nur BSD-, MIT- und eigene Daten enthält.

**Erlaubt**

- Verlinken.
- Wikidata-IDs.
- AGW- und PCGW-Daten in einer getrennten Datei mit Nennung, Lizenz-Link und Hinweis auf Änderungen.
- Einzelne Fakten wie „nutzt DX11“ oder „Easy Anti-Cheat“: Fakten sind in den USA nicht geschützt.
- Den ProtonDB-Dump unter ODbL.

**Unklar**

- Spenden: Ob Spenden „nicht kommerziell“ bleiben, ist nicht sicher geklärt. Gelegentliche Spenden gelten nach CC-Auslegung wohl als unkritisch.
- Notizen: Ob AGW-Bewertungen bloße Fakten sind, ist offen. Die Notiztexte sind sicher geschützt, darum übernehmen wir nur die Bewertung, die Version und einen Link.
- EU-Datenbankrecht: Den ganzen Bestand jede Nacht abzurufen, ist eine wiederholte, systematische Entnahme (Richtlinie 96/9/EG, Art. 7). Das Recht schützt nur Datenbanken von Herstellern aus der EU. Wer AGW und PCGW rechtlich betreibt und wo, ist (unsicher). CodeWeavers sitzt in den USA. Am einfachsten löst eine schriftliche Erlaubnis alle drei Fragen.

**Verboten**

- Wiki-Daten unter die GPL stellen.
- Wiki-Daten in einen Build packen, den Dritte verkaufen.
- Werbung oder Bezahlfunktionen auf diesen Daten.
- Den Login-Zwang oder die Cloudflare-Sperren von PCGW umgehen.
- MacGamingDB- oder CodeWeavers-Daten ohne Erlaubnis spiegeln.

### 3. Einbau

#### Ablauf in der nächtlichen Action

1. `scripts/fetch-agw.py` ruft die AGW-Seiten ab, alles mit eigenem User-Agent und Kontaktangabe, höchstens etwa 1 Anfrage pro Sekunde:
  - list=embeddedin&eititle=Template:Compatibility/macOS listet die Seiten auf.
  - prop=revisions&rvprop=content|timestamp mit 50 Seiten je Anfrage holt den Wikitext. Das sind rund 40 Anfragen.
  - Später nur noch geänderte Seiten über list=recentchanges.
  - Ausgelesen werden nur {{Compatibility/macOS}} und die Infobox: Bewertungen, steam appid, gogcom id. Aus den Notizen nimmt das Skript nur die Version (Muster CrossOver ?\d+(\.\d+)*, GPTK ?\d, D3DMetal, DXMT) und den Zeitstempel der Seite, keinen Notiztext.

2. `scripts/fetch-wikidata.py` stellt eine einzige SPARQL-Abfrage: Steam (P1733) mit OPTIONAL GOG (P12727) und Epic-Slug (P6278), gefiltert auf Videospiele.
3. `build-profiles.py` bekommt zwei neue Optionen: --agw agw.json --wikidata ids.json.
  - profiles.json bleibt permissiv und bekommt nur eine neue Alias-Tabelle aus Wikidata und AreWeAntiCheatYet.
  - Daraus abgeleitete AGW-Daten gehen in `profiles/agw.json`, mit Lizenzkopf und profiles/LICENSE-applegamingwiki.

4. Wenn eine Quelle ausfällt:
  - Fällt sie nur aus, bleibt der alte Stand, markiert als "stale".
  - Ändert sich ihr Format, schlägt der Lauf fehl, und die alte Datei bleibt gültig. Cartouche macht es genauso.
  - Die Prüfung in profiles.yml erweitern: Felder, IDs, und dass Mindestzahlen nicht unterschritten werden.

5. Nebenbei: GitHub schaltet geplante Workflows in öffentlichen Repos nach 60 Tagen ohne Aktivität ab. Bei nächtlichen Commits ist das unkritisch, aber gut zu wissen.

Beispiel für `profiles/agw.json` (Werte zur Veranschaulichung):

#### IDs über Steam, Epic und GOG

- Schlüssel bleibt die Steam-ID. Die Prüfung app_id.isdigit() kann bleiben.
- Neu ist eine Alias-Tabelle auf oberster Ebene, z. B. "aliases": {"gog": {"2049187585": "870780"}, "epic": {"<namespace>": "870780"}}. Ältere App-Versionen ignorieren unbekannte Schlüssel.
- GOG: Die Produkt-ID kommt aus Wikidata P12727, der AGW-Infobox (gogcom id) oder PCGW (GOGcom_ID).
- Epic:
  - Der stabilste Schlüssel ist der Namespace. AreWeAntiCheatYet führt Epic schon so ({"namespace": …, "slug": …}), aber nur für 73 Spiele.
  - Wikidata kennt nur den Store-Slug.
  - Der App-Name, den legendary verwendet, ist ein Codename, bei Control Calluna (unsicher), und passt zu keinem Titel.
  - Ob legendarys Metadaten den Namespace verlässlich mitbringen, bitte prüfen (unsicher).

- Rückfall Name: Titel normalisieren (™, ®, „Ultimate/Definitive/GOTY Edition“ weg, Satzzeichen weg) und nur eindeutige Treffer nehmen, markiert als "match": "name". Diese Treffer werden schwächer angezeigt. Heroic sucht AGW nur nach Titel und findet „Control Ultimate Edition“ deshalb nicht.

#### Abbildung auf unsere Stufen

| Nightforge | CodeWeavers | AppleGamingWiki | MacGamingDB | eigener Bericht |
|---|---|---|---|---|
| **Läuft gut** | 5 Runs Great, 4 Runs Well | perfect, playable | Excellent, Very Good, Good | „Lief gut“ |
| **Läuft mit Anpassungen** | 3 Limited Functionality; 4–5 mit „Tips“-Seite | – (nur über Notizen erkennbar, zu unzuverlässig) | Playable, Barely Playable | „Lief mit Anpassungen“ |
| **Läuft nicht** | 2 Installs Will Not Run, 1 Will Not Install | runs, menu, unplayable | Unplayable | „Lief nicht“ |
| **Anti-Cheat** | nie aus diesen Quellen, nur AreWeAntiCheatYet und die Analyse der Spieldateien |  |  |  |
| nicht verwenden | „?“, als veraltet markiert | unknown, na, Freitext | einzelner negativer Bericht |  |

**Regeln für die App**

- Rang in `Compatibility.rate`: Fremde Bewertungen kommen ganz am Ende, direkt vor „Nicht getestet“. Eigene Profile, Anti-Cheat, Mac-Version und die Ergebnisse von LaunchHealth gehen immer vor.
- Kennzeichnung: Die Plakette zeigt „laut Berichten“. Die Hilfe nennt Quelle und Version, z. B. „AppleGamingWiki · CrossOver 23.5“.
- Negatives sperrt nie: Eine negative fremde Bewertung blockiert keinen Download, anders als Anti-Cheat. Sie erscheint nur als Warnung.
- Widersprüche: Widersprechen sich Quellen, gilt „gemischt“, und das Spiel bleibt „Nicht getestet“ mit Hinweis.
- Grafikweg: Der größte praktische Nutzen ist ein Feld wie reportedGraphics (aus MacGamingDB oder aus AGW-Notizen wie „D3DMetal“). Damit stellt LaunchHealth.attempts diesen Weg nur an den Anfang der Reihenfolge. Die Ausweichwege bleiben, nichts wird hart umgestellt.

#### Andere Versionen als unsere

| Bewertet mit | Nähe zu Nightforge (winecx 4.7.3 / Wine 11.17, DXMT 0.80, D3DMetal 4.0b3) | positive Bewertung | negative Bewertung |
|---|---|---|---|
| CrossOver 26.x (seit 10.2.2026; Wine 11.0, D3DMetal 3.0, DXMT 0.72; Quellen bis 26.3 gesehen) | am nächsten | zählt voll | zählt voll |
| CrossOver 25.x (Wine 10, D3DMetal 2.1, „Auto“ pro Spiel mit DXMT) | nah | voll | nur als Warnung |
| CrossOver 23–24 (D3DMetal 1.x, GPTK 1–2) | mittel | als „wahrscheinlich“ | ignorieren |
| CrossOver ≤ 22, Whisky (etwa CrossOver 22 + GPTK 1) | weit | ignorieren | ignorieren |
| ohne Version (bei AGW der Normalfall) | Alter der letzten Seitenänderung | ≤ 24 Monate wie 23–24 | ignorieren |

- Asymmetrie: Positives altert langsam, Negatives schnell, weil Fehler mit neuen Versionen meist verschwinden. Control hatte unter CrossOver einen schwarzen Bildschirm, der mit 22 beziehungsweise D3DMetal behoben war.
- Grafikweg zählt mit: Ein „Runs Great“ von CrossOver sagt nicht, welchen Grafikweg „Auto“ gewählt hat. Nur MacGamingDB und manche AGW-Notizen nennen ihn.

#### Was es realistisch bringt (Steam-Top-100 vom 25.10.2026)

| Gruppe | Spiele | AGW: CrossOver- oder Wine-Bewertung | Whisky | Mythic |
|---|---|---|---|---|
| Läuft wahrscheinlich | 21 | 15 | 12 | 3 |
| Unsicher | 16 | 10 | 3 | 2 |
| Nur DirectX 12 | 9 | 2 | 2 | 1 |
| **Wo Wine-Daten zählen** | **46** | **≈27** | 17 (veraltet) | 6 |
| Mac-Version / Anti-Cheat / kein Spiel | 28 / 22 / 4 | (für uns ohne Nutzen) |  |  |

- Methode: Abgleich nach Namen, Fehler etwa ±2. Grundlage ist der AGW-Stand vom 7.7.2026, den Bourbon-OSS veröffentlicht. AGW-Bewertungen haben meist keine Version.
- Nicht messbar: MacGamingDB und CodeWeavers waren gesperrt. Beide dürften viele große Titel kennen. Bei MacGamingDB stehen aber meist nur 1–2 Berichte, bei CodeWeavers oft alte Versionen.
- Plätze 101–200 habe ich nicht gemessen, weil die Steam-Charts gesperrt waren. Ich erwarte eher weniger Abdeckung (unsicher).
- Wo der Abstand am größten ist: bei neuen DX12-Spielen. Dort helfen am ehesten MacGamingDB (D3DMetal-Berichte) und eigene Berichte.
- GOG: Was es auch auf Steam gibt, deckt die Steam-ID mit ab. GOG führt meist ältere DX9/DX11-Einzelspieler-Spiele, die AGW und CodeWeavers gut kennen. Exklusive Titel lassen sich nur über den Namen finden.
- Epic: Bei Spielen, die es auch auf Steam gibt, wie bei Steam. Für Epic-Exklusivtitel gibt es weder ein Epic-Feld bei AGW noch einen verlässlichen ID-Weg. Das ist der schwächste Teil.

### 4. Eigene Berichte der Nutzer

#### So machen es andere

| Projekt | Wie Berichte hereinkommen | Konto | Schutz | Daten offen |
|---|---|---|---|---|
| ProtonDB | Fragebogen auf der Website, Systeminfo aus Steam | Steam-Login | nur der letzte Bericht je Nutzer zählt; Mindestsystem; Formel nicht öffentlich | Dump unter ODbL, ohne Nutzer-IDs |
| MacGamingDB | Formular (Weg, Grafikweg, Leistung, FPS, Chip, Version) | Magic Link, Apple, Steam | Melden, Ausblenden, Prüfung durch Sprachmodell | nein |
| Heroic | sammelt nichts; zeigt ProtonDB, Steam-Deck-Status, AGW und eine eigene Mac-Anti-Cheat-Liste (MIT, seit 2/2026 nicht mehr aktualisiert) | – | – | – |
| Lutris | Installer-Skripte auf lutris.net, keine Bewertungen im Programm *(unsicher)* | Konto auf lutris.net | Moderation | – |
| Bottles | 39 Installer, Note vom Maintainer nach 6 Fragen, per PR | GitHub | Review | keine Lizenz |
| Whisky | Doku-Seiten per PR | GitHub | Review, Lint | archiviert |
| Mythic | geplante Bewertung „How well did X run?“ mit 5 Sternen nach dem Spiel; das Hochladen wurde nie gebaut („TODO … spam protection“) | – | – | – |
| AreWeAntiCheatYet | Issue-Formulare mit Pflicht-Beleg; Maintainer pflegt `games.json` | GitHub | Beleg, Review, CI | MIT |
| shadPS4, Vita3K, Xenia, Azahar | ein Issue pro Spiel, Status als Label; eine Action baut daraus JSON oder XML als Release | GitHub | Pflicht-Kästchen, Bot schließt falsch formatierte und doppelte Issues (Vita3K), „outdated“ nach 365 Tagen, Tester-Liste | Vita3K MIT, Xenia BSD |
| xemu | eigener Server, Token über eine Discord-Rolle | Discord | Token | warnendes Beispiel: alte anonyme Berichte zeigten die IP öffentlich |

#### Vorschlag

1. „Wie lief es?“ bleibt zuerst lokal.
  - Nach dem Spiel (ab ein paar Minuten Spielzeit) erscheinen drei Knöpfe: gut / mit Anpassungen / nicht, dazu „Nicht mehr fragen“.
  - Die Antwort fließt nur in die eigene Bewertung auf dem Mac. Nichts verlässt den Mac.

2. Teilen ist ein eigener, ausdrücklicher Schritt, standardmäßig aus.
  - Der Knopf „Bericht ansehen und teilen…“ zeigt den genauen Text.
  - Danach öffnet er im Browser ein vorausgefülltes GitHub-Issue, wie ProblemReport heute. Abschicken muss der Nutzer dort selbst.

3. Issue-Formular `.github/ISSUE_TEMPLATE/compat-report.yml`:
  - Kopf: labels: [report].
  - Textfelder mit id, damit die URL sie füllen kann. Ob sich Auswahllisten und Kästchen per URL vorbelegen lassen, ist (unsicher). Darum steht das Ergebnis in einem Textfeld, und die Action prüft es.
  - Pflicht-Kästchen: „Ich gebe diesen Bericht unter CC0 frei.“ Dann dürfen wir die Daten auch an AGW, MacGamingDB oder CodeWeavers weitergeben.

4. Action `reports.yml` läuft bei issues: [opened, edited] und braucht nur das eingebaute Token mit issues: write.
  - Sie liest die ### Feld-Abschnitte und prüft die festen Werte und das Format der IDs.
  - Fehlerhafte Berichte bekommen einen Kommentar und werden geschlossen. Gültige bekommen das Label report:valid und werden als erledigt geschlossen, damit die Issue-Liste sauber bleibt.

5. Nachts baut `scripts/build-reports.py` aus allen gültigen, nicht als invalid markierten Berichten die Datei `profiles/reports.json` (CC0). Sie enthält je Spiel und Grafikweg: Zahl der Antworten gut/Anpassungen/nicht, Chips, neueste Nightforge-Version und Datum.
6. Anzeige:
  - „1 Bericht“ steht nur als Text da.
  - Eine Stufe gibt es erst ab 3 verschiedenen Konten mit mindestens ⅔ Übereinstimmung, aus den letzten beiden Engine-Ständen.
  - Ein Grafikweg rückt in der Reihenfolge erst nach vorn, wenn mindestens 3 übereinstimmende Berichte ihn nennen.
  - Nach 12 Monaten oder einem Engine-Wechsel gilt ein Bericht als „alt“.

**Was gesendet wird, und nur nach Klick im Browser:**

- Store und Store-ID, Spielname
- Nightforge-Version; Versionen von winecx, DXMT, D3DMetal und DXVK
- tatsächlich genutzter Grafikweg und Herkunft des Profils (mac, umu, keins)
- Chip-Familie (z. B. „M5 Pro“), macOS-Version
- Ergebnis, Änderungen aus einer festen Liste (anderer Grafikweg, Bildratenlimit, Startoption, …), auf Wunsch eine FPS-Spanne und ein Freitext

**Nicht gesendet:**

- Namen der Steam-, Epic- oder GOG-Konten
- macOS-Benutzername und Pfade (vorher den Befund zu Benutzernamen in ProblemReport beheben)
- Seriennummer, Hardware-UUID, Bibliothek, genaue Spielzeit
- Logs, außer der Nutzer hängt sie selbst an

**Schutz gegen Spam und Manipulation**

- GitHub-Konto als Hürde, dazu ein Mindestalter des Kontos (z. B. 30 Tage, prüft die Action über GET /users/{login}).
- Pro Konto, Spiel und Nightforge-Version zählt nur der letzte Bericht, wie bei ProtonDB.
- Höchstens etwa 10 Berichte pro Konto und Tag.
- Nur feste Werte werden gezählt. Freitext erscheint nie in der App.
- Maintainer können Berichte mit invalid aussortieren.
- Auffällige Fälle gehen automatisch zur Prüfung, z. B. „läuft gut“ bei einem Spiel, das am Anti-Cheat scheitert.
- Später eine Tester-Liste mit mehr Gewicht, wie bei Vita3K.
- Eigene Tests gewinnen immer. Berichte ändern nie selbst die Starteinstellungen.

**Ehrlich bei „kein Konto, keine Telemetrie“**

- Nightforge selbst sendet nichts und läuft nicht im Hintergrund.
- Teilen ist Opt-in, pro Bericht, mit Vorschau.
- Ehrlich dazusagen: „Zum Teilen brauchst du ein GitHub-Konto. Dein GitHub-Name steht öffentlich am Bericht, und GitHub sieht deine IP-Adresse.“
- Anonym ohne GitHub-Konto ginge nur über einen Vermittler, z. B. einen kostenlosen Cloudflare Worker mit Turnstile und einer GitHub App (Vorbilder: design4pro/astro-github-support-form, buvis/feedback). Das ist in der Praxis doch ein Server: Er sieht IPs und braucht eine Datenschutzerklärung. Für den Anfang nicht empfohlen.
- Der Fahrplan sieht für Phase 8 einen „kleinen Server“ vor. Der GitHub-Weg kommt ohne ihn aus.

Skizze des Formulars:

### 5. Befund Control

**Eckdaten**

- Steam 870780; GOG 2049187585; Epic App-Name Calluna (unsicher, aus einer Vortex-Erweiterung).
- Control.exe ist ein Startprogramm (braucht laut PCGW .NET 3.5). Die Spiele selbst sind Control_DX11.exe und Control_DX12.exe. -dx11 und -dx12 wählen den Weg (laut PCGW, nur über Dritte gesehen).
- Bei Epic erschien es 2019 ohne DRM; GOG ist DRM-frei.
- Anti-Cheat: keiner gefunden.

**Was die Quellen zum Mac sagen**

| Quelle | Aussage | Grafikweg | Version, Stand |
|---|---|---|---|
| Native Mac-Version | „Control Ultimate Edition“ für Apple Silicon (macOS 14+, M1+; Raytracing ab M3) im Mac App Store seit etwa 26.3.2025; auf Steam laut einer Fan-Seite seit etwa Dezember 2025 *(unsicher)* | Metal | – |
| CodeWeavers „Control“ | **Runs Great**, Last Tested 26.0.0 (1 Bewertung), auch Bewertungen für 25.1.1, 25.0.1, 24.0.5; Kopf: macOS 14, CrossOver 23.5, 1080p Ultra, 60 FPS | nicht angegeben | *(nur Suchtreffer)* |
| CodeWeavers „Control Ultimate Edition“ | eigener Eintrag: mit 25.0.0 auf macOS 15 bis ins Spiel | nicht angegeben | *(nur Suchtreffer)* |
| AppleGamingWiki | CrossOver **perfect** („Solid 30 fps on M1 Pro with Crossover 23.5 and Heroic“, also Epic- oder GOG-Version; „Dark screen fixed with D3DMetal and DX12“); Wine/GPTK **perfect** („Control_DX12.exe in Control.exe umbenennen“); Parallels playable (DX11-Programm); nativ perfect | **DX12 + D3DMetal** | CrossOver 22–23.5, 2021–23 |
| r/macgaming (3/2025, M4 Max, 2K) | CrossOver mit D3DMetal ~58 FPS ohne Raytracing, 39–41 FPS mit RT High; nativ 49–63 bzw. 40–46 | D3DMetal (GPTK 2) | *(Einzelbericht)* |
| Whisky / Mythic | Platinum / 5 von 5, ohne Details | GPTK | 2024 |
| DXMT | kein Issue, kein Profil für Control | – | – |
| MacGamingDB | nicht prüfbar (gesperrt) | – | – |
| ProtonDB (Linux) | 432 Berichte, 402 „läuft“ | – | Okt 2026 |

**Folgerung:** Jeder dokumentierte Erfolg auf dem Mac nutzt **DirectX 12 über D3DMetal** oder die native Version. DX11 über DXMT oder DXVK ist nirgends belegt. Das passt zum Absturz am 1.11. mit der Epic-Version unter DX11.

**Fallen**

1. Das Startprogramm. Der GPTK-Tipp „DX12-Programm in Control.exe umbenennen“ zeigt, dass der Launcher selbst das Problem sein kann.
  - Meine Vermutung (unsicher): Startet Epic Control.exe und findet GameAnalysis darin keine D3D-Importe, besteht die Liste der Versuche nur aus DXMT und DXVK, und D3DMetal kommt gar nicht dran.
  - Mit graphics: d3dmetal im Profil steht D3DMetal bei Spielen mit DX11 und DX12 an erster Stelle (LaunchHealth.swift:27). Das greift aber nur, wenn die Analyse beide APIs erkennt.
  - Den Epic- und GOG-Code von Nightforge enthält mein Checkout nicht. Das hier ist abgeleitet.

2. DX11 als Standard führt offenbar in den Absturz oder einen schwarzen Bildschirm.
3. Namen und IDs: „Control“ und „Control Ultimate Edition“ sind bei CodeWeavers getrennte Einträge. Der Epic-Codename Calluna passt zu keinem Titel, und Heroic findet die AGW-Seite nicht.
4. Raytracing gibt es nativ erst ab M3. Über D3DMetal ist es nur für den M4 Max berichtet.
5. Steam-Besitzer sollten die native Version bekommen. Ob Steam für 870780 ein 64-bit-macOS-Depot anbietet, war hier nicht prüfbar. Wenn ja, wählt Nightforges Mac-Weg es von selbst. Epic und GOG liefern vermutlich nur Windows (abgeleitet).
6. EOS-Overlay oder andere Epic-Eigenheiten: keine Quelle gefunden (ungeprüft).

**Test**

1. Bei der Epic-Version Control_DX12.exe direkt mit D3DMetal starten, hilfsweise Control.exe -dx12.
2. Wenn das läuft, in mac.json eintragen:

- Dazu braucht es ein neues Profilfeld für das Startprogramm (z. B. executable; gibt es heute nicht) und den Epic- und GOG-Alias auf 870780.

### 6. Gesperrte Hosts und was ungeprüft blieb

**Gesperrt** (die Netzwerkregeln dieser Umgebung haben DNS oder Verbindung verweigert):

- CodeWeavers: www.codeweavers.com, crosstie.codeweavers.com, media.codeweavers.com
- Wikis: applegamingwiki.com, pcgamingwiki.com, wikidata.org, query.wikidata.org, wikipedia.org
- Mac-Spieleseiten: applesilicongames.com, macgamingdb.app, portingkit.com, getmythic.app, doesitarm.com, isapplesiliconready.com, parallels.com
- Spiele und Stores: protondb.com, store.steampowered.com, api.steampowered.com, steamspy.com, isthereanydeal.com, lutris.net, api.igdb.com
- Lizenz- und Rechtstexte: gnu.org, creativecommons.org, eur-lex.europa.eu
- Sonstige: reddit.com (über einen Spiegel gelesen), docs.google.com, web.archive.org, atpeaz.com, alanwake.info, winehq.org
- Bei GitHub ging nur Lesen über git clone, raw.githubusercontent.com und die Suche.

**Dadurch ungeprüft:**

- Nutzungsbedingungen und robots.txt von CodeWeavers.
- Die Control-Seiten bei CodeWeavers und AGW im Original (nur Suchtreffer und der Bourbon-Stand).
- Die AGW-Lizenz in der Fußzeile.
- Der genaue Wortlaut der PCGW-API-Seite.
- Abdeckung von MacGamingDB und CodeWeavers bei den Top-100 und bei Control.
- Die Abdeckung von Wikidata.
- Die Steam-Mac-Version von Control.
- Die Plätze 101–200 der Steam-Charts.

Freigeben lassen sich die Hosts in den Einstellungen der Umgebung: Umgebungsmenü in der Titelleiste der Sitzung → Edit → Network access, dann die Hosts unter „Allowed domains“ eintragen. Anleitung: [https://code.claude.com/docs/en/cloud-environments#network-access](https://code.claude.com/docs/en/cloud-environments#network-access)

### 7. Quellen

**CodeWeavers und CrossOver**

- https://www.codeweavers.com/compatibility
- https://www.codeweavers.com/compatibility/rating-system
- https://www.codeweavers.com/compatibility/crossover/control
- https://www.codeweavers.com/compatibility/crossover/media/control-ultimate-edition
- https://support.codeweavers.com/en_US/the-compatibility-database
- https://support.codeweavers.com/en_US/advanced-settings-in-crossover-mac
- https://www.codeweavers.com/privacy-policy
- https://www.codeweavers.com/crossover/eula
- https://www.codeweavers.com/crossover/changelog
- https://phoronix.com/news/CrossOver-26
- https://www.omgubuntu.co.uk/2026/02/crossover-26-released
- https://appleinsider.com/articles/26/02/10/crossover-26-update-adds-compatibility-for-blockbuster-expedition-33-and-helldivers-2
- https://alternativeto.net/news/2026/2/crossover-26-released-with-wine-11-ntsync-on-linux-and-support-for-many-new-games-on-mac

**AppleGamingWiki und PCGamingWiki**

- https://www.applegamingwiki.com/wiki/Control
- https://www.applegamingwiki.com/wiki/Template:Rating
- https://www.applegamingwiki.com/wiki/AppleGamingWiki:Editing_guide
- https://www.applegamingwiki.com/w/api.php
- https://github.com/PCGamingWiki/appleclocked
- https://www.pcgamingwiki.com/wiki/PCGamingWiki:API
- https://www.pcgamingwiki.com/wiki/Control
- https://github.com/PCGamingWiki/api
- https://github.com/tosdr/tosdr-snapshots (Kopie der PCGW-Rechtsseite)

**Wikidata und IGDB**

- https://www.wikidata.org/wiki/Property:P1733
- https://www.wikidata.org/wiki/Property:P12727
- https://www.wikidata.org/wiki/Property:P2725
- https://www.wikidata.org/wiki/Property:P6278
- https://www.wikidata.org/wiki/Property:P6337
- https://query.wikidata.org/
- https://discuss.dev.twitch.com/t/commercial-use-of-igdb-api/23567

**MacGamingDB und andere Mac-Launcher**

- https://macgamingdb.app
- https://github.com/neo773/macgamingdb (`docs/NOTICE.md`, `docs/seo-issues.md`, `packages/macgamingdb-server/src/database/schema.ts`, openapi.json)
- https://github.com/PyroSoftPro/Bourbon-OSS (`tools/compat_sources.py`, `data/community_compat.json`)
- https://github.com/BRYANN2K/cartouche (`docs/DATA-SCHEMA.md`, `tools/compat/fixtures/README.md`)
- https://github.com/HyperPlay-Gaming/hyperplay-desktop-client
- https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher (src/backend/wiki_game_info/)
- https://github.com/Heroic-Games-Launcher/MacAnticheatData
- https://github.com/MythicApp/Mythic (HarmonyRatingView.swift)
- https://github.com/MythicApp/Compatibility-Database

**Weitere Listen**

- https://www.applesilicongames.com/
- https://github.com/ThatGuySam/doesitarm
- https://github.com/Whisky-App/Whisky
- https://github.com/Whisky-App/whisky-book (`src/game-support/control-ultimate-edition.md`)
- https://github.com/3Shain/dxmt (Wiki, `src/util/config/config.cpp`)
- https://github.com/apple/homebrew-apple
- https://github.com/Gcenx/game-porting-toolkit
- https://github.com/Sikarugir-App/Sikarugir
- https://www.paulthetall.com/mac-games-ports/
- https://kb.parallels.com/en/122485
- https://github.com/bottlesdevs/programs
- https://github.com/lutris/lutris
- https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet

**Berichtssysteme**

- https://www.protondb.com/contribute
- https://github.com/bdefore/protondb-data
- https://github.com/shadps4-compatibility/shadps4-game-compatibility
- https://github.com/Vita3K/compatibility
- https://github.com/xenia-canary/game-compatibility
- https://github.com/azahar-emu/compatibility-list
- https://github.com/xemu-project/xemu-website
- https://github.com/design4pro/astro-github-support-form
- https://github.com/buvis/feedback

**GitHub-Dokumentation**

- https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms
- https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue
- https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- https://docs.github.com/en/site-policy/github-terms/github-terms-of-service
- https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies

**Lizenzen und Recht**

- https://www.gnu.org/licenses/license-list.html
- https://creativecommons.org/compatiblelicenses
- https://wiki.creativecommons.org/wiki/ShareAlike_compatibility:_GPLv3
- https://wiki.creativecommons.org/NonCommercial_interpretation
- https://wiki.creativecommons.org/4.0/Sui_generis_database_rights
- https://eur-lex.europa.eu/eli/dir/1996/9/2019-06-06/eng
- https://opendatacommons.org/licenses/odbl/

**Control**

- https://www.atpeaz.com/install-play-control-on-macos/
- https://www.reddit.com/r/macgaming/comments/1jjna3v/
- https://www.macrumors.com/2024/11/20/control-ultimate-edition-mac-february-12-2025/
- https://appleinsider.com/articles/25/03/27/wuthering-waves-and-control-ultimate-edition-now-available-on-mac
- https://www.alanwake.info/2025/12/31st-december-2025-mac-version-of.html
- https://apps.apple.com/app/id6502953520

**Nightforge intern**

- `docs/TODO.md` (Abschnitt „Abdeckung der Top 100“)
- Übersicht „Steam Top 100 auf dem Mac“ vom 25.10.2026: [Steam Top 100 auf dem Mac](https://claude.ai/artifact/TWQ3kkV6W7szsgyPyh6dWp) (nur für den Besitzer sichtbar)
- `Sources/Nightforge/Compatibility.swift`, LaunchHealth.swift, GameAnalysis.swift, ProblemReport.swift
- `scripts/build-profiles.py`, `.github/workflows/profiles.yml`, `components/manifest.json`
