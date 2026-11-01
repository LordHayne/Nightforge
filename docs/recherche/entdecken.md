<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHTDYxjoCTBKvVQBaxw (1.11.2026) -->

## Entdecken – Store-Schnittstellen

*Recherche für den geplanten Tab „Entdecken“ in Nightforge · Stand 31.10.2026*

> **Wie belastbar das ist:** Diese Recherche-Umgebung durfte die Store-Hosts nicht erreichen. Gesperrt waren `store.steampowered.com`, `api.steampowered.com`, `store-site-backend-static.ak.epicgames.com`, `catalog.gog.com`, `api.gog.com` und `embed.gog.com`. Ich konnte also **keinen Endpunkt selbst live aufrufen**.

> Die Angaben stammen aus drei Quellen:

> - Quellcode aktiver Projekte: Heroic, Playnite, legendary, Rare, gogdl, Lutris, Home Assistant, RomM, DroidDeck, hearth-os, dealfox.
> - Steams Protobuf-Definitionen von SteamDatabase (Stand 30.10.2026).
> - Antworten, die andere Projekte mitgeschnitten und als Test-Fixtures eingecheckt haben. Bei jedem Beispiel stehen Quelle und Datum.

> **Belegt** heißt: so in Code oder Mitschnitt gesehen. **Ungeprüft** heißt: abgeleitet, vor dem Einbau kurz live testen.

