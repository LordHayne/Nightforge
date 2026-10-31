# Entwurf: Mehr Infos pro Spiel („Über das Spiel“)

Stand 31.10.2026, Phase 1 (Recherche und Entwurf) abgeschlossen; der Nutzer hat entschieden (siehe unten). Gebaut wird erst nach dem OK des Nutzers und nachdem
2.5 (größere Schrift) und 7.3 (GOG) in `claude/ux-roadmap-next` gemergt sind. Phase 2 nimmt die Korrektur der
Bibliotheksfilter „Controller“ und „Läuft super“ für Epic- und GOG-Spiele mit, weil sie dieselbe Datenschicht braucht.

Wunsch des Nutzers: Das Aussuchen soll mehr Spaß machen, „kurze Spielbeschreibung usw.“, so wie in Steam,
GOG Galaxy, Heroic und Playnite.

## Kurz

- Die Spielseite scrollt. Der erste Bildschirm bleibt, wie er ist. Unter dem Logo stehen 2 Zeilen Beschreibung und
  „Mehr über das Spiel ⌄“. Darunter kommt der Abschnitt **Über das Spiel**: Screenshots, Beschreibung, Genres,
  „So spielt man es“ (Einzelspieler, Online-Koop, Lokaler Koop, Geteilter Bildschirm, Gegeneinander) und die
  Karte „Auf einen Blick“ (Entwickler, Publisher, Erschienen, Deutsch Text/Sprachausgabe, Altersfreigabe).
- Steam liefert fast alles, vieles sogar offline aus `appinfo.vdf`. Epic gibt ohne Anmeldung kaum etwas her. Für
  Epic und GOG nimmt Nightforge darum **dasselbe Spiel auf Steam**. Das findet GOGs öffentliche GamesDB per ID,
  nicht über den Namen: 40 von 40 Epic-Spielen des Nutzers gefunden, 39 davon mit Steam-ID.
- Mit diesem Steam-Gegenstück funktionieren dann auch die Filter „Controller“ und „Läuft super“ für Epic und GOG.
- Für Steam selbst ist Steams **Store-Browse-API** (`IStoreBrowseService/GetItems`, ohne Schlüssel) die beste Quelle.
  Sie liefert 50 Spiele in einer Anfrage (0,6 s): deutsche Kurzbeschreibung, Entwickler, Tags, Spielmodi,
  Controller, Sprachen mit Ton/Untertiteln, USK, Bewertung („Sehr positiv · 90 %“), Screenshots und die
  **Cover-Adressen mit Hash**. Ohne diese Adressen bleiben die Cover neuer Store-Treffer leer.
- **Bibliothek** (Zusatzauftrag): eine Zeile mit drei Chips, „Alle Stores ▾“, „Zuletzt gespielt ▾“ und „Filter ▾“.
  Die Filter liegen in einem kleinen Glas-Panel, aktive Filter stehen als abwählbare Chips in der Zeile. So bleibt
  sie auch bei 980 pt einzeilig. Eine Suche findet immer alles, Filter und Store ruhen so lange.

## Bilder (Offscreen-Render der echten Views, auf dem Stand von 2.5)

Gerendert mit einer Kopie der echten `LibraryView` und den Prototyp-Views. Overcooked! 2 ist hier ein Epic-Spiel,
das seine Angaben vom Steam-Gegenstück bekommt (echte Daten vom 31.10.). No Man's Sky ist ein Steam-Spiel.

| Bild | Was |
|---|---|
| `images/spielinfos/1-seite-oben-1512.jpg` | Spielseite wie heute, plus 2 Zeilen Beschreibung unter dem Titel; unten lugt „Über das Spiel ⌄“ herein |
| `images/spielinfos/2-seite-unten-1512.jpg` | Nach dem Scrollen: Screenshot-Leiste, Beschreibung, Genre-Chips, Spielmodi, Karte „Auf einen Blick“ mit Hinweis „Angaben von Steam“ |
| `images/spielinfos/3-seite-oben-980.jpg` | Kleinstes Fenster (980 × 640): Die Beschreibung weicht als Erstes, damit „Spielen“ sichtbar bleibt |
| `images/spielinfos/4-seite-unten-980.jpg` | Kleinstes Fenster, gescrollt: 3 Kacheln, die letzte mit „+192 Bilder“ |
| `images/spielinfos/5-bild-gross-1512.jpg` | Ein Screenshot groß, über allem: ← →, Esc schließt |
| `images/spielinfos/6-startseite-mit-zeile-980.jpg` | Verworfene Variante: Startseite mit dem ersten Satz → läuft bei 980 × 640 über |
| `images/spielinfos/7-startseite-heute-980.jpg` | Startseite heute zum Vergleich (schon ohne Zeile voll, siehe Nebenfunde) |
| `images/spielinfos/8-filterzeile-1512.jpg` | Bibliothek mit der neuen Zeile: „Alle Stores ▾ · Zuletzt gespielt ▾ · Filter ▾“, Sortierung nicht mehr oben rechts |
| `images/spielinfos/8b-filterzeile-980.jpg` | Dasselbe im kleinsten Fenster: eine Zeile, Suche neben dem Titel |
| `images/spielinfos/9-store-menue-1512.jpg` | Klick auf den Store-Chip: kleines Glas-Menü mit Zahlen je Store |
| `images/spielinfos/10-nur-epic-1512.jpg` | Nur Epic: Chip gefüllt, Zahl oben „93 von 198 Spielen“ |
| `images/spielinfos/11-filter-panel-pad-980.jpg` | Filter-Panel im kleinsten Fenster, Pad-Rahmen auf „Zu zweit am Mac“; zwei aktive Filter als Chips mit ✕ in der Zeile |
| `images/spielinfos/12-suche-overcooked-1512.jpg` | Suche: Overcooked! 2 von Epic unter „Deine Spiele“, der Steam-Treffer „Overcooked! 2“ fehlt (Gegenstück), die Zeile sagt „Filter und Store ruhen“ |
| `images/spielinfos/13-suche-sheep-1512.jpg` | Store-Treffer mit echten Covern aus der Store-Browse-API; zwei Spiele ohne Hochformat-Cover zeigen noch den Platzhalter |

