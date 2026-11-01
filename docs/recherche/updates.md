<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHV3kAL8mReFqLcYnvX (1.11.2026) -->

## Hintergrund-Updates für Nightforge: Recherchebericht

Ich habe nur gelesen und gesucht. Am Nightforge-Repo ist nichts geändert, es gab keine Commits, Pushes oder PRs und keine Anmeldung an einem echten Konto. Fremde Quellen habe ich nur in den Scratchpad geklont.

### Kurzfassung

1. Die Verzögerung erklärt sich sehr wahrscheinlich so: Seit der Steam-Beta vom Dezember 2024 hat AutoUpdateBehavior vier Werte.
  - 0 heißt heute „Use global setting“. Die globale Vorgabe ist „Let Steam decide when to update“ (Wert 3). Nightforge schreibt 0 und landet damit genau im Zeitplan.
  - 2 heißt „Immediately download updates“.
  - Die Werte stehen in Valves eigenem Client-Code. Ob der Manifest-Wert genau so gelesen wird, muss ein Test bestätigen (T1/T2).

2. So plant Steam: Spiele, die in den letzten 72 h gespielt wurden, lädt es sofort. Alle anderen lädt es „morgens“ um etwa 4 Uhr Ortszeit (±3 h), verteilt über bis zu 14 Tage. „Update delayed for 12165 secs“ ist der Countdown bis zu diesem Termin.
3. Es gibt keinen offiziellen „Jetzt aktualisieren“-Befehl von außen.
  - Untauglich sind die steam://-URLs, die Client-Konsole und -applaunch mit sofortigem Abbruch.
  - Steams eigene Buttons rufen intern SteamClient.Downloads.ResumeAppUpdate auf. Das erreicht man nur über den CEF-Debug-Port. Der hat keine Anmeldung, also kann jedes lokale Programm den angemeldeten Client fernsteuern. Rot.

4. Empfehlung Steam (Wine): Im eigenen Prefix alle Spiele auf AutoUpdateBehavior 2 setzen, bei beendetem Steam. Nightforge steuert das „Wann“ darüber, ob Steam läuft. Während eines Spiels pausiert Steam die Downloads selbst. Gelb, nach den Tests T1–T5 grün.
5. Steam für Mac: gleiches Prinzip. Es darf aber nur abwechselnd mit dem Wine-Steam laufen, weil sich die beiden gegenseitig abmelden („Session Replaced“, schon in `docs/TODO.md:58`

 beobachtet). Gelb.
6. Epic (legendary): grün. Update-Check, Update ohne Start, Fortsetzen und Platzprüfung sind eingebaut. Achtung: -y ohne --skip-dlcs installiert nach dem Update alle DLCs.
7. GOG (gogdl): grün, mit eigener Buchführung. gogdl führt keine Liste installierter Spiele. Nightforge muss buildId und ETag selbst speichern, so wie Heroic.
8. macOS: Downloads im Ruhezustand sind für Drittanbieter nicht möglich. Machbar ist „Nightforge offen, am Netzteil, Bildschirm darf aus“. Das entspricht den „Display-Off Low Power Downloads“ des Steam Deck.

### Wie belastbar die Belege sind

- Gesperrte Seiten: steampowered.com, steamcommunity.com, developer.valvesoftware.com, partner.steamgames.com, steamdb.info, playstation.com, xbox.com, nintendo.com, support.gog.com, epicgames.com und support.apple.com waren aus dieser Sitzung nicht erreichbar. Aussagen von dort kenne ich nur aus Zusammenfassungen von Suchmaschinen; sie sind mit (Suchzitat) markiert.
- Direkt gelesen: GitHub und developer.apple.com.
- Wichtigste Steam-Quelle: Valves eigener Client-Inhalt (UI-JavaScript, Übersetzungen, Strings aus steamclient.so), gespiegelt in SteamDatabase/SteamTracking @ 6b238f0 vom 31.10.2026. Die zentralen Stellen habe ich selbst nachgeprüft.
- Markierungen:
  - [offiziell]: Valve, Apple oder der Konsolenhersteller selbst
  - [Client]: Valve-Client-Code, nicht dokumentiert
  - [Code]: Quellcode von Fremdprojekten, selbst gelesen
  - [Forum/Presse]: Foren oder Berichte
  - [Schluss]: meine Folgerung

---

### 1. Steam für Windows im eigenen Wine-Prefix

#### 1.1 Warum Steam wartet

- [offiziell, über Presse] Valve, 30.03.2020: „Only games played within the last 3 days will be updated immediately.“ Die anderen werden „for the next off-peak local time period“ eingeplant und „over several more days“ verteilt. Wer ein Spiel starten will, bekommt das Update sofort. Quellen: PC Gamer, Engadget.
- [Client] Die Planer-Einstellungen mit Valves Hilfetexten stehen in steamclient.txt L21190–21194, zum Beispiel „If the user hasn’t played this game in a while, pick a morning up to this many days out to update.“
- Standardwerte laut SteamCMD-Commands-List L368–372:
  - TargetHour = 4
  - TimeSpreadMinutes = 360, also ±3 h
  - RecentlyPlayedThresholdHours = 72
  - NotPlayedTimeSpreadDays = 14

- Vom Server vorgegebene Werte (Mitschnitt Oktober 2024, App 7): ebenfalls 72 h und 4 Uhr, siehe stmsrv 7.vdf L31–52.
- Log-Zeilen:
  - (Update delayed for %d secs) (L135)
  - AppID %u scheduler update : %s, not played for %u seconds, update disabled for %u seconds (L12415)

