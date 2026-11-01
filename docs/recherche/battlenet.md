<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHQPyhJHQDCAjg87AMS (1.11.2026) -->

## Battle.net in Nightforge: Recherchebericht

Ich habe nur gelesen und gesucht. Im Repo ist nichts geändert, nichts committet und nichts gepusht. Der Bericht liegt zusätzlich unter `/tmp/claude-0/-home-user-Nightforge/0e43bacb-d604-55b3-8e25-e53e0c1983ff/scratchpad/reports/Battlenet Integration für Nightforge.md`.

**Einschränkung:** Blizzards eigene Seiten (EULA, Support, Foren, develop.battle.net) sowie ProtonDB, der Steam-Store, SteamDB, PCGamingWiki und GamingOnLinux waren in dieser Umgebung per Netzwerkregel gesperrt. Aussagen aus diesen Quellen beruhen nur auf Suchergebnis-Ausschnitten und sind mit **†** markiert. Den Quellcode auf GitHub (Playnite, Lutris, GOG-Galaxy-Plugin, WowUp, bnetlauncher, Arctium) habe ich direkt gelesen. Auf einem echten Mac mit Battle.net ist nichts getestet.

---

### Kurzfassung

Ein Battle.net-Store ist machbar, aber nur nach dem Muster, das Nightforge schon für Steam nutzt: Die **offizielle Battle.net-App bleibt Pflicht**.

- Erkennen: Nightforge liest die lokale Installationsdatenbank product.db der App.
- Starten: Die App startet das Spiel per --exec="launch <Code>".
- Spielende: Nightforge sieht Laufen und Ende an den Prozessen im Installationsordner.

Für die Mac-Versionen (WoW, Diablo III, Hearthstone, StarCraft I/II, Heroes, Warcraft III: Reforged) geht das ohne Wine. Anti-Cheat spielt dabei keine Rolle.

| Thema | Ampel | Warum |
|---|---|---|
| Installierte Spiele erkennen, Spielende erkennen | Grün | Pfad und Format sind aus mehreren aktuellen Projekten bekannt |
| Spiele starten | Gelb | `--exec` ist auf dem Mac nur durch Code von 2021 belegt; Battle.net muss laufen und angemeldet sein |
| Besessene, nicht installierte Spiele | Gelb | nur über einen undokumentierten Endpunkt der Blizzard-Kontoseite nach Web-Login; eine offizielle API gibt es nicht |
| Overwatch, Diablo IV, Diablo II: Resurrected | Gelb | alle drei gibt es auf Steam mit bloßer Kontoverknüpfung; auf Apple Silicon laufen sie unter CrossOver erst seit CrossOver 26.1 mit macOS 26.5 wieder |
| Call of Duty | Rot | Anti-Cheat RICOCHET ist ein Kernel-Treiber, ab Black Ops 7 kommen TPM 2.0 und Secure Boot dazu |
| Recht | kein Verbot gefunden | Playnite, Lutris, GOG Galaxy und die Xbox-App machen dasselbe seit Jahren offen und unbehelligt; die EULA-Klauseln sind aber weit gefasst |

Zwei Befunde bestimmen die Reihenfolge:

1. Nightforge enthält heute nur Steam. Epic, GOG und das StoreProvider-Protokoll sind erst geplant, anders als der Auftrag annahm.
2. Die Battle.net-App für den Mac läuft noch als Intel-Version. Apple hält Rosetta 2 nach macOS 27 nur noch für ältere Spiele bereit.

### Nightforge kennt heute nur Steam: Battle.net wäre der erste zweite Store

Im untersuchten Stand (Version `0.2.1-dev`, `Resources/Info.plist:24-25`

, Commit `ffd6285`) ist **nur Steam** umgesetzt, und zwar auf drei Wegen:

- Windows-Steam im eigenen Wine-Prefix
- Valves Steam für Mac für native Versionen
- Steam in fremden CrossOver- oder Whisky-Bottles (README.md:24, `Sources/Nightforge/MacSteam.swift:4-7`

)

Was fehlt:

- Epic und GOG stehen nur als Recherche-Punkte 7.2 und 7.3 in der Roadmap (`docs/ROADMAP.md:271-272`

).
- `StoreProvider` ist Punkt 7.1 (`docs/ROADMAP.md:270`

). Es setzt das anbieterneutrale Spielmodell 0.2 mit GameID { provider, id } voraus (`docs/ROADMAP.md:59-64`

).
- Keine Abstraktion im Code: In Sources/ gibt es kein einziges protocol. struct Game trägt als Identität eine Steam-appID: Int (`Sources/Nightforge/Library.swift:20-75`

). Auch Spieloptionen, Artwork-Cache und Profile hängen an ganzzahligen Steam-IDs (`Sources/Nightforge/Launcher.swift:182-199`

, `Sources/Nightforge/Artwork.swift:41`

, `Sources/Nightforge/Profiles.swift:211-218`

).
- Battle.net steht in keiner Roadmap-Phase. Der einzige Treffer ist der Vermerk „Battle.net (Overwatch)“ bei den ungeprüften Launcher-Spielen (`docs/TODO.md:106-107`

).

Daraus folgt: Battle.net kann nicht als „vierter Store“ an eine fertige Schnittstelle andocken. Es wäre die **erste Nicht-Steam-Umsetzung von 7.1**.

Epic und GOG sollen laut Roadmap ohne Hersteller-Client über legendary bzw. gogdl laufen (`docs/ROADMAP.md:271-272`

). Battle.net braucht dagegen wie Steam einen offiziellen Client, den Nightforge fernsteuert. Damit prüft Battle.net die neue Abstraktion an dem Fall, der Steam am ähnlichsten ist. Die empfohlene Reihenfolge am Ende setzt deshalb 0.2 und 7.1 vor jede Battle.net-Arbeit.

### Methodik: GitHub-Code direkt gelesen, Blizzard nur als Suchausschnitt

Grundlage sind sieben Recherche-Stränge vom 1. November 2026 und ein rein lesender Blick ins Nightforge-Repo (Branch `claude/lucid-franklin-tosu3p`, Commit `ffd6285`). Belege aus dem Repo stehen als `Datei:Zeile`.

Den **GitHub-Quellcode** dieser Projekte habe ich **direkt gelesen**, meist auf feste Commits verlinkt:

- Playnite BattleNetLibrary
- GOG-Galaxy-Blizzard-Plugin
- Lutris
- WowUp
- bnetlauncher
- Arctiums Spiegel der Blizzard-„productconfig“-Dateien

**Per Netzwerkregel gesperrt** waren:

- Blizzard-Seiten (blizzard.com, Support, Foren, News, Shop) und develop.battle.net
- ProtonDB, Steam-Store, SteamDB, PCGamingWiki, GamingOnLinux
- unter anderem PC Gamer, Tom’s Hardware, Blizzard Watch, InsideMacGames und learn.microsoft.com

Aussagen aus diesen Quellen sind mit **†** markiert. Zitate und Abschnittsnummern daraus muss jemand vor einer Veröffentlichung gegen die Live-Seite prüfen. Auch die übrigen Presse- und Forenquellen habe ich überwiegend nur über Suchergebnisse gesehen. Eigene Schlussfolgerungen sind als „Ableitung“ gekennzeichnet. Das ist keine Rechtsberatung.

### Ampel je Teil

| Teil | Frage | Ampel | Kern |
|---|---|---|---|
| 1 | Installierte Mac-Spiele erkennen | **Grün** | `product.db` mit bekanntem Pfad und Schema, von mehreren aktuellen Open-Source-Projekten genutzt |
| 1 | Mac-Spiele starten | **Gelb** | `--exec` auf dem Mac nur durch Galaxy-Code von 2021 belegt; WoW-Classic-Varianten haben keinen Startcode; Battle.net muss laufen und angemeldet sein |
| 1 | Spielende erkennen | **Grün** | Prozesse im Installationsordner abfragen; diese Logik hat Nightforge schon für Mac-Spiele |
| 1 | Zukunft der Mac-App | **Gelb** | Battle.net-App und Agent sind Intel-only; Rosetta 2 gibt es allgemein nur bis macOS 27 |
| 2 | Bibliothek: installierte Spiele | **Grün** | lokal, ohne Login |
| 2 | Bibliothek: besessene Spiele | **Gelb** (offizielle API: **Rot**) | nur über einen undokumentierten Endpunkt der Kontoseite mit Web-Login; Sitzungen laufen ab |
| 2 | Namen und Cover | **Gelb** | Namen liefert der Server; Cover ohne API-Key nur per Direktlink oder Steam-CDN |
| 3 | Windows-Titel über Steam (OW, D4, D2R) | **Grün/Gelb** | auf Steam mit bloßer Kontoverknüpfung; Nightforges Steam-Weg existiert; Battle.net-Besitzer müssen D4 und D2R neu kaufen |
| 3 | Windows-Titel über Battle.net unter Wine | **Gelb** | läuft bei CrossOver; im Nightforge-Prefix ungetestet |
| 4 | Anti-Cheat bei OW, D4, D2R | **Gelb** | kein Kernel-Treiber; frühere Fehlbann-Wellen unter Wine wurden zurückgenommen |
| 4 | Call of Duty | **Rot** | RICOCHET-Kernel-Treiber, ab BO7 zusätzlich TPM 2.0 und Secure Boot |
| 5 | Recht: lokal lesen und per `--exec` starten | **Grün/Gelb** | kein Verbot gefunden, aber weite „Data Mining“-Klausel |
| 5 | Recht: besessene Spiele über die Kontoseite | **Gelb** | undokumentierter Endpunkt; Klausel gegen „unautorisierte Verbindungen“ |