Das Harness (Prototyp-Views `Proto.swift`, Patch der Spielseite, Render-Treiber) und die Rohdaten liegen außerhalb
des Repos im Notizordner der Sitzungsgruppe unter `game-metadata/`.

## Ist-Stand

- **Spielseite** (`DetailLevel` → `GameDetail` + `ThisGameCard`, LibraryView.swift): Sie scrollt nicht und ist
  unten ausgerichtet. Über dem Titel steht `MetaLine` (Läuft super · GENRE / JAHR · STORE), darunter Kennzahlen
  (Zuletzt gespielt, Spielzeit, Größe, Metascore, Controller). Bei 980 × 640 ist der erste Bildschirm schon voll.
- **Daten** (`StoreFacts`, `SteamCatalog.storeFacts`): Tags, Genres, Jahr und Metascore. Sie kommen nur aus Steams
  `appinfo.vdf` und nur für Spiele mit Steam-Eintrag. `StoreSearch.details` fragt `appdetails` nur nach Preis,
  Plattformen, Metascore und Controller.
- **Epic** (`EpicStore`): legendarys `metadata/*.json` werden schon gelesen (Kategorien, Bilder, Namespace).
- **Filter** (`LibraryFilters.admits`): „Controller“ prüft `game.controller == .full`, das nur Steam setzt.
  „Läuft super“ geht über `compatibility(of:)`, das Profile nur per `steamAppID` sucht. Epic und GOG fallen
  deshalb immer heraus (Overcooked! 2 von Epic zeigt „Maus & Tastatur“).

## Quellen je Store

| | Steam (eigenes Spiel) | Epic | GOG |
|---|---|---|---|
| **Schon auf der Platte** | `appinfo.vdf`, je Spiel unter `common`: `associations` (Entwickler, Publisher), `category` (Spielmodi, Controller), `supported_languages` (je Sprache `supported`/`full_audio`/`subtitles`), `steam_release_date`, `genres`, `store_tags`, `metacritic_score`, `review_percentage`. Keine Beschreibung, keine Screenshots. | legendary `metadata/<AppName>.json`: Titel, `developer` (meist die Firma hinter dem Konto), Bilder (`DieselGameBox` breit, `DieselGameBoxTall` Cover, **kein Logo**). `description` ist bei 87 von 105 Spielen nur der Titel, sonst Englisch. Kein Genre, kein Erscheinungsjahr (`creationDate` ist das Katalogdatum), keine Modi. | Was der GOG-Zweig schon holt: GamesDB `platforms/gog/external_releases/<id>` (Titel, Cover, Hintergrund, Mac). Im selben Antwort-JSON stehen schon `game.releases` (mit Steam-ID), `summary` (nur Englisch), `genres`, `game_modes`, `screenshots`. |
| **Online, ohne Login** | **Erste Wahl:** `api.steampowered.com/IStoreBrowseService/GetItems/v1?input_json=…` (ohne Schlüssel, bis 50 App-IDs pro Anfrage, `context.language = german`). Je Spiel: `basic_info.short_description` (Deutsch), Entwickler, Publisher, `tagids` mit Gewicht, `categories` (getrennt nach Spielern, Merkmalen und Controller), `release`, `reviews` („Sehr positiv“, 90 %), `game_rating` (`agency` 4 = USK; 17 ist Steams eigene Einstufung und zählt nicht), `supported_languages` (je Sprache `full_audio`/`subtitles`), `screenshots`, `trailers` und `assets` (`library_capsule`, `library_hero`, `header` mit Hash-Pfad). Gemessen: 50 Spiele, 268 KB, 0,6 s. **Rückfall:** `store.steampowered.com/api/appdetails?appids=…&l=german&cc=DE` (ein Spiel pro Anfrage): `short_description` (Deutsch), `genres`, `categories` (deutsche Namen und IDs), `developers`, `publishers`, `release_date`, `screenshots` (600×338 und 1920×1080), `movies` (HLS/DASH), `ratings` (`usk`, `pegi`, `esrb`; dazu Steams eigene erzeugte Einstufungen, die nicht zählen), `supported_languages` (HTML, `*` = Sprachausgabe), `controller_support`. | GraphQL (`store.epicgames.com/graphql`, auch `launcher.store…`): **403, Cloudflare-Prüfung**, nicht nutzbar (und nicht zu umgehen). Katalog (`catalog-public-service…/bulk/items`): **401, braucht Login**. Alter Inhaltsdienst `store-content-ipv4.ak.epicgames.com/api/de/content/products/<slug>`: Deutsch, mit Kurzbeschreibung, Entwickler, Datum, Sprachen nach Text/Ton und PEGI. Er braucht aber den Slug und traf nur **16 von 30** (neuere Produkte fehlen). → **Steam-Gegenstück** | `api.gog.com/v2/games/<id>?locale=de-DE`: `overview`/`description` (Deutsch, HTML), Entwickler, Publisher, `globalReleaseDate`, `tags` (deutsche Genres), `features` (`single`, `multi`, `coop`, `controller_support` …), `localizations` (je Sprache `text`/`audio`), `screenshots` (Größen über `formatter`, z. B. `product_card_screenshot_748`), `videos` (YouTube), `pegiRating`/`esrbRating`. Cache-Control 1 Tag. |
| **Sprache** | `l=german`/`english` nach `AppLanguage` (wie `StoreSearch.regionItems`) | über das Steam-Gegenstück; GamesDB nur Englisch | `locale=de-DE`/`en-US` |
| **Stabilität** | Beide undokumentiert. GetItems nutzt Steams eigener Store (Web und Client), appdetails seit Jahren gleich (Heroic, Playnite, Lutris). appdetails: etwa 200 Anfragen pro 5 Minuten und IP (Erfahrungswert, darüber 429/403); GetItems braucht für 200 Spiele 4 Anfragen. | GamesDB: öffentlich, von GOG Galaxy für alle Plattformen genutzt | v2 wird von Galaxy und Heroic genutzt |

