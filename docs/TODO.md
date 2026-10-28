# Nightforge – offene Punkte

Was liegen geblieben ist und irgendwann angegangen werden kann. Stand: 26.10.2026, nach dem
Umstieg auf winecx 4.7.3 mit D3DMetal (PR #7), dem Controller-Paket (PR #8) und dem Code-Audit
(behoben in PR #4, #5, #11, #12, #14–#19, der Rest steht unten unter „Aus dem Code-Audit“).

Neue Punkte unten in den passenden Abschnitt, Erledigtes löschen (die Geschichte steht im Git-Log).
Jeder Punkt nennt, wo man anfängt.

## Nach dem Engine-Wechsel neu prüfen

Die Tests vom 26.10. liefen größtenteils noch auf Wine 11.18 (Gcenx). Seit PR #7 läuft winecx 4.7.3.

- **Getestete Spiele auf winecx gegenprüfen.** Palworld (DXMT, 60 FPS), Deadlock (DXVK, 60–120 FPS),
  Left 4 Dead 2 (WineD3D), OxyRail und 7 Days to Die. Die Ergebnisse und Profile in
  `profiles/mac.json` beziehen sich auf 11.18.
- **Left 4 Dead 2.** Auf 11.18 scheitert DXVK an seinen Puffern (`vkCreateBuffer`, MoltenVK lehnt
  externe Speicher-Handles ab). WineD3D läuft, stürzt aber nach etwa einer Minute ab, und im Spiel fehlte der Ton.
  `-vulkan` (Valves DXVK) und WineD3D mit Vulkan starten nicht. Auf winecx (26.10.) scheitert DXVK schon früher:
  `VK_ERROR_FEATURE_NOT_PRESENT` bei `vkCreateDevice`, weil der Vulkan-Layer dort nicht geladen wird (siehe
  „Aus dem Code-Audit“ → Vulkan-Layer). WineD3D bleibt der Weg. Zum Ton:
  In der Cloud-Konfiguration stehen `volume "0.008"` und Quadro-Lautsprecher, also erst im Spiel unter
  Optionen → Audio hochdrehen, bevor man Wine verdächtigt.
- **Andere Source-Spiele** (Team Fortress 2, Garry's Mod): Sie bekommen jetzt dieselbe DirectX-9-Leiter wie L4D2.
  Noch kein einziges getestet.
- **Unreal-Spiele allgemein.** Bis 26.10. bekam kein Unreal-Spiel DXMT. Die Einstellungen reichten nur drei
  Ordner tief, `<Projekt>/Binaries/Win64/*-Shipping.exe` liegt auf Ebene 4. Wer ein Unreal-Spiel für
  „läuft schlecht“ hielt, sollte es erneut versuchen (z. B. Marvel Rivals).
- **msync (PR #1)** ist auf 11.18 portiert. winecx bringt ein eigenes msync mit, der Patch greift dort nicht.
  Klären, ob der 11.18-Weg noch gebraucht wird.

## DirectX 12 (D3DMetal)

- **Echtes DX12-Spiel aus den Top 100 testen.** Gemessen ist bisher nur der Wukong-Benchmark
  (D3DMetal 69 FPS im Schnitt). Kandidaten: Elden Ring (offline, ohne EAC),
  Resident Evil 4, Monster Hunter Wilds, Street Fighter 6, Space Marine 2, Planet Zoo 2.
- **Bekannte Stolpersteine, die automatisch abgefangen werden sollen** (Plan in den Notizen der DX12-Sitzung):
  `ROSETTA_ADVERTISE_AVX=1` lässt Wukong abstürzen; Unreals Hinweis „AMD driver has known issues“
  (D3DMetal meldet sich als AMD); Frame Generation und DLSS schalten sich beim ersten Start ein und stürzen ab.
- **MTL_HUD** erscheint unter D3DMetal 4.0 nicht (Metal-4-Backend?).
- **Lizenz:** GPTK 4.0b3 erlaubt die Weitergabe nur nicht-kommerziell und unverändert. Nightforge muss
  kostenlos bleiben, D3DMetal.framework wird nur ganz und unverändert weitergegeben. Kein Streaming-Dienst
  damit (2C). Apple kann die Lizenz jederzeit beenden (Abschnitt 5). Plan B wäre dann, dass Nightforge das
  Toolkit aus Apples eigenem Download holt, wie die kommerzielle App Apara es macht.

## Steam und Start

- **Steam-Fragen vor dem Start** (EULA, Controller-Firmware „ShowInterstitials“, Startoption bei
  Mac-Spielen mit mehreren Optionen wie Project Zomboid): Sie erscheinen, wenn der Spieler in Nightforge
  „Bestätige im Steam-Fenster“ klickt. Ein Klick ist für den Nutzer okay. Wünschenswert wäre, die
  Standard-Startoption automatisch zu wählen. Kandidat: `steam://launch/<id>/<Typ>` (Steam kennt die Typnamen
  Default, Option1…). Ein Versuch blieb ohne Wirkung, lief aber, während schon ein Dialog offen war.
  Also ungeklärt.
- **Windows-Steam ignoriert manchmal `steam.exe -shutdown`.** Dann hilft nur `wineserver -k`. Läuft Steam gar
  nicht, startet `-shutdown` ein neues Steam. Nightforges eigenes Beenden darauf prüfen.
- **steam-shutdown.sh** hält jeden Prozess unter `\steamapps\common\` für ein Spiel, auch in
  Test-Prefixen, und holt Nightforge dann nach vorne.
- **Steam-Anmeldung zwischen den Steams.** Steam für Mac und die Windows-Steam melden sich gegenseitig ab
  („Session Replaced“). Beobachtet wurde auch: Steam hängt, beendet sich nicht oder drängt sich nach vorne.

### Engine-Rückfall (3.3, Branch `claude/engine-rollback-02a61e`)

- **Speicher-Anzeige zählt die gehaltene Engine doppelt.** Sie ist ein APFS-Klon und teilt ihre Blöcke mit dem
  Original. `Library.folderSize` summiert aber `totalFileAllocatedSize`, also erscheint sie in Einstellungen ›
  Speicher mit voller Größe (bis 1,4 GB), solange das Original noch da ist.
- **Nach dem Zusammenführen mit 0.2 (GameID):** `EngineRollback` merkt sich Spiele unter der Steam-App-ID, und
  `LaunchHealth.confirmedWays` liest `launchHealth.<id>`. Beides auf die neue ID umstellen.
- **Nur Abstürze eines Spiels zählen.** Startet Steam selbst mit der neuen Engine nicht, greift der Rückfall nicht.
- **Datum der ersten gehaltenen Engine:** Es ist der Tag, an dem 3.3 zum ersten Mal lief, nicht der Tag, an dem
  diese Engine kam.

## Mac-Versionen

- **Windows-Fallback** hat noch nie wirklich ausgelöst (keine Mac-Version ist bisher abgestürzt).
- **Speicherplatz vor Updates prüfen.** Steam für Mac hat Batman bei einem Auto-Update geleert und
  dann wegen Platzmangel pausiert. Nightforge zeigt das an und bietet „Weiter laden“
  (`Engine.unpauseDownload`). Vor einem *Download* prüft Nightforge den Platz inzwischen (`SpaceCheck`, UX-Roadmap 4.1);
  vor *Updates*, die Steam von selbst startet, noch nicht (Steams `BytesToStage`, `UpdateState.pending`).

## Controller

- **DualSense in Windows-Spielen auf winecx:** OxyRail funktioniert seit dem Xbox-360-ID-Patch (PR #8).
  Noch offen: Hotplug auf winecx (auf 11.18 geprüft: SDL nimmt den Pad nach Aus/An wieder auf) und weitere
  Spiele (reine XInput-Spiele, Unreal, DirectInput-Spiele).
- **Preis des Xbox-360-ID-Patches:** Windows-Spiele mit eigener DualSense-Unterstützung zeigen Xbox-Symbole,
  adaptive Trigger, Lichtleiste und Bewegungssensor fehlen. Ein besserer Weg bräuchte beides: den rohen Pad
  für solche Spiele und einen XInput-Pad für den Rest (`engine/patches/winebus-*-xbox360-ids.patch`).
- **Mac-Ports mit dem synthetischen Xbox-Pad** (`ControllerCompatibility`): bisher nur mit Batman geprüft.
  Andere alte Ports (Feral, Aspyr) wären gute Kandidaten.

## Darstellung und Leistung

- **MetalFX im Vulkan-Layer** (Retina für Vulkan-Spiele, PR #1): Die Metal-Seite ist geprüft, in einem Spiel noch nicht.
- **MoltenVK 1.4.2** (PR #1) ist in keinem Spiel getestet. 1.4.0 scheiterte an Shadern von No Man's Sky.
- **D3DM_MAX_FPS** wirkt jetzt über Steams Start-Umgebung. Prüfen, ob die gelernte Bildratengrenze
  (FramePacing) auch für D3DMetal-Spiele greift.
- **TV-Modus an einem echten TV** (`GameDisplay.swift`, PR #6): Mit einem Monitor am MacBook bestätigt (Fenster
  wandert beim Anstecken, Windows-Spiel öffnet dort, Hauptbildschirm kommt danach zurück). Am TV noch offen: die
  Erkennung am Namen (`Candidate.isTV`, Liste der Marken) und das Vollbild des Launchers.
- **Hinweis „Spielt auf: …“** neben Play, wenn ein externer Bildschirm das Spiel bekommt, damit man weiß, wo es
  aufgeht. Ansatz: `GameDisplay.screen?.localizedName` in `LibraryView`, nur bei mehr als einem Bildschirm.
- **Ton über HDMI.** macOS stellt meist selbst auf den TV um, aber nicht immer. Erst am TV prüfen; falls nötig beim
  Spielstart das Audiogerät des Spiel-Bildschirms wählen (CoreAudio, Transport HDMI/DisplayPort) und danach zurück,
  wie `GameDisplay.enterGame`/`leaveGame` es mit dem Hauptbildschirm machen.

## Anti-Cheat und GeForce Now

- **Store-Suche warnt nicht vor reinen Online-Spielen mit Anti-Cheat** (z. B. Bless Unleashed). Die Sperre
  `antiCheatOnline` braucht Steams Kategorie „Einzelspieler“, die die Store-Suche nicht liefert; in der
  Bibliothek greift sie. Ansatz: `StoreSearch.details` um `categories` erweitern (appdetails, Kategorie 2).
- **GeForce-Now-Link beim allerersten Klick:** Führt er über die Anmeldung, landet man danach auf der
  Startseite statt beim Spiel (getestet 26.10.). Der Erklär-Dialog sagt deshalb, danach noch einmal zu klicken.
  Angemeldet landet der Link direkt auf der Spielseite.
- Anti-Cheat wird nie umgangen. Fortschritt gibt es nur, wenn Entwickler, Epic oder BattlEye macOS/Wine freischalten.

## Abdeckung der Top 100

Übersicht vom 26.10.: https://claude.ai/artifact/TWQ3kkV6W7szsgyPyh6dWp
(Artifact, nur für den Besitzer sichtbar.)

- Etwa 28 Spiele haben eine Mac-Version, etwa 21 laufen wahrscheinlich über Wine, 22 sind durch Anti-Cheat
  blockiert, 9 sind reine DX12-Spiele (jetzt Kandidaten für D3DMetal).
- **Launcher-Spiele** sind ungeprüft: EA app (Sims 4, FC), Rockstar Launcher (GTA V, RDR2),
  Battle.net (Overwatch), REDlauncher (Witcher 3, startet DX12 als Standard).
- **Rocket League:** Die Startoption ohne Anti-Cheat nutzt ein anderes Programm (`RocketLeague.exe`).
  `SteamCatalog.antiCheatOffArguments` übernimmt aber nur Optionen mit demselben Programm. Die Mac-Version ist
  der Stand von 2020 ohne Online-Spiel.
- Übersicht nach DX12- und winecx-Tests aktualisieren (Liste: `ISteamChartsService/GetMostPlayedGames`).

## Wartung und Community

Ziel: Mac-Gaming gemeinsam voranbringen, keine Konkurrenz und kein Geld. Nightforge soll nicht an einer
Person hängen (Whisky ist 2025 daran gescheitert).

- **Hinweis auf CrossOver.** In der README und in den Einstellungen (Über/Hilfe) erwähnen, dass CodeWeavers
  einen großen Teil der Wine-Entwicklung finanziert und CrossOver für Fortgeschrittene und Support die
  richtige Wahl ist. Freundlich, ohne Vergleichstabelle.
- **Nur geprüfte Komponenten ausliefern.** `components.yml` committet neue Versionen heute direkt ins
  `manifest.json` auf `main`. Besser: ein Bot-PR, den die Tests (`tests/*/run.sh` auf einem macOS-Runner)
  durchlaufen müssen und der erst nach einem kurzen Spieltest gemergt wird. Dazu ein Rückweg: Die vorherige
  Version bleibt im Manifest, und Nightforge kann auf sie zurückfallen (`ComponentStore`).
- **Tests in der CI** laufen seit PR #5 (`ci.yml`: Build, alle `tests/*/run.sh`, Profil- und Manifest-Prüfung).
  Offen: dieselben Tests als Pflicht für die Bot-PRs aus dem Punkt darüber. Echte Spiele bleiben Handarbeit.
- **Problembericht ausbauen.** `ProblemReport` öffnet schon ein GitHub-Issue. Ergänzen: Komponenten-Versionen,
  Grafik-Layer und Profil mitschicken, Issue-Vorlage im Repo, der Nutzer sieht vorher alles. Nichts automatisch
  senden, kein Tracking. Vorher den Benutzernamen-Befund unter „Aus dem Code-Audit“ beheben.
- **Profile von der Community.** `profiles/` als Ort beschreiben, an dem jeder per PR ein Spiel eintragen kann:
  kurze Anleitung (`CONTRIBUTING.md`), Format erklären, Prüfung per CI (JSON gültig, Felder bekannt).
  Später überlegen, die Profile als offene Liste auch anderen Projekten anzubieten (ähnlich ProtonDB).
- **Fixes an die Ursprungsprojekte zurückgeben.** Kandidaten: DXMT-Patch für Wine 11 (3Shain/dxmt), der
  winebus-Xbox-ID-Patch und msync (Gcenx), die Patches in `engine/patches`. Was dort gemergt wird, müssen wir
  nicht bei jedem Update selbst nachziehen.
- **macOS-Betas früh testen.** Jeden Juni mit der neuen Beta Einrichtung, Steam-Start, ein DXMT-, ein D3DMetal- und
  ein Mac-Spiel durchgehen, damit der September keine Überraschung wird.
- **Ehrlich sagen, was geht.** Eine Liste „geprüft läuft“ in README oder App, alles andere als „probier es aus“.
  Schützt vor Erwartungen, die niemand allein erfüllen kann.
- **Mehr Leute mit Schreibrechten.** Sobald jemand regelmäßig beiträgt, Mitbetreuer aufnehmen. Releases und
  Komponenten-Pakete (`scripts/package-d3dmetal.sh`) so dokumentieren, dass sie nicht nur auf einem Mac gehen.

## Neue Oberfläche (UX-Roadmap, Nacht 26./27.10.) – in der echten App prüfen

Gebaut in PR #27, ein Commit je Roadmap-Punkt (Stand je Punkt in `docs/ROADMAP.md`). Geprüft mit Tests, mit dem echten
`LibraryModel` gegen die echte Bibliothek und mit Offscreen-Renderings – **nicht** per Klick in der laufenden App,
weil die Bildschirmfreigabe abgelehnt war.

- **Navigation mit Maus, Tastatur und DualSense** durchspielen: Startseite ↔ Bibliothek ↔ Spielseite, Esc/B,
  Doppelklick auf nicht installierte Cover, ↑ aus der Leiste und der obersten Rasterzeile in die Knöpfe,
  Filter- und Sortier-Segmente mit dem Pad, Zurück in die Bibliothek an dieselbe Scroll-Position.
- **Einmal echt erleben:** Dock-Menü (Rechtsklick aufs Dock-Symbol), Mitteilung „<Spiel> is ready to play“ mit
  „Play“ (macOS fragt beim ersten Mal), `nightforge://play/<id>` und „Add to Applications“ (findet Spotlight die
  App?), „Update & Play“ bei einem echten Update, Download-Ring und Wachhalten bei einem echten Download,
  „Welcome back“ nach einer echten Sitzung (wird die Steam-Cloud-Zeile grün?), das Fehlstart-Sheet, das
  Platz-Sheet.
- **Glas-Look** (`Glass.swift`): Am 27.10. auf dem echten Bildschirm angesehen – der Hintergrund scheint durch, die
  Ränder leuchten, Spielen glänzt bernsteinfarben. „Willkommen zurück“ und die Einstellungen sind seitdem Glas-Dialoge
  im Hauptfenster wie im Entwurf (Branch `claude/ux-roadmap-next`). Seit dem Abend des 27.10. sind auch alle übrigen
  Sheets und alle Alerts Glas-Dialoge (`GlassDialog`/`GlassQuestion` in `Glass.swift`, roter Knopf `Theme.danger`);
  jeden auf dem Bildschirm angesehen, Return/Esc geprüft. Offen: mit einem echten Controller durchgehen (A startet
  jetzt auf der Standardantwort, `padFocus(preferred:)`); die Picker bleiben System-Popups mit blauem Pfeil; die
  Textfelder im Stores-Tab und der Lade-Kringel im Spielknopf sind noch System (dort arbeiten andere Branches).
- **Entscheidungen (27.10. getroffen):** 2.3 wie vorgeschlagen (siehe Roadmap); „Save battery when unplugged“ (3.4)
  bleibt standardmäßig aus; „Welcome back“ nach jeder Sitzung ab einer Minute. Abweichungen von der Vorlage, die
  angeglichen werden: Genre/Jahr/Store-Zeile über dem Titel, Suche im Bibliothekskopf mit Beispiel, Metascore auf der
  Spielseite, Bibliothekskopf „105 Spiele · aktuell vor 2 Min.“.
- **`syncstate` in `remotecache.vdf`:** Nur „1“ (im Einklang) ist sicher belegt; die anderen Werte während eines
  Uploads einmal beobachten und `CloudSaves` danach schärfen.
- **`LibraryView.swift` (über 1700 Zeilen) und `LibraryModel.swift` (fast 1900)** sind mit der Navigation weiter
  gewachsen. Die drei Ebenen, die Sheets und die Navigation in eigene Dateien ziehen – erst wenn keine anderen
  Branches mehr an diesen Dateien arbeiten.

### Danach gebaut (Branch `claude/ux-roadmap-next`, auf PR #27) – in der echten App prüfen

Nur mit Tests auf Test-Ordnern und Renderings geprüft:

- **Shader-Caches leeren** und **Spielstart** am 27.10. geprüft: 149,7 MB weg, alle Ordner leer; OxyRail startete
  danach „butterweich“ im Vordergrund, „Willkommen zurück“ kam, die Steam-Cloud-Zeile wurde grün. Die Rückkehr zu
  Nightforge dauerte 20–30 s (nach dem Spielende nur alle 10 s geschaut) – behoben, jetzt 4–7 s; einmal nachprüfen.
- **Download-Geschwindigkeit** (4.4): Steht bei einem echten Download „12 MB/s · noch 25 Min.“ unter dem Spiel, und passt die Restzeit ungefähr?
- **Nightforge komplett entfernen** (4.3): **Nicht** im eigenen Konto ausprobieren – es löscht die Windows-Umgebung mit allen Windows-Spielen. Besser mit leerem HOME (`build/fh`, wie beim Test der Ersteinrichtung; am 27.10. mit Test-Spielständen vorbereitet, gelöscht würde nur dort und in den Metal-Caches unter `/var/folders`). Zu prüfen:
  - Landen die Spielstände in `Dokumente/Nightforge Saves/<Datum>`?
  - Fragt macOS nach dem Zugriff auf „Dokumente“?
  - Legt sich die App in den Papierkorb?
- **Spielstand-Wahl** (3.2): Ein Spiel mit Mac- und Windows-Version auf beiden Seiten spielen und dann wechseln. Kommt die Frage „Mit welchem Spielstand …“, und liegt der ersetzte Stand in `Backups/`?
- **Externes Laufwerk** (4.2): Ein Laufwerk mit einer Steam-Bibliothek abziehen. Zeigt das Spiel „Schließe <Name des Laufwerks> an, um zu spielen“? (Irgendein externes Laufwerk – „T7“ war nur das Beispiel im Entwurf.) Danach Bibliothek anlegen und verschieben ausprobieren (siehe Recherche in der Roadmap).

### Gefunden beim Test am 27.10.

- **Nur eigene Spiele, Demos für den Rest** (ROADMAP 2.6, Branch `claude/steam-ownership-3b3bdd`): Behoben. Nightforge
  liest Steams Lizenzliste (`userdata/<Konto>/config/licensecache`), 100 von 105 Spielen sind besessen. Noch offen:
  - **Demo ohne Lizenz einmal echt durchspielen.** Der Glas-Dialog und `steam://install/<Demo>` im Windows-Steam sind
    noch nicht in der echten App geprüft. Erscheint Steams Installationsdialog vor Nightforge, und lädt die Demo nach dem Bestätigen?
    Auf diesem Mac hat gerade kein angezeigtes Spiel eine Demo ohne Lizenz.
  - **Steam-Familienbibliothek** ist ungeprüft: Stehen geliehene Spiele in der Lizenzliste (`owner_id` ≠ eigenes Konto)?
  - **Installierte Spiele ohne Lizenz** (z. B. ein Gratis-Wochenende, das nach dem Laden ablief) bleiben „installiert“
    und starten dann nicht. Ansatz: `SteamCatalog.owns` beim Start prüfen und dasselbe ehrlich sagen.
  - **The Last Caretaker Demo** (Unreal 5.7.4): Behoben am 28.10. (Branch `claude/caretaker-demo-black-700351`),
    in der echten App gesehen: D3D12 über D3DMetal, 3024×1964, ~50 FPS mit FSR-Bildgenerierung. Ursache des schwarzen
    Bilds: Unreals DirectX-11-Weg. Unter DXMT bleibt er schwarz, und der Grafikspeicher wächst um ~400 MB/s (die Videos
    sind es nicht, auch ohne `Movies` gleich). DXVK 3 auf KosmicKrisp und D3DMetal stürzen mit `-dx11` ab. Das Profil
    in `profiles/mac.json` startet sie mit DirectX 12 über D3DMetal, ohne AVX-Hinweis (sonst illegale Instruktion beim
    Shader-Vorbereiten nach ~2 min), mit Retina, ohne Nanite und virtuelle Schatten (`Engine.ini`, 30 → 64 FPS), ohne
    Raytracing/MegaLights und mit Startwerten FSR „Performance“ + Bildgenerierung, „Niedrig“. Dafür neu in Profilen:
    `iniSettings`, `retina`, `fileEdits` mit `root`/`once`. Nebenbei behoben: `Engine.installedWineNow` nahm den jüngeren
    Ordner `wine/11.18` statt winecx, damit galt D3DMetal als fehlend und kein D3DMetal-Profil griff (auch Wukong nicht).
    Noch offen:
    - **Erster Start eines neuen Spielers** läuft mit den Werten der Demo (Episch, Raytracing, TSR), weil ihre
      `GameUserSettings.ini` erst danach existiert; die Profil-Änderungen greifen ab dem zweiten Start.
    - **Hintergrundvideo im Menü bleibt schwarz** (4K-H.264, `GStreamer-Video-CRITICAL … gst_caps_is_fixed`). Spielbar,
      aber der Video-Weg in winecx (Electra/WMF über winegstreamer) ist ungeprüft.
    - **Maus im Menü reagiert träge** mit Bildgenerierung (~25–30 echte Bilder/s). Der Nutzer behält sie lieber an.
    - **Ein Start aus Nightforge hing einmal im Ladebildschirm** (Bild eingefroren, 170 % CPU), direkt nach dem ersten
      Umschalten auf Retina und D3DMetal-Variablen. Drei Starts danach liefen durch; Ursache unklar.
    - **„Läuft super“ nach einem schwarzen Start**: `LaunchHealth` bestätigt jeden Weg, der 30 s läuft, und
      `Compatibility.rate` macht daraus „Läuft super“. Für die Demo erledigt (Profil), für Spiele ohne Profil bleibt es so.
      Idee: ein Spiel, das in den ersten Minuten nur Schwarz zeigt oder dessen Speicher davonläuft, als Fehlstart werten.
    - **Retina kostet einen Steam-Neustart** beim Wechsel zwischen einem Retina-Spiel und den anderen. Wine nimmt den
      Retina-Modus nur für eine ganze Sitzung; pro Programm (`AppDefaults\<exe>\Mac Driver`) wirkt er nicht – auch der
      Eintrag für `NMS.exe` im Prefix tut nichts.
  - **Toast „Steam lädt … nicht herunter“** ist in der App nicht gesehen. Der Eintrag selbst wechselte richtig; der Toast
    verschwindet nach 5 s und fiel in die Wartezeit.
- **Beenden mit offenem Dialog geht nicht** (⌘Q und `osascript … quit` tun nichts, solange ein Sheet offen ist). Seit
  die Einstellungen ein Sheet sind, fällt das eher auf; vor dem Beenden Sheets schließen.
- **Download-Knopf oben** erscheint nur, solange etwas lädt; im Entwurf ist er immer da (Panel mit „Nichts lädt
  gerade“). Mit dem Nutzer besprechen (gemeldet von der Sitzung „Vorlage angleichen“, 27.10.).
- **Mehrere Steam-Symbole in der Menüleiste** (Nutzer, 27.10. 21:58: drei auf einmal). Vermutlich bildet Wine das
  Tray-Symbol des unsichtbaren Windows-Steam als macOS-Statussymbol ab, und nach Neustarts von Steam bleiben alte stehen
  (dazu kommt das echte Steam für Mac). Prüfen: wer welches Symbol besitzt; Tray-Symbol des Windows-Steam abschalten
  oder beim Beenden aufräumen.
- **Zwei Nightforge-Symbole im Dock** (Nutzer, 27.10. 21:48). Das zweite ist „Nightforge Game“, die Hülle, in der die
  Wine-Prozesse laufen (wineserver, explorer, winedevice). Eigentlich sollen Hintergrundprozesse kein Dock-Symbol
  zeigen (`hide-steam-dock.dylib`) – herausfinden, welcher Prozess es trotzdem zeigt und wann.
- **DualSense** fehlte ab 20:08 in Nightforge: zum Laden getrennt, danach scheiterte macOS mit jedem Versuch, ihn
  wieder zu verbinden (bluetoothd „result 329“), obwohl er in der Liste stand. Seit 21:00 wieder verbunden – Nightforge
  zeigte ihn ohne Neustart (Hinweisleiste, Einstellungen › Controller, PlayStation-Symbole). Kein Fehler in Nightforge.

## Aus dem Code-Audit

Befunde vom 26.10., die noch offen sind. Alles andere ist behoben (PR #4, #5, #11, #12, #14–#19).

### Entscheidungen

- **Updates sind nicht echt signiert.** `Updater.install` prüft nur `codesign --verify` auf eine Ad-hoc-Signatur,
  `scripts/install.sh` lädt ohne Prüfsumme. Bewusst offen gelassen. Wege: ein Ed25519-Schlüssel als Repo-Secret
  (Release-Zip signieren, im Updater und in install.sh prüfen) oder ein Apple-Developer-Account (Developer ID, Notarisierung).

### Vulkan-Layer und winecx

- **winecx hat keinen Vulkan-Loader, der Layer wird nie geladen.** Seine `winevulkan.so` lädt `libMoltenVK.dylib`
  direkt (Gcenx' 11.18 ging über `libvulkan.1.dylib`), also findet sich kein Layer aus
  `Nightforge Game.app/…/implicit_layer.d`. Seit PR #7 fehlen damit für Vulkan- und DXVK-Spiele: das Aussortieren
  nicht unterstützter Funktionen (No Man's Sky, DXVK in L4D2 scheitert genau daran), die Sampler-Grenze, der HDR-Filter
  und MetalFX. Ansatz: den Khronos-Loader (aus der Gcenx-Engine oder MoltenVK-Release) in die winecx-Engine legen und
  winevulkan auf ihn lenken (Name `libMoltenVK.dylib` → Loader, MoltenVK per ICD-JSON), dabei die „MoltenVK-ICD-Falle“
  aus den Game-Mode-Notizen beachten. Erst danach lässt sich PR #13 im Spiel prüfen.
- **KosmicKrisp** (LunarGs Vulkan-Treiber auf Metal, 28.10. getestet): Als x86_64 gebaut nach dem Rezept aus
  dappermint/winecx-gptk PR #12 (`shadexternals/mesa-kosmickrisp`, Mesa 063dfae + Patches für `fillModeNonSolid` und das
  Speicherbudget, Khronos-Loader 32fcb94; Homebrew `llvm`, `spirv-llvm-translator`, `spirv-tools`). winecx lädt ihn ohne
  Änderung: `CX_ACTIVE_GRAPHICS_BACKEND=wined3d`, `CX_LIBVULKAN=<libvulkan.1.dylib>`, `VK_DRIVER_FILES=<icd.json>`.
  Mit Unreal 5.7 (The Last Caretaker Demo) aber noch nicht nutzbar: vkd3d-proton 3.1 bricht ab („Lacking support for
  transform feedback“), DXVK 3.1.1 kann keine geteilten Ressourcen anlegen (`VK_KHR_external_memory_win32` fehlt) und das
  Spiel stürzt ab. Nächster Versuch: DXVK mit einem Patch, der geteilte Ressourcen ungeteilt anlegt, und ein Spiel ohne
  geteilte Texturen (DirectX 9–11). Nicht als Komponente ausgeliefert; Bau braucht Netz und LLVM (~2 GB).
- **PR #13** (Entwurf): Layer-Fixes (freigegebene `CAMetalLayer`, Speicherleck pro Frame, Abbau, Retina pro Fenster).
  Kompiliert, aber ungetestet, weil der Layer unter winecx nicht läuft (siehe oben).
- **MetalFX auf der exportierten Metal-Queue** verlässt sich darauf, dass MoltenVK synchron einreicht. Mit
  `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0` könnte das Upscaling ein halbfertiges Bild lesen.
- **`steamwebhelper-wrapper.c`** startet den echten Helper ohne Job-Object. Wird der Wrapper beendet, bleibt CEF
  verwaist (passt zu den bekannten Shutdown-Hängern).

### Lieferkette

- **Nächtliche Daten gehen ungeprüft an alle.** `components.yml` und `profiles.yml` committen direkt auf `main`,
  umu-protonfixes und AreWeAntiCheatYet werden ab `HEAD` gelesen. Siehe „Nur geprüfte Komponenten ausliefern“ oben.
- **Build-Eingaben ohne Prüfsumme.** In `graphics.yml` `WINE_TOOLCHAIN_URL`, das Gcenx-Archiv, der inotify-Header und
  Klone per Tag, in `tools.yml` das cabextract-Archiv; dazu `brew install … || true`. Die Actions selbst sind seit dem
  Audit auf Commit-SHAs festgelegt, Dependabot hält sie aktuell.
- **Dependabot-PRs #21–#26** (cache 4→6, upload-artifact 4→7, download-artifact 4→8, setup-python 5→7) erst nach
  einem Release- oder Grafik-Build mergen. Ihre grünen Checks laufen nicht durch `release.yml` und `graphics.yml`, die
  diese Actions nutzen. upload- und download-artifact zusammen hochziehen.
- **Erster Lauf der Lizenz-Pakete (PR #14).** Nach den ersten Releases mit Lizenzen und Quellarchiv prüfen, dass
  `update-components.py` weiter genau ein Asset pro Komponente findet. Beim nächsten DXMT-Update die Lizenz prüfen
  (v0.80 ist MIT, neuere DXMT-Versionen LGPL).

### Steam und Start

- **Steams erstes Update auf einem frischen winecx-Prefix dauert rund 11 Minuten**: Der alte Bootstrapper startet alle
  13 s neu (164 Installationsläufe, „Bad NTFS transaction canary“), bis das Update durch ist. Die Einrichtung wartet
  das ab, aber für neue Nutzer ist es lang. Mit 11.18 vergleichen; vielleicht hilft ein Neustart von Steam durch
  Nightforge, sobald das Paket geladen ist.

### Leistung

- **Downloads:** Alle 3 s läuft ein kompletter Rescan mit `folderSize` über `downloading/<id>`. Nur die Manifeste der
  ladenden Spiele neu lesen und die Ordnergröße cachen.
- **SwiftUI:** `LibraryModel` ist ein `ObservableObject` mit 26 `@Published`, jede Änderung zeichnet alles neu.
  `@Observable` (ab macOS 14) oder das Modell aufteilen.
- **`MacSteam`** hat eine 1-Hz-Schleife; eine Exit-Quelle (`DispatchSource.makeProcessSource`) wäre ruhiger.

### Wartbarkeit

- `LibraryModel`, `Engine` und `LibraryView` haben je über 1000 Zeilen. Den SDK-Fallback gibt es 7-mal
  (`build.sh`, `tests/*/run.sh`), dazu etwa 10 eigene Process-Helfer und mehrfach definierte Pfadkonstanten.
- **`engine/patches`:** Die Patches werden in Glob-Reihenfolge angewendet (`frame-log` baut auf `metalfx-fit-window`
  auf, sortiert aber davor). Nummerieren und eine README mit Upstream-Stand anlegen; ein Umbenennen löst auf `main`
  einen neuen Grafik-Build aus.