- Nebenbefund: bDelayGameUpdatesOnBeta = 0 („If not, they’ll all be ASAP“). Im Steam-Beta-Client gibt es also womöglich gar keine Planung. Ich empfehle das nicht: Der Server kann den Wert ändern, und der Beta-Client wäre im Prefix ein zusätzliches Risiko.

#### 1.2 `AutoUpdateBehavior` heute

| Wert | Anzeige im aktuellen Client | Bedeutung |
|---|---|---|
| 0 | „Use global setting“ | Global gibt es nur „Let Steam decide when to update“ (= 3, Standard) oder „Only update at game launch“ (= 1) |
| 1 | „Wait until I launch the game“ | Update nur beim Start |
| **2** | **„Immediately download updates“**, Untertitel „Prioritize this game before other downloads“ | sofort, vor anderen Downloads |
| 3 | „Let Steam decide when to update“, Untertitel „Considers factors like when you last played the game, etc.“ | Zeitplan |

- Belege [Client]:
  - Enum 0–3: sp.js L94789–94792
  - Spiel-Dropdown, das SteamClient.Apps.SetAppAutoUpdateBehavior(appid, wert) aufruft: L646780–646864
  - Globale Auswahl, nur 3 oder 1: L683385–683410
  - Texte: steamui_english.json L1873–1882 und L2289–2297
  - Eingeführt mit der Beta vom 11.12.2024 (Suchzitat): GamingOnLinux

- Ältere Belegung: 0 = Always, 1 = Launch, 2 = HighPriority (decky-frontend-lib App.ts L1360–1364). Auch dort ist 2 die hohe Priorität.
- [Schluss] In beiden Belegungen bedeutet 0 nie „sofort“. Auch „Always“ unterlag seit 2020 der 3-Tage-Regel.

#### 1.3 Wege zu einem sofortigen Update, bewertet