**Steam-Gegenstück (eine Datenschicht für Seite und Filter):**
1. Steam-Spiel: die eigene App-ID.
2. Epic: `gamesdb.gog.com/platforms/epic/external_releases/<AppName>` → `game.releases[platform_id == "steam"]`.
   Gemessen am 31.10. mit 40 Epic-Spielen des Nutzers: 40 gefunden, 39 mit Steam-ID (ohne: Evil Dead: The Game).
   Die Katalog-ID und der Namespace von Epic geben 404, es zählt der AppName.
3. GOG: dieselbe Liste steckt schon in der GamesDB-Antwort, die `GOGRelease.from(gamesDB:)` liest. Phase 2 merkt
   sich daraus nur noch `steamAppID`, ohne eine Anfrage mehr.
4. Sonst über den Namen: `StoreSearch.search(name)`, aber nur bei genau gleichem Namen nach dem Normalisieren
   (Kleinschreibung, ohne ™®©, Satzzeichen, Leerraum). Ein falsches Gegenstück ist schlimmer als keins.
5. Wo nichts gefunden wird: die eigenen Daten des Stores (GOG v2 vollständig; Epic: der alte Inhaltsdienst per
   Slug, dann legendarys Entwickler und eine echte Beschreibung, wo eine da ist).

## Entwurf: was wo erscheint

**Spielseite, erster Bildschirm (Bild 1, 3).** Er bleibt wie heute, mit zwei Ergänzungen:
- Unter Logo oder Titel stehen 2 Zeilen Kurzbeschreibung (15 pt, `Theme.ink` 82 %, wie der Satz der Startseite),
  darunter der Link „Mehr über das Spiel ⌄“ in Natriumgelb. Er scrollt nach unten, statt aufzuklappen, damit
  nichts springt.
- **Der Play-Knopf bleibt immer auf dem ersten Bildschirm.** `ViewThatFits` probiert 2 Zeilen, 1 Zeile, keine.
  Bei 980 × 640 bleibt so keine Zeile (Bild 3), dann steht die Beschreibung nur unten. Das Logo gibt wie in 2.5
  zuerst nach.
- Unten lugt die Überschrift „ÜBER DAS SPIEL ⌄“ herein: Die Seite zeigt so, dass es weitergeht.
- `MetaLine` bekommt Genre und Jahr jetzt auch für Epic und GOG („GELEGENHEITSSPIEL / 2018 · EPIC GAMES“).

**Spielseite, nach dem Scrollen (Bild 2, 4).** Hinter der Seite bleibt die Hero-Grafik stehen. Ein Verlauf zu
`Theme.night` 90 % scrollt mit und dunkelt sie ab. Es gibt keinen Blur, nur eine billige Ebene (UI-Leistung).
Oben blendet die Seite unter der Kopfleiste weich aus (`scrollEdgeEffectStyle(.soft)` ab macOS 26, vorher harter
Rand wie heute; offscreen nicht sichtbar).
1. **Screenshot-Leiste**: So viele ganze 16:9-Kacheln, wie in die Breite passen (150 pt hoch, im kleinsten Fenster
   118). Die letzte zeigt „+N Bilder“. Die Vorschaubilder kommen erst beim Öffnen der Seite und werden auf
   Kachelgröße verkleinert gecacht. Ein Klick (Pad: A) zeigt das Bild groß (Bild 5): ← → blättern, Esc/B schließt.
   Das große Bild wird erst dann geladen und nur im Speicher gehalten. Höchstens 12 Bilder pro Spiel.
