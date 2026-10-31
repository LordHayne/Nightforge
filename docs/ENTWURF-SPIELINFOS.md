# Entwurf: Mehr Infos pro Spiel („Über das Spiel“)

Stand 31.10.2026, Phase 1 (Recherche und Entwurf). Gebaut wird erst nach dem OK des Nutzers und nachdem
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
| **Online, ohne Login** | `store.steampowered.com/api/appdetails?appids=…&l=german&cc=DE`: `short_description` (Deutsch), `genres`, `categories` (deutsche Namen und IDs), `developers`, `publishers`, `release_date`, `screenshots` (600×338 und 1920×1080), `movies` (HLS/DASH), `ratings` (`usk`, `pegi`, `esrb`; dazu Steams eigene erzeugte Einstufungen, die nicht zählen), `supported_languages` (HTML, `*` = Sprachausgabe), `controller_support`. | GraphQL (`store.epicgames.com/graphql`, auch `launcher.store…`): **403, Cloudflare-Prüfung**, nicht nutzbar (und nicht zu umgehen). Katalog (`catalog-public-service…/bulk/items`): **401, braucht Login**. Alter Inhaltsdienst `store-content-ipv4.ak.epicgames.com/api/de/content/products/<slug>`: Deutsch, mit Kurzbeschreibung, Entwickler, Datum, Sprachen nach Text/Ton und PEGI. Er braucht aber den Slug und traf nur **16 von 30** (neuere Produkte fehlen). → **Steam-Gegenstück** | `api.gog.com/v2/games/<id>?locale=de-DE`: `overview`/`description` (Deutsch, HTML), Entwickler, Publisher, `globalReleaseDate`, `tags` (deutsche Genres), `features` (`single`, `multi`, `coop`, `controller_support` …), `localizations` (je Sprache `text`/`audio`), `screenshots` (Größen über `formatter`, z. B. `product_card_screenshot_748`), `videos` (YouTube), `pegiRating`/`esrbRating`. Cache-Control 1 Tag. |
| **Sprache** | `l=german`/`english` nach `AppLanguage` (wie `StoreSearch.regionItems`) | über das Steam-Gegenstück; GamesDB nur Englisch | `locale=de-DE`/`en-US` |
| **Stabilität** | undokumentiert, seit Jahren gleich (Heroic, Playnite und Lutris nutzen es). Limit etwa 200 Anfragen pro 5 Minuten und IP (Erfahrungswert, darüber 429/403). | GamesDB: öffentlich, von GOG Galaxy für alle Plattformen genutzt | v2 wird von Galaxy und Heroic genutzt |

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

- Eine JSON-Datei pro Spiel unter `~/Library/Application Support/Nightforge/GameInfo/<GameID.key>.json` (3–6 KB,
  300 Spiele ≈ 1,5 MB). Application Support statt Caches, damit es offline sicher da ist. Zwillinge kommen in
  `GameInfo/twins.json` ({Key: Steam-App-ID oder 0 für „keins“}). „Keins“ wird nach 30 Tagen neu gefragt.
- Neu gefragt wird nach 30 Tagen oder bei anderer App-Sprache. Offline bleibt das Alte stehen, wie bei `Metascores`.
- Screenshot-Vorschauen kommen nach `Caches/Nightforge/Artwork/<key>_shot<n>.jpg` (über `ArtworkStore`, neue
  `ArtKind.shot`, `maxPixelSize` 560).
- **Anfragen:** Beim Öffnen einer Seite ohne Infos gibt es 1 Anfrage. Im Hintergrund werden nur Epic- und GOG-Spiele
  ohne Infos nachgeholt, weil die Filter sie brauchen: höchstens 1 Anfrage alle 2 s, bei 429/403 zehn Minuten Pause.
  Eigene Steam-Spiele brauchen das nicht, `appinfo.vdf` liefert die Filterdaten offline. Für die Spiele auf der
  Bühne der Startseite (höchstens 8) holt Nightforge die Infos vorab, damit die Seite sofort voll ist.

**Filterkorrektur (gehört zu Phase 2):**
- `Game.controller` für Epic/GOG: vom Gegenstück (`categories` 28 → voll, 18 → teilweise), sonst GOGs Merkmal
  `controller_support` (sagt nicht „teilweise“ → voll). Ohne Angabe bleibt der Wert unbekannt, nicht „keine“. Die
  Kennzahl zeigt dann „–“ statt „Maus & Tastatur“ (passt zu `StarterFacts.controller` als Optional im GOG-Zweig).