| Weg | Ampel | Befund |
|---|---|---|
| **`AutoUpdateBehavior "2"`** (Steam mit `-shutdown` beenden, Manifest ändern, mit `-silent` starten) | **gelb** (grün nach T1) | Offizielle Einstellung pro Spiel, bleibt über Neustarts erhalten. Steam lädt weiter eins nach dem anderen. Dass 2 die Wartezeit überspringt, steht nur im UI-Text („Immediately download updates“), nicht in einer Valve-Aussage. Ein Fremdskript macht genau das „to avoid scheduled downloads“ (ssdk, laut Recherche-Agent; nicht selbst geprüft). Forenberichte bestätigen das (Suchzitat: [Steam-Forum](https://steamcommunity.com/discussions/forum/0/595139910033253710)). |
| `StateFlags "1030"` (+ `ScheduledAutoUpdate "0"`) bei beendetem Steam | gelb, nur als Rückfallweg | Steam schreibt diesen Zustand selbst während eines laufenden Updates: 6 → 1030 → 4, beobachtet in [reverb-g2-Doku](https://github.com/Wintch/reverb-g2/blob/main/docs/137-steam-headless-control.md). Nightforge nutzt 1026 schon erfolgreich für Neuinstallationen. Für **installierte** Spiele habe ich keinen Bericht gefunden (T4). |
| CEF-Debug-Port + `SteamClient.Downloads.ResumeAppUpdate(appid,"0")` bzw. `QueueAppUpdate` + `SetQueueIndex` | **rot** | Technisch der „richtige“ Weg: „Download now“ (`#Downloads_MoveToTop_Tooltip`) und der Update-Button rufen genau `ResumeAppUpdate` auf ([sp.js L620106](https://github.com/SteamDatabase/SteamTracking/blob/6b238f051b07371ea3af4312636821859708e4b5/ClientExtracted/steamui/sp.js#L620106), [L657784–657868](https://github.com/SteamDatabase/SteamTracking/blob/6b238f051b07371ea3af4312636821859708e4b5/ClientExtracted/steamui/sp.js#L657784-L657868)). Ein Decky-Plugin startet damit geplante Updates sofort ([decky-download-all index.tsx L95–180](https://github.com/bentemple/decky-download-all/blob/6bccc73c9a15a29b6e0584504e01c945795c943f/src/index.tsx#L95-L180)). **Aber:** Freigeschaltet wird der Port über die Datei `.cef-enable-remote-debugging` oder `-cef-enable-debugging`. Er hat keine Anmeldung und läuft mit `--remote-allow-origins=*` ([steamclient.txt L2572–2573](https://github.com/SteamDatabase/SteamTracking/blob/6b238f051b07371ea3af4312636821859708e4b5/Strings/steamclient.txt#L2572-L2573)). Jedes lokale Programm könnte so die angemeldete Steam-Sitzung übernehmen. Dazu ist es eine interne API: Mit SteamOS 3.8 hat sich die Signatur geändert, es kam ein zweites Argument `remote_client_id` dazu (siehe Plugin-Code). Das passt nicht zu „Nightforge sieht dein Login nie“. |
| `steam://validate/<id>` | rot | Ruft `VerifyApp` auf ([sp.js L549051](https://github.com/SteamDatabase/SteamTracking/blob/6b238f051b07371ea3af4312636821859708e4b5/ClientExtracted/steamui/sp.js#L549051)) und öffnet laut Agent die Bibliotheksseite. Kein Beleg, dass es ein anstehendes Update startet. |
| `steam://install/<id>`, `steam://update/<id>` | rot | `install` öffnet sonst den Installationsassistenten. `update` steht nicht in der Link-Tabelle des Clients. Ein Fremdtest gegen einen laufenden Client mit verschobenem Update ergab 12 Minuten lang keinen Download ([reverb-g2-Doku](https://github.com/Wintch/reverb-g2/blob/main/docs/137-steam-headless-control.md)). |
| `steam://open/console` + Befehl | rot | Im Client gibt es **kein** `app_update`, das gibt es nur in steamcmd. Vorhanden sind unter anderem `app_install`, `app_delay_update`, `app_update_cancel` und `download_depot` ([steamclient.txt L33442–33457](https://github.com/SteamDatabase/SteamTracking/blob/6b238f051b07371ea3af4312636821859708e4b5/Strings/steamclient.txt#L33442-L33457), [steamui.txt L27183](https://github.com/SteamDatabase/SteamTracking/blob/6b238f051b07371ea3af4312636821859708e4b5/Strings/steamui.txt#L27183)). Die Konsole erzwingt das Hauptfenster. Ohne Fenster ließe sie sich nur über CEF bedienen. |
| `-applaunch` und sofort abbrechen | rot | Der Startwunsch löst das Update sofort aus (Valve 2020). Dabei erscheint aber Start-Oberfläche, und es gibt `launch_on_completion`: Das Spiel startet womöglich nach dem Update von selbst. Das Verhalten beim Abbruch ist nicht belegt. |
| config.vdf `AutoUpdateWindowEnabled/Start/End` | – | Schränkt nur auf ein Zeitfenster ein, beschleunigt nichts. Schlüssel: [steamclient.txt L12598–12600](https://github.com/SteamDatabase/SteamTracking/blob/6b238f051b07371ea3af4312636821859708e4b5/Strings/steamclient.txt#L12598). |

#### 1.4 Was Steam beibehält und was es zurücksetzt

- Manifeste nur bei beendetem Steam ändern. Steam hält sie im Speicher und schreibt sie beim Beenden zurück [Forum/Code]. Nightforge macht das bereits so (Engine.restartSteamInBackground).
- `AutoUpdateBehavior` ist eine UI-Einstellung und bleibt erhalten. In Foren heißt es, sie werde gelegentlich nach Client-Updates überschrieben. Nightforge sollte sie daher bei jedem Steam-Start prüfen.
- `StateFlags`, `UpdateResult`, `ScheduledAutoUpdate` und `Bytes*` verwaltet Steam selbst. Handänderungen sind nirgends dokumentiert.
- config.vdf: Die Einstellungen sind offiziell (UI), das Dateiformat nicht. Auch hier nur bei beendetem Steam schreiben.
- CEF: -cef-enable-debugging geht bei Steams Selbst-Neustart verloren, die Markerdatei bleibt. Beides ist ohnehin rot.

#### 1.5 Erkennen, dass ein Update ansteht

- Bei laufendem Steam (empfohlen): Im appmanifest steht StateFlags & 2 (Update Required), oder TargetBuildID ist weder 0 noch gleich buildid.
  - Die Größe liefern BytesToDownload (komprimiert) und BytesToStage (zu schreiben).
  - Beides kann anfangs eine Schätzung sein: update_is_prefetch_estimate (decky Downloads.ts L100–148).
  - Steam schreibt den Zustand auch dann, wenn das Update nur eingeplant ist. Foren-Tipps setzen 6 → 4, um Updates zu unterdrücken (Suchzitat: Nexus-Forum).
  - Im content_log steht state changed : Update Required,... (Update delayed for N secs).

- Ohne laufendes Steam: Das Manifest ist dann veraltet.
  - `appcache/appinfo.vdf`

 ist binär, seit Juni 2024 im Format v41 mit String-Tabelle (SteamAppInfo). Sie enthält depots.branches.<public|BetaKey>.buildid.
  - Das geht lokal und ohne Netz, ist aber nur so frisch wie Steams letzte Sitzung. Ein Parser für v41 steckt zum Beispiel in protontricks steam.py.

- Anonymes PICS braucht kein Nutzerlogin, aber eine eigene Steam-Protokoll-Implementierung (wie SteamKit2). Der Drittdienst api.steamcmd.net würde die App-IDs an Dritte schicken, also nein.
- `ISteamApps/UpToDateCheck` ist unbrauchbar. Es erwartet die PatchVersion aus steam.inf für Gameserver, keine buildid (xPaw-API-Doku, SourceMod-Beispiel).

#### 1.6 Fortschritt während des Ladens

- `BytesDownloaded` schreibt Steam nur bei Zustandswechseln. Das haben zwei Fremdprojekte unabhängig beobachtet (Arcadia #278, FamiDrive #59), und es deckt sich mit eurer Beobachtung.
- content_log (auf Windows, Linux und Mac gleich):
  - update started : download X/Y, … stage A/B kommt nur beim Start und Fortsetzen.
  - Current download rate: … Mbps kommt etwa alle 60 s, aber global, ohne App-ID.
  - Am Ende steht scheduler finished : removed from schedule (result …, state 0x4).

- Verlässliche Kombination [Schluss]:
  - die belegte Größe von steamapps/downloading/<id> gegen BytesToStage, wie es Nightforge schon tut,
  - plus die nettop-Bytes des Steam-Prozesses, wie in MacSteamProgress,
  - fertig, wenn StateFlags == 4 und buildid == TargetBuildID.
  - Vorsicht bei der Vorbelegungsphase („Preallocating“ bzw. „Reserving Space“, T7).

- `UpdateResult` ist ein `EAppUpdateError`, kein `EResult`. Belege: steamui_english.json L1590–1647, selbst geprüft. Die Zuordnung zum Manifestfeld ist ein [Schluss], aber stimmig.
  - Routine, kein Fehler: 0 kein Fehler, 2 pausiert, 4 suspendiert (beim Abmelden)
  - 6 kein Internet
  - 11 Schreibfehler auf der Platte
  - 12 Not enough free disk space
  - 13 beschädigte Inhaltsdateien
  - 15 ungültiger Installationspfad
  - 16 Spiel läuft bereits
  - 21 Content-Server nicht erreichbar
  - 31 beschädigte Update-Dateien
  - 35 andere Sitzung spielt
  - 43 Kontingent der Platte erschöpft
  - 52 Laufwerk nicht eingebunden

- `StateFlags`:
  - 2 Update Required, 4 Fully Installed, 512 Paused, 1024 Update Started, 1048576 Downloading, 2097152 Staging
  - „App Running“ ist im aktuellen Client 0x2000, nicht 64, wie es Lutris und Playnite annehmen. Belege: Log 0x2204 = Fully Installed, Update Paused, App Running in steam-for-linux #10906 laut Recherche-Agent; selbst konnte ich das Issue nicht öffnen.

#### 1.7 steamcmd: rot

- Eigene Anmeldung nötig. Anonym kommt man nur an Inhalte aus dem anonymen Paket, etwa Dedicated Server. Gekaufte Spiele brauchen Name, Passwort und Steam Guard. Danach liegt ein Login-Token auf der Platte. Das verletzt „Nightforge sieht dein Login nie“.
- Wirft den laufenden Client raus. Steam erlaubt keine zwei Sitzungen derselben LoginID von derselben IP (SteamKit SteamUser.cs, DepotDownloader-README). Ein Forenbericht dazu: „every time I used SteamCMD I was logged out of the client“.
- Umgeht die Buchführung des Clients. steamcmd schreibt eigene Manifeste und bringt den Zustand des Clients nicht auf den neuen Stand. Bei laufendem Client drohen doppelte Downloads oder kaputte Daten.
- Auf dem Mac nur für Intel, braucht also Rosetta.
- Für DepotDownloader und steamctl gilt dasselbe, steamctl ist zudem verwaist.

---

### 2. Steam für Mac

- [Schluss] Es ist derselbe Client-Code (geteilte UI). Also gelten derselbe Planer, dieselben Werte 0–3, dieselben Log-Zeilen und dieselben Fehlercodes.
- Unsichtbar starten: open -g -a Steam --args -silent, oder wie MacSteam.start() über NSWorkspace mit hides = true und -silent.
  - Fremdcode warnt: -j erreicht nur den Bootstrapper, und ein erneutes Öffnen von Steam.app holt ein Fenster nach vorn (warzag SteamInstaller.swift, laut Agent).
  - MacSteam.guardWindows() deckt das bereits ab.

- Ist ein kurzer, unsichtbarer Start nur fürs Update sinnvoll? Ja, als zweite Stufe, mit diesen Bedingungen:
  1. Nie parallel zum Wine-Steam. Die beiden melden sich gegenseitig ab („Session Replaced“, `docs/TODO.md:58`

). Beim Abmelden bricht Steam Updates ab (update canceled : Disabled (Suspended), Code 4). Also Wine-Steam beenden, Mac-Steam starten, aktualisieren, Mac-Steam beenden, Wine-Steam wieder starten.
  2. Es ist der echte Client des Nutzers. Wert 2 ändert eine sichtbare Einstellung pro Spiel in dessen Steam. Freunde sehen den Nutzer online. Steam aktualisiert sich beim Start eventuell selbst. Ist die Anmeldung abgelaufen: abbrechen und kein Fenster zeigen.
  3. Erst nach Start und PICS-Abgleich weiß der Mac-Client, dass ein Update ansteht (T8).
  4. Steam für Mac belegt die volle Größe sofort, so steht es im Kommentar von MacSteamProgress. Der Fall „Batman geleert und dann wegen Platzmangel pausiert“ (`docs/TODO.md:64`

) zeigt: Freien Platz vorher prüfen.

- Ampel: gelb.

---

### 3. Epic über legendary

Code: [derrod/legendary @ 42f6bde](https://github.com/derrod/legendary/tree/42f6bdeadde3a9526dc8eb713763476999ac217b).

- Update-Check für alle Spiele in einem Aufruf: legendary list-installed --check-updates --csv. Die Spalte „Update available“ ist True oder False (cli.py L291–326).
  - Die JSON-Ausgabe enthält die verfügbare Version nicht.
  - Heroic ruft legendary list --third-party auf und vergleicht dann installed.json mit assets.json (library.ts L284–380).
  - Braucht das gespeicherte Epic-Token, legendary erneuert es selbst.

- Update ohne Start: legendary update <AppName> --update-only -y --skip-sdl --skip-dlcs
  - update ist nur ein Alias von install. Ohne --update-only würde ein fehlendes Spiel neu installiert (L874–877, L2849).
  - Mit `-y`, aber ohne `--skip-dlcs` installiert legendary nach dem Update alle DLCs (L1104–1123). Heroic ruft update -y --skip-sdl ohne --skip-dlcs auf. Ob Heroics mitgelieferte legendary-Version sich hier anders verhält, habe ich nicht geprüft.
  - Installierte DLCs stehen als eigene Einträge in der Liste und werden einzeln aktualisiert.

- Fortsetzen nach Abbruch:
  - Die Resume-Datei liegt unter ~/.config/legendary/tmp/<App>.resume (core.py L1613–1615) und wird pro fertiger Datei fortgeschrieben (manager.py L123–152, L584).
  - Dateien entstehen als .tmp und werden umbenannt. Eine unterbrochene große Datei beginnt also von vorn.
  - Prozess beenden und denselben Befehl erneut aufrufen setzt fort (cli.py L1049).

- Speicherplatz und externe Laufwerke sind eingebaut (core.py L1730–1747):
  - disk_space_delta wird mit dem freien Platz verglichen; bei Mangel kommt „Not enough available disk space!“.
  - Fehlt der Pfad, kommt „make sure all necessary mounts are available“.

- Bandbreite: Es gibt keinen Schalter für eine Grenze. Nur --max-workers (Standard min(2 × CPU, 16)) und --max-shared-memory (L2829–2834).
- Immer nur ein Update: legendary sperrt installed.json; es kann nur eine Instanz installieren (lgndry.py L322–332, cli.py L845–848).
- Fortschritt: Zeilen wie = Progress: 12.34% (n/m), Running for …, ETA: … und  - Downloaded: X MiB, Written: Y MiB (manager.py L766–770). Heroic wertet sie aus (games.ts L397–430).
- Veraltetes Spiel starten: legendary launch verweigert online den Start mit „Game is out of date“, außer mit --skip-version-check (cli.py L639–648). Genau das spricht für Hintergrund-Updates.
- So macht es Heroic (@ 509a34f):
  - Die Einstellung autoUpdateGames steht standardmäßig auf aus (config.ts L339).
  - Geprüft wird beim Start und nach jedem beendeten Update. Einen periodischen Timer habe ich nicht gefunden (main.ts L626–640).
  - autoUpdate() stellt jedes aktualisierbare Spiel in die Warteschlange. Es überspringt Spiele mit ignoreGameUpdates und solche, deren Ordner fehlt (existsSync) (storeManagers/index.ts L42–62).
  - Die Warteschlange lädt eins nach dem anderen und pausiert automatisch, wenn der Rechner offline geht (downloadqueue.ts L29–39, L82–116).
  - Pausieren heißt Prozess beenden, Fortsetzen heißt erneut aufrufen (L257–280).
  - Keine Pause bei laufendem Spiel, im Akkubetrieb oder bei getaktetem Netz.

- Ampel: grün.

---

### 4. GOG über gogdl

Code: [heroic-gogdl @ 6c6ef53](https://github.com/Heroic-Games-Launcher/heroic-gogdl/tree/6c6ef53fd4965d8d9b943c73d9400fe55eadc6ba).

- Update-Check, so wie Heroic ihn macht (gog/library.ts L940–1066):
  1. Builds abfragen: GET https://content-system.gog.com/products/<id>/os/<windows|osx>/builds?generation=2&_version=2, mit Bearer-Token.
  2. Den ersten Build ohne Branch nehmen.
  3. Dessen Meta-URL mit If-None-Match: <gespeichertes versionEtag> abrufen.
  4. Status 200 mit neuem ETag heißt: Update vorhanden.

- Alternative: gogdl info <id> --platform windows --lang … liefert JSON mit buildId, versionEtag und versionName (manager.py L61–68, v2.py L58–94).
- Wichtig: gogdl führt keine Liste installierter Spiele. Nightforge muss bei Installation und Update selbst speichern: buildId, versionEtag, Branch, Sprache und DLCs. Heroic tut das in installedGamesStore. gogdl selbst bewahrt nur das Manifest des installierten Builds für Deltas auf (<config>/heroic_gogdl/manifests/<id>, constants.py L31, v2.py L97–147).
- Update ohne Start: gogdl --auth-config-path <auth.json> update <id> --platform windows --path <Spielordner> --support <Ordner> --lang de-DE --skip-dlcs|--with-dlcs [--dlcs a,b] --max-workers N
  - update ist ein Alias von download (args.py L55–97).
  - So ruft es auch Heroic auf (gog/games.ts ab L1104).

- Fortsetzen: über .gogdl-resume im Spielordner, pro Datei (task_executor.py L27, L145–178).
- Speicherplatz: gogdl prüft selbst und meldet „Unable to proceed, Not enough disk space“ mit Exit-Code 2 (v2.py L262–265, dl_utils.py L129–132).
- Bandbreite: nur über --max-workers.
- Fortschritt: Zeilen wie = Progress: 12.34 written/total, Running for …, ETA … (progressbar.py L90–99).
- Veraltetes Spiel starten: gogdl launch prüft keine Version. Heroic fragt in dem Fall „This game has an update, apply update now?“ (helpers/library.ts L160–220).
- Galaxy [Forum, die offizielle Seite war gesperrt]:
  - Auto-Update ist pro Spiel standardmäßig an, dazu gibt es den globalen Schalter „Auto-update games“.
  - Es gibt „Pause downloads when playing“ und eine Bandbreitengrenze.
  - Ein Zeitfenster gibt es nicht; es steht nur als Wunsch auf GOGs Wunschliste.
  - Quellen: GOG-Forum, GOG-Forum zur Bandbreite, Changelog (Suchzitat).

- Ampel: grün, mit eigener Buchführung.

---

### 5. Konsolen und Steam Deck, und was davon zu macOS passt

Die Herstellerseiten waren gesperrt, deshalb sind die meisten Angaben Suchzitate.

| Plattform | Im Ruhemodus | Während eines Spiels | Reihenfolge |
|---|---|---|---|
| PS5 | Lädt mit „Stay Connected to the Internet“. „Auto-Install in Rest Mode“ schließt ein pausiertes Spiel ([Sony](https://www.playstation.com/en-gb/support/hardware/automatic-updates-playstation/)) | nichts Offizielles | nicht dokumentiert |
| Xbox Series | Nächtliches Wartungsfenster, etwa 2–6 Uhr. Seit 2023 nach CO₂-Daten geplant, **nur wenn eingesteckt** ([Xbox Wire](https://news.xbox.com/en-us/2023/01/11/xbox-carbon-aware/)) | Downloads gedrosselt, schneller bei pausiertem Spiel ([Game Informer](https://www.gameinformer.com/2021/03/17/new-xbox-update-speeds-up-downloads-while-games-are-suspended)) | nicht dokumentiert |
| Switch | Lädt im Standby, wenn genug Platz ist ([Nintendo](https://en-americas-support.nintendo.com/app/answers/detail/a_id/56286)) | Bestimmte Software pausiert den Download | nicht dokumentiert. Online-Spiele verlangen die gleiche Version ([Smash-Beispiel](https://en-americas-support.nintendo.com/app/answers/detail/a_id/42809)) |
| Steam | – | „Allow downloads during gameplay“ ist standardmäßig aus | **zuletzt gespielt zuerst (72 h)**, der Rest nachts |
| Steam Deck | Seit 17.11.2025 „Display-Off Low Power Downloads“: am Netzteil standardmäßig an, im Akkubetrieb aus ([GamingOnLinux](https://gamingonlinux.com/2025/11/steam-deck-gets-display-off-low-power-downloads-in-a-new-stable-update)) | wie Steam | wie Steam |
| Epic Launcher | – | Einstellbar, ob Spiele während des Spielens aktualisiert werden. Dazu Zeitplan, Tempolimit und Reihenfolge per Ziehen ([Epic 2025](https://store.epicgames.com/news/epic-games-new-download-manager)) | manuell |

**Was davon auf den Mac passt** (Apple-Doku direkt gelesen):

- Kein Download im Ruhezustand.
  - Erzwungenen Schlaf (Deckel zu, Apple-Menü, Akku leer) kann man nicht verhindern, nur verzögern (QA1340).
  - Dark Wake und Power Nap stehen Drittanbietern nicht zur Verfügung (Apple-Forum, DTS).
  - Also gilt: „solange Nightforge offen ist“.

- Wach halten: ProcessInfo.beginActivity(options: [.idleSystemSleepDisabled, .suddenTerminationDisabled], reason:) oder IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep).
  - Der Bildschirm darf trotzdem schlafen gehen, wie beim „Display-Off“ des Deck.
  - Die Assertion schützt zugleich vor App Nap.
  - Quellen: Apple-Doku zu IOPMAssertion, Energy Efficiency Guide.
  - Apple rät ausdrücklich, Downloads im Akkubetrieb zu verschieben.

- Netzteil erkennen: IOPSGetProvidingPowerSourceType(IOPSCopyPowerSourcesInfo()) == kIOPSACPowerValue. „UPS Power“ zählt nicht als Netzteil. Für Änderungen IOPSCreateLimitedPowerNotification nutzen (Apple-Doku).
- Stromsparmodus und Hitze: ProcessInfo.isLowPowerModeEnabled gibt es ab macOS 12. thermalState sollte höchstens .fair sein (Apple-Doku).
- Datenvolumen: Mit NWPathMonitor nicht laden, wenn isExpensive (iPhone-Hotspot) oder isConstrained (Datensparmodus, auf dem Mac pro WLAN seit macOS 13) gilt (isExpensive, isConstrained). Kein Store tut das selbst, Nightforge wäre hier vorn.
- Schlaf und Aufwachen: NSWorkspace.willSleepNotification gewährt bis zu 30 s zum sauberen Pausieren, nach didWakeNotification alles neu prüfen (Apple-Doku).
- Freier Platz: volumeAvailableCapacityForOpportunisticUsageKey, also „available capacity … for storing nonessential resources“ (Apple-Doku, Checking Volume Storage Capacity). Hintergrund-Updates sind genau so ein Fall; vom Nutzer gestartete Installationen nutzen dagegen „Important Usage“.

---

### 6. Fallstricke

- Speicherplatz.
  - SteamPipe baut die neue Datei neben der alten („to update a 25 GB pack file, SteamPipe will always build a new, 25GB file“, Suchzitat aus partner.steamgames.com/doc/sdk/uploading). Der Bedarf reicht also bis BytesToStage.
  - Bei Mangel steht UpdateResult 12, und das Update bleibt pausiert in der Warteschlange.
  - legendary und gogdl prüfen selbst.
  - Nightforge sollte vor jedem Start prüfen: Opportunistic-Kapazität ≥ Bedarf × 1,1 + 2 GB [Schluss]. Bei Steam für Mac die volle Spielgröße ansetzen.

- Externe Laufwerke.
  - Steam führt bIsMounted und zeigt „installed on a drive that is not currently connected“; dazu gehört Code 52.
  - legendary bricht sauber ab, Heroic überspringt per existsSync.
  - Bei gogdl muss Nightforge selbst vorher prüfen, ob /Volumes/<Name> eingebunden ist; bei Wine ebenso das Laufwerk hinter der Zuordnung von D:.
  - Spiele auf fehlenden Laufwerken kommen gar nicht erst in die Warteschlange.

- Ein Spiel startet, während sein Update läuft.
  - Steam erledigt das selbst: Das Update kommt vor dem Start, „launch_on_completion“ ist möglich, -applaunch führt das schon heute aus („Update & Play“).
  - Bei Epic und GOG muss Nightforge den Start sperren, sonst läuft ein halb aktualisierter Ordner. Stattdessen „Update wird fertig geladen … N %“ zeigen und danach starten.

- Ein anderes Spiel startet.
  - Laufende legendary- oder gogdl-Updates beenden und danach fortsetzen.
  - Steam pausiert selbst, wenn AllowDownloadsDuringGameplay aus ist (Standard laut Fremd-Doku, Schlüssel in steamclient.txt L12278). Im eigenen Prefix ausdrücklich auf "0" setzen (T5).

- Anti-Cheat- und Online-Spiele.
  - Steam verlangt online das Update vor dem Start.
  - legendary verweigert veraltete Spiele.
  - GOG startet sie zwar, aber für den Mehrspielermodus braucht man meist die gleiche Version.
  - Anti-Cheat läuft unter Wine meist ohnehin nicht (`docs/TODO.md:97`

). Hintergrund-Updates helfen vor allem gegen „erst 20 GB laden, dann spielen“.

- Weitere Punkte.
  - legendary lässt keine zwei Installationen parallel zu. Vom Nutzer gestartete Installationen sollten Vorrang haben und den Hintergrund-Updater pausieren.
  - Mit Wert 2 könnten Steam-Updates einen neuen Download überholen, den der Nutzer gestartet hat (T6).
  - Steam aktualisiert sich beim Start eventuell selbst, unter Wine kann das lange dauern (`docs/TODO.md:500`

).

---

### 7. Ergebnis pro Store

| Store | Ampel | Empfohlener Weg | „Update nötig“ erkennen | Fortschritt | Risiken |
|---|---|---|---|---|---|
| **Steam (Wine)** | **gelb** (grün nach T1–T5) | Alle Spiele im eigenen Prefix auf `AutoUpdateBehavior "2"`, auch in `Engine.requestDownload`, das heute `0` schreibt. Dazu config.vdf `AllowDownloadsDuringGameplay "0"` und `AutoUpdateWindowEnabled "0"`. Nur bei beendetem Steam schreiben. Das „Wann“ steuert, ob Steam läuft. | `StateFlags & 2`, `TargetBuildID ∉ {0, buildid}`, `BytesToStage` | belegte Größe von `downloading/<id>` / `BytesToStage`, nettop, content_log. Ende: `StateFlags 4` und `buildid == TargetBuildID` | Wirkung von 2 nur aus dem UI-Text belegt. Steam setzt den Wert eventuell zurück. Reihenfolge der Spiele mit Wert 2 ist unbekannt. Neustart nötig. |
| **Steam für Mac** | **gelb** | Wie oben, plus unsichtbarer Start mit `-silent` nur im Update-Fenster. Strikt abwechselnd mit dem Wine-Steam. Danach beenden, wenn Nightforge ihn gestartet hat. | wie oben, erst nach dem PICS-Abgleich | nettop + content_log (`MacSteamProgress`) | Session Replaced, echter Client des Nutzers, sichtbare Einstellung, volle Vorbelegung des Platzes |
| **Epic (legendary)** | **grün** | `legendary update <App> --update-only -y --skip-sdl --skip-dlcs`, installierte DLCs einzeln | `legendary list-installed --check-updates --csv` | `= Progress:`-Zeilen | Nur eine Instanz. Unterbrochene große Datei beginnt neu. Keine Bandbreitengrenze. |
| **GOG (gogdl)** | **grün** (mit eigener Buchführung) | `gogdl … update <id> --platform … --path … --support … --lang … --skip-dlcs --max-workers N` | ETag gegen den Builds-Endpunkt (wie Heroic), alternativ `gogdl info` gegen gespeicherte buildId | `= Progress:`-Zeilen | Nightforge muss buildId, ETag und Branch speichern. Laufwerk vorher selbst prüfen. |
| Steam: CEF-Port, `steam://`, Konsole, `-applaunch`-Abbruch, steamcmd | **rot** | – | – | – | Sicherheit, Login, Fenster, keine Wirkung |

---

### 8. Ablaufvorschlag für den Hintergrund-Updater

**Grundsatz:** Nightforge plant, die Stores führen aus. Es läuft immer genau ein Update. Der Nutzer stellt nichts ein.

1. Update-Fenster („Tor“). Alle Bedingungen müssen gleichzeitig erfüllt sein:
  - Nightforge ist offen.
  - Stromquelle ist das Netzteil.
  - Stromsparmodus aus, thermalState ≤ .fair.
  - Netz verbunden, nicht isExpensive, nicht isConstrained.
  - Kein Spiel läuft (Nightforge-Status plus Engine.windowsGameRunning).
  - Keine vom Nutzer gestartete Installation läuft.
  - Seit dem letzten Spielende sind mindestens 2 Minuten vergangen.

2. Wann geprüft wird:
  - beim Start von Nightforge, alle 6 h, nach dem Aufwachen, bei Netzwechsel und nach jedem fertigen Update;
  - Epic: ein Aufruf von list-installed --check-updates --csv;
  - GOG: ein ETag-Abruf pro Spiel;
  - Steam (Wine): Manifeste lesen, solange Steam läuft;
  - Steam für Mac: nur, wenn das Tor offen ist und gerade kein Wine-Steam-Update läuft. Dann einmal unsichtbar starten, auf Anmeldung und Abgleich warten (T8), Manifeste lesen.

3. Warteschlange:
  - sortiert nach zuletzt gespielt, absteigend, wie Steams 72-h-Regel und Konsolen;
  - bei Gleichstand das kleinere Update zuerst;
  - nicht verbundene Laufwerke und Spiele ohne genug Platz überspringen und als „Update wartet: Platz“ kennzeichnen.

4. Ausführen, eins nach dem anderen, dabei beginActivity(.idleSystemSleepDisabled) halten:
  - Epic/GOG: Prozess starten, Fortschrittszeilen lesen. Schließt sich das Tor, Prozess beenden (SIGINT, nach Frist SIGTERM). Geht das Tor wieder auf, denselben Befehl erneut aufrufen; die Resume-Datei setzt fort.
  - Steam (Wine):
    - Einmalig und bei jedem Steam-Start prüfen, dass alle Manifeste AutoUpdateBehavior 2 haben. Wenn nicht: Steam beenden, Wert setzen, mit -silent starten.
    - Danach lädt Steam selbst. Nightforge beobachtet Manifeste, downloading/ und nettop.
    - Pausen: Bei Spielstart pausiert Steam selbst. Bei Akkubetrieb oder getaktetem Netz und ohne laufendes Spiel: steam.exe -shutdown. Steam erst beim nächsten „Spielen“ oder bei wieder offenem Tor starten.

  - Steam für Mac: erst, wenn die Wine-Steam-Liste leer ist. Wine-Steam beenden, Mac-Steam unsichtbar starten, warten bis StateFlags 4, Mac-Steam beenden, Wine-Steam wieder starten.

5. Schlafen: Bei willSleep Epic- und GOG-Prozesse beenden. Bei didWake das Tor neu prüfen.
6. Spielen während eines Updates:
  - Ist es dasselbe Spiel: Update im Vordergrund fertig laden und dann starten. Steam macht das selbst; bei Epic und GOG übernimmt Nightforge.
  - Ist es ein anderes Spiel: Hintergrund-Update sofort pausieren.

7. Oberfläche: Abzeichen auf dem Cover („Aktuell“, „Wird aktualisiert · 43 %“, „Update wartet: zu wenig Platz“). Keine Einstellungen, höchstens „Updates jetzt pausieren“ im Menü.

---

### 9. Offene Fragen, die nur ein Test am echten System klärt

Ich habe diese Tests nur beschrieben, nicht ausgeführt. Alle Tests mit eigenen **Testkonten** und kostenlosen Spielen, in einem eigenen macOS-Benutzer oder Test-Prefix, nie mit dem Konto des Nutzers.

- T1, Wert 2 überspringt die Wartezeit? Kostenloses, oft gepatchtes Steam-Spiel installieren und über 72 h nicht spielen. Wenn laut SteamDB ein Patch kommt, prüfen: Mit Wert 0 sollte (Update delayed for …) erscheinen. Dann mit Wert 2 (Steam beendet, Wert gesetzt, neu gestartet) prüfen, ob es sofort losgeht (scheduler update : …, update started).
- T2, liest Steam 0 als „Use global setting“? In den Spiel-Eigenschaften nachsehen, welche Option angezeigt wird. Dann jede Option in der UI wählen und das appmanifest vergleichen.
- T3, bleibt der Wert? Nach mehreren Steam-Neustarts und einem Client-Update prüfen, ob 2 noch im Manifest steht.
- T4, Rückfallweg `StateFlags 1030`: Bei verschobenem Update Steam beenden, 1030 und ScheduledAutoUpdate 0 setzen, starten. Beginnt der Download sofort?
- T5, Downloads während des Spielens: AllowDownloadsDuringGameplay "0" setzen. Pausiert Steam die Updates anderer Spiele, während ein Spiel über -applaunch unter Wine läuft? Welchen Schlüssel und Wert schreibt der UI-Schalter tatsächlich?
- T6, Reihenfolge: Mehrere Spiele mit Wert 2 und ein neuer Download, den der Nutzer anstößt: In welcher Reihenfolge lädt Steam?
- T7, Vorbelegung unter Wine/APFS: Wächst die belegte Größe von downloading/<id> stetig oder springt sie? Gegen nettop-Bytes vergleichen.
- T8, Steam für Mac unsichtbar starten: Wie lange nach dem Start stehen StateFlags 2 und TargetBuildID im Manifest? Blitzt ein Fenster auf, und wie verhält sich die Selbstaktualisierung?
- T9, Session Replaced: Lädt ein abgelösster Client weiter? Wird ein Update fortgesetzt, das beim Wechsel unterbrochen wurde?
- T10, Steam mitten im Download beenden: Setzt Steam beim nächsten Start fort, oder bleibt das Update pausiert (StateFlags 512)?
- T11, legendary und DLCs: Mit -y ohne --skip-dlcs an einem Testspiel mit nicht installierten DLCs prüfen, ob sie mitinstalliert werden. Mit --skip-dlcs prüfen, ob installierte DLCs sauber einzeln aktualisieren.
- T12, Abbrechen und Fortsetzen bei legendary und gogdl: Wie viel Fortschritt geht bei großen Pak-Dateien verloren? Beendet sich der Prozess bei SIGINT bzw. SIGTERM sauber?
- T13, GOG ohne gespeicherten ETag (Spiele, die vor dieser Funktion installiert wurden): Funktioniert der Rückfall auf den buildId-Vergleich mit gogdl info?
- T14, externes Laufwerk abziehen: Was tun Steam (Wine, D:), legendary und gogdl mit einem anstehenden Update?
- T15, Deckel zu mitten im Download: Für jeden Store prüfen, ob das Update nach dem Aufwachen korrekt fortgesetzt wird.
- T16, Platzbedarf: Großes Steam-Update mit großen Pak-Dateien. Wie viel Platz braucht es tatsächlich, verglichen mit BytesToStage?

---

### 10. Quellen und Code-Stände

- Valve-Client: SteamDatabase/SteamTracking @ 6b238f0
- Decky-Typen: decky-frontend-lib @ 8326000
- Decky-Plugin: decky-download-all @ 6bccc73
- legendary: derrod/legendary @ 42f6bde
- gogdl: heroic-gogdl @ 6c6ef53
- Heroic: HeroicGamesLauncher @ 509a34f
- Planer-Standardwerte: SteamCMD-Commands-List @ 7db7d46
- Planer-Werte vom Server: stmsrv @ bbd9d0e
- Andere Launcher setzen keine Updates durch, sie starten und installieren nur: Playnite (steam://install, -silent steam://rungameid), Lutris (acf mit StateFlags 1026 plus steam://install), GameHub. Beleg: PlayniteExtensions SteamGameController.cs, lutris runners/steam.py.
- In Nightforge:
  - `Sources/Nightforge/Engine.swift:1411-1440`

: requestDownload schreibt AutoUpdateBehavior 0
  - `Sources/Nightforge/Library.swift:399-402`

: wertet UpdateResult 12 aus
  - `docs/TODO.md:58`

: Session Replaced
  - `docs/TODO.md:64-67`

: Speicherplatz