2. **Links**: die ganze Kurzbeschreibung, darunter bis zu 4 Genre-Chips, dann „SO SPIELT MAN ES“ mit Chips aus
   Symbol und Wort: Einzelspieler · Online-Koop · Lokaler Koop · Geteilter Bildschirm · Gegeneinander. Es stehen nur
   die da, die zutreffen.
3. **Rechts** die Karte „AUF EINEN BLICK“: gleich breit wie „Dieses Spiel“ darüber (310 pt), dickes Glas. Darin
   Entwickler, Publisher (oder eine Zeile „Entwickler & Publisher“, wenn beide gleich sind), Erschienen,
   „Deutsch ✓ Text ✓ Sprachausgabe“ (auf englischen Macs fehlt die Zeile) und die Altersfreigabe als Farbschild:
   USK in Deutschland, sonst PEGI, sonst ESRB, Steams eigene erzeugte Einstufungen nie. Bei Angaben vom Gegenstück
   steht darunter „Angaben von Steam – dasselbe Spiel dort.“
   Controller steht schon oben bei den Kennzahlen und kommt hier nicht noch einmal.

**Startseite (Bild 6, 7):** Empfehlung: keine Beschreibung. Die Spalte ist bei 980 × 640 heute schon voll, mit dem
ersten Satz läuft sie unter die Leiste. Bei Spielen „Als Nächstes“ sagt der Satz von StarterPicks schon, warum
dieses Spiel.

**Bibliothek:** Die Karten bleiben Cover und Name. Mehr Text unter 154 pt breiten Covern macht das Raster unruhig.

## Bibliothek: Filterzeile, Store-Filter, Store-Treffer (Zusatzauftrag 31.10.)

Heute stehen oben rechts die Sortierung als Segment („Zuletzt gespielt | Name | Speicherplatz“) und die Suche.
In der Zeile darunter stehen das Segment „Alle | Auf diesem Mac | Nicht geladen“ und die drei Schalter
„Läuft super“, „Controller“ und „Mac-Version“. Bei 980 pt rutscht die Sortierung schon in eine eigene Zeile. Ein
Store-Filter hätte keinen Platz mehr.

**Neue Zeile (Bild 8, 8b, 10):** Oben stehen Titel, Zahl und Frische links, rechts nur die Suche (und
„Ausgeblendet 3“ davor, wenn es ausgeblendete Spiele gibt, wie heute). Darunter folgen drei Chips aus Glas, in
gleicher Höhe wie heute (32 pt):
1. **„Alle Stores ▾“**, nur wenn mindestens zwei Stores verbunden sind. Mit dem Pad schaltet A weiter:
   Alle → Steam → Epic Games → GOG → Alle (nur verbundene Stores). Ein Mausklick öffnet ein kleines Glas-Menü mit
   der Zahl je Store (Bild 9). Ein gewählter Store füllt den Chip hell wie heute ein aktiver Schalter
   („Epic Games ▾“). Gemeinsame Karten („STEAM + EPIC“) zählen bei jedem ihrer Stores, das sagt eine Zeile unten im
   Menü. Oben steht dann „93 von 198 Spielen“ (gibt es schon: `countText`, sobald `filters.narrows`).
2. **„Zuletzt gespielt ▾“**: Sortierung als ein Chip. A schaltet weiter, ein Klick öffnet dasselbe kleine Menü.
3. **„Filter ▾“** öffnet ein Glas-Panel (Bild 11). Jeder Filter ist ein Schalter mit der Zahl der Spiele, die er
   übrig lässt: Läuft super · Mit Controller spielbar · Zu zweit am Mac (Lokaler Koop oder geteilter Bildschirm,
   neu aus den Spielmodi) · Mac-Version · Nur auf diesem Mac. Unten „Alle Filter aus“. Mit dem Pad: A öffnet,
   ↑↓ wandert, A schaltet, B schließt. Ein Klick daneben schließt wie bei `DownloadsPanel`. Am Chip steht die Zahl
   der aktiven Filter als Natriumpunkt.
4. Rechts neben einem Trennstrich stehen die **aktiven Filter als Chips mit ✕**, ein Klick oder A nimmt den Filter
   heraus. Passen nicht alle in die Zeile, steht nur der erste da und „+2“ (`ViewThatFits`). So bleibt die Zeile
   bei 980 pt einzeilig (Bild 11: Store, Sortierung, Filter und zwei aktive Chips passen gerade).

Pad: ↑ aus der ersten Rasterzeile erreicht die Chips wie heute die Segmente (`PadFocus`, IDs `library.store`,
`library.sort`, `library.filter`, `library.active.<n>`).

**„Auf diesem Mac / Nicht geladen“:** Bei „Zuletzt gespielt“ gruppiert das Raster schon nach „Installiert“,
„Wird geladen“ und „In deiner Bibliothek“. Das Segment wiederholt das nur. Gebraucht wird es allein bei „Name“ und
„Speicherplatz“, wo das Raster eine Liste ist. Vorschlag: Das Segment fällt weg, im Panel steht der Schalter
„Nur auf diesem Mac“ (installiert oder lädt gerade). „Nicht geladen“ allein entfällt, dafür ist die Gruppe
„In deiner Bibliothek“ da.