### Teil 1: Mac zuerst – Battle.net fernsteuern statt ersetzen

#### Acht Blizzard-Titel haben noch Mac-Clients

Mac-Clients haben nur noch WoW (alle Varianten), Hearthstone, StarCraft II, StarCraft: Remastered, Diablo III, Heroes of the Storm und Warcraft III: Reforged. Jedes neuere Blizzard- und Activision-Spiel erscheint nur für Windows ([Blizzard Watch](https://blizzardwatch.com/2024/12/05/quiet-sunsetting-mac-support-blizzards-franchises/) †).

Das bestätigen Blizzards eigene productconfigs: Bei diesen Titeln fehlt die `mac`-Plattform ([Arctium-Spiegel](https://github.com/Arctium/bnet-tact-channel-configs/tree/dc4937ee90fb3b4bfbc976501ced57d1d4e6e10a)):

- Overwatch (pro), Diablo IV (fenris), D2R (osi)
- Diablo Immortal, Warcraft Rumble, die Warcraft-Remaster
- alle Call-of-Duty-Titel

| Titel | Mac-Client | Apple Silicon | Belege |
|---|---|---|---|
| World of Warcraft (Retail) | ja | **nativ arm64** seit Patch 9.0.2 (17.11.2020); *Midnight* verlangt mindestens macOS 12 und M2 | [AppleInsider](https://appleinsider.com/articles/20/11/17/blizzard-updates-world-of-warcraft-to-natively-support-apple-silicon); [Battle.net-Shop](https://us.shop.battle.net/en-us/product/world-of-warcraft-midnight) † |
| WoW Classic, Classic Era, Anniversary | ja, im selben WoW-Produkt über die Versionsauswahl ([Forum](https://us.forums.blizzard.com/en/wow/t/how-do-i-open-classic-wow-on-a-mac/1643947) †) | **unsicher, widersprüchlich**: AppleGamingWiki bewertet nativ mit „Perfect“, ein Forenthread von 2021 nennt Classic noch Rosetta | [AppleGamingWiki](https://www.applegamingwiki.com/wiki/World_of_Warcraft:_Classic); [Forum 2021](https://us.forums.blizzard.com/en/wow/t/classic-compatible-with-m1/862171) † |
| Hearthstone | ja, nur über Battle.net | **unsicher, widersprüchlich**: ein Forenbeitrag vom 5.6.2026 sagt „jetzt Universal“, Blizzard-Forenthreads berichten Intel unter Rosetta | [InsideMacGames](https://www.insidemacgames.com/forum/thread-32729-lastpost.html) †; [HS-Forum](https://us.forums.blizzard.com/en/hearthstone/t/native-hearthstone-on-mac-with-apple-silicon/139128) †; [Recharge.com](https://www.recharge.com/blog/en-gb/how-to-download-hearthstone-on-pc-mac-mobile-2026) |
| Diablo III | ja | **Universal** seit 2.7.8 (Herbst 2024) | [Blizzard News](https://news.blizzard.com/en-us/article/24135096/diablo-iii-ptr-2-7-8-has-concluded) †; [Macworld](https://www.macworld.com/article/666832/diablo-iii-review-highly-addictive-if-unambitious-action-rpg-sequel.html) |
| StarCraft II | ja | Intel, Rosetta; ein Absturzbericht unter macOS 26.5 | [AppleGamingWiki](https://www.applegamingwiki.com/wiki/StarCraft_II); [SC2-Forum](https://us.forums.blizzard.com/en/sc2/t/starcraft-ii-crashing-on-macos-265/31907) † |
| StarCraft: Remastered | ja | Intel, Rosetta; braucht macOS 12 | [AppleGamingWiki](https://www.applegamingwiki.com/wiki/StarCraft) |
| Heroes of the Storm | ja | Intel, Rosetta | [MacGamesList](https://www.macgameslist.com/rosetta-2-mac-games) |
| Warcraft III: Reforged | ja; am 3.10.2024 per Fernlöschung entfernt, mit Patch 2.0 am 13.11.2024 zurück | Intel, Rosetta (Forum, Herbst 2026) | [Wikipedia](https://en.wikipedia.org/wiki/Warcraft_III:_Reforged); [WC3-Forum](https://us.forums.blizzard.com/en/warcraft3/t/how-much-longer-will-forsaken-kingdoms-run-on-the-mac/39292) † |
| Warcraft I/II Remastered | nein | – | [Mac4Ever](https://www.mac4ever.com/mac/185290-warcraft-1-et-warcraft-2-remastered-sont-disponibles-sur-pc-mais-pas-sur-mac) |

**Die Battle.net-App selbst ist Intel-only.** Eine Community-Zählung vom September 2026 kommt samt Agent auf „56-for-56 Intel“ ([WoW-Forum](https://us.forums.blizzard.com/en/wow/t/rosetta-was-a-bridge-not-a-roadmap-battlenet-and-agent-are-56-for-56-intel/2344535) †, ebenso [RosettaCheck](https://rosettacheck.com/apps/5nfqmtbm)). Blizzard teilt dazu nur mit, man sei „actively investigating and planning“ ([Blizzard-Forum](https://us.forums.blizzard.com/en/blizzard/t/battlenet-on-macs-future-macos-compatibility-changes/59297) †).

Apple hält Rosetta 2 bis macOS 27 als allgemeines Werkzeug bereit. Ab macOS 28 bleibt nur ein Teil für „older unmaintained games that rely on Intel-based frameworks“ ([MacRumors](https://www.macrumors.com/2025/06/10/apple-to-phase-out-rosetta-2/)).

**Ableitung:** Die Battle.net-App ist kein Spiel. Ohne arm64-Version könnte sie ab macOS 28 nicht mehr starten, und damit auch keines der Mac-Spiele, die über sie laufen. Weil der Architekturstatus mehrerer Titel unsicher ist, sollte Nightforge ihn zur Laufzeit am installierten Binary prüfen, statt ihn fest einzutragen.

#### product.db verrät Installationsort und Zustand ohne Login

**Wo die Dateien liegen:**

- Mac: `/Users/Shared/Battle.net/Agent/product.db`

. Diesen Pfad nutzen das GOG-Galaxy-Plugin (2021) und das aktuelle WowUp (Oktober 2026) (Galaxy `consts.py`; WowUp mac).
- Unter Wine: im Prefix unter `drive_c/ProgramData/Battle.net/Agent/product.db`

. Fehlt die Datei dort, wertet Lutris alle Battle.net-Spiele als nicht installiert (Lutris).
- Nutzer-Konfiguration: ~/Library/Application Support/Battle.net/Battle.net.config (JSON). Für den Mac ist sie nur durch den Galaxy-Code von 2021 belegt. Ihr Abschnitt Games führt pro uid ServerUid, LastPlayed (Unix-Sekunden) und Resumable (Galaxy-Testdaten).

**Format:** `product.db` ist eine unverpackte Protobuf-Nachricht `ProductDb`. Das Schema ist per Reverse Engineering ermittelt und liegt als `.proto` im Galaxy-Plugin (MIT) ([product_db.proto](https://github.com/bartok765/galaxy_blizzard_plugin/blob/83cfb024ebc00cbc71702f101671bea596cfc96f/src/product_db.proto#L87-L123)). Die für Nightforge nötigen Felder:

| Feld (Nummer) | Bedeutung |
|---|---|
| `product_installs[]` (1) | ein Eintrag pro installiertem Produkt |
| `.uid` (1) | Agent-Kennung, oft mit Sprachendung, etwa `wow_enus` |
| `.product_code` (2) | TACT-Code, etwa `wow`, `hsb`, `s2` |
| `.settings.install_path` (3.1) | Installationsordner |
| `.settings.play_region` (3.2) | Region |
| `.cached_product_state.base_product_state.installed` / `.playable` / `.update_complete` / `.current_version_str` (4.1.1 / 4.1.2 / 4.1.3 / 4.1.7) | Zustand und Version |
| `update_progress.progress`, `total_to_download`, `download_remaining` | Download-Fortschritt |
| `product_operations.active_operation` | `OP_UPDATE`, `OP_REPAIR` usw. ([proto](https://github.com/bartok765/galaxy_blizzard_plugin/blob/83cfb024ebc00cbc71702f101671bea596cfc96f/src/product_db.proto#L36-L85)) |

WowUp liest 2026 zusätzlich zwei neuere Felder: Feld 6 in `ProductInstall` ist die Produktfamilie (etwa `wow`), Feld 13 in `UserSettings` der Unterordner der Variante (etwa `_retail_`, `_classic_era_`) ([WowUp product-db.ts](https://github.com/WowUp/WowUp/blob/d57478f3e56e5ab79dc9294bb205ba67498c3e4a/wowup-electron/src/common/wowup/product-db.ts#L1-L34)). Lutris hat google-protobuf durch einen eigenen Mini-Decoder ersetzt, „adapted from“ dem Galaxy-Parser ([Lutris product_db.py](https://github.com/lutris/lutris/blob/89cc4398a6064cd1bbf9bf4bed6820592b566c67/lutris/util/battlenet/product_db.py)).

**Ableitung:** In Swift reicht swift-protobuf mit dem MIT-Schema oder ein Decoder ohne Abhängigkeiten für rund acht Felder.

**Worauf beim Auslesen zu achten ist:**

- Schlüssel: product_code taugt, uid nicht, weil uids Sprachendungen tragen (s2_plpl, diablo3_plpl in den Galaxy-Testdaten).
- Installiert: Galaxy wertet ein Spiel als installiert, wenn playable or installed gilt. Einträge, deren Ordner fehlt, überspringt es („Probably outdated product.db after uninstall“) (local_games.py).
- Mac-Bundles: Blizzards productconfigs legen Mac-Spiele standardmäßig unter /Applications ab.
  - WoW nutzt _retail_/World of Warcraft.app. Alle Classic-Varianten nutzen World of Warcraft Classic.app im jeweiligen Unterordner. install_path zeigt dabei auf den obersten WoW-Ordner (Arctium wow; WowUp).
  - Weitere Bundles: Hearthstone.app, StarCraft II `Support/SC2Switcher.app`

, Diablo III.app, Heroes `Support/HeroesSwitcher.app`

, x86_64/Warcraft III.app, StarCraft `x86/StarCraft.app`

 (Arctium s2, d3).

- Zugriffsrechte, ungeprüft: Ein Forenthread erwähnt, dass der Agent selbst nach Festplattenvollzugriff bzw. App-Verwaltung fragt. Ob ein nicht gesandboxtes Nightforge die Datei in /Users/Shared ohne Rückfrage lesen kann, ist ungeprüft.

#### `--exec` startet nur über die laufende, angemeldete Battle.net-App

| Weg | Was passiert | Beleg | Urteil |
|---|---|---|---|
| `Battle.net --exec="launch <Code>"` | startet das Spiel über den Client, **nur wenn dieser bereit ist**; bei einem gerade erst gestarteten Client läuft der Befehl ins Leere | Playnite wartet auf mindestens 5 Prozesse plus 5 s ([Playnite](https://github.com/JosefNemec/PlayniteExtensions/blob/886468f65724e6fd104f3a09847a17ba57cfb430/source/Libraries/BattleNetLibrary/BattleNetGameController.cs#L200-L216)); Lutris wartet fest 15 s ([Lutris](https://github.com/lutris/lutris/blob/89cc4398a6064cd1bbf9bf4bed6820592b566c67/lutris/services/battlenet.py#L165-L236)); bnetlauncher wartet auf 3 Kindprozesse, maximal 120 s ([bnetlauncher](https://github.com/dafzor/bnetlauncher/blob/8bf5ea91745683496bc2f53a63fb474eb5f43b2a/bnetlauncher/Clients/BnetClient.cs#L103-L218)) | **Standardweg** |
| dasselbe auf dem Mac | Galaxy ruft `/Applications/Battle.net.app/Contents/MacOS/Battle.net --exec=…` auf, sobald das Fenster „Blizzard Battle.net“ erscheint (Zeitlimit 60 s); danach versteckt es den Client und beendet ihn per `osascript` | [Galaxy local_client.py](https://github.com/bartok765/galaxy_blizzard_plugin/blob/83cfb024ebc00cbc71702f101671bea596cfc96f/src/local_client.py#L139-L187); [local_client_base.py](https://github.com/bartok765/galaxy_blizzard_plugin/blob/83cfb024ebc00cbc71702f101671bea596cfc96f/src/local_client_base.py#L85-L154) | **Gelb**: Code von 2021; laut productconfig liegen die echten App-Versionen inzwischen unter `~/Library/Application Support/Battle.net/Versions` ([Arctium bna](https://github.com/Arctium/bnet-tact-channel-configs/blob/dc4937ee90fb3b4bfbc976501ced57d1d4e6e10a/phx/variants/bna/productconfig)) |
| `battlenet://<Code>` | öffnet heute nur noch den Spiel-Tab; `battlenet://Pro` „does nothing“ | [Blizzard-Forum](https://us.forums.blizzard.com/en/blizzard/t/shortcuts-do-not-actually-start-the-games/1797) †; [EU-OW-Forum](https://eu.forums.blizzard.com/en/overwatch/t/desktop-shortcut-with-battlenet-pro-doesnt-launch-game-any-more/5160) †; bnetlauncher wich deshalb aus ([Changelog](https://github.com/dafzor/bnetlauncher/blob/8bf5ea91745683496bc2f53a63fb474eb5f43b2a/changelog.txt#L105-L113)) | nur als Rückfall „Battle.net öffnen“; ob das Schema auf macOS registriert ist, ist ungeprüft |
| `--game=<uid>`, `--install --game=<uid>`, `--exec="install <CODE>"` | öffnet die Spielseite bzw. stößt die Installation an | [Playnite](https://github.com/JosefNemec/PlayniteExtensions/blob/886468f65724e6fd104f3a09847a17ba57cfb430/source/Libraries/BattleNetLibrary/BattleNetGameController.cs#L32-L58); [Galaxy](https://github.com/bartok765/galaxy_blizzard_plugin/blob/83cfb024ebc00cbc71702f101671bea596cfc96f/src/local_client_base.py#L101-L109); Lutris | für „Installieren“ |
| WoW-Classic-Varianten | kein bestätigter `--exec`-Code. Galaxy startet `open "<install_path>/World of Warcraft Launcher.app" --args productcode=wow_classic`; bnetlauncher klickt den Play-Knopf per Pixelfarbe; Playnite hält einen getrennten Start für unmöglich | [Galaxy](https://github.com/bartok765/galaxy_blizzard_plugin/blob/83cfb024ebc00cbc71702f101671bea596cfc96f/src/local_client_base.py#L139-L144); [bnetlauncher](https://github.com/dafzor/bnetlauncher/blob/8bf5ea91745683496bc2f53a63fb474eb5f43b2a/bnetlauncher/Clients/BnetClient2.cs#L31-L131); [Playnite #510](https://github.com/JosefNemec/PlayniteExtensions/issues/510) | **Gelb/Rot**; die Klick-Simulation nicht übernehmen |
| Spiel-Binary direkt | umgeht die Anmelde-Übergabe vom Client (`OnlineService.SSO=true` bei D3, `-sso=1` bei SC2/Heroes, `-sso -launch` bei D4) und das Patchen | [Arctium d3](https://github.com/Arctium/bnet-tact-channel-configs/blob/dc4937ee90fb3b4bfbc976501ced57d1d4e6e10a/diablo3/variants/d3/productconfig), [fenris](https://github.com/Arctium/bnet-tact-channel-configs/blob/dc4937ee90fb3b4bfbc976501ced57d1d4e6e10a/fenris/variants/fenris/productconfig); Blizzard nennt Mac-Starts ohne Battle.net „not working as intended“ ([Support 301162](https://us.support.blizzard.com/en/article/301162) †) | **nicht nutzen** |

**Muss Battle.net laufen und angemeldet sein? In der Praxis ja.**

- Alle untersuchten Integrationen starten den Client zuerst und warten, bis er bereit ist.
- Nutzer berichten, --exec greife nur „signed in and Battle.net running“, sonst lande man auf dem Startbildschirm (LaunchBox-Forum).
- Ein direkt gestartetes Spiel bekommt laut einem OSOL-Issue keine Anmeldedaten vom Client (Lightrun-Spiegel †).
- Ein einzelner Nutzer meldet, WoW lasse sich auf dem Mac direkt starten. Veraltete Builds starten ohne Update über Battle.net aber nicht (WoW-Forum †, WoW-Forum †).
- Blizzards Agent erlaubt „update while executing“ nur für bna und agent, nicht für Spiele (Arctium agent).

**Ableitung zu macOS:** `open -a Battle.net --args …` übergibt die Argumente vermutlich nur an eine neu gestartete Instanz. Dafür gibt es keinen Beleg. Der direkte Prozessaufruf wie bei Galaxy ist vorzuziehen.

#### Spielende: Prozesse im Installationsordner zählen

Battle.net startet das Spiel nicht als eigenen Kindprozess. So lösen es die anderen:

- Galaxy durchsucht auf dem Mac alle Prozesse („on macOS games are spawn not as client children“). Es vergleicht ihre Programmpfade mit allen ausführbaren Dateien unter install_path, alle 0,5 s und höchstens 60 s lang (Galaxy).
- Playnite beobachtet jeden Prozess, dessen Programm im Installationsordner liegt. Das Ende meldet es, wenn der ganze Prozessbaum weg ist (Playnite).
- StarCraft II und Heroes starten über „Switcher“-Programme (switcher: true). Deshalb braucht es eine kurze Karenzzeit (Arctium s2).
- Starts außerhalb des Launchers erkennt Galaxy an einem geänderten LastPlayed in Battle.net.config (plugin.py).
- Der Battle.net-Prozess taugt nicht als Lebenszeichen. Eine Client-Einstellung kann ihn beim Spielstart beenden (Lutris-Forum).

Für Nightforge passt das genau:

- Mac-Spiele werden schon über den Ordnerpräfix in ps erkannt (`Sources/Nightforge/LibraryModel.swift:169-177`

).
- Als Ende gilt „gone for three looks, ~6–9 s“ (`Sources/Nightforge/LibraryModel.swift:140-167`

).
- Eine Spielzeit speichert Battle.net in keiner bekannten Datei. Nightforge müsste sie selbst messen. Die Steam-Spielzeit stammt heute aus Steams localconfig.vdf (`Sources/Nightforge/Library.swift:454-486`

).

### Teil 2: Bibliothek – installiert lokal, besessen nur per Web-Login

#### Keine offizielle API kennt die besessenen Spiele

**Offizielle API:**

- Die dokumentierten OAuth-Scopes sind openid, wow.profile, sc2.profile und d3.profile (ueberauth_bnet). Einen Endpunkt für besessene Spiele gibt es nicht.
- Auf die Frage danach antwortete das Blizzard-API-Forum, nur die im Developer Portal gelisteten Endpunkte seien öffentlich; andere zu nutzen „might be against the ToS“ (Blizzard-Forum †).
- Die API braucht Client-ID und Secret. Zu Public Clients empfahlen Blizzard-Vertreter einen Server-Proxy (PKCE-Thread †). Das passt nicht zu Nightforges Regel „kein Account, keine Telemetrie“ (`docs/ROADMAP.md:34`

).
- Die einzige offizielle Besitz-Schnittstelle stellt Microsoft aufgrund der EU-Zusagen zur Übernahme von Activision Blizzard bereit, und nur für Cloud-Streaming-Anbieter im EWR (Xbox-FAQ; Microsoft Learn †).

**Was alle funktionierenden Open-Source-Bibliotheken tatsächlich nutzen:** die undokumentierten Endpunkte **`https://account.battle.net/api/games-and-subs`** und **`/api/classic-games`**.

- Login: Der Nutzer meldet sich in einer eingebetteten Web-Ansicht auf Blizzards eigener Login-Seite an. 2FA erledigt dabei Blizzards Seite selbst.
- Sitzung: Playnite speichert nur die Session-Cookies und frischt sie über /oauth2/authorization/account-settings auf (Playnite BattleNetAccountClient.cs).
- Antwort: gameAccounts[] mit titleId, `localizedGameName` und gameAccountStatus (GamesAndSubs.cs).

Dokumentierte Schwachstellen:

- 2021 bis 2023 mussten sich Nutzer alle paar Tage neu anmelden, teils nach weniger als einem Tag (Playnite #125).
- Partnerspiele wie Call of Duty fehlten 2020 in der Antwort (Galaxy #24).
- Neue Titel fehlten im Januar 2026, weil sie nicht in Playnites handgepflegter Tabelle standen (Playnite #510).

Für besessene, aber nicht installierte Spiele ist **keine lokale Datei** bekannt. Lokale Dateien liefern nur installierte Spiele.

| Projekt | Lizenz, Stand | Besessene Spiele | Installierte Spiele | Start | macOS |
|---|---|---|---|---|---|
| Playnite BattleNetLibrary | MIT; aktiv bis 2026, GitHub-Repo am 28.10.2026 archiviert, Umzug zu Codeberg ([Repo](https://github.com/JosefNemec/PlayniteExtensions), [Lizenz](https://github.com/JosefNemec/PlayniteExtensions/blob/master/LICENSE.md)) | Web-Ansicht mit Cookies, `games-and-subs` und `classic-games` | Windows-Registry, als Rückfall `product.db` (uid, Code, Pfad) ([BattleNetLibrary.cs](https://github.com/JosefNemec/PlayniteExtensions/blob/886468f65724e6fd104f3a09847a17ba57cfb430/source/Libraries/BattleNetLibrary/BattleNetLibrary.cs#L63-L150)) | `--exec` | nein |
| GOG-Galaxy-Plugin (bartok765, FriendsOfGalaxy) | MIT; letzter Commit 11/2021 ([Lizenz](https://github.com/bartok765/galaxy_blizzard_plugin/blob/master/LICENSE)) | OAuth mit **öffentlich im Code stehendem Client-Secret** plus Cookies, gibt sich als Firefox aus ([consts.py](https://github.com/bartok765/galaxy_blizzard_plugin/blob/master/src/consts.py), [http_client.py](https://github.com/bartok765/galaxy_blizzard_plugin/blob/master/src/http_client.py)) | `product.db` und `Battle.net.config` | `--exec` | **ja** |
| Lutris | GPL-3.0; aktiv 10/2026 | keine, nur ein statischer Katalog | `product.db` im Wine-Prefix | `--exec` nach 15 s | Linux/Wine ([battlenet.py](https://github.com/lutris/lutris/blob/master/lutris/services/battlenet.py)) |
| WowUp | GPL-3.0; aktiv 10/2026 | – | `product.db` samt Feldern 6 und 13 (nur WoW) | – | ja |
| bnetlauncher | GPL-3.0; Wartungsmodus ([Lizenz](https://github.com/dafzor/bnetlauncher/blob/master/license.txt)) | – | `product.db` | `--exec`, für PTR/Classic ein Klick | nein |
| Steam ROM Manager; NonSteamLaunchers | GPL-3.0; MIT | – | `product.db` (nur Windows) bzw. `Battle.net.config` (`Resumable`) ([SRM](https://github.com/SteamGridDB/steam-rom-manager/blob/master/src/lib/parsers/battle-net.parser.ts), [NSL](https://github.com/moraroy/NonSteamLaunchers-On-Steam-Deck/blob/main/NSLGameScanner.py)) | – | nein |
| Heroic | – | **kein Battle.net**; 2021 „not planned“, offene Anfrage von 2025 ([Heroic-Games-Launcher/HeroicGamesLauncher#347](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/347), [Heroic-Games-Launcher/HeroicGamesLauncher#4575](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/4575)) | – | – | – |
| Arctium bnet-tact-channel-configs | **keine Lizenzdatei**; Spiegel öffentlicher Blizzard-Daten | – | Binärpfade, Mac-Bundles, Startargumente | – | – |

**Lizenzen:** MIT- und GPL-3.0-Code ist mit Nightforges GPL-3.0 vereinbar, solange die MIT-Vermerke erhalten bleiben. Praktisch übernimmt Nightforge ohnehin nur Tabellen, das Schema und Abläufe, weil alles in C# oder Python vorliegt. Einen gepflegten Open-Source-Bibliotheksimport für den Mac gibt es nicht; Nightforge wäre der erste.

#### Vier Kennungen pro Spiel

Jedes Spiel hat vier Kennungen:

- Startcode für --exec: das sind die im Auftrag genannten Kürzel (Pro, WoW, Hero, S2, D3, Fen, OSI).
- Agent-uid in product.db und Battle.net.config.
- TACT-Code der Versionsserver.
- `titleId` der Kontoseite (Galaxy-README).

Ich habe Playnites Tabelle ausgewertet. In 30 von 33 Fällen ist die `titleId` der Startcode als Big-Endian-ASCII-Zahl, etwa 5272175 = „Pro“. Ausnahmen sind DRTL, WAR1 und W2BN. Playnites PNTA-Eintrag dupliziert vermutlich AUKS ([BattleNetGames.cs](https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/BattleNetLibrary/BattleNetGames.cs)).

| Spiel | Startcode | uid | TACT | titleId | Mac |
|---|---|---|---|---|---|
| World of Warcraft | WoW | wow | wow | 5730135 | ja |
| WoW Classic / Classic Era | keiner bestätigt | wow_classic / wow_classic_era | ebenso | keine eigene | ja |
| Hearthstone | WTCG | hs_beta | hsb | 1465140039 | ja |
| StarCraft II / Remastered | S2 / S1 | s2 / s1 | s2 / s1 | 21298 / 21297 | ja |
| Diablo III | D3 | diablo3 | d3 | 17459 | ja |
| Heroes of the Storm | Hero | heroes | hero | 1214607983 | ja |
| Warcraft III: Reforged | W3 | w3 | w3 | 22323 | ja |
| Overwatch | Pro | prometheus | pro | 5272175 | nein |
| Diablo IV | Fen (FEN bei Galaxy/Lutris) | fenris | fenris | 4613486 | nein |
| Diablo II: Resurrected | OSI | osi | osi (TACTLib: `osib`) | 5198665 | nein |
| Diablo Immortal / Warcraft Rumble | ANBS / GRY | anbs / gryphon | ebenso | 1095647827 / 4674137 | nein |
| Warcraft I/II Remastered | W1R / W2R | w1r / w2r | ebenso | 5714258 / 5714514 | nein |
| Call of Duty (HQ, ab MWII) | AUKS (Name in den Quellen uneinheitlich) | auks | auks | 1096108883 | nein |

Quellen: [Playnite](https://github.com/JosefNemec/PlayniteExtensions/blob/886468f65724e6fd104f3a09847a17ba57cfb430/source/Libraries/BattleNetLibrary/BattleNetGames.cs#L32-L446), [Galaxy definitions.py](https://github.com/bartok765/galaxy_blizzard_plugin/blob/83cfb024ebc00cbc71702f101671bea596cfc96f/src/definitions.py#L69-L111), [Lutris](https://github.com/lutris/lutris/blob/89cc4398a6064cd1bbf9bf4bed6820592b566c67/lutris/services/battlenet.py#L22-L68), [prefill TactProduct.cs](https://github.com/tpill90/battlenet-lancache-prefill/blob/master/BattleNetPrefill/TactProduct.cs). Ob Startcodes zwischen Groß- und Kleinschreibung unterscheiden, hat niemand geprüft.

#### Namen vom Server, Cover nur mit Kompromissen

**Namen:**

- Für besessene Spiele liefert localizedGameName den Namen, lokalisiert und aktuell. Nightforge kann unbekannte Titel damit anzeigen, statt sie wie Playnite zu verwerfen.
- Für installierte Spiele ohne Web-Login braucht es eine mitgelieferte Tabelle von product_code zu Name.

**Cover ohne API-Key gibt es nur mit Kompromissen:**

- Playnite verlinkt Blizzard-CDN-Bilder direkt, für Titel ab etwa 2022 aber gar keine (BattleNetMetadataProvider.cs).
- Lutris nimmt Cover vom eigenen Server lutris.net/games/cover/<slug>.jpg.
- NonSteamLaunchers nutzt undokumentierte SteamGridDB-Webendpunkte ohne Schlüssel und fällt auf Steams CDN zurück (NSL).
- Offizielle APIs brauchen Schlüssel: SteamGridDB einen API-Key, IGDB Client-ID und Secret (steamgriddb npm; igdb-atlas).
- Nightforge heute holt Artwork nur aus Steams Cache und CDN und hat keinerlei API-Keys (`Sources/Nightforge/Artwork.swift:22-24`

, `Sources/Nightforge/Artwork.swift:142-148`

).
- Markenrecht: Blizzards Markenrichtlinien erlauben Marken nur nicht-kommerziell und jederzeit widerruflich (Logo and Trademark Guidelines †).

**Ableitung:**

- Für Titel, die es auch auf Steam gibt, passt Steam-CDN-Art über eine feste Zuordnung.
- Für den Rest bieten sich eine selbst gepflegte, nachladbare URL-Liste und eine Textkachel als Rückfall an.
- Cover sollten nicht ins Repo gebündelt werden.

### Teil 3: Steam ersetzt Battle.net bei drei Windows-Titeln

| Titel | Auf Steam | Battle.net-App nötig? | Steam Deck | ProtonDB | Folge für Nightforge |
|---|---|---|---|---|---|
| **Overwatch** (ehemals OW2). **Datum der Umbenennung unsicher**: angekündigt am 4.2.2026 zum Saisonstart am 10.2. ([Wccftech](https://wccftech.com/were-dropping-the-2-overwatch-2-is-now-just-called-overwatch-moving-forward/), [PC Gamer](https://www.pcgamer.com/games/fps/overwatch-2-drops-the-2-and-goes-back-to-being-overwatch-as-blizzard-launches-its-biggest-update-ever-next-week-we-want-to-gain-players-confidence-we-want-them-to-have-trust-in-the-game) †); eine andere Notiz nennt den 10.2.2026 | ja, seit 10.8.2023, App 2357570 ([Neowin](https://www.neowin.net/news/blizzard-will-bring-some-of-its-games-to-steam-starting-with-overwatch-2-on-august-10/)) | nein, nur Kontoverknüpfung im Browser ([PCWorld](https://www.pcworld.com/article/2002088/); [Support 340609](https://support.blizzard.com/en/article/340609) †) | **widersprüchlich**: „Playable“ (Label von GamingOnLinux, [itemdb](https://www.gamingonlinux.com/itemdb/app/17974/) †; [TouchArcade](https://toucharcade.com/?p=312244)) gegen „weder Verified noch Playable“ ([TechRadar](https://www.techradar.com/gaming/overwatch-2-is-a-disaster-on-steam-deck)); offizielles Valve-Label unbestätigt | Platinum laut [SteamDeckHQ](https://steamdeckhq.com/game-reviews/steam-deck/overwatch-2-2/) (2023); 2026 Berichte über einen Bruch nach einem Update ([ProtonDB](https://www.protondb.com/app/2357570) †), unbestätigt | kostenlos, also Steam-Weg ohne Neukauf |
| **Diablo IV** | ja, seit 17.10.2023, App 2344520 ([Blizzard News](https://news.blizzard.com/de-de/article/24009153/diablo-iv-ist-ab-17-oktober-auf-steam-erhaeltlich) †) | nein (Nutzerberichte); Kontoverknüpfung nötig ([LevelUp](https://www.levelup.com/en/news/780534/Diablo-IV-you-will-need-Battlenet-to-play-on-PC-Game-Pass-how-to-link-your-accounts); [Steam-Community](https://steamcommunity.com/app/2344520/discussions/0/3874844033658917926)) | **Verified** ([Windows Central](https://www.windowscentral.com/gaming/its-official-diablo-4-will-be-steam-deck-verified)) | **widersprüchlich**: Gold, eine Listung vom Mai 2026 Platinum ([ProtonDB](https://www.protondb.com/app/2344520) †) | Battle.net-Besitzer müssen neu kaufen ([Xfire](https://www.xfire.com/do-you-need-buy-diablo-4-again-play-steam-2474)); Erweiterungen „once per platform“ ([RPG Site](https://www.rpgsite.net/news/19169-diablo-4-lord-of-hatred-expansion-dlc-editions-ultimate-deluxe-standard-preorder-price)) |
| **Diablo II: Resurrected** | ja, seit 11.2.2026 als „Infernal Edition“, App 2536520 ([PC Gamer](https://www.pcgamer.com/games/rpg/diablo-2-resurrected-is-now-on-steam-and-is-verified-for-steam-deck) †) | **widersprüchlich**: das Store-Kleingedruckte nennt laut einem Nutzer „Battle.net® desktop app required“, Steam- und Deck-Nutzer berichten nur von der Kontoverknüpfung ([Thread](https://steamcommunity.com/app/2536520/discussions/0/760680996704177868/), [Deck-Thread](https://steamcommunity.com/app/2536520/discussions/0/807972271756011319/)) | **Verified** ([GamingOnLinux](https://www.gamingonlinux.com/2026/02/diablo-ii-resurrected-infernal-edition-gets-released-on-steam-and-steam-deck-verified/) †) | nicht gefunden; laut GamingOnLinux „works just fine“ mit Proton 10 † | kein Gratis-Steam-Exemplar für Battle.net-Besitzer ([Technobezz](https://www.technobezz.com/news/diablo-2-resurrected-launches-on-steam-with-new-warlock-dlc)) |
| **Call of Duty** | ja: HQ App 1938090, BO7 App 3606480 ([SteamDB](https://steamdb.info/app/3606480) †) | kein Battle.net, aber ein Activision-Konto ([CoD-Store](https://www.callofduty.com/en/store/games/blackops7)); Steam-Käufe lassen sich nicht mit Battle.net verknüpfen ([Support 312419](https://us.support.blizzard.com/en/article/312419) †) | nicht Verified; für BO7 erwartet PCGamesN „Unsupported“, offiziell unbestätigt ([PCGamesN](https://www.pcgamesn.com/call-of-duty-black-ops-7/steam-deck)) | „Borked“ laut [Steam-Community](https://steamcommunity.com/app/1938090/discussions/0/5230393378263958980/) | rot, egal über welchen Store |
| **Warcraft III: Reforged** | nein; Battle.net, seit 26.6.2025 auch Game Pass PC ([warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/Warcraft_III:_Reforged)) | – | – | – | nativer Mac-Client (Teil 1) |

Weitere Punkte:

- StarCraft, Hearthstone und WoW: Für sie wurde kein Steam-Release gefunden. Das ist ein unsicherer Negativbefund, weil der Steam-Store gesperrt war.
- Kontoverknüpfung: Ein Battle.net-Konto lässt sich mit genau einem Steam-Konto verknüpfen (Support 000014014 †).
- Steam-Weg auf dem Mac: Er bedeutet Windows-Steam unter Wine, denn der Mac-Steam kann Windows-Titel nicht starten. Ob das Verknüpfungs-Popup im Spiel unter Wine funktioniert, ist ungeprüft. Nightforge hat diesen Weg schon (`Sources/Nightforge/Launcher.swift:303-373`

).

**Bei Overwatch sperrt Nightforge sich selbst aus (Ableitung aus dem Code, selbst nachgeprüft):**

1. Die Profil-Pipeline wertet den AreWeAntiCheatYet-Status „Supported“ als „online gesperrt“. Sie nimmt an, das Anti-Cheat laufe dann nur dank eines Linux-Builds (`scripts/build-profiles.py:58-61`

).
2. Deshalb steht „Overwatch 2“ mit antiCheatOnline: ["Warden"] und GeForce-NOW-Link in den Profilen (`profiles/profiles.json:4317-4324`

).
3. markAntiCheat sperrt reine Online-Spiele (`Sources/Nightforge/Library.swift:88`

, `Sources/Nightforge/Library.swift:289-301`

).
4. Der Play-Knopf öffnet dann GeForce NOW (`Sources/Nightforge/LibraryModel.swift:454-498`

).

Teil 4 zeigt, dass die Annahme für Overwatch nicht zutrifft. Der billigste Gewinn bei den Windows-Titeln ist deshalb eine **Korrektur der eigenen Daten**, nicht Battle.net unter Wine.

### Teil 4: Anti-Cheat – Blizzard-Titel laufen, Call of Duty nie

**Blizzard-eigene Titel:**

- Overwatch nutzt Blizzards „Defense Matrix“, ein Bündel aus Anti-Cheat, SMS Protect und einer Task-Force (Blizzard †).
- 2022 entschied sich das Team ausdrücklich gegen Kernel-Anti-Cheat (Forbes).
- Der Anti-Cheat-Tracker von GamingOnLinux führt Overwatch als „Works“ (Stand 11.2.2026) (GamingOnLinux †).
- Für Diablo IV und D2R ist das Anti-Cheat nicht öffentlich dokumentiert; Warden ist nur eine Annahme.
- Bis November 2026 wurde für Blizzard-eigene Titel kein Hinweis auf eine TPM- oder Secure-Boot-Pflicht gefunden.

**Call of Duty:**

- RICOCHET ist ein Windows-Kernel-Treiber.
- Ab Black Ops 7 sind ausdrücklich TPM 2.0 und Secure Boot Pflicht; ohne sie „won’t be able to play“ (Blizzard News †; TechRadar).
- GamingOnLinux führt BO6, BO7, MW 2019, MWIII und Warzone als „Broken“ (RICOCHET-Tracker †).
- Unter Proton startet BO7 nicht einmal bis ins Menü (Techlomedia).

**Damit ist bestätigt, dass Call of Duty blockiert ist.** Es lauffähig zu machen, hieße TPM oder Secure Boot vorzutäuschen, also Anti-Cheat zu umgehen.

**Offizielle Linie und Praxis:**

- Blizzard sagt „nicht unterstützt“: Die Spiele seien „not intended to work on Linux“, es gebe „no plans“ für Linux-Kompatibilität (Support 11571 †).
- Trotzdem behob Blizzard wiederholt Linux-Fehler, zuletzt Abstürze von Overwatch im Dezember 2025 (GamingOnLinux †) und von Diablo IV im Juli 2026 (GamingOnLinux †).

**Banns, gemischtes Bild:**

- Overwatch 2018 und 2021: Linux-Nutzer unter Wine/DXVK wurden in Wellen gebannt. Beide Male wurden die Banns zurückgenommen, 2021 laut Nutzerberichten (PCGamesN; Slashdot/Phoronix; Dexerto; Reddit-Spiegel).
- Diablo III 2012, widersprüchlich: Cinemablend meldete Dauer-Banns für Linux-Nutzer (Cinemablend). Ein Blizzard-Sprecher sagte dagegen, Linux und Wine „will not result in being banned, but cheating will“, und man habe keinen Fall gefunden, der allein auf Linux oder Wine beruhte (Tom’s Hardware †).
- Diablo IV und Mac-CrossOver-Nutzer: keine Bannwelle, nur einzelne, unbelegte Forenberichte (Blizzard-Forum †).

| Titel | Status auf Apple Silicon | Leistung (Nutzer- und Entwicklerangaben) |
|---|---|---|
| Overwatch | CodeWeavers: Mac „Runs Well“, getestet mit CrossOver 26.3.0 ([DB](https://www.codeweavers.com/compatibility/crossover/overwatch-2)); AppleGamingWiki: „Perfect“ ([Wiki](https://www.applegamingwiki.com/wiki/Overwatch_2)) | M1 Pro, 1080p Low: CrossOver mit D3DMetal 58,4 fps (1 % Low 7,4), Recall mit DXMT 99,6 fps (1 % Low 36,0), Eigenmessung des Autors ([Recall](https://github.com/AsherJN/recall)); Hauptproblem ist Ruckeln beim Shader-Kompilieren ([stutter-fix](https://github.com/tholtman1-del/overwatch-mac-stutter-fix)) |
| Diablo IV | AppleGamingWiki: „Perfect“ ([Wiki](https://www.applegamingwiki.com/wiki/Diablo_IV)) | Mac mini M4: 44 fps bei 1080p High; M4 Max: 60 fps bei 1080p High ([macgamingdb](https://macgamingdb.app/games/diablo-iv)) |
| D2R | laut CodeWeavers unterstützt mit CrossOver 23.5 und Sonoma ([CodeWeavers](https://www.codeweavers.com/unleash/diablo-ii-resurrected-on-mac)) | keine aktuellen Daten |

**Ausfall im Frühjahr 2026:** Alle drei Titel liefen von etwa März bis Mai 2026 wegen eines Rosetta-2-Deadlocks nicht mehr, beginnend mit Diablo IV Season 12 ([D4-Forum](https://us.forums.blizzard.com/en/d4/t/diablo-iv-invisibleno-game-window-after-season-12-update-macos-via-crossover/242939) †; [Apple Developer Forums](https://developer.apple.com/forums/thread/814383)). Die Lösung braucht beides: „Wine changes in CrossOver 26.1 in addition to Rosetta changes in macOS 26.5“ ([CodeWeavers-Blog](https://www.codeweavers.com/blog/mjohnson/2026/5/18/finally-diablo-iv-and-overwatch-are-playable-with-crossover-261-macos-265)).

**Strukturelle Risiken:**

- Whisky wird seit April 2025 nicht mehr entwickelt (MacRumors).
- CrossOver 27 setzt für x86-Windows-Programme auf FEX statt Rosetta; das finale Release ist für Anfang 2027 geplant (CodeWeavers-Blog).
- Nightforges eigener Stack basiert auf winecx 4.7.3 mit D3DMetal und richtet Rosetta selbst ein (`components/sources.json:3-80`

, README.md:24). Ob er die Wine-Korrektur aus CrossOver 26.1 enthält, ist offen.

### Teil 5: Recht – kein Verbot gefunden, aber weite Klauseln

Maßgeblich ist der Blizzard-EULA, Stand „LAST REVISED March 21, 2024“; eine neuere Fassung wurde nicht gefunden ([EULA](https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement) †). Abschnitt 1.C verbietet unter anderem:

- Reverse Engineering und Modifikation (EULA en-gb †)
- „Data Mining“, also jeden „unauthorized process or software that intercepts, collects, reads, or ‚mines‘ information generated or stored by the Platform“
- Verbindungen „using third-party programs or tools not expressly authorized by Blizzard“ (EULA †)

Ein Verbot, Battle.net unter Wine oder CrossOver zu betreiben, steht in den gefundenen Passagen nicht. Eine Blizzard-Aussage zu Launchern von Drittanbietern wurde weder als Erlaubnis noch als Verbot gefunden.

**Wogegen Blizzard dokumentiert vorgegangen ist:**

- Server-Emulation (bnetd) (Wikipedia bnetd)
- Bots (Glider) (MDY v. Blizzard)
- Apps, die Spieldaten während des Spiels auslesen (Visor und Pursuit, 2018) (Engadget)
- kommerzielles Streaming ohne Vertrag (GeForce NOW, 2020) (Windows Central)

Microsofts eigene Xbox-PC-App zeigt seit September 2025 installierte Battle.net-Spiele in einer gemeinsamen Bibliothek und startet sie ([Xbox Wire](https://news.xbox.com/en-us/2025/09/15/access-gaming-library-xbox-on-windows-pc-and-handheld/)). Das ist keine Erlaubnis für Dritte. Es zeigt aber, dass der Eigentümer das Zusammenführen von Bibliotheken für legitim hält.

| Nightforge-Aktion | Einschlägige Klausel | Vorbilder ohne bekannte Folgen | Ampel | Absicherung |
|---|---|---|---|---|
| `product.db` / `Battle.net.config` lesen | „Data Mining … reads … stored by the Platform“; wörtlich angreifbar | Lutris, Galaxy-Plugin, Playnite, WowUp | **Grün/Gelb** | nur lesen, nie schreiben, nichts hochladen, keine Prozesse oder Speicher anfassen |
| Start über die offizielle App mit `--exec` | keine direkte | Playnite, Lutris, bnetlauncher; Xbox-App | **Grün** | keine Parameter manipulieren; Rückfall „Battle.net öffnen“ |
| Besessene Spiele über die Kontoseite | „not expressly authorized“-Verbindungen; undokumentierter Endpunkt, laut Forenantwort möglicherweise gegen die ToS † | Playnite, Galaxy-Plugin | **Gelb** | Opt-in; Login nur auf Blizzards Seite; sich nicht als Browser ausgeben (anders als Galaxy); sparsame Abrufe; „Abmelden“ löscht alle Cookies |
| Windows-Battle.net unter Wine | kein Verbot, nur „nicht unterstützt“ | CrossOver wirbt offen mit Diablo IV ([CodeWeavers](https://www.codeweavers.com/unleash/diablo-iv-on-mac)) | **Grün/Gelb** | unveränderte App; Risikohinweis mit Link auf Support 11571 |
| Cover und Namen | Marken nur nicht-kommerziell, widerruflich † | Playnite, Lutris | **Gelb** | Namen nur als Bezeichnung; keine Blizzard-Logos im Branding; nicht bündeln; Hinweis „not affiliated“ wie `README.md:142` |

**Developer-API:** Sie brächte zusätzliche Pflichten mit sich, etwa eine Cache-Lebensdauer von höchstens 30 Tagen und keine Monetarisierung ([API Terms](https://www.blizzard.com/en-us/legal/a2989b50-5f16-43b1-abec-2ae17cc09dd6/blizzard-developer-api-terms-of-use) †). Für Nightforge entfällt sie, weil sie keine Besitzliste liefert.

**Ableitung zum EU-Recht:** Das EU-Interoperabilitätsrecht (Art. 6 RL 2009/24/EG) betrifft Dekompilierung. Nightforge dekompiliert nichts und übernimmt das Format aus Open-Source-Parsern. Eine Prüfung nach deutschem oder EU-AGB-Recht fehlt.

### Vorschlag: der Battle.net-Store in Nightforge

#### Architektur: zweiter `StoreProvider`, Muster „Client fernsteuern“

Was ein `StoreProvider` abdecken müsste, liegt bei Steam heute als statische Funktionen verstreut:

- Setup und Login-Status
- Bibliotheks-Scan und Download
- Start mit Bestätigung, Lauf- und Ende-Erkennung
- Artwork
- Lebenszyklus des Clients

(`Sources/Nightforge/Engine.swift:160-174`

, `Sources/Nightforge/Library.swift:97-99`

, `Sources/Nightforge/Launcher.swift:212-301`

)

**Neue Dateien:** Battle.net setzt dieselbe Liste in eigenen Dateien um, etwa `BattleNet.swift`, `BattleNetSetup.swift` und `ProductDB.swift`, nach dem Vorbild von `MacSteam.swift` und `MacSteamSetup.swift` (`Sources/Nightforge/MacSteamSetup.swift:1-40`

). Sie gehören nicht in `Engine.swift` und `LibraryModel.swift`, die schon über 1000 Zeilen lang sind (`docs/TODO.md:195-198`

).

**Wiederverwendbar:**

- die Versionswahl Mac/Windows (`Sources/Nightforge/MacVersion.swift:18-66`

)
- AntiCheatBlock mit GeForce-NOW-Link (`Sources/Nightforge/Profiles.swift:105-126`

)
- die Mac-Prozesserkennung über den Ordnerpräfix (`Sources/Nightforge/LibraryModel.swift:169-177`

)

**Anzupassen:**

1. Profilformat: Profile mit Schlüsseln wie bnet:<product_code> würden ältere Versionen still überspringen (`Sources/Nightforge/Profiles.swift:216`

). Das Format bleibt also abwärtskompatibel.
2. Profil-Pipeline: Sie übernimmt heute nur Steam-IDs von AreWeAntiCheatYet und nur appStore == "STEAM" von GeForce NOW (`scripts/build-profiles.py:197`

, `scripts/build-profiles.py:214`

).
3. Fester Steam-Pfad: \steamapps\common\ steht viermal fest im Code (`Sources/Nightforge/LibraryModel.swift:169-177`

, `Sources/Nightforge/Engine.swift:200-203`

, `Sources/Nightforge/Engine.swift:532-536`

, `Sources/Nightforge/SteamPriority.swift`

).
4. GameAnalysis: Battle.net als bekannter Fremd-Launcher (`Sources/Nightforge/GameAnalysis.swift:130-137`

).

**Tests:** nach dem Muster `tests/BattleNetTest/` mit `run.sh`. Abzudecken sind der Parser für `product.db`, die Abbildung von Code auf Name und Startcode und die Pfadzuordnung, jeweils mit Fixture-Dateien (`docs/ROADMAP.md:36`

).

#### Erster Start: Battle.net wird gefunden, nicht eingerichtet

| Schritt | Was passiert | Begründung / Beleg |
|---|---|---|
| 1 | Nightforge prüft beim Start lokal und ohne Netz, ob `/Applications/Battle.net.app`

 und `/Users/Shared/Battle.net/Agent/product.db`

 vorhanden sind | „Offline zuerst“ (`docs/ROADMAP.md:34-35`

); lokal lesen gibt keine Daten nach außen |
| 2a | Ist Battle.net vorhanden, erscheint in der Bibliothek „Battle.net: N Mac-Spiele installiert“, ganz ohne Einstellung | Galaxy-Muster „`bna` in products“ ([parsers.py](https://github.com/bartok765/galaxy_blizzard_plugin/blob/83cfb024ebc00cbc71702f101671bea596cfc96f/src/parsers.py#L52-L94)) |
| 2b | Fehlt Battle.net, gibt es einen Knopf „Battle.net hinzufügen“: am Ende des Onboardings neben „Also add Epic Games or GOG“ und im Tab „Stores“. Er installiert die offizielle Mac-App wie `MacSteamSetup` (Download, Signaturprüfung, Kopie nach `/Applications`) | `docs/ROADMAP.md:261`

, `docs/ROADMAP.md:147-150`

, `Sources/Nightforge/MacSteam.swift:95-130`

; Installer-URL und Blizzards Team-ID sind **nicht recherchiert** |
| 3 | Die Anmeldung findet im Battle.net-Fenster statt, mit dem Hinweis „Melde dich in Battle.net an – Nightforge sieht deine Anmeldung nie“ | wie bei Steam (`Sources/Nightforge/SetupView.swift:42`

) |
| 4 | Optional und nur nach ausdrücklicher Zustimmung: „Auch nicht installierte Spiele zeigen?“ öffnet Blizzards Login-Seite in einer Web-Ansicht; danach liest Nightforge `games-and-subs`. Läuft die Sitzung ab, bleiben die installierten Spiele sichtbar, ein Banner bietet „Neu anmelden“ an | Opt-in-Regel (`docs/ROADMAP.md:34`

); Sync-Banner (`docs/ROADMAP.md:278-279`

); Playnite [JosefNemec/PlayniteExtensions#125](https://github.com/JosefNemec/PlayniteExtensions/issues/125) |
| 5 | Die Übersicht am Ende: „X laufen nativ · Y über deinen Steam · Z brauchen Windows · CoD läuft nicht auf dem Mac“ | Roadmap 6.1 (`docs/ROADMAP.md:257-264`

) |

**Ableitung zu Schritt 4:** Die Login-Seite läuft in Nightforges Prozess. Das README-Versprechen „Nightforge never sees your login“ (`README.md:24`) gilt dort nur, wenn Nightforge nachweislich nichts aus der Seite liest. Das sollte im Text offen benannt werden.

#### Was die Bibliothek zeigt

| Zustand | Quelle | Karte | Aktion |
|---|---|---|---|
| Mac-Version installiert | `product.db`: `installed‖playable`, Ordner existiert | Mac-Badge, „nativ“ oder „Rosetta“ je nach Binary | **Spielen** |
| Update nötig oder läuft | `playable=false`, `active_operation=OP_UPDATE`, `update_progress` | „Battle.net aktualisiert … 42 %“ | Battle.net zeigen (Zuordnung eigene Ableitung) |
| WoW-Varianten | ein `product.db`-Eintrag je Variante, Unterordner aus Feld 13 | eigene Karte je Variante | Retail: Spielen; Classic: Spielen über den Launcher-Weg (ungeprüft), sonst Battle.net öffnen |
| Besessen, nicht installiert (Opt-in) | `games-and-subs` | Name aus `localizedGameName` | **Installieren** öffnet Battle.net mit `--game=<uid>`; den Download macht Battle.net |
| Windows-only, auch auf Steam besessen | Steam-Bibliothek | eine Karte für beide Stores, „Start through Steam“ | Steam-Weg (Roadmap 7.4, `docs/ROADMAP.md:273-276`

) |
| Windows-only, nur Battle.net | `games-and-subs` bzw. `product.db` im Battle.net-Prefix | „Windows-Version“ mit Risikohinweis | vor Etappe 6: „Kommt später“ bzw. GeForce NOW; danach Spielen (Windows) |
| Call of Duty (RICOCHET) | Profil `antiCheat` | „Läuft nicht auf dem Mac – Anti-Cheat“ | GeForce NOW, das Battle.net seit 29.2.2024 anbietet ([Thurrott](https://www.thurrott.com/games/298571/nvidia-geforce-now-adds-battle-net-integration)) |

#### Klick auf „Spielen“ bei Mac-Versionen

| # | Ablauf | Beleg / Baustein |
|---|---|---|
| 1 | `product.db` neu lesen; ist das Spiel nicht spielbar, „Battle.net aktualisiert“ anzeigen statt zu starten | Galaxy, proto |
| 2 | Läuft Battle.net nicht, versteckt starten; bei aktivem Battle.net-Store schon beim Start von Nightforge im Hintergrund, so wie Steam (`Sources/Nightforge/LibraryModel.swift:403-451`

) | sonst verletzen 5–15 s Wartezeit das Ziel „< 10 s bis das Spiel läuft“ (`docs/ROADMAP.md:37`

) |
| 3 | Warten, bis Battle.net bereit ist (Fenster „Blizzard Battle.net“ oder Prozesszahl, höchstens 60 s). Fehlt die Anmeldung, Battle.net nach vorn holen; nur bei einer echten Rückfrage zeigen, wie bei Steam (`Sources/Nightforge/LibraryModel.swift:1212-1304`

) | Galaxy, Playnite |
| 4 | `/Applications/Battle.net.app/Contents/MacOS/Battle.net --exec="launch <Code>"` als Prozess aufrufen; WoW Classic über `open "<install_path>/World of Warcraft Launcher.app" --args productcode=<code>` (ungeprüft) | Galaxy |
| 5 | Start bestätigen: ein Prozess unter `install_path` innerhalb von 60 s, sonst Battle.net zeigen und erklären | Galaxy 60 s |
| 6 | Lauf und Ende über die vorhandene Abfrage alle 3 bzw. 10 s; das Ende nach „three looks“ deckt die Switcher von SC2 und Heroes ab; dann kommt Nightforge nach vorn und misst die Spielzeit selbst | `Sources/Nightforge/LibraryModel.swift:105-167`

 |
| 7 | Battle.net beenden, wenn Nightforge endet und kein Spiel läuft (`osascript … quit app "Battle.net"`) | Galaxy; analog `README.md:33` |

#### Klick auf „Spielen“ bei Windows-Versionen

| # | Ablauf | Beleg / Baustein |
|---|---|---|
| 1 | Weg wählen: Gibt es eine Steam-Kopie, startet sie über Windows-Steam (`-applaunch`); Battle.net bleibt unbeteiligt | `Sources/Nightforge/Launcher.swift:303-373`

; Teil 3 |
| 2 | Prüfen über das Profil `bnet:<code>`: CoD wird gesperrt. Für OW, D4 und D2R erscheint einmal der Hinweis „nicht von Blizzard unterstützt; frühere Fehlbanns wurden zurückgenommen, Garantie gibt es keine“. Unter macOS < 26.5 kommt ein Hinweis auf den Deadlock | Teil 4 |
| 3 | Windows-Battle.net in einem **eigenen Prefix**, weil `stopAll` alle Prozesse des gemeinsamen Prefix beendet (`Sources/Nightforge/Engine.swift:244-253`

). Den Installer vom Hersteller laden, nicht weiterverteilen, wie `SteamSetup.exe` (`Sources/Nightforge/Engine.swift:36`

). Login im Battle.net-Fenster | ob der Client unter winecx läuft, ist ungetestet (`docs/TODO.md:106-107`

); Schalter für eine stille Installation unbekannt |
| 4 | Bibliothek aus `<prefix>/drive_c/ProgramData/Battle.net/Agent/product.db`; Windows-Pfade auf `drive_c` abbilden | Lutris; [WowUp linux](https://github.com/WowUp/WowUp/blob/d57478f3e56e5ab79dc9294bb205ba67498c3e4a/wowup-electron/app/services/warcraft/warcraft-platform.linux.ts#L136) |
| 5 | Client bereit machen (Lutris: 15 s), dann `Battle.net.exe --exec="launch Fen"` über Wine | Lutris |
| 6 | Grafik wie bisher aus den Spieldateien: D4 (DX12) mit D3DMetal, für OW DXMT testen. Die D3DMetal-Variablen setzt Nightforge heute nur über Steams Startumgebung; das muss für Battle.net neu gelöst werden | `README.md:98`, `Sources/Nightforge/Engine.swift:120-134`

; Recall-Messung |
| 7 | Lauf und Ende: `ps`-Muster aus `install_path` statt `\steamapps\common\`; danach Battle.net und wineserver nur im Battle.net-Prefix stoppen | Architektur oben |

### Stolpersteine und offene Fragen

| Stolperstein | Wirkung | Gegenmaßnahme |
|---|---|---|
| Battle.net-App und Agent sind Intel-only, Rosetta gibt es allgemein nur bis macOS 27 | ab macOS 28 droht der Ausfall aller Mac-Spiele über Battle.net (Ableitung) | früh beobachten; der Direktstart ist kein Ausweg (Anmeldung, Updates) |
| `--exec` auf dem heutigen Mac-Client ist unbelegt | die Kernfunktion könnte nur den Tab öffnen | zuerst ein Probe-Tool wie `tests/CatalogProbe` auf einem echten Mac |
| Ein frisch gestarteter Client braucht 5–15 s | verletzt das Ziel < 10 s | Hintergrundstart bei aktivem Store |
| WoW-Classic-Varianten haben keinen Startcode | Start nur halb automatisch | Launcher-Weg testen, sonst ehrlich „in Battle.net Version wählen“ |
| Web-Sitzungen laufen nach Tagen oder Stunden ab | besessene Spiele verschwinden | nur zusätzlich zu `product.db`; Banner statt stillem Verschwinden |
| Handgepflegte Codetabellen veralten | neue Titel fehlen | `localizedGameName` anzeigen, FourCC als Startcode-Vermutung, Tabelle über die Profil-Pipeline nachladen |
| Overwatch ist in den eigenen Profilen online gesperrt | Steam-Overwatch landet bei GeForce NOW | Abbildung von „Supported“ für Warden/Defense Matrix prüfen, mit Risikohinweis freigeben |
| Gemeinsamer Wine-Prefix, `\steamapps\common\` fest im Code | Battle.net-Spiele würden beendet oder nicht erkannt | eigener Prefix, Pfadmuster vom Store liefern lassen |
| Abhängigkeit von macOS 26.5 plus Wine-Korrektur | Windows-Titel brechen nach Spiel-Patches | Kompatibilitätsmatrix, Mindestversionen |
| Battle.net speichert keine Spielzeit | keine „zuletzt gespielt“-Daten von Blizzard | selbst messen, `LastPlayed` als Signal |

**Offene Fragen**, nur durch Tests oder freigegebene Hosts zu klären:

- Mac-Client:
  - Gilt der Binärpfad `/Applications/Battle.net.app/Contents/MacOS/Battle.net`

 noch, und nimmt er --exec an?
  - Ist battlenet:// auf macOS registriert?
  - Woran erkennt Nightforge auf dem Mac sicher, dass jemand angemeldet ist? (Kandidat: Hauptfenster, wie bei Galaxy)
  - Liegt Battle.net.config 2026 noch am selben Ort und im selben Format?
  - Sind Hearthstone und WoW Classic arm64?
  - Aktualisiert der Agent Spiele, wenn die App geschlossen ist?

- Windows-Client:
  - Läuft er unter winecx 4.7.3?
  - Gibt es Schalter für eine stille Installation?

- Bibliothek:
  - Braucht D2R auf Steam die Battle.net-App?
  - Liefert games-and-subs Partner- und Game-Pass-Titel?

- Zukunft und Recht:
  - Fällt Battle.net ab macOS 28 unter Apples Ausnahme für Spiele?
  - Was sagt der aktuelle EULA-Volltext genau?

### Empfohlene Reihenfolge

| Etappe | Inhalt | Voraussetzung | Ampel |
|---|---|---|---|
| 0 | Probe auf einem echten Mac: `product.db` lesen, `--exec`, Fenster und Login, `lipo` | – | Grün |
| 1 | Roadmap **0.2** `GameID { provider, id }` samt Migration der Int-Schlüssel | – | Grün |
| 2 | Roadmap **7.1** `StoreProvider`, Steam als erste Umsetzung | 0.2 | Grün |
| 3 | **Battle.net-Mac**: installierte Spiele, Start, Ende, Hintergrundstart; Tests mit Fixtures | 7.1, Probe | Grün/Gelb |
| 4 | Daten: Profilschlüssel `bnet:`, CoD sperren, GeForce NOW für Battle.net, Overwatch-Abbildung korrigieren, Battle.net in `GameAnalysis` | 3 | Grün |
| 5 | Besessene Spiele per Opt-in-Web-Login; Cover-Strategie | 3 | Gelb |
| 6 | Windows-Titel: zuerst Steam-Kopien zusammenführen (7.4), danach Windows-Battle.net im eigenen Prefix | 4; Windows-Client getestet | Gelb |
| – | Call of Duty | nie, nur GeForce NOW | Rot |

Etappe 3 vor Epic und GOG (7.2/7.3) zu setzen ist eine Einschätzung.

- Dafür: Battle.net-Mac ist kleiner, weil kein eigener Downloader nötig ist, und es erprobt StoreProvider am Muster „Client fernsteuern“.
- Dagegen: das Rosetta-Risiko der Battle.net-App.

### Fazit

Bei den Windows-Titeln bringt Battle.net unter Wine am wenigsten. Am meisten bringt der vorhandene Steam-Weg zusammen mit einer Korrektur der eigenen Anti-Cheat-Daten. Overwatch ist kostenlos auf Steam und läuft laut CodeWeavers auf dem Mac unter CrossOver, wird aber von Nightforges eigenen Profildaten derzeit gesperrt.

Battle.net als eigener Store lohnt sich zuerst für die Mac-Versionen. Dort fällt jede Anti-Cheat-Frage weg, und Nightforge kann seine Prozess- und Ende-Logik fast unverändert übernehmen.

Der eigentliche Engpass liegt nicht in Nightforge, sondern in zwei Abhängigkeiten von Blizzard:

- Die Startschnittstelle --exec ist undokumentiert und auf dem heutigen Mac-Client unbestätigt.
- Ob die Battle.net-App für den Mac ab macOS 28 überhaupt noch startet, hängt davon ab, ob Blizzard rechtzeitig eine arm64-Version liefert.

Für die Planung entscheidet ein kurzer Test auf einem echten Mac mehr als jede weitere Recherche. Bestätigt er `--exec` und die Login-Erkennung, ist Battle.net-Mac der kleinste und sauberste Kandidat, um das noch fehlende `StoreProvider`-Protokoll an einem zweiten Store zu prüfen. Scheitert er, bleibt ein ehrlicher Rückfall mit „in Battle.net öffnen“, und dann wäre die Arbeit an Epic und GOG zuerst die bessere Wahl.