> Für einen Live-Test diese Hosts in den Einstellungen der Cloud-Umgebung freigeben: *Network access → Allowed domains*, Anleitung unter [https://code.claude.com/docs/en/cloud-environments#network-access](https://code.claude.com/docs/en/cloud-environments#network-access).

---

### 1. Empfehlung: welche Quelle für welche Rubrik

#### 1.1 Übersicht

| Rubrik | Steam | Epic | GOG |
|---|---|---|---|
| **Angebote** | `search/results?specials=1&json=1`, Details danach per `IStoreBrowseService/GetItems`. Für eine kurze Startreihe reicht `featuredcategories` → `specials`. | GraphQL `searchStore(onSale:true)` | `catalog.gog.com/v1/catalog?discounted=eq:true&order=desc:discount` (Heroic sortiert mit `desc:trending`) |
| **Beliebt / Charts** | `ISteamChartsService/GetMostPlayedGames` (Top 100 nach Spielerzahl) und `IStoreTopSellersService/GetWeeklyTopSellers` mit `country_code=DE` | GraphQL `Storefront.collectionLayout(slug:"top-sellers")`. Fragil, Rückfall: `searchStore` mit `sortBy:"relevancy"`. | `order=desc:bestselling` oder `desc:trending` |
| **Neu** | `search/results?filter=popularnew&json=1` (beliebte Neuheiten), alternativ `featuredcategories` → `new_releases`. Monatsbestenliste: `ISteamChartsService/GetTopReleasesPages`. | `searchStore(sortBy:"releaseDate", releaseDate:"[,<heute>]")` | `order=desc:releaseDate`, Spiele mit Datum in der Zukunft herausfiltern (wie DroidDeck) |
| **Gratis zum Behalten** (befristete Aktion) | `search/results?maxprice=free&specials=1&category1=998&json=1`. In `GetItems` zusätzlich `is_free_temporarily`, `purchase_options[].is_free_to_keep`, `free_to_keep_ends`. | `freeGamesPromotions` (wöchentlich, seit Jahren stabil) | `sections.gog.com/v1/pages/2f`, Abschnitt `GIVEAWAY_SECTION` (fragil) |
| **Free-to-Play** | `IStoreQueryService/Query` mit `price_filters.only_free_items:true` | `searchStore(freeGame:true)` (so macht es Rare) | `catalog?price=between:0,0` |
| **Gratis-Wochenende** | `Query` → Feld `free_weekend` (so macht es Auto-Claim) | – | – |
| **Suche** | `IStoreQueryService/SearchSuggestions` mit `data_request`: Plattform, Preis und Controller in einem Aufruf. Heute nutzt `StoreSearch` dafür `search/results` und `storesearch`. | `searchStore(keywords:…)` | `catalog?query=like:<begriff>&order=desc:score` |
| **Genre / Tags** | Namen: `IStoreService/GetTagList?language=german`. Filtern: `Query` mit `tagids_must_match`, oder `search/results?tags=<id>`. | Tag-IDs (Rare-Liste oder `Catalog.tags`) plus `searchStore(tag:"…")` | `catalog?genres=in:<slug>`. `genres`, `tags` und `features` kommen in der Antwort mit. |
| **Spielseite** | `GetItems`: Bilder, Kurztext, Preis, Plattformen, Systemanforderungen, Anti-Cheat-Feld. Langtext als HTML: `api/appdetails?l=german`. | GraphQL `catalogOffer` oder `egs-platform-service …/products/{id}`. Langtext (alt): `store-content…/content/products/{slug}` | `api.gog.com/products/{id}?expand=description,screenshots,videos&locale=de-DE`, Preis aus `catalog?productId=in:{id}` |
| **Mac-Version** | `platforms.mac`, zusätzlich `release.mac_release_date` und in den Systemanforderungen `requires_apple_silicon` | Tag **9548** „macOS“ oder `technicalRequirements.macos` | `operatingSystems` enthält `osx`, bzw. `content_system_compatibility.osx` |
| **Controller** | `categories.controller_categoryids`: **28** = voll, **18** = teilweise. In `appdetails`, `featuredcategories` und `storesearch` heißt das Feld `controller_support`. | Tag **9549** „Controller Support“ | `features[].slug == "controller_support"` |
| **Anti-Cheat** | Nightforge-eigene Liste (`AntiCheatBlock`). Zusätzlich `extra_details.anticheat` aus `GetItems` (Feld existiert laut Protobuf, ob es befüllt wird: ungeprüft). | eigene Liste | eigene Liste (bei GOG selten nötig) |

**Kaufen** passiert immer im Store, nicht in der App:

| Store | Link |
|---|---|
| Steam | `https://store.steampowered.com/app/<id>` |
| Epic | `https://store.epicgames.com/de/p/<slug>` |
| GOG | `storeLink` aus der Katalog-Antwort |

Heroic macht das genauso: Den Epic-Store öffnet es in einer WebView (`src/frontend/screens/WebView/index.tsx`

), für GOG gibt es eine eigene Angebotsansicht (`src/frontend/screens/Discounts`).

#### 1.2 Architektur-Empfehlungen

1. Zwei Stufen. Eine Liste liefert IDs und das Nötigste. Danach werden die Details gebündelt nachgeladen: bei Steam per GetItems mit vielen IDs auf einmal statt einem appdetails-Aufruf pro Treffer. Das senkt das 429-Risiko deutlich. StoreSearch.details(for:) ruft heute für jeden Treffer einzeln appdetails auf.
2. Ein gemeinsames Modell für alle Stores: Store, ID, Titel, Bilder (breit/hoch), Preis in Cent plus Währung, Rabatt in %, Ende der Aktion, Mac-Flag, Controller, Tags, Store-URL. Preise selbst formatieren, wie es StoreSearch schon tut. Die Textpreise der Stores sind uneinheitlich formatiert.
3. Cache:DatenLebensdauerVorbildListen1–3 hDroidDeck und hearth: 3 hEpic-Gratisspiele1× täglich und zum `endDate` der Aktion (Wechsel donnerstags 16:00 UTC laut Daten)Home Assistant: 1× täglichDetails24 h–Tag-Listenwöchentlich, über `have_version_hash`–
4. Pro Host drosseln:
  - Steam-Storefront (appdetails) mit mindestens 1,5 s Abstand (hearth). Rest etwa 350 ms (hearth).
  - Bei HTTP 429 zurückweichen: Playnite wartet 2,5 s und versucht es bis zu 10-mal.

5. Leise scheitern, wie StoreSearch heute: Fällt eine Quelle aus, bleibt die Reihe leer. Wenn Epic mit 403 antwortet (Cloudflare-Prüfung), „Im Browser öffnen“ anbieten (so macht es hearth).
6. Region und Sprache aus Locale.current.region und AppLanguage ableiten, wie in StoreSearch.regionItems:StoreParameter für DeutschlandSteam`cc=DE&l=german` bzw. `context:{language:"german",country_code:"DE"}`Epic`country:"DE", locale:"de-DE"` (egs-platform-service: `locale=de`)GOG`countryCode=DE&locale=de-DE&currencyCode=EUR`
7. Badge in dieser Reihenfolge:
  1. Store meldet eine Mac-Version → „Mac-Version“.
  2. Sonst Compatibility.rate mit platform = .windows und antiCheatBlock. Ergebnis „Anti-Cheat blockiert“ oder „nur über GeForce Now“ (die Logik existiert schon), sonst „läuft wahrscheinlich“ bzw. „noch nicht getestet“.
  3. Steams extra_details.anticheat.kernel_mode kann als zusätzliches Signal dienen, nachdem es live geprüft ist.

8. Login ist nirgends nötig. Zwei Ausnahmen sind optional:
  - GOG hideOwned=true mit Bearer-Token (Heroic).
  - Epic-GraphQL mit legendary-Token (Rare).

---

### 2. Steam

Es gibt zwei Host-Familien:

- Storefront store.steampowered.com. Undokumentiert, Parameter cc und l, seit über zehn Jahren in Gebrauch.
- Service-Methoden api.steampowered.com/<Interface>/<Methode>/v1/?input_json=<URL-kodiertes JSON>. Undokumentiert, Felder bekannt aus Steams Protobufs. Funktionieren in der Praxis ohne API-Key (Belege je Endpunkt).

Offiziell dokumentiert ist nur die Web-API mit Key, unter den Steam Web API Terms of Use ([https://steamcommunity.com/dev/apiterms](https://steamcommunity.com/dev/apiterms)): **100.000 Aufrufe pro Tag** pro Key. Für die Store-Abfragen hier braucht Nightforge keinen Key.

#### 2.1 `featuredcategories` – Startseiten-Reihen

|  |  |
|---|---|
| URL | `GET https://store.steampowered.com/api/featuredcategories?cc=DE&l=german` |
| Login | nein |
| Limit | keines dokumentiert. Für den Storefront-Host gilt grob ~200 Anfragen / 5 min / IP (siehe 2.4). |
| Inhalt | `specials`, `top_sellers`, `new_releases`, `coming_soon`, dazu nummerierte Spotlights (`"0"`, `"1"` …) und `status`. Kurze Listen, gut für eine Startreihe, nicht zum Blättern. |
| Nutzer | hearth-os (Store-Ansicht, Live-Check in CI), Bibliotheken SteamWebAPI2, steam-api-ts, UniveGame (Swift) |

Beispiel, gekürzt (Mitschnitt hearth-os `fixtures/steam_featured.json`

, Okt. 2026, `cc=US`):

```
{"specials":{"id":"cat_specials","name":"Specials","items":[{
  "id":1091500,"type":0,"name":"Cyberpunk 2077",
  "discounted":true,"discount_percent":70,"original_price":5999,"final_price":1799,"currency":"USD",
  "large_capsule_image":"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1091500/…/capsule_616x353_alt_assets_9.jpg?t=1792682505",
  "windows_available":true,"mac_available":true,"linux_available":false,
  "discount_expiration":1793037600,"controller_support":"full"}]},
 "top_sellers":{…},"new_releases":{…},"coming_soon":{…},"status":1}
```

`mac_available` und `controller_support` sind direkt enthalten. Verwandt: `api/featured/?cc=DE&l=german` mit `featured_win` (belegt in hearth). Ein `featured_mac` gibt es wahrscheinlich ebenfalls (ungeprüft).

#### 2.2 `search/results` – die Store-Suche mit Filtern

|  |  |
|---|---|
| URL | `GET https://store.steampowered.com/search/results/?json=1&category1=998&cc=DE&l=german&start=0&count=50` plus Filter |
| Login | nein |
| Antwort | `json=1` liefert `{"items":[{"name":…,"logo":"…/apps/<appid>/…"}]}`. Die App-ID steht in der Logo-URL (so parst es `StoreSearch.gameHits` heute schon). Mit `infinite=1` kommen HTML-Schnipsel und `total_count`. |
| Nutzer | Nightforge `StoreSearch` (heute), Playnite UniversalSteamMetadata (HTML-Variante), dealfox, Auto-Claim, mehrere Bots |

Filter (belegt in Code):

| Parameter | Wirkung |
|---|---|
| `category1=998` | nur Spiele |
| `specials=1` | im Angebot |
| `filter=topsellers` | Bestseller |
| `filter=popularnew` | beliebte Neuheiten |
| `sort_by=Released_DESC` | neueste zuerst |
| `maxprice=free` | kostenlos. Zusammen mit `specials=1`: „gratis zum Behalten“ (dealfox, Free-Games-Claimer) |
| `hidef2p=1` | Free-to-Play ausblenden |
| `tags=<id>` | nach Tag filtern |
| `term=` | Suchbegriff |

Ungeprüft:

- os=mac, analog zum belegten os=win.
- category2=28 für volle Controller-Unterstützung.

Weil die JSON-Antwort nur Name und Bild enthält, braucht es immer eine zweite Stufe (`GetItems`).

#### 2.3 `storesearch` – schnelle Titelsuche

|  |  |
|---|---|
| URL | `GET https://store.steampowered.com/api/storesearch/?term=<begriff>&cc=DE&l=german` |
| Login | nein. Limit: laut InternalSteamWebAPI-Wiki „no known rate limit“. |
| Treffer | etwa 10, aller Typen (auch DLC und Bundles) |
| Nutzer | Nightforge `StoreSearch.detailedHits` (heute), printing-press game-goat, hearth-os |

Beispiel, gekürzt (Mitschnitt hearth-os `fixtures/steam_search.json`

, Okt. 2026, `cc=US`):

```
{"total":10,"items":[{"type":"app","name":"Hades II","id":1145350,
  "price":{"currency":"USD","initial":2999,"final":2999},
  "tiny_image":"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1145350/…/capsule_231x87.jpg",
  "metascore":"94","platforms":{"windows":true,"mac":true,"linux":false},
  "streamingvideo":false,"controller_support":"full"}]}
```

Mit `cc=NL` kommt `"currency":"EUR"` (Beispiel im InternalSteamWebAPI-Wiki).

#### 2.4 `appdetails` – klassische Spielseite

|  |  |
|---|---|
| URL | `GET https://store.steampowered.com/api/appdetails?appids=<id>&cc=DE&l=german`, optional `&filters=basic,price_overview,platforms,…` |
| Login | nein |
| Limit | **etwa 200 Anfragen / 5 min / IP, danach HTTP 429**. RomM: „Undocumented, but the storefront starts returning 429 at roughly 200 requests per 5 minutes per IP“ (`backend/adapters/services/steam.py`

). Playnite fängt 429 ab und wartet 2,5 s (`SteamShared/MetadataProvider.cs`

). Mehrere IDs pro Aufruf gehen nach Community-Wissen nur mit `filters=price_overview` (ungeprüft). |
| Inhalt | `detailed_description` / `about_the_game` als **HTML in der gewählten Sprache**, `short_description`, `header_image`, `screenshots[].path_full`, `movies`, `price_overview`, `platforms`, `mac_requirements`, `controller_support`, `categories`, `genres`, `release_date`, `metacritic`, `recommendations` |
| Nutzer | Playnite (`SteamShared/WebApiClient.cs`

), RomM, Nightforge `StoreSearch.details` |

Beispiel, gekürzt (Mitschnitt aus `quer/steam-store-ripoff/99300.json`

, ältere Antwort mit EU-Preis):

```
{"99300":{"success":true,"data":{
  "type":"game","name":"Renegade Ops","steam_appid":99300,"is_free":false,
  "controller_support":"full",
  "price_overview":{"currency":"EUR","initial":1299,"final":1299,"discount_percent":0,
                    "initial_formatted":"","final_formatted":"12,99€"},
  "platforms":{"windows":true,"mac":false,"linux":false},
  "categories":[{"id":2,"description":"Single-player"},{"id":28,"description":"Full controller support"}],
  "genres":[{"id":"1","description":"Action"}],
  "header_image":"https://…/steam/apps/99300/header.jpg",
  "screenshots":[{"id":0,"path_thumbnail":"…600x338.jpg","path_full":"…1920x1080.jpg"}]}}}
```

**Empfehlung:** nur noch für den HTML-Langtext auf der Detailseite verwenden, alles andere über `GetItems`.

#### 2.5 `IStoreBrowseService/GetItems` – Details gebündelt

|  |  |
|---|---|
| URL | `GET https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json=<JSON>` |
| Login / Key | nein. Ohne Key belegt bei raycast/extensions (Steam-Erweiterung), DLSS Swapper, DroidDeck, Harbor, Drop-OSS, printing-press („keyless“). xPaws Doku führt `key` formal als Pflicht, praktisch ist er es nicht. |
| Limit | keines dokumentiert. Projekte bündeln 24–100 IDs pro Aufruf (Harbor 24). printing-press drosselt die Service-Hosts auf 3 Anfragen/s. |
| Sprache / Region | `"context":{"language":"german","country_code":"DE"}` |
| Felder | Definition `StoreItem` in `SteamDatabase/Protobufs/steam/steammessages_storebrowse.steamclient.proto`

, Stand 30.10.2026 |

Anfrage:

```
{"ids":[{"appid":1145350},{"appid":1091500}],
 "context":{"language":"german","country_code":"DE"},
 "data_request":{"include_assets":true,"include_release":true,"include_platforms":true,
   "include_basic_info":true,"include_tag_count":20,"include_screenshots":true,
   "include_all_purchase_options":true,"include_reviews":true,"include_extra_details":true}}
```

Für Nightforge wichtige Felder:

| Feld | Bedeutung |
|---|---|
| `platforms.mac`, `platforms.windows`, `platforms.steamos_linux` | Plattformen (bei Linux heißt der Schlüssel `steamos_linux`, nicht `linux`) |
| `release.mac_release_date` | Datum der Mac-Version |
| `extra_details.system_requirements.platforms[]` | Systemanforderungen mit `platform` (2 = Mac) und `requires_apple_silicon` |
| `categories.controller_categoryids` | Controller: 28 = voll, 18 = teilweise. Harbor wertet genau das aus (`detail-extras-data.ts`). Die Kategorien kommen auch ohne eigenes `include_*`-Flag mit (siehe Mitschnitt unten). |
| `extra_details.anticheat` | `name`, `kernel_mode`, `boot_protection`. Feld existiert, Befüllung ungeprüft. |
| `best_purchase_option` | `final_price_in_cents`, `original_price_in_cents`, `formatted_final_price`, `discount_pct`, `active_discounts[].discount_end_date`, `is_free_to_keep`, `free_to_keep_ends` |
| `is_free`, `is_free_temporarily`, `free_weekend` | Gratis-Status |
| `assets` | Bilder; URL = `asset_url_format` mit Dateiname, z. B. `header`, `main_capsule`, `library_capsule`, `hero_capsule` |
| `screenshots`, `trailers` | Medien |
| `basic_info.short_description`, `full_description_bbcode` | Texte (Langtext als **BBCode**, nicht HTML) |
| `tagids`, `tags[]` | Tags |
| `reviews.summary_filtered` | `percent_positive`, `review_score_label` (lokalisiert) |

Beispiel, gekürzt. Gleiche `StoreItem`-Struktur, mitgeschnitten über `IStoreQueryService/Query` am 29.10.2026 ohne Key (gameagenda `fixtures/steam/query/query-spanish-es-000000-20.json`

, `language:"spanish"`, `country_code:"ES"`):

```
{"response":{"store_items":[{
  "item_type":0,"id":10,"success":1,"visible":true,"name":"Counter-Strike",
  "store_url_path":"app/10/CounterStrike","appid":10,"type":0,
  "categories":{"supported_player_categoryids":[1,49,36,37],"feature_categoryids":[66,68,69,75,8,62]},
  "reviews":{"summary_filtered":{"review_count":170397,"percent_positive":96,"review_score":9,
             "review_score_label":"Extremadamente positivas"}},
  "assets":{"asset_url_format":"steam/apps/10/${FILENAME}?t=1745368572",
            "main_capsule":"capsule_616x353.jpg","header":"header.jpg"},
  "release":{"steam_release_date":973065600},
  "platforms":{"windows":true,"mac":true,"steamos_linux":true,"vr_support":{},
               "steam_deck_compat_category":2}}]}}
```

#### 2.6 `IStoreQueryService/Query` und `SearchSuggestions` – Filtern und Suchen

**Query**

|  |  |
|---|---|
| URL | `GET https://api.steampowered.com/IStoreQueryService/Query/v1/?input_json=<JSON>` |
| Key | ohne Key mitgeschnitten (29.10.2026, siehe 2.5). Die Community-Doku `benhurk/IStoreQueryService-Query-v1-Documentation` nennt einen Key als Pflicht. ALunaProject und printing-press schreiben ausdrücklich, dass es ohne geht. |
| Seiten | bis 1000 Einträge pro Seite (benhurk, Auto-Claim). Gesamtzahl in `metadata.total_matching_records`. |

Filter laut Protobuf `webui/service_storequery.proto`

:

| Filter | Zweck |
|---|---|
| `type_filters.include_games` | nur Spiele |
| `released_only`, `coming_soon_only` | veröffentlicht / demnächst |
| `tagids_must_match:[{"tagids":[…]}]`, `tagids_exclude` | Tags ein- oder ausschließen |
| `price_filters.only_free_items` | nur Kostenloses |
| `price_filters.min_discount_percent` | Mindestrabatt. Auto-Claim nutzt `1`, um alle reduzierten Apps zu bekommen und daraus Gratis-Wochenenden zu lesen. |
| `regional_top_n_sellers`, `global_top_n_sellers` | auf die Bestseller begrenzen |
| `review_score_filter`, `release_date_filter` | Bewertung, Erscheinungsdatum |

Sortierwerte (laut benhurk, ungeprüft): 1 = alphabetisch, 2 = App-ID, 20 = neueste, 21 = Anteil positiver Bewertungen.

**SearchSuggestions**

|  |  |
|---|---|
| URL | `…/IStoreQueryService/SearchSuggestions/v1/?input_json={"search_term":"hades","max_results":20,"context":{…},"data_request":{…},"filters":{"type_filters":{"include_games":true}}}` |
| Treffer | bis 100. `start` wird ignoriert, es gibt keine zweite Seite (printing-press). |
| Vorteil | Liefert über `data_request` Plattform, Preis und Controller gleich mit. Damit wäre der heutige Zwei-Aufruf-Weg in `StoreSearch` ein Aufruf. |

#### 2.7 `ISteamChartsService` – Charts

**GetMostPlayedGames**

|  |  |
|---|---|
| URL | `GET https://api.steampowered.com/ISteamChartsService/GetMostPlayedGames/v1/` |
| Key | ohne Key belegt: splashboard („no auth required“), steam-lancache-prefill, Harbor, cartouche |
| Region | optional `input_json` mit `context` und `data_request`. Dann kommt pro Rang ein eingebettetes `item` (StoreItem), sonst nur App-IDs. |
| Inhalt | Top 100 nach täglicher Spitzen-Spielerzahl |

Beispiel, gekürzt (Mitschnitt cartouche `tools/compat/fixtures/2026-10-19/steam/most-played.json`

):

```
{"response":{"rollup_date":1792195200,"ranks":[
  {"rank":1,"appid":730,"last_week_rank":1,"peak_in_game":1360532},
  {"rank":2,"appid":570,"last_week_rank":2,"peak_in_game":969895}]}}
```

Weitere Methoden (Felder laut `webui/service_steamcharts.proto`

):

- GetGamesByConcurrentPlayers: aktuell gleichzeitig Spielende.
- GetTopReleasesPages: monatliche „Top-Neuerscheinungen“ mit item_ids.
- GetMonthTopAppReleases.

Für Entdecken ist **Meistgespielt** als Reihe „Beliebt“ gut. Nachteil: die Liste ist voller Free-to-Play-Dauerbrenner. Deshalb besser mit Topsellern mischen.

#### 2.8 `IStoreTopSellersService/GetWeeklyTopSellers` – Bestseller pro Land

|  |  |
|---|---|
| URL | `GET https://api.steampowered.com/IStoreTopSellersService/GetWeeklyTopSellers/v1/?input_json={"country_code":"DE","context":{"language":"german","country_code":"DE"},"data_request":{"include_basic_info":true},"page_start":0,"page_count":20}` |
| Key | nicht nötig (XasYer/steam-plugin, gofurry/steam-go) |
| Antwort | laut Protobuf `start_date`, `ranks[]` mit `rank`, `appid`, `last_week_rank`, `consecutive_weeks`, `first_top100`, dazu `next_page_start`. Echter Mitschnitt nicht gefunden: kurz live prüfen. |

#### 2.9 Tags, Genres, Kategorien

| Methode | URL / Inhalt | Beleg |
|---|---|---|
| `IStoreService/GetTagList` | `GET https://api.steampowered.com/IStoreService/GetTagList/v1/?language=german&have_version_hash=<hash>` → `{"response":{"version_hash":"…","tags":[{"tagid":19,"name":"Action"}]}}` (Struktur laut Protobuf). Liefert nichts, wenn sich der Hash nicht geändert hat. | Playnite `SteamShared/SteamTagNamer.cs`

, ohne Key |
| `IStoreService/GetMostPopularTags` | `?language=german`: die wichtigsten Tags | xPaw |
| `IStoreBrowseService/GetStoreCategories` | `?language=german`: Kategorien mit `type`. 3 = ControllerSupport, 2 = Feature, 1 = SupportedPlayers. | Protobuf |
| `appdetails` → `genres` | IDs wie `"1"` = Action. In `GetItems` unter `extra_details.links_and_info.genreids`. | Mitschnitt oben |

Die Tag-ID für „Free to Play“ ist bekanntlich 113; per `GetTagList` bestätigen.

#### 2.10 Mac und Controller auf einen Blick

| Quelle | Mac | Controller |
|---|---|---|
| `featuredcategories` | `mac_available` | `controller_support` (`"full"`, `"partial"`, sonst fehlt das Feld) |
| `storesearch` | `platforms.mac` | `controller_support` (nicht immer vorhanden) |
| `appdetails` | `platforms.mac`, `mac_requirements` | `controller_support`, `categories` 28/18 |
| `GetItems` / `Query` | `platforms.mac`, `release.mac_release_date`, `system_requirements` mit `requires_apple_silicon` | `categories.controller_categoryids` 28/18 |

Hinweis: `platforms.mac:true` sagt nichts darüber, ob die Mac-Version auf aktuellem macOS oder nativ auf Apple Silicon läuft. Alte 32-Bit-Builds gibt es noch. Für die „Mac-Version“-Badge die vorhandene Nightforge-Logik (`MacVersion.swift`) nachschalten.

#### 2.11 Nutzungsbedingungen Steam

- Die Steam Web API Terms (https://steamcommunity.com/dev/apiterms) regeln die Web-API mit Key: 100.000 Aufrufe/Tag, keine vorgetäuschte Partnerschaft mit Valve, Valve kann den Zugang jederzeit entziehen. Für die Storefront- und Service-Endpunkte ohne Key gibt es keine eigenen Bedingungen und keine Zusage. Valve duldet sie seit Jahren.
- Sie werden breit eingesetzt: Playnite (Metadaten), RomM, Home-Assistant-nahe Projekte, Raycast, DLSS Swapper. SteamDatabase pflegt die Felddefinitionen öffentlich.
- SteamDB selbst hat keine öffentliche API und bittet in seiner FAQ, die Seite nicht automatisiert abzugrasen. Als Datenquelle für Nightforge also nicht nutzen, nur als Nachschlagewerk.
- Bilder und Texte gehören den Publishern. Anzeigen mit Link zum Store ist üblich. Nicht dauerhaft in großen Mengen spiegeln oder weiterverteilen.

---

### 3. Epic Games Store

Epic hat **keine öffentliche Store-API**. Es gibt vier Wege:

1. Der Gratisspiele-Feed (CDN, sehr stabil).
2. Die Store-GraphQL-Schnittstelle auf zwei Hosts.
3. Der neue egs-platform-service.
4. Der alte CMS-Host store-content.

#### 3.1 `freeGamesPromotions` – wöchentliche Gratisspiele

|  |  |
|---|---|
| URL | `GET https://store-site-backend-static-ipv4.ak.epicgames.com/freeGamesPromotions?locale=de-DE&country=DE&allowCountries=DE`. Ohne `-ipv4` funktioniert es genauso. |
| Login | nein. Statisch über CDN ausgeliefert. |
| Limit | keines bekannt. Home Assistant fragt 1× täglich (`SCAN_INTERVAL = timedelta(days=1)`). |
| Nutzer | Rare (`store_api.py`), Home Assistant (Integration `epic_games_store`, über epicstore_api), hearth-os, dealfox, epicstore_api, viele Discord-Bots |

Logik „ist gratis“ (Home Assistant `helper.py`, dealfox):

- Jetzt gratis: In promotions.promotionalOffers[].promotionalOffers[] gibt es einen Eintrag mit discountSetting.discountPercentage == 0 (0 bedeutet 100 % Rabatt), und die aktuelle Zeit liegt zwischen startDate und endDate. Zusätzlich ist price.totalPrice.discountPrice == 0.
- Kommt demnächst: dieselbe Struktur in upcomingPromotionalOffers.
- Der Feed enthält auch normale Rabatte und Platzhalter („Mystery Game“, HA-Fixture free_games_mystery_special.json). Daher immer nach der Regel oben filtern.
- Fehlermeldungen mit Code 1004 sind normales Rauschen und werden ignoriert, auch vom offiziellen Client (epicstore_api _clean_1004_errors).
- Ein falsches Land führt zu Fehler 5222 (invalid_country_code, HA-Fixture).

Beispiel, gekürzt (Mitschnitt Home Assistant `tests/components/epic_games_store/fixtures/free_games_one.json`

, EUR):

```
{"data":{"Catalog":{"searchStore":{"elements":[{
  "title":"Borderlands 3 Season Pass","id":"c3913a91e07b43cfbbbcfd8244c86dcc","namespace":"catnip",
  "offerType":"DLC","productSlug":"borderlands-3/season-pass",
  "keyImages":[{"type":"OfferImageWide","url":"https://cdn1.epicgames.com/offer/catnip/…3840x2160…"},
               {"type":"OfferImageTall","url":"https://cdn1.epicgames.com/offer/catnip/…1200x1600…"}],
  "price":{"totalPrice":{"discountPrice":4999,"originalPrice":4999,"currencyCode":"EUR",
           "fmtPrice":{"originalPrice":"49,99 €","discountPrice":"49,99 €"}}},
  "promotions":{"promotionalOffers":[],"upcomingPromotionalOffers":[{"promotionalOffers":[
     {"startDate":"2023-03-09T16:00:00.000Z","endDate":"2023-03-16T16:00:00.000Z",
      "discountSetting":{"discountType":"PERCENTAGE","discountPercentage":30}}]}]},
  "catalogNs":{"mappings":[{"pageSlug":"borderlands-3","pageType":"productHome"}]},
  "categories":[{"path":"addons"},{"path":"freegames"}]}]}}}}
```

Store-Link bauen (Home Assistant `get_game_url`): `https://store.epicgames.com/de/p/<slug>`. Als Slug zuerst `offerMappings[0].pageSlug` nehmen, dann `catalogNs.mappings[0].pageSlug`, dann `productSlug`. Bei `offerType == "BUNDLE"` steht im Pfad `bundles` statt `p`.

#### 3.2 Store-GraphQL – Suche, Angebote, Neu, Topseller, Detail

| Host | Wer nutzt ihn | Verhalten |
|---|---|---|
| `https://launcher.store.epicgames.com/graphql` | legendary (`api/egs.py`

, `_store_gql_host`), Heroic (`legendary/games.ts`

), **Rare (Store-Tab)**, Lacro59 `playnite-plugincommon`, CreamInstaller, SKIF | POST mit `User-Agent: … EpicGamesLauncher`. Rare schickt das legendary-Token mit, Heroic nicht. |
| `https://store.epicgames.com/graphql` | Playnite EpicLibrary (`WebStoreClient.cs`), epicstore_api, hearth-os, dealfox (GET mit `?query=`) | **Cloudflare-Browserprüfung**: epicstore_api braucht dafür `cloudscraper` („to battle the anti-bot protections … not a silver bullet“). hearth-os fängt HTTP 403 ab und verweist auf den Browser. |

**Empfehlung:** primär `launcher.store.epicgames.com` mit EGL-User-Agent und, wenn vorhanden, dem legendary-Token. Bei 403 auf `store.epicgames.com` ausweichen. Klappt beides nicht, die Reihe leer lassen und „Im Browser öffnen“ anbieten.

**`searchStore`:** Argumente belegt im Rare-Code `rare/components/tabs/store/constants.py`

 und `api/models/query.py`

:

```
{"query":"query searchStoreQuery($country:String!,$locale:String,$count:Int,$start:Int,$keywords:String,$category:String,$sortBy:String,$sortDir:String,$tag:String,$onSale:Boolean,$freeGame:Boolean,$releaseDate:String){Catalog{searchStore(country:$country,locale:$locale,count:$count,start:$start,keywords:$keywords,category:$category,sortBy:$sortBy,sortDir:$sortDir,tag:$tag,onSale:$onSale,freeGame:$freeGame,releaseDate:$releaseDate){elements{title id namespace description effectiveDate keyImages{type url} productSlug urlSlug tags{id} catalogNs{mappings(pageType:\"productHome\"){pageSlug}} offerMappings{pageSlug} price(country:$country){totalPrice{discountPrice originalPrice currencyCode fmtPrice(locale:$locale){originalPrice discountPrice}} lineOffers{appliedRules{endDate}}}} paging{count total}}}}",
 "variables":{"country":"DE","locale":"de-DE","count":24,"start":0,
   "category":"games/edition/base|bundles/games","sortBy":"releaseDate","sortDir":"DESC","onSale":true}}
```

| Rubrik | Variablen |
|---|---|
| Angebote | `onSale:true` (hearth `EPIC_SALE` mit `sortBy:"relevancy"`) |
| Neu | `sortBy:"releaseDate"`, `releaseDate:"[,2026-10-31T00:00:00.000Z]"` (hearth `EPIC_NEW`) |
| Free-to-Play | `freeGame:true` (Rare) |
| Suche | `keywords:"…"` |
| Genre / Tags | `tag:"1216\|9548"` (mehrere IDs mit `\|`, wie Rare) |
| Sortierung | `sortBy`: `releaseDate`, `title`, `currentPrice`, `relevancy`; `comingSoon` (epicstore_api) |

Tag-IDs (Rare `constants.py`, gegengeprüft mit der Epic-Doku unten):

| Gruppe | IDs |
|---|---|
| Plattform | **macOS 9548**, Windows 9547 |
| Funktionen | **Controller 9549**, Einzelspieler 1370, Mehrspieler 1203, Koop 1264 |
| Genres | Action 1216, Adventure 1117, RPG 1367, Shooter 1210, Strategy 1115, Indie 1263, Simulation 1393, Racing 1212, Puzzle 1298, Survival 1080 |

Vollständige Liste: `Catalog{tags(namespace:"epic",start:0,count:999){elements{id name aliases}}}` (epicstore_api `CATALOG_TAGS_QUERY`).

Beispiel, gekürzt (Mitschnitt hearth-os `fixtures/epic_search.json`

, Okt. 2026):

```
{"data":{"Catalog":{"searchStore":{"elements":[{
  "title":"Hades II","id":"adbc94588a184ce3a6122a19aae940ae","namespace":"36a21c249987423a93f8442cc40a0e33",
  "description":"Battle beyond the Underworld …","effectiveDate":"2024-05-06T16:30:00.000Z",
  "keyImages":[{"type":"OfferImageWide","url":"https://cdn1.epicgames.com/spt-assets/…/hades-ii-7sgi1.png"},
               {"type":"OfferImageTall","url":"https://cdn1.epicgames.com/spt-assets/…/hades-ii-1rb3z.png"}]
  }]}}}}
```

**Topseller / Meistgespielt:**

```
{Storefront{collectionLayout(slug:"top-sellers",locale:"de-DE"){collectionOffers{title id namespace keyImages{type url} productSlug price(country:"DE"){totalPrice{discountPrice originalPrice currencyCode fmtPrice(locale:"de-DE"){originalPrice discountPrice}}}}}}}
```

- Weitere Slugs (epicstore_api EGSCollectionType): most-played, top-wishlisted, most-popular, top-player-reviewed.
- Diese Abfrage liefert immer einen 1004-Fehler mit; den ignoriert sogar der offizielle Client.
- hearth-os prüft im CI parallel Storefront und Collection, offenbar weil Epic hier umgebaut hat. Als fragil behandeln.

**Detailseite:**

```
Catalog{catalogOffer(namespace:"<ns>",id:"<offerId>",locale:"de-DE"){title description longDescription developerDisplayName publisherDisplayName releaseDate keyImages{type url} tags{id name groupName} price(country:"DE"){…}}}
```

Belegt in hearth `EPIC_OFFER` und epicstore_api `OFFERS_QUERY`. Mac-Anforderungen: Heroic fragt `Product{sandbox(sandboxId:"<ns>"){configuration{… on StoreConfiguration{configs{shortDescription technicalRequirements{macos{minimum recommended} windows{…}}}}}}}` (`getExtraFromGraphql`).

#### 3.3 `egs-platform-service` – der neue Store-Dienst

Dokumentiert in `LeleDerGrasshalmi/FortniteEndpointsDocumentation/EpicGames/EGSPlatformService`, Stand 31.10.2026. „Auth Required: No“.

| Endpunkt | Zweck |
|---|---|
| `GET https://egs-platform-service.store.epicgames.com/api/v1/egs/products/<productId>?country=DE&locale=de&store=EGS` | Produkt mit Bildern, Kurztext, Tags (Plattformen, Genres, Features) |
| `GET …/api/v1/egs/mappings/<slug>?country=DE&locale=de` | Slug → `offerId`, `sandboxId` |
| `GET …/api/v2/public/discover/home?count=10&country=DE&locale=de&platform=windows&start=0&store=EGS` | Entdecken-Startseite (belegt im hearth-os-Live-Check) |
| `…/products/<id>/critic-reviews/open-critic`, `…/category-cards`, `…/offers/<id>/age-rating` | Kritiken, Kategorien, Altersfreigabe |

Beispiel, gekürzt (aus der Doku):

```
{"__typename":"Product","id":"prod-fn","title":"Fortnite",
 "media":{"card16x9":{"imageSrc":"https://cdn1.epicgames.com/offer/fn/Blade_2560x1440…"},
          "card3x4":{"imageSrc":"https://cdn1.epicgames.com/offer/fn/Blade_1200x1600…"}},
 "shortDescription":"Create, play, and battle with friends for free …",
 "tags":{"features":[{"id":"9549","name":"Controller Support"}],
         "genres":[{"id":"1216","name":"Action"}],
         "platforms":[{"id":"9547","name":"Windows"}]}}
```

Liefert keinen Preis; den holt man per GraphQL. Läuft auf einem anderen Host als `store.epicgames.com/graphql`; ob Cloudflare hier dazwischengeht, ist ungeprüft.

#### 3.4 `store-content.ak.epicgames.com` – alter Langtext

`GET https://store-content.ak.epicgames.com/api/de/content/products/<slug>` liefert `pages[pageType=productHome].data.about` (Beschreibung) und `requirements.systems[]`.

- Heroic: „try the API first, it works for most games“, sonst GraphQL.
- Rare und Playnite nutzen es auch.
- Das CMS ist Altbestand. Neuere Titel fehlen öfter, daher nur als Rückfall verwenden.

#### 3.5 Mac und Controller bei Epic

| Signal | Quelle |
|---|---|
| Mac-Version | Tag **9548** in `tags`. Bei egs-platform-service unter `tags.platforms`. Oder `technicalRequirements.macos` ist nicht leer. |
| Controller | Tag **9549** |
| Endgültig Mac | Erst nach dem Kauf über legendary (Asset-Liste für Plattform `Mac`). Für Entdecken reicht der Tag. |

#### 3.6 Nutzungsbedingungen Epic

- Es gibt keine öffentliche Store-API und keine Freigabe. Epics allgemeine Nutzungsbedingungen verbieten nach meiner Kenntnis automatisierten Zugriff auf ihre Dienste. Den genauen Wortlaut vor dem Release prüfen.
- Praxis: legendary, Heroic, Rare, Playnite und Home Assistant nutzen genau diese Endpunkte seit Jahren, ohne dass Epic dagegen vorgegangen ist. Die Cloudflare-Prüfung auf store.epicgames.com zeigt aber, dass Epic Bots bremst.
- Nicht umgehen (kein cloudscraper o. Ä.), sondern auf den Browser ausweichen, wie hearth-os.
- Heroic baut für Epic gar keinen eigenen Store, sondern zeigt https://www.epicgames.com/store/<lang>/ in einer WebView.

---

### 4. GOG

#### 4.1 `catalog.gog.com/v1/catalog` – eine Quelle für fast alles

|  |  |
|---|---|
| URL | `GET https://catalog.gog.com/v1/catalog?limit=48&page=1&productType=in:game,pack&countryCode=DE&locale=de-DE&currencyCode=EUR` plus Filter |
| Login | nein. Optional `Authorization: Bearer <token>` für `hideOwned=true` (Heroic). |
| Limit | keines bekannt. Heroic lädt bis zu 30 Seiten **parallel** (`Promise.all`), GOG verträgt das offenbar. |
| Sprache / Region | `countryCode`, `locale`, `currencyCode`. Wenn eine Region nichts liefert, fallen Heroic und DroidDeck auf `US/USD` zurück. Die Region des eingeloggten Kontos liefert `https://embed.gog.com/userData.json` (`country`, `selectedCurrency.code`, Heroic). |
| Nutzer | **Heroic Deals** (`src/backend/discounts/index.ts`

, Okt. 2026), Playnite GOG Metadata (Jeshibu), DroidDeck (Store-Reihen), hearth-os, nebula-mobile, gameyfin, DLSS Swapper |

Belegte Parameter:

| Parameter | Wirkung | Beleg |
|---|---|---|
| `order=desc:trending` | im Trend | Heroic, DroidDeck |
| `order=desc:bestselling` | Bestseller | gameyfin, nebula, hearth |
| `order=desc:releaseDate`, `desc:storeReleaseDate` | Neu | DroidDeck, hearth |
| `order=desc:discount` | höchster Rabatt zuerst | DroidDeck, hearth |
| `order=desc:score`, `asc:price` | Relevanz bei Suche, Preis aufsteigend | DroidDeck, nebula |
| `discounted=eq:true` | nur Angebote | Heroic |
| `price=between:0,0` | kostenlos | DroidDeck |
| `query=like:<begriff>` | Suche | DroidDeck, DLSS Swapper, Playnite-Erweiterung |
| `genres=in:<slug>` (z. B. `rpg`, `action`) | Genre | nebula |
| `systems=in:windows` | Betriebssystem | gameyfin. `systems=in:osx` analog, ungeprüft. |
| `productId=in:<id>,<id>`, `slug=eq:<slug>` | gezielt Preise für bekannte IDs | hearth |
| `productType=in:game,pack,dlc` | Produkttypen | Heroic |
| `hideOwned=true` | Gekauftes ausblenden (mit Token) | Heroic |

Beispiel, gekürzt (Mitschnitt hearth-os `fixtures/gog_catalog.json`

, Okt. 2026, `US/USD`; mit `DE/EUR` kommt die Währung EUR):

```
{"pages":2084,"productCount":8335,"products":[{
  "id":"1274966284","slug":"cyberpunk_2077_ultimate_edition","title":"Cyberpunk 2077: Ultimate Edition",
  "productType":"pack","releaseDate":"2023.09.26",
  "coverHorizontal":"https://images.gog-statics.com/257b15….png",
  "coverVertical":"https://images.gog-statics.com/499f5f….jpg",
  "screenshots":["https://images.gog-statics.com/459b8c…_{formatter}.jpg"],
  "developers":["CD PROJEKT RED"],"operatingSystems":["windows","osx"],
  "price":{"final":"$31.99","base":"$79.99","discount":"-60%",
           "finalMoney":{"amount":"31.99","currency":"USD","discount":"48.00"},
           "baseMoney":{"amount":"79.99","currency":"USD"}},
  "genres":[{"name":"Role-playing","slug":"rpg"}]}]}
```

Weitere Felder aus dem dealfox-Fixture (2026):

- features:[{"name":"Controller support","slug":"controller_support"}, …]
- tags:[{"name":"Adventure","slug":"adventure"}, …]
- reviewsRating, reviewsCount, storeLink

Bild-URLs mit `{formatter}` brauchen einen Größen-Token, z. B. `ggvgm` oder `1600` (arnav-games-Notiz, ungeprüft).

#### 4.2 `api.gog.com/products/{id}` – Spielseite

|  |  |
|---|---|
| URL | `GET https://api.gog.com/products/<id>?expand=description,screenshots,videos&locale=de-DE` |
| Login | nein (Token nur für Downloads) |
| Inhalt | `content_system_compatibility.{windows,osx,linux}`, `description.lead/full/whats_cool_about_it` (HTML), `images` (Bild-URLs ohne Protokoll, beginnen mit `//`), `screenshots[].formatter_template_url`, `videos`, `release_date`, `links.product_card`. **Kein Preis.** |
| Nutzer | Heroic (`gog/library.ts`

 `getProductApi`), Playnite GogLibrary (`GogApiClient.cs`: `?expand=description&locale={1}`), hearth-os, gogapidocs |

Beispiel, gekürzt (Mitschnitt hearth-os `fixtures/gog_product.json`

):

```
{"id":1207664663,"title":"The Witcher 3: Wild Hunt - Complete Edition","slug":"the_witcher_3_wild_hunt",
 "content_system_compatibility":{"windows":true,"osx":false,"linux":false},
 "game_type":"pack","release_date":"2015-05-19T01:00:00+0200",
 "images":{"background":"//images-1.gog-statics.com/a31cc2….jpg","logo":"//images-4.gog-statics.com/…_glx_logo.jpg"},
 "description":{"lead":"<div …><img src=\"https://items.gog.com/the_witcher_3_wild_hunt/COVER_970x300_EN.png\"></div>…"},
 "screenshots":[{"image_id":"3176c5…","formatter_template_url":"https://images-4.gog-statics.com/3176c5…_{formatter}.png"}]}
```

Ergänzend:

- `api.gog.com/v2/games/<id>?locale=de-DE`: _embedded.product, supportedOperatingSystems mit Systemanforderungen, Tags, Features. Heroic nutzt das für die Anforderungen.
- `api.gog.com/products/<id>/prices?countryCode=DE`: Preise unter _embedded.prices[].finalPrice (im hearth-Live-Check, Format ungeprüft). Einfacher ist catalog?productId=in:<id>.

#### 4.3 Gratis-Aktionen (Giveaways)

|  |  |
|---|---|
| URL | `GET https://sections.gog.com/v1/pages/2f?locale=de-DE&countryCode=DE&currencyCode=EUR` |
| Auswertung | Abschnitt mit `sectionType == "GIVEAWAY_SECTION"` → `properties.product` (Produktdaten im Katalogformat) und `properties.endDate` (dealfox `internal/freegames/gog.go`

, Fixture vom Sept. 2026) |
| Achtung | `2f` ist die Kennung der Startseite und kann sich ändern. Das Spiel ist im Katalog **nicht** reduziert (GameRadar-Notiz: „El giveaway de portada de GOG NO es un descuento del catálogo“). Als **fragil** einstufen. |

Dauerhaft kostenlose GOG-Spiele liefert dagegen stabil `catalog?price=between:0,0`.

#### 4.4 `embed.gog.com` – Altbestand

- embed.gog.com/games/ajax/filtered?mediaType=game&search=…&page=… ist die alte Store-Liste (gogapidocs von 2018, Beispiel mit "symbol":"€", worksOn.Mac). Playnite GogLibrary nutzt die Variante auf www.gog.com noch für die Suche. GOGs aktueller Store läuft über catalog.gog.com. Nicht neu darauf bauen.
- `embed.gog.com/userData.json`

 (Region und Währung) und `embed.gog.com/user/wishlist.json`

 (Wunschliste, Login nötig) bleiben nützlich (Heroic, Lutris).

#### 4.5 Mac und Controller bei GOG

| Signal | Quelle |
|---|---|
| Mac | `operatingSystems` enthält `"osx"` (Katalog) bzw. `content_system_compatibility.osx` (products) |
| Controller | `features[].slug == "controller_support"`. Ob es dafür einen Server-Filter gibt, ist ungeprüft; clientseitig filtern geht immer. |

#### 4.6 Nutzungsbedingungen GOG

- Keine öffentliche Doku und keine ausdrückliche Freigabe für den Katalog.
- GOG duldet Drittclients seit Jahren: Heroic samt gogdl, Lutris, Minigalaxy, Playnite, gogdb.org.
- Heroic betreibt sogar eine eigene Angebotsansicht direkt auf catalog.gog.com und sendet User-Agent: HeroicGamesLauncher/<version>.
- Empfehlung: einen eigenen User-Agent mitschicken (Nightforge/<version>), maßvoll abfragen, auf storeLink verlinken.

---

### 5. Risiken

#### 5.1 Inoffizielle Schnittstellen

Außer der Steam-Web-API mit Key ist **alles hier undokumentiert**. Die Stores können jederzeit ohne Ankündigung Felder umbenennen, Endpunkte abschalten oder Bot-Schutz einbauen. Das passiert tatsächlich, 2026 gleich mehrfach:

- Steam: Seit Oktober 2026 antwortet Steam auf öffentliche Spielelisten in Community-Profilen nur noch mit der Login-Seite (Kommentar in hearth-os `tools/store-live-check.py`

).
- Epic: Der alte CMS-Host store-content wird zurückgebaut, collectionLayout wurde umgebaut (hearth prüft zwei Varianten), auf store.epicgames.com/graphql sitzt Cloudflare.
- GOG: Die Store-Liste ist von embed.gog.com/games/ajax/filtered zu catalog.gog.com gewandert.
- Allgemeine Stimmung: PCGamingWiki hat nach seiner Server-Migration (August 2026) anonyme Cargo-Abfragen abgeschaltet (Notiz in arnav-games). Datenquellen werden insgesamt restriktiver.

#### 5.2 Stabilität pro Quelle, grob eingeschätzt

| Quelle | Einschätzung |
|---|---|
| Steam `appdetails`, `storesearch`, `featuredcategories`, `search/results` | über 10 Jahre stabil, breit genutzt |
| Steam `IStoreBrowseService`, `IStoreQueryService`, `ISteamChartsService` | Valves eigener neuer Store nutzt sie. Felder per SteamDatabase-Protobufs nachvollziehbar, Definitionen täglich aktualisiert. |
| Epic `freeGamesPromotions` | seit Jahren stabil, von Home Assistant im Kern genutzt |
| Epic GraphQL über `launcher.store.epicgames.com` | stabil, legendary und Heroic hängen daran. Cloudflare kann jederzeit kommen. |
| Epic `collectionLayout`, `store-content`, `egs-platform-service` | fragil bzw. neu |
| GOG `catalog.gog.com`, `api.gog.com/products` | stabil, von Heroic aktiv genutzt |
| GOG `sections.gog.com` Giveaway | fragil (feste Seiten-ID `2f`) |

#### 5.3 Limits

- Steam-Storefront: etwa 200 Anfragen / 5 min / IP, danach 429. Für den Fall ohne Retry-Header gilt: das Limit ist weich und wird teils als success:false statt 429 sichtbar (browser-use-Notiz). Gegenmittel: GetItems bündeln, 24 h cachen, ≥ 1,5 s Abstand für appdetails.
- Steam-Service-Methoden: kein Limit bekannt; mit 3 Anfragen/s wird es konservativ gehalten (printing-press).
- Epic und GOG: keine Limits bekannt. Bei Epic ist Cloudflare das eigentliche Limit, also sparsam abfragen.
- Weil die IP des Nutzers abfragt, betreffen Limits nur ihn. Ein Nightforge-eigener Server fällt weg, ebenso ein Single Point of Failure, aber auch zentrales Caching.

#### 5.4 Region und Daten

- Preise: Steam richtet die Währung nach cc (DE → EUR, final_formatted z. B. "12,99€"). Epic braucht ein gültiges ISO-Land (sonst Fehler 5222). GOG kann für manche Regionen leer antworten (Rückfall US/USD wie bei Heroic) und zeigt dann keine Euro-Preise. In dem Fall den Preis ausblenden, nicht in Dollar anzeigen.
- Texte: Steam liefert Deutsch per l=german bzw. language:"german". Epic per locale:"de-DE", der Feed freeGamesPromotions liefert Texte aber oft nur auf Englisch. GOG per locale=de-DE, die Beschreibungen sind oft nur auf Englisch.
- Mac-Flags sind Herstellerangaben: mac:true heißt nicht „läuft auf aktuellem macOS / Apple Silicon“. Den Epic-Tag 9548 setzt der Publisher. Die bestehende Nightforge-Prüfung (Mac-Version, Kompatibilität) nachschalten.
- Anti-Cheat: Kein Store liefert das verlässlich. Steams extra_details.anticheat ist neu und ungeprüft. Die Nightforge-Liste (AntiCheatBlock mit GeForce-Now-ID) bleibt die Hauptquelle.

#### 5.5 Recht und Darstellung

- Bilder, Texte und Logos gehören Publishern und Stores. Anzeigen mit Quelle und Link zum Store ist bei Launchern üblich (Heroic, Playnite, Rare). Nicht dauerhaft in großen Mengen spiegeln, nicht neu verteilen.
- Store-Namen und -Logos nur zur Kennzeichnung verwenden, keine Partnerschaft andeuten. Die Steam-API-Bedingungen verlangen das ausdrücklich.
- Keine Bot-Sperren umgehen (Cloudflare, Captchas). Laut Rare braucht schon „zur Wunschliste hinzufügen“ ein Captcha.

#### 5.6 Absicherung in Nightforge

1. Jede Quelle einzeln kapseln. Fällt sie aus, bleibt die Reihe leer, wie bei StoreSearch.
2. Mitgeschnittene Antworten als Test-Fixtures einchecken und Parser dagegen testen. Zusätzlich ein Live-Check im CI, der nur warnt (Vorbild: hearth-os `tools/store-live-check.py`

, CI-Job „store-live“). Er zeigt Formatänderungen früh, ohne den Build zu brechen.
3. Endpunkt-URLs und GraphQL-Abfragen zentral halten, sodass sich eine kaputte Quelle per Update schnell abschalten oder ersetzen lässt.
4. Für Epic von Anfang an den Ausweg „Im Browser öffnen“ einplanen.

---

#### Quellen (Auswahl)

- SteamDatabase Protobufs: https://github.com/SteamDatabase/Protobufs (`steam/steammessages_storebrowse.steamclient.proto`

, `webui/service_storequery.proto`

, `webui/service_steamcharts.proto`

, `webui/service_storetopsellers.proto`

)
- xPaw Steam Web API Documentation: https://steamapi.xpaw.me · https://github.com/xPaw/SteamWebAPIDocumentation
- Revadike InternalSteamWebAPI: https://github.com/Revadike/InternalSteamWebAPI
- benhurk IStoreQueryService-Doku: https://github.com/benhurk/IStoreQueryService-Query-v1-Documentation
- Steam Web API Terms of Use: https://steamcommunity.com/dev/apiterms
- Playnite-Erweiterungen: https://github.com/JosefNemec/PlayniteExtensions (`SteamShared/WebApiClient.cs`

, MetadataProvider.cs, SteamTagNamer.cs, `EpicLibrary/Services/WebStoreClient.cs`

, `GogLibrary/Services/GogApiClient.cs`

)
- Heroic: https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher (`src/backend/discounts/index.ts`

, `storeManagers/legendary/games.ts`

, `storeManagers/gog/library.ts`

, `frontend/screens/WebView/index.tsx`

)
- legendary: https://github.com/derrod/legendary (`legendary/api/egs.py`

) · gogdl: https://github.com/Heroic-Games-Launcher/heroic-gogdl
- Rare (Epic-Store-Tab): https://github.com/RareDevs/Rare (rare/components/tabs/store/)
- epicstore_api: https://github.com/SD4RK/epicstore_api
- Home Assistant Epic-Integration: https://github.com/home-assistant/core (homeassistant/components/epic_games_store, tests/components/epic_games_store/fixtures)
- Epic-Endpunkt-Doku: https://github.com/LeleDerGrasshalmi/FortniteEndpointsDocumentation (EpicGames/EGSPlatformService)
- gogapidocs (2018): https://github.com/Yepoleb/gogapidocs
- RomM: https://github.com/rommapp/romm (`backend/adapters/services/steam.py`

)
- hearth-os: https://github.com/Dragongamer9/hearth-os (`tools/store-live-check.py`

, hosts/hearth-core/src/storefront/)
- DroidDeck: https://github.com/Droid-Deck/DroidDeck (`stores/gog/GogStoreCatalog.kt`

)
- dealfox: https://github.com/depthbomb/dealfox (internal/freegames/) · Auto-Claim: https://github.com/BambooFury/Auto-Claim (`frontend/scanner/freeweekend.ts`

)
- Mitschnitte: https://github.com/LucasPrezFdez/gameagenda (Steam Query, 29.10.2026) · https://github.com/BRYANN2K/cartouche (GetMostPlayedGames, 19.10.2026) · Harbor: https://github.com/Harborofficial/Harbor (Controller-Kategorien 28/18)