**Während einer Suche** ruhen Filter und Store-Filter (nicht gelöscht): Die Suche findet immer alle Spiele. Heute
gelten die Filter weiter, und „Kein Spiel passt zu …“ verwirrt, wenn ein vergessener Filter das gesuchte Spiel
ausblendet. Statt der Chips steht dort eine graue Zeile: „Die Suche findet alle 198 Spiele – Filter und Store
ruhen, bis du sie leerst.“ (Bild 12). Die Sortierung spielt keine Rolle, Treffer kommen nach Güte. Ist die Suche
leer, ist alles wieder wie vorher.

**Store-Treffer bei der Suche („Im Steam-Store“):**
- **Steam allein reicht.** Treffer aus Steam sind die, die Nightforge am besten kann: Profile, „Läuft super“, Mac-
  Versionen, Anti-Cheat-Hinweis und Steam für Mac hängen alle an der Steam-App-ID. GOG ginge öffentlich
  (`catalog.gog.com/v1/catalog?query=like:<Begriff>&locale=de-DE&countryCode=DE`: Preise, Cover, Merkmale, 0,3 s),
  Epic nicht (keine Suche ohne Browser). Zwei Store-Gruppen machen die Suche länger, ohne dass der Nutzer
  mehr spielen kann.
- **Keine Treffer für Spiele, die man schon hat.** Heute zeigt „overcooked“ das eigene Overcooked! 2 von Epic *und*
  denselben Titel zum Kaufen auf Steam. Der Abgleich läuft nur über die `GameID` (`steam.728880` ≠ `epic.Potoo`).
  Mit dem Gegenstück fällt der Steam-Treffer weg (Bild 12).
- **Store-Filter:** Eine Suche lässt ihn ruhen wie die anderen Filter, Steam-Treffer kommen also immer (gebaut so, 31.10.).
- **Platzhalter-Cover** („A Sheep Game“, „Death a Live“): Neue Steam-Apps legen ihre Bilder nur noch unter einem
  Hash-Pfad ab (`/apps/5391790/<hash>/header.jpg`). Die festen Adressen in `ArtworkStore.remoteURLs`
  (`/apps/<id>/library_600x900_2x.jpg` usw.) geben dort 404. GetItems liefert `assets.library_capsule` samt Hash
  (Bild 13). Wenige kleine Spiele haben gar kein Hochformat-Cover (in Bild 13 zwei von 12). Für sie gibt es das breite
  `main_capsule` mittig auf einer einmal weichgezeichneten Kopie seiner selbst, wie die Bühne der Startseite.
  Das wird einmal berechnet und gecacht, ist also kein Live-Effekt. Gilt auch für eigene Spiele, deren Steam keine
  lokalen Bilder hat.

## Datenmodell und Cache (Phase 2)

```swift
/// What a game is, for its page and the library's filters: from its own store or the same game on Steam.
struct GameInfo: Codable, Equatable {
    var summary: String?                 // plain text, the Mac's language, else English
    var language: String                 // "de"/"en" – asked again when the app's language changes
    var genres: [String]                 // up to 4, in the app's language
    var developers: [String], publishers: [String]
    var released: Date?
    var modes: Set<PlayMode>             // .single, .onlineCoop, .localCoop, .splitScreen, .versus
    var controller: ControllerSupport?   // nil: nobody says
    var macLanguage: LanguageSupport?    // text / audio in the Mac's language
    var age: AgeRating?                  // system (USK/PEGI/ESRB) and age
    var screenshots: [Screenshot]        // thumbnail and full URL, up to 12
    var source: GameID                   // "steam.728880" for Overcooked! 2 from Epic
    var asked: Date
}
```

- Gebaut (31.10.): eine Datei `~/Library/Application Support/Nightforge/GameInfo/known.json` mit `infos` (nach Quelle,
  „steam.728880“) und `twins` (Epic-/GOG-Key → Steam-App-ID oder keine). 107 Spiele ≈ 390 KB. Application Support
  statt Caches, damit es offline sicher da ist. „Keins“ wird nach 30 Tagen neu gefragt.
- Neu gefragt wird nach 30 Tagen oder bei anderer App-Sprache. Offline bleibt das Alte stehen, wie bei `Metascores`.
- Screenshot-Vorschauen kommen nach `Caches/Nightforge/Artwork/<key>_shot<n>.jpg` (über `ArtworkStore`, neue
  `ArtKind.shot`, `maxPixelSize` 560).
- **Anfragen:** Steam-Infos kommen gebündelt über GetItems, 50 Spiele pro Anfrage. Nach einem Scan holt Nightforge
  alle fehlenden Infos nach (200 Spiele = 4 Anfragen, je 1 s Abstand), zuerst die Epic- und GOG-Gegenstücke (für die
  Filter) und die Spiele auf der Bühne. Dazu je Epic-Spiel einmal GamesDB (Zwilling, 1 Anfrage alle 0,5 s; danach
  gecacht) und je GOG-Spiel einmal GOG v2. Öffnet man eine Seite ohne Infos, wird sofort einzeln gefragt. Bei
  429/403 gibt es zehn Minuten Pause. Offline ändert sich nichts, `appinfo.vdf` liefert die Filterdaten eigener
  Steam-Spiele ohnehin.