- `compatibility(of:)`: Profil per `game.gameID.steamAppID ?? twin(of: game)`. Damit greift „Läuft super“ auch bei
  Epic und GOG. Dasselbe gilt für die Profile beim Start (`ProfileStore.profile(for:)`). Ob dort schon das
  Gegenstück gelten soll, prüfe ich in Phase 2 einzeln: Ein Steam-Profil passt nicht zwingend auf Epics Build.
- Nach dem Nachholen ruft das Modell `applyFilter()` auf, damit die Filter das neue Wissen nutzen.

## Offene Entscheidungen (für den Nutzer)

1. **Wo steht die Kurzbeschreibung?** Empfehlung: 2 Zeilen auf dem ersten Bildschirm, die bei kleinem Fenster als
   Erstes weichen, und alles Weitere unten beim Scrollen (wie Bild 1–4). Alternative: alles erst nach dem Scrollen.
   Der erste Bildschirm bleibt dann genau wie heute.
2. **Startseite?** Empfehlung: nichts Neues (Bild 6 gegen Bild 7). Alternative: der erste Satz, aber nur, wenn das
   Fenster hoch genug ist.
3. **Trailer?** Empfehlung: in Phase 2 nur Screenshots. Später geht es ohne Browser: Steam liefert Trailer als HLS,
   das AVKit direkt abspielt (eine Kachel „▶ Trailer“ vorne in der Leiste). GOG hat nur YouTube.
4. **Neuer Bibliotheksfilter „Zu zweit“** (Lokaler Koop / Geteilter Bildschirm) aus denselben Daten? Empfehlung: ja,
   als kleiner Zusatz. Er passt zum Spielen am Fernseher mit Controller. Die Karten selbst bleiben unverändert.

Ohne Entscheidung festgelegt: Altersfreigabe als USK → PEGI → ESRB; der Hinweis „Angaben von Steam“ bei Daten vom
Gegenstück; „Deutsch“-Zeile nur auf deutschen Macs; „Mehr über das Spiel“ scrollt statt aufzuklappen.

## Aufwand (Phase 2)

| Teil | Etwa |
|---|---|
| Datenschicht: `GameInfo.swift` (Modell, Parser für appdetails, appinfo-Felder, GOG v2, GamesDB, legendary, alter Epic-Inhaltsdienst), `GameInfoStore.swift` (Cache, Reihenfolge, Zwillinge, Drossel), `SteamCatalog` (associations, category, supported_languages), `GOGRelease.steamAppID` | 1 Tag |
| Views: `GameAbout.swift` (Teaser, Abschnitt, Chips, Leiste, Karte, Freigabe, Großbild), scrollende `DetailLevel`, Pad-Fokus (↓ von der Knopfreihe in die Leiste, `PadFocus.reveal`), Tastatur im Großbild, Texte in `Strings.swift` | 1–1,5 Tage |
| Filterkorrektur (Controller, Läuft super) + optional Filter „Zu zweit“ | ½ Tag |
| Tests: `tests/GameInfoTest` mit echten Antworten als Fixtures (appdetails DE für 728880 und 275850, GOG v2, GamesDB Epic, legendary), Zwillingssuche, Cache/Neufragen, Filter; dazu `StringsTest` und `TextScaleTest` | ½ Tag |

Zusammen etwa 3 Tage einer Sitzung, ca. 1 000–1 300 neue Zeilen, danach der Live-Blick mit dem Koordinator.
Konfliktgefahr: `LibraryView.swift` (`DetailLevel`, `GameDetail`) und `LibraryModel.swift`. Darum erst nach den
Merges von 2.5 und GOG.

## Nebenfunde

- **Startseite bei 980 × 640** (auf dem Stand von 2.5, Bild 7): Bei einem Epic-Spiel ohne Logo, „Als Nächstes“ und
  dem StarterPicks-Satz rückt die Spalte bis an die Kopfleiste. Die Meta-Zeile läuft unter die Kachel „Alle Spiele“.
  Das gibt es schon heute und gehört nicht zu dieser Aufgabe.
- **Epic-Spiele haben kein Logo** (legendary kennt nur `DieselGameBox`-Bilder), darum steht der Name in großer
  Schrift. Mit dem Steam-Gegenstück könnte `ArtworkStore` Steams `logo.png` als Ersatz nehmen. Das ist ein kleines
  Extra für Phase 2, wenn gewünscht.
- **Doppelte Spiele (7.4)** erkennen Steam ↔ Epic bisher nur am Titel, „vorsichtig“ (ROADMAP 7.4, Recherche 28.10.).
  Die GamesDB-Zuordnung oben ist eine echte ID-Zuordnung (Epic-AppName → Steam-App-ID). `DuplicateGames` könnte
  sie später mitbenutzen, sobald die Zwillinge im Cache liegen.