**Filterkorrektur (gehört zu Phase 2):**
- `Game.controller` für Epic/GOG: vom Gegenstück (`controller_categoryids` 28 → voll, 18 → teilweise), sonst GOGs Merkmal
  `controller_support` (sagt nicht „teilweise“ → voll). Ohne Angabe bleibt der Wert unbekannt, nicht „keine“. Die
  Kennzahl zeigt dann „–“ statt „Maus & Tastatur“ (passt zu `StarterFacts.controller` als Optional im GOG-Zweig).
- `compatibility(of:)`: Profil per `game.gameID.steamAppID ?? twin(of: game)`. Damit greift „Läuft super“ auch bei
  Epic und GOG. Dasselbe gilt für die Profile beim Start (`ProfileStore.profile(for:)`). Ob dort schon das
  Gegenstück gelten soll, prüfe ich in Phase 2 einzeln: Ein Steam-Profil passt nicht zwingend auf Epics Build.
- Nach dem Nachholen ruft das Modell `applyFilter()` auf, damit die Filter das neue Wissen nutzen.

## Entscheidungen (Nutzer, 31.10., alle vier Empfehlungen angenommen)

1. **Kurzbeschreibung:** 2 Zeilen auf dem ersten Bildschirm, die bei kleinem Fenster als Erstes weichen. Der Rest
   steht unten beim Scrollen.
2. **Das Segment „Alle | Auf diesem Mac | Nicht geladen“ fällt weg.** Dafür kommt „Nur auf diesem Mac“ ins
   Filter-Panel.
3. **Store-Treffer nur von Steam**, ohne Spiele, die man in einem anderen Store schon hat, und mit echten Covern
   über den Hash-Pfad.
4. **In Phase 2 nur Screenshots**, Trailer später.

Dazu: Das kleine Extra „Steam-Logo für Epic- und GOG-Spiele über das Gegenstück“ darf mit, wenn es klein bleibt.
Die HTML-Entitäten in Store-Treffern gehören in Phase 2.

Ohne Entscheidung festgelegt, weil die Bilder es zeigen oder der Auftrag es vorgibt:
- Startseite unverändert (Bild 6 läuft bei 980 × 640 über).
- Filter „Zu zweit am Mac“ im Panel.
- Store-Chip wie vorgegeben.
- Die Suche lässt Filter und Store ruhen.
- Altersfreigabe als USK → PEGI → ESRB.
- Hinweis „Angaben von Steam“ bei Daten vom Gegenstück.
- „Deutsch“-Zeile nur auf deutschen Macs.
- „Mehr über das Spiel“ scrollt, statt aufzuklappen.

## Plan Phase 2: zwei Abschnitte, je mit eigenem Live-Test

Start erst auf das Go des Koordinators nach den Merges von 2.5 und GOG (`git merge claude/ux-roadmap-next`).
Abschnitt B baut auf A auf (`GameInfoStore`). Jeder Abschnitt endet mit grünen Testsuiten, einem sauberen
`./build.sh`, lokalen Commits und einem Live-Test durch den Koordinator. Danach beginnt der nächste.

### Abschnitt A: Daten, Filter, Bibliothek (etwa 2½ Tage)

1. **`GameInfo.swift`:** das Modell (`GameInfo`, `PlayMode`, `LanguageSupport`, `AgeRating`, `Screenshot`) und
   reine Parser ohne Netz, jeder mit Fixture:
   - `from(getItems:)`, Steams Store-Browse-API, die Hauptquelle. Spielmodi aus `supported_player_categoryids`:
     2 Einzelspieler, 38 Online-Koop, 39 Lokaler Koop, 24/37/39 geteilter Bildschirm, 36/49 gegeneinander.
     Controller aus `controller_categoryids` 28/18. Sprachen aus `supported_languages` (elanguage 3 = Deutsch).
     USK über `game_rating.agency == 4`, Genres über `StoreFacts.tagName`.
   - `from(appDetails:)` als Rückfall.
   - `from(gogV2:)`: HTML von `overview` zu Text, `features`, `localizations`.
   - `from(legendary:)`: nur Entwickler und eine echte Beschreibung.
   - Steam-Gegenstück aus GamesDB (`game.releases`).
   Der alte Epic-Inhaltsdienst kommt nur dazu, wenn der Live-Test Epic-Spiele ohne Gegenstück und ohne Infos zeigt.
2. **`GameInfoStore.swift`** (actor):
   - Cache in `Application Support/Nightforge/GameInfo/known.json` (Infos und Zwillinge in einer Datei).
   - Zwillinge: GOG über `GOGRelease.steamAppID`, das neu aus derselben GamesDB-Antwort kommt; Epic über GamesDB
     `epic/<AppName>`; sonst `StoreSearch` mit genau gleichem Namen nach dem Normalisieren.
   - Nachholen nach dem Scan in 50er-Bündeln: zuerst Epic- und GOG-Gegenstücke, dann die Bühne, dann der Rest.
   - Drossel: 10 Minuten Pause bei 429/403. Nach 30 Tagen oder bei anderer App-Sprache wird neu gefragt.
   - Offline gilt das Alte.
3. **`SteamCatalog`:** `category` → Spielmodi für eigene Steam-Spiele offline, damit „Zu zweit am Mac“ ohne Netz
   funktioniert.
4. **`LibraryModel`:**
   - Infos auf die Karten übertragen: `controller` für Epic und GOG, unbekannt statt „keine“.
   - `compatibility(of:)` über das Gegenstück.
   - Nach dem Nachholen `applyFilter()` aufrufen.
   - Die Suche lässt Filter und Store ruhen.
   - Store-Treffer ohne Gegenstücke eigener Spiele, und bei Store „Epic“ oder „GOG“ keine Steam-Treffer.
5. **`LibraryFilters`:**
   - `status` fällt weg. Neu sind `store: Provider?`, `onMac` und `couch`.
   - `narrows` und `cleared` werden angepasst.
   - Gemeinsame Karten zählen bei jedem ihrer Stores. Die Filter werden nicht gespeichert, deshalb braucht es
     keine Migration.
6. **`LibraryGrid` › `LibraryToolbar`:**
   - Kopfzeile mit Titel, Zahl, Frische, „Ausgeblendet“ und Suche.
   - Die Chip-Zeile: `ChoiceChip`, `FilterPanel`, `StoreMenu`, `ActiveChip`.
   - Die Panels arbeiten wie `DownloadsPanel`: Klick daneben oder B/Esc schließt (`InputRouter`).
   - `PadFocus`-IDs `library.store`, `library.sort`, `library.filter`, `library.active.<n>`, `filter.<id>`.
   - Das Sync-Banner aus dem GOG-Zweig bleibt unter der Zeile.
7. **Bilder:**
   - `ArtworkStore.remoteURLs` nimmt zuerst die Asset-Pfade mit Hash aus `GameInfo` (Cover, Hero).
   - Ohne Hochformat-Cover gibt es das breite Bild auf seiner einmal weichgezeichneten, gecachten Kopie.
   - Extra: Epic- und GOG-Spiele ohne Logo bekommen Steams Logo über das Gegenstück, sonst bleibt es beim Namen.
8. **`StoreSearch`:** HTML-Entitäten in Namen auflösen (`&amp;`, `&quot;`, `&#39;`).
9. **Texte und Tests:**
   - Texte über `L10n`.
   - Neu: `tests/GameInfoTest` (Parser mit den Fixtures aus `game-metadata/data/`, Zwilling über den Namen,
     Cache und Neufragen).
   - `LibraryFiltersTest` erweitern (Store, gemeinsame Karten, Zu zweit, Nur auf diesem Mac).
   - `SearchTest`: Filter ruhen, keine Treffer für eigene Spiele.
   - Dazu `StringsTest` und `TextScaleTest`.

**Live-Test A** (Koordinator, echte App, 198 Spiele):
- Die Zeile bei 1512 und 980 pt einzeilig.
- Store-Chip: „Epic Games“ zeigt „93 von 198 Spielen“, das Menü zeigt die Zahl je Store, eine gemeinsame Karte
  steht in beiden Stores.
- „Mit Controller spielbar“ zeigt Overcooked! 2 (Epic).
- „Läuft super“ enthält Epic- und GOG-Spiele mit Profil.
- „Zu zweit am Mac“ und „Nur auf diesem Mac“ funktionieren.
- Pad: ↑ aus dem Raster, A öffnet das Panel, ↑↓ und A schalten, B schließt.
- Suche „overcooked“: kein Steam-Treffer für Overcooked! 2. Suche „sheep“: echte Cover, kein `&amp;`.
- Zeit vom ersten Nachholen nach dem Scan, gemessen.
- Offline-Start zeigt dasselbe.
- Epic-Spiel mit Steam-Logo auf Startseite und Spielseite.

### Abschnitt B: Spielseite (etwa 1½–2 Tage)

1. **`GameAbout.swift`:** `SummaryTeaser`, `GameAboutSection`, `InfoChip`, `ScreenshotStrip`, `FactsCard`,
   `AgeBadge`, `ScreenshotLightbox`. Vorlage ist der Prototyp in `game-metadata/harness/Proto.swift`, mit
   `.font(size:)` und `.displayFont` statt `.system`.
2. **`DetailLevel`:**
   - `ScrollView` mit dem ersten Bildschirm in `ViewThatFits` (2, 1 oder 0 Zeilen) und `GameAboutSection` darunter.
   - Ein mitlaufender Verlauf über dem Hintergrund.
   - `scrollEdgeEffectStyle(.soft)` ab macOS 26.
   - „Mehr über das Spiel“ scrollt über `ScrollViewReader`.
3. **`GameDetail`:**
   - Der Teaser unter dem Logo.
   - `MetaLine` bekommt Genre und Jahr aus `GameInfo` auch für Epic und GOG.
   - Die Kennzahl „Controller“ zeigt „–“, wenn nichts bekannt ist.
4. **`ArtworkStore`:**
   - `ArtKind.shot`: Vorschaubilder, `maxPixelSize` 560, Cache-Datei `<key>_shot<n>.jpg`.
   - Höchstens 12 Bilder.
   - Das große Bild nur im Speicher, solange das Großbild offen ist.
5. **Pad und Tasten:**
   - ↓ von der Knopfreihe in die Leiste, ←→ in der Leiste, A öffnet groß.
   - Im Großbild ←→ blättern, B/Esc schließt. `PadFocus.reveal` beim Scrollen.
   - Die Tastatur im Großbild gleich.
6. **Tests:** `TextScaleTest`, `StringsTest`, dazu ein Offscreen-Render mit dem Harness als Kontrolle, bei 1512
   und 980 pt und mit größerer Schrift.

**Live-Test B** (Koordinator):
- Die Seite eines Steam-, eines Epic- und eines GOG-Spiels. Beim Epic-Spiel steht „Angaben von Steam“ in der Karte.
- 980 × 640: „Spielen“ ist sichtbar.
- Größere Schrift an.
- Scrollen mit Trackpad und Pad.
- Großbild mit Pad und Tastatur.
- Offline: Die Seite ist voll, außer den Screenshots, die noch nie geladen wurden.
- USK-Schild und die „Deutsch“-Zeile stimmen bei No Man's Sky (USK 6, Text und Sprachausgabe) und Overcooked! 2
  (Text ja, Sprachausgabe nein).

## Aufwand (Phase 2)

| Teil | Etwa |
|---|---|
| Datenschicht: `GameInfo.swift` (Modell, Parser für GetItems, appdetails als Rückfall, appinfo-Felder, GOG v2, GamesDB, legendary, alter Epic-Inhaltsdienst), `GameInfoStore.swift` (Cache, Reihenfolge, Zwillinge, Drossel, 50er-Bündel), `SteamCatalog` (associations, category, supported_languages), `GOGRelease.steamAppID` | 1 Tag |
| Spielseite: `GameAbout.swift` (Teaser, Abschnitt, Chips, Leiste, Karte, Freigabe, Großbild), scrollende `DetailLevel`, Pad-Fokus (↓ von der Knopfreihe in die Leiste, `PadFocus.reveal`), Tastatur im Großbild, Texte in `Strings.swift` | 1–1,5 Tage |
| Bibliothek: neue Zeile (Store-, Sortier-, Filter-Chip, Panel, aktive Chips, Pad), `LibraryFilters.store` und `.couch`, Suche lässt Filter ruhen | 1 Tag |
| Filterkorrektur (Controller, Läuft super), Store-Treffer ohne eigene Spiele, Cover mit Hash-Pfad, `&amp;` in Treffernamen | ½ Tag |
| Tests: `tests/GameInfoTest` mit echten Antworten als Fixtures (GetItems und appdetails DE für 728880/275850, GOG v2, GamesDB Epic, legendary), Zwillingssuche, Cache/Neufragen; `LibraryFiltersTest` (Store, Zählung gemeinsamer Karten, Ruhen bei Suche); `StringsTest`, `TextScaleTest` | ½–1 Tag |

Zusammen etwa 4–5 Tage einer Sitzung, ca. 1 600–2 000 neue Zeilen, danach der Live-Blick mit dem Koordinator.
Konfliktgefahr: `LibraryView.swift` (`DetailLevel`, `GameDetail`), `LibraryGrid.swift` (`LibraryToolbar`; GOG
fügt dort ein zweites Sync-Banner ein) und `LibraryModel.swift`. Darum erst nach den Merges von 2.5 und GOG.
Geteilt wie im Plan oben: erst Abschnitt A, dann B, nacheinander, weil B `GameInfoStore` aus A braucht.

## Nebenfunde

- **HTML-Reste in Store-Treffern:** Die Store-Suche gibt Namen mit `&amp;` zurück („PROFITS 2167: Planetar-
  Ressourcen-Optimierungs- &amp; Infrastruktur-…“). `StoreSearch.gameHits` müsste HTML-Entitäten auflösen.
  Kleine Korrektur, gehört in Phase 2.

- **Startseite bei 980 × 640** (auf dem Stand von 2.5, Bild 7): Bei einem Epic-Spiel ohne Logo, „Als Nächstes“ und
  dem StarterPicks-Satz rückt die Spalte bis an die Kopfleiste. Die Meta-Zeile läuft unter die Kachel „Alle Spiele“.
  Das gibt es schon heute und gehört nicht zu dieser Aufgabe.
- **Epic-Spiele haben kein Logo** (legendary kennt nur `DieselGameBox`-Bilder), darum steht der Name in großer
  Schrift. Mit dem Steam-Gegenstück könnte `ArtworkStore` Steams `logo.png` als Ersatz nehmen. Das ist ein kleines
  Extra für Phase 2, wenn gewünscht.
- **Doppelte Spiele (7.4)** erkennen Steam ↔ Epic bisher nur am Titel, „vorsichtig“ (ROADMAP 7.4, Recherche 28.10.).
  Die GamesDB-Zuordnung oben ist eine echte ID-Zuordnung (Epic-AppName → Steam-App-ID). `DuplicateGames` könnte
  sie später mitbenutzen, sobald die Zwillinge im Cache liegen.
