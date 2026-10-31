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
  Ursache und Plan (Steam für Mac in die Ersteinrichtung, Regeln für den Wechsel): `docs/PLAN-STEAM-FUER-MAC-EINRICHTUNG.md`.
  Wechselregeln (`SteamSwitch`) und Erststart-Baustein (`MacSteamPrep`) sind gebaut, aber noch nicht live getestet.
  Offen: die Haken in `Setup.swift` (nach setup-speed) und die Anzeige in `SetupView` (nach design-setup-home).

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
- **PS-Taste im Spiel** (`SteamGuideButton`, 29.10.): Vor jedem Steam-Start schaltet Nightforge „Guide-Taste
  fokussiert Steam“ ab (`Controller_CheckGuideButton` in `userdata/<id>/config/localconfig.vdf`), bei Windows-Steam
  und Steam für Mac. So öffnet die PS-Taste außerhalb von Spielen kein Big Picture mehr. Laut steamui (Stand Oktober 2026)
  fragt Steam die Einstellung im Spiel nicht ab und reicht den Druck ans Overlay weiter. Ungeprüft: was die Taste
  in einem Windows-Spiel tut (dort gibt es kein Overlay, `gameoverlayrenderer=d`), und ob das Overlay in
  Mac-Spielen damit noch aufgeht.
- **Zwei Controller, lokaler Koop mit Split-Screen** (Nutzer, 29.10.): ungeprüft. Erwartet wird:
  - Windows-Spiele: winebus/SDL gibt jeden Pad als eigenen Xbox-360-Pad weiter (XInput-Plätze 1–4).
  - Neuere Mac-Spiele mit dem GameController-Framework können mehrere Pads von sich aus.
  - Offen ist, ob macOS bei alten Mac-Ports mit dem synthetischen Xbox-Pad (`ControllerCompatibility`) mehr als einen Pad nachbildet.
  - Nightforge selbst hängt sich an jeden Pad (`InputRouter`), beide steuern die Oberfläche.

  Testen mit zwei Pads (DualSense + Xbox oder zwei DualSense):
  - je ein Windows- und ein Mac-Spiel mit lokalem Koop aus der Bibliothek;
  - ob jeder Spieler seinen eigenen Pad bekommt und die Reihenfolge stimmt;
  - ob ein zweiter Pad, der mitten im Spiel eingeschaltet wird, noch ankommt;
  - ob der Controller-Test der Ersteinrichtung bei zwei Pads sinnvoll bleibt (er zeigt nur einen).

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
  jetzt auf der Standardantwort, `padFocus(preferred:)`); die Picker in den Einstellungen bleiben System-Popups mit blauem Pfeil (die Spieloptionen haben seit 2.3 Glas-Segmente); die
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
- **Grafik-Voreinstellungen und Karte „This game“** (2.3, Branch `claude/presets-2-3-390808`): Nur offscreen gerendert (echte Views, Deutsch und Englisch) – der Blick in die echte App wurde am 28.10. abgelehnt. In der echten App prüfen: Spieloptionen (Karten, „Expert options“ aufklappen, scrollt es bei kleinem Fenster, folgt der Pad-Fokus?), die Karte rechts neben dem Titel (passt sie bei 980 pt Fensterbreite?), „Back to the Profile“ in der Karte, ein Start mit „Most compatible“ (kommt DXVK bzw. WineD3D zuerst, 60 FPS, ohne MetalFX?).
- **Externes Laufwerk** (4.2/4.3, Branch `claude/external-drive-4-2-710e3d`): Gebaut und mit Test-Ordnern geprüft (auch auf dem USB-Stick „Spiele test“, HFS+), aber noch nie mit echtem Steam. In der echten App prüfen:
  - Ein kleines Windows-Spiel über „Install on Spiele test“ laden (Platz-Sheet oder „Wohin soll …?“). Nimmt Steam die Bibliothek `Z:\Volumes\Spiele test\Nightforge Games` an und lädt dorthin?
  - Dasselbe Spiel in Einstellungen › Speicher mit „Verschieben nach …“ zurück auf den Mac und wieder auf den Stick. Fortschritt im Download-Panel, Steam danach wieder an, findet Steam das Spiel ohne neue Prüfung, startet es?
  - Stick abziehen: „Schließe Spiele test an, um zu spielen“? Wieder einstecken: spielbar, ohne Nightforge neu zu starten? (Beim Einstecken startet Nightforge die Windows-Steam neu, sobald nichts läuft.)
  - Ein Spiel vom Stick deinstallieren und den Stick abziehen: Darf **nicht** „Schließe … an“ zeigen (Steam schreibt seine Liste beim Start neu – sonst bleibt der Eintrag in `apps`).
  - Fragt macOS nach dem Zugriff auf Wechseldatenträger – für Nightforge (Kopieren) und für „Nightforge Helper“ (Steam, Wine)?
  - Mac-Version (Steam für Mac, Bibliothek `…/Nightforge Games/Steam for Mac`) und Epic-Spiel (`…/Nightforge Games/Epic Games`) einmal hin und zurück.
  - Noch nicht gebaut: Ein Laufwerk mit Spielen aus einer früheren Nightforge-Installation wird erst beim nächsten Laden oder Verschieben dorthin wieder als Bibliothek eingetragen (dann mit seinen Spielen), nicht schon beim Einstecken.

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
- **`osascript … quit` meldet „abgebrochen“ (-128)** (28.10., beim Test von 7.4): Einmal mit offenen Einstellungen –
  die App lief weiter (siehe oben); einmal endete sie trotz der Meldung wenige Sekunden später. Wer Nightforge per
  Skript beendet, darf sich nicht auf den Rückgabewert verlassen, sondern muss mit
  `pgrep -f "Nightforge.app/Contents/MacOS/Nightforge"` warten, bis sie wirklich weg ist – sonst laufen zwei Nightforge
  (ist dabei für ein paar Sekunden passiert, der Testbuild wurde sofort wieder beendet).
- **Ein `build/`-Ordner eines Worktrees wurde von außen geleert** (28.10. gegen 23:08, Worktree `merge-dupes-7-4`):
  `build/Nightforge.app` war weg, während andere Sitzungen bauten und testeten. Ursache unklar – vielleicht ein Aufräumen
  von Worktree-Builds wegen der `nightforge://`-Links oder der Dock-Symbole. Vor dem Start eines Testbuilds prüfen, dass
  er noch da ist; wer Builds anderer Worktrees aufräumt, sagt es in den Sitzungsnotizen.
- **Download-Knopf oben** erscheint nur, solange etwas lädt; im Entwurf ist er immer da (Panel mit „Nichts lädt
  gerade“). Mit dem Nutzer besprechen (gemeldet von der Sitzung „Vorlage angleichen“, 27.10.).
- **Mehrere Steam-Symbole in der Menüleiste** (Nutzer, 27.10. 21:58: drei auf einmal). Vermutlich bildet Wine das
  Tray-Symbol des unsichtbaren Windows-Steam als macOS-Statussymbol ab, und nach Neustarts von Steam bleiben alte stehen
  (dazu kommt das echte Steam für Mac). Prüfen: wer welches Symbol besitzt; Tray-Symbol des Windows-Steam abschalten
  oder beim Beenden aufräumen.
- **Nightforge Helper (Dock-Fix vom 28.10.) – noch offen:** Steam, Wine, Spiele, Epic-Downloads und die Skripte
  starten über `Nightforge Helper.app` (Datenordner, `Detached.swift`), damit eine beendete Nightforge nicht im Dock
  stehen bleibt. Geprüft: ⌘Q mit Steam, ⌘Q während eines Spiels, Neustart, Spielende. Noch nicht gesehen:
  - **Berechtigungen** gehören für macOS jetzt dem Helfer: Abfragen (Spiele/Bibliotheken auf externen Laufwerken,
    lokales Netzwerk, „Steam steuern“ für das Beenden von Steam für Mac) kommen unter „Nightforge Helper“,
    vielleicht einmal neu.
  - **DMG-Installation** (mit Quarantäne-Flag): Der Helfer wird von Nightforge selbst geschrieben und trägt keins.
    Weist macOS ihn trotzdem ab, startet Nightforge nach höchstens 10 s wie früher als Kindprozess und bleibt für
    den Rest des Laufs dabei (dann wieder zwei Symbole).
  - **Mitteilungen und Dock-Menü** nicht eigens geprüft (es gibt nur noch einen Eintrag, also sollten sie treffen).
- **`reopened()` im Beenden-Skript** (`pgrep -f "Nightforge.app/Contents/MacOS/Nightforge"`) zählt jede Befehlszeile,
  die den Pfad nur erwähnt – im Test hielt es eine Shell dafür und beendete sich, ohne Steam zu beenden. Robuster:
  `pgrep -x Nightforge` (Prozessname). `MacVersionTest` ersetzt `pgrep` und müsste mitziehen.
- **`nightforge://`-Links** öffnen die Standard-Kopie (`~/Applications`), auch wenn gerade ein Worktree-Build läuft – nur
  auf diesem Mac mit vielen registrierten Kopien. Zum Testen: `open -a <Build>.app "nightforge://play/<ID>"`.
- **DualSense** fehlte ab 20:08 in Nightforge: zum Laden getrennt, danach scheiterte macOS mit jedem Versuch, ihn
  wieder zu verbinden (bluetoothd „result 329“), obwohl er in der Liste stand. Seit 21:00 wieder verbunden – Nightforge
  zeigte ihn ohne Neustart (Hinweisleiste, Einstellungen › Controller, PlayStation-Symbole). Kein Fehler in Nightforge.

### Epic Games – offene Tests mit echtem Konto (Stand 28.10.)

Schon geprüft: verbinden, Bibliothek (93 Spiele), laden, spielen (20 Minutes Till Dawn, 60 FPS), deinstallieren in der
App (27.10.); Update & Play, Größe vor dem Download, Civ VI mit DLC laden, abbrechen, deinstallieren samt DLC nur ohne
Fenster über ein Testprogramm (28.10., `claude/stoic-gould-8fba7f`). Noch offen – ersetzt die Prüfliste im ersten Punkt
von „Epic Games“ unten:

- [ ] **Cloud-Spielstände:** ein Spiel mit Epic-Cloud (z. B. A Plague Tale, Control) spielen und beenden – vorher
      „Spielstand wird geholt …“, danach im „Willkommen zurück“ „Dein Spielstand ist bei Epic Games“.
- [ ] **Offline-Start:** WLAN aus, ein installiertes Epic-Spiel starten (startet ohne Anmeldecode; „Offline: Bereit“ /
      „Braucht Internet“ auf der Spielseite stimmt).
- [ ] **Weiterladen nach Neustart:** großen Download starten, Nightforge beenden und wieder öffnen (auch nach einem
      Neustart des Macs) – der Download läuft dort weiter, wo er war.
- [ ] **Tempo und Restzeit** im Download-Panel bei einem großen Spiel; zwei Epic-Downloads hintereinander (der zweite
      wartet, läuft danach von selbst an).
- [ ] **In der App selbst** (bisher nur ohne Fenster): „Wird aktualisiert … 42 %“ im Play-Knopf bei einem Update,
      „Download 12 GB · Auf dem Mac 25 GB“ und „Größe wird geprüft …“ auf der Spielseite, Platz-Sheet bei vollem Mac,
      „Deine Zusatzinhalte: …“ auf der Spielseite.
- [ ] **Ownership-Token:** ein Spiel mit `requires_ot` in `installed.json` laden und starten.
- [ ] **Anmeldung:** „Mit Google/Apple anmelden“ im Epic-Fenster; abgelaufene Anmeldung („Erneut anmelden“ im Banner
      und in Einstellungen › Stores) mit einem echt abgelaufenen Login.
- [ ] **Anti-Cheat:** Destiny 2 oder Century – Play öffnet GeForce Now; Fortnite zeigt „Läuft nicht“, ohne Download.
- [ ] **„Spielen“ blendete OxyRail aus** (siehe unten) einmal von Hand nachstellen.

### Epic Games (Branch `claude/epic-games-d52d35`, Roadmap 0.2, 7.1, 7.2)

- **Mit echtem Konto noch prüfen** (verbinden, laden, spielen gingen am 27.10.): ein Spiel mit Epic-Cloud-Spielständen
  (Abgleich vor/nach dem Spielen, Zeile im „Willkommen zurück“), Deinstallieren, Abbrechen eines größeren Downloads,
  Weiterladen nach einem Neustart von Nightforge, Offline-Start, ein Spiel mit Ownership-Token (`requires_ot`),
  „Mit Google/Apple anmelden“ (öffnet im selben Fenster), Tempo/Restzeit im Download-Panel bei einem großen Spiel,
  in der App selbst (28.10. nur ohne Fenster geprüft, siehe Roadmap 7.2): „Wird aktualisiert … 42 %“ im Play-Knopf, offline
  startet die alte Version, „Download 12 GB · Auf dem Mac 25 GB“ und „Größe wird geprüft …“, Platz-Sheet bei vollem Mac,
  „Deine Zusatzinhalte: …“ auf der Spielseite, zwei Epic-Downloads hintereinander (der zweite wartet, läuft dann an).
- **Doppelt gekaufte Spiele (7.4, Branch `claude/merge-dupes-7-4-b22892`):** Am 28.10. in der App mit der Maus gesehen
  (ARK, Karte, Spielseite, Wechsel Steam ↔ Epic, Größe, Zähler 192). Noch offen: Store-Wahl per Pad, ein Download im nicht
  gewählten Store (Fortschritt auf Cover und Spielseite), Ausblenden/Anheften einer zusammengeführten Karte. ARC Raiders
  stand am 28.10. in keiner der beiden Bibliotheken auf dem Mac.
- **Esc auf der Spielseite, wenn die Suche noch den Fokus hatte** (28.10., gefunden beim 7.4-Test, nicht von 7.4): Die
  Bibliothek bleibt hinter einer Spielseite stehen, ihr Suchfeld behielt den Tastaturfokus – Esc leerte die verdeckte
  Suche, statt zurückzugehen, und Buchstaben (H, P, O …) wären in die Suche getippt worden. **Behoben** im selben Branch:
  Das Suchfeld gibt den Fokus ab, sobald die Bibliothek verlassen wird (`LibrarySearchField`, `onChange(of: route)`).
  In der App geprüft (28.10., 23:10): ⌘F, „ark surv“, Spielseite per Klick, Esc → zurück in die Bibliothek, Suche bleibt.
- **„Spielen“ blendete OxyRail aus** (28.10., Prüfung per Fernsteuerung): Ein Klick auf „Spielen“ startete OxyRail und
  zeigte zugleich „OxyRail ist aus deiner Bibliothek ausgeblendet“. Im Code löst nur der Augen-Knopf oder H das aus;
  vermutlich ein Fehlklick, als das Fenster gerade nach vorne kam. Nicht nachvollzogen – im Auge behalten.
- **Update & Play mit DLCs:** Alle Teile zählen gleich viel – bei Spiel + 1-KB-DLC steht der Balken nach dem Spiel auf
  50 % und springt dann auf 100 %. Besser nach Größe gewichten (legendary schreibt die Größe erst, wenn ein Teil startet).
- **DLCs eines schon wartenden Downloads:** Steht ein Spiel schon in `Epic/downloads.json` (von einem Build ohne DLCs),
  kommen seine DLCs nicht dazu; sie folgen erst mit „Aktualisieren & spielen“. Ältere Builds schreiben `library.json`
  ohne `dlcs` – der neue Build holt sie beim nächsten Abgleich zurück.
- **Reste vom Test am 27.10.:** `Prefix/drive_c/Program Files/Epic Games/MinutesTillDawnxgosd` (12 KB, nur
  dxmt.conf/dxvk.conf) – vor dem Fix 6bd8f20 deinstalliert; kann weg.
- **Wartende Epic-Downloads** zeigen „Download wird vorbereitet …“, solange ein anderer Epic-Download läuft (legendary
  installiert nur eins zugleich). Besser: „Wartet auf <Spiel>“ – braucht einen Wartezustand in `InstallState`.
- **Abbrechen während der Zusatzinhalte** entfernt auch das schon geladene Spiel (Spiel und DLCs sind ein Download).
  Vielleicht: dann nur die DLCs abbrechen und das Spiel behalten.
- **Voraussetzungen der Spiele** (VC++-Pakete usw., `prereq_info` in `installed.json`) überspringt legendary mit `-y`.
  Fehlt etwas, lernt Nightforge es aus `wine.log` (winetricks) – oder den Installer des Spiels einmal unter Wine starten.
- **Nicht dabei:** Spiele, die über EA app oder Ubisoft Connect laufen (ausgelassen), Mac-Versionen
  von Epic-Spielen, Rockstar-Spiele, die `EpicGamesLauncher.exe` als Elternprozess erwarten (legendarys Wrapper-Exe).
- **GeForce Now für Epic-Anti-Cheat-Spiele** nur, wenn das Spiel auch auf Steam ist (GeForce-Now-ID des Steam-Zwillings).
  Fortnite & Co. bekommen „Läuft nicht“ ohne GeForce-Now-Knopf; GeForce Nows Katalog hat `EPIC`-Varianten mit eigener ID.
- **Epic ohne Steam:** Die Ersteinrichtung richtet Engine und Prefix nur zusammen mit Steam ein. Wer nur Epic verbindet,
  sieht die Bibliothek, aber Starten scheitert ohne Engine („Nightforges Engine ist noch nicht installiert“).
- **legendary-Updates:** Komponente ist auf 0.21.1 gepinnt (`components/sources.json`). Der Schnellstart (`PackedApp` in
  `Legendary.swift`) nutzt, wie PyInstallers Starter sich selbst startet (`_PYI_APPLICATION_HOME_DIR` usw.). Vor einem
  Update prüfen, dass ein Aufruf aus dem entpackten Ordner weiter ~0,2 s braucht; sonst fällt es auf 5–16 s zurück.
  Sauberer wäre ein eigener onedir-Build per GitHub-Workflow wie bei den Grafik-Paketen.
- **legendary fragt beim Start** `api.legendary.gl/v1/version.json` ab (Epic-Client-Daten, keine Nutzerdaten) – erst
  nach dem Verbinden. In „Über“ erwähnen oder per `config.ini` abschalten (dann fehlen Epics neue Client-Daten).
- **Alte Schlüssel aufräumen:** `GameIDMigration` lässt „options.570“, „library.hidden“ usw. für ältere Builds stehen.
  In einer späteren Version löschen.
- **Noch offen aus der Roadmap:** Store-Filter in der Bibliothek (2.1, mit Warnsymbol bei Sync-Fehler), „Start through
  <anderer Store>“ im Fehlstart-Sheet (1.2; die Store-Wahl selbst ist mit 7.4 da). „Also add Epic Games“ im ersten Start
  (6.1) entfällt nach Entscheidung des Nutzers (29.10.): Epic verbindet man in Settings › Stores.

### Trackpad-Gesten (Branch `claude/musing-haslett-71514d`, Roadmap 5.5)

Mit zwei Fingern am 28.10. am echten Trackpad geprüft. Offen:

- **Vor und Cover-Größe gibt es nur am Trackpad.** Die Roadmap-Regel will für jede Aktion einen Tasten- und einen
  Controller-Weg. Möglich wären ⌘[ / ⌘] wie in Safari und ⌘+ / ⌘− für die Cover (`InputRouter.handleKey`,
  `CoverSize.current`), am Pad vielleicht R3 für die Größe.
- **Drei Finger** (`swipe(with:)`) sind nicht ausprobiert, weil beim Nutzer drei Finger zwischen Vollbild-Apps wechseln.
  Die Richtung (`deltaX > 0` = zurück, wie WebKit) ist ungeprüft.
- **macOS 14:** Die Leiste meldet ihre Ränder erst ab macOS 15 (`onScrollGeometryChange`). Unter 14 geht über der Leiste
  nie vor, daneben schon. Nicht auf 14 ausprobiert.
- **Zurück zur Startseite:** Beim Mitgleiten scheint nur die Bibliothek durch (sie liegt schon hinter einer Spielseite).
  Die Startseite erscheint erst am Ende mit dem Überblenden. Sie dahinter vorzurendern wäre schöner.

### Größere Schrift (Branch `claude/larger-text-2-5-2d1360`, Roadmap 2.5)

Nur offscreen gerendert (echte Views, Deutsch und Englisch, aus und an, 1512 × 900 und 980 × 640). Ausgeschaltet
pixelgleich mit vorher, außer den Korrekturen unten. In der echten App prüfen:

- **Umschalten im laufenden Betrieb:** Werden in Einstellungen › Allgemein sofort alle Texte größer, auch im offenen
  Sheet und hinter ihm, ohne dass das Sheet zugeht?
- **Kleines Fenster (980 × 640), Schalter an:** Startseite (runde Knöpfe unter „Spielen“), Spielseite (Logo wird
  kleiner, Knöpfe in zwei Zeilen), Bibliothek (Suchfeld-Hinweis ganz lesbar), Download-Panel, Hinweisleiste mit
  verbundenem Controller (Akku-Pille links) – nicht gerendert.
- **Erster Start unter ~680 pt Fensterhöhe:** Anmeldung (mit QR-Hinweis) und Ergebnis scrollen jetzt, statt die obere
  Leiste hinauszuschieben (die Anmeldung tat das bei 640 pt schon ohne größere Schrift). Holt der Pad-Fokus den Knopf
  am Ende ins Bild? Stört der Scrollbereich das Wischen mit zwei Fingern nicht?
- **Einstellungen mit größerer Schrift** sind bis ~770 pt hoch (Allgemein): Passt das Sheet bei kleinem Fenster auf den
  Bildschirm? Die Werte der System-Popups (Sprache, Nach dem Start) bleiben 13 pt – wirkt das störend?
- **Spielseite mit vielen Hinweisen** (Kompatibilität, Akku, Low Power Mode, Versionen) bei 640 pt Höhe war schon vorher
  zu hoch und wird mit größerer Schrift höher. Nächster Schritt wäre, dass sie scrollt wie der erste Start.
- **Nicht gerendert:** Controller-Test mit echtem Pad, Epic-Anmeldehinweis und Sync-Banner, leere Bibliothek,
  Store-Wahl (7.4), Hinweise aus der Spielanalyse, Steam-für-Mac-Fortschritt, „Willkommen zurück“ mit Cloud-Zuständen.

## Ideen für später

- **Lizenzen in „Über“ zum Aufklappen** (Idee des Nutzers, 28.10.; noch nicht anfangen):
  - Ein Klick oder A auf eine Komponente (Wine, DXMT …) wechselt im selben Glas-Sheet in eine Detailansicht, kein
    zweites Sheet darüber. Oben „‹ Zurück“ (B/Esc), weiche Überblendung.
  - Darin der vollständige Lizenztext, scrollbar und sauber gesetzt. Für LGPL-2.1, GPL-3.0, Zlib, Apache-2.0 und MIT
    die Standardtexte mitliefern; bisher liegen nur Nightforges, umu-protonfixes' und AreWeAntiCheatYets Dateien in der App.
  - Unten ein unaufdringlicher Knopf zum Quellcode, möglichst zur mitgelieferten Version. Die `source`-URL steht schon in
    `components/manifest.json`. Wo sie aufs Nightforge-Repo zeigt (eigene Builds: Grafik, Gamepad, cabextract), zwei
    Links: „Original: <Projekt>“ und „Unser Build: Nightforge“.
  - D3DMetal ist Apples Game Porting Toolkit, nicht quelloffen: klar sagen („Proprietär, nur auf Apple-Hardware“),
    Apples Lizenztext, kein Quellcode-Knopf.
- **Startseite direkt nach dem ersten Start** (Nutzer, 29.10., mehrfach: „wirkt sehr karg“, „zu leer“, „sieht
  langweilig aus“): Nach „Los geht's“ zeigt Home bei einem neuen Nutzer nur „Alle 100 Spiele“, „Bibliothek öffnen“
  und ein Band mit der einzigen Kachel „Alle Spiele“. **Gebaut und gemergt am 29.10. (a5103ef):** Home ist die
  Bühne (Entwurf 2d, `HomeStage.swift`) mit „Für den Anfang“ (`StarterPicks.swift`). Offen: mit einem wirklich neuen
  Konto ansehen (weniger als drei gespielte Spiele).
- **Wartezeit der Ersteinrichtung lebendig machen** (Nutzer, 29.10.): **gebaut und gemergt am 29.10. (a5103ef).**
  Rechts neben der Checkliste stehen der Controller-Test mit Tasten-Chips und 11 Tipps; live mit DualSense geprüft.
  Kein Epic in der Ersteinrichtung.
- **Emulation** (Nutzer, 29.10., „was wäre, wenn Nightforge emulation machen könnte“; nur Brainstorming):
  - Idee: Konsolenspiele in derselben Bibliothek, mit Covern und Controller-Bedienung wie alles andere.
  - Emulatoren wären Komponenten wie legendary oder gogdl, z. B. RetroArch-Kerne, Dolphin, DuckStation, PPSSPP
    oder PCSX2. Lizenzen (meist GPL) und Apple-Silicon-Versionen sind je Emulator zu prüfen.
  - Grenzen: Nightforge liefert keine ROMs oder BIOS und lädt keine herunter, nur eigene Dumps des Spielers. Keine
    Switch-Emulatoren: Nintendo hat 2024 Yuzu verklagt, Ryujinx wurde danach eingestellt.
  - Vorbild und Konkurrenz auf dem Mac: OpenEmu. Nightforges Vorteil wäre eine einzige Bibliothek für Steam, Epic, GOG
    und Konsolen.
  - Erst besprechen: Umfang (welche Konsolen), Ordner für ROMs, Cover-Quelle, Speicherstände.
- **Ersteinrichtung weiter beschleunigen** (29.10., Session setup-speed, Branch `claude/setup-speed-ec0a53`; Lauf 5:
  Anmeldefenster nach 2:57). Gebaut, der Live-Lauf mit Zeitmessung steht aus:
  - **Steams Update vorab laden** (`SteamPackages.swift`): Installer, 32-Bit-Schritt (19 Pakete, 247 MB) und 64-Bit-Client
    laufen parallel zu `wineboot`, jede Datei per SHA-256 geprüft. Die 32-Bit-Pakete liegen vor Steams erstem Start in
    `package/`. Die 64-Bit-Pakete kommen erst nach dem „Shutdown“ des 32-Bit-Schritts dazu, denn dessen Aufräumen löscht alle
    Paketdateien. Im Probe-Präfix lud danach keiner der beiden Schritte etwas, vorher waren es 13–24 s je Schritt.
    Erwartet: −25 s.
  - **Wrapper im richtigen Moment**: direkt nach „Verification complete“ von Steams eigenem Neustart; nur in dieser Phase
    schaut Nightforge alle 50 ms nach. Davor legt Steams Prüfung Valves Helper zurück, auch bei gleicher Größe und gleichem
    Datum. Danach startet der Client den Wrapper selbst, und es braucht keinen Neustart mehr. Probe-Präfix: Steam-Start bis
    Anmeldefenster 37 s statt 83 s (Lauf 5). Erwartet: −25…30 s.
  - **Wenn der Moment verpasst wird**: Valves Browser endet, und Steams Client startet den Wrapper (siehe unten);
    ein hängender Browser (Chrome begonnen, 5 s keine Message-Loop) ebenso. Das 20-s-Netz bleibt.
  - **Lauf 6** (29.10., 23:24; Probe-Merge mit steam-guide-dylib und external-drive): 4:24, davon Windows 3:10. Der
    Steam-Teil lief live wie geplant: Steam-Start bis Anmeldefenster 38 s statt 83 s, kein Neustart, 64-Bit-Schritt ohne
    Download. Der 32-Bit-Schritt lud noch die 32-Bit-Varianten von CEF (96 MB, 6 s); jetzt kommen beide Varianten vorab.
  - **Nachmessung** in einem leeren Home (Harness mit dem echten `SetupModel`, echte Downloads, ohne App-Oberfläche):
    - Dieselbe Mischung wie Lauf 6: 2:03 (Engine 26 s, Windows 52 s, Steam 44 s).
    - Endstand: 2:05 und 1:50 (Windows 52 s und 41 s, Steam 45 s und 44 s).
    - a5103ef ohne diesen Branch: Der Neustart nach dem Update hing fünfmal hintereinander, dann gab die Einrichtung auf.
  - **Langsamer Windows-Schritt**: Einmal nachgestellt (2:12). 87 s lang lief `wine wineboot --init` ohne wineserver,
    also Wines erster Start der frisch entpackten Engine (Rosetta übersetzt), sonst 5–7 s. Zeitgleich lief Time Machine.
    Auf das Vorabladen wartet der Schritt nicht. Das Vorabladen kostet dort trotzdem Zeit (ohne 37 s, mit 41–58 s) und
    spart im Steam-Schritt ~39 s. Es startet jetzt erst, wenn wineboot Dateien anlegt.
  - **Hänger der Schleife**: Einmal stand die Einrichtung 12 min (Time Machine aktiv). Der Wrapper kam dabei zu spät, Valves
    Helper lief, danach ein Neustart. Wrapper-Tausch und `ps`-Abfrage laufen jetzt neben dem Main-Thread.
  - **Moment verpasst, Browser hängt** (30.10.): Es endet nur Steams Browser (`Engine.endWebHelpers`), und Steams Client startet
    ihn von selbst neu, nach dem Tausch also den Wrapper. Im Probe-Präfix kam er jedes Mal nach ~8 s wieder (4 von 4,
    „Restart webhelper process“). Erst nach drei Browsern ohne Erfolg, oder wenn 25 s lang keiner kommt, startet ganz Steam
    neu wie bisher. Die 20-s-Regel aus console_log greift nicht mehr, sobald dieser Start einen Browser hatte.
  - **Rosetta**: Der langsame Windows-Schritt kam am 30.10. nachmittags wieder, ohne Time Machine und ohne Vorabladen. Eine
    Stichprobe zeigt Wines Loader 12 min lang in `open()` der eigenen Datei, noch in dyld (über Rosetta). Ein natives `open()`
    derselben Datei ging sofort. Rosettas Übersetzungsdienst `oahd` hing also; später erholte er sich von selbst. Abhilfe
    beim Nutzer: Mac neu starten oder `sudo killall oahd`. Vermutung, nicht belegt: Auch der hängende Browser nach einem
    Neustart wartet auf eine Übersetzung.
  - **Verworfen**: Den htmlcache zu leeren half nicht (Lauf 5). Die Ursache des Hängers bleibt offen. In fünf nachgestellten
    Varianten trat er nie auf (kalte/warme Engine, früh/spät beendet, SIGKILL wie `stopAll`, Game-Mode-Loader). Der erste
    Browserstart in einem frischen Präfix hängt nicht.
  - **Windows-Umgebung aus einer Vorlage**: empfohlen, aber nicht gebaut, denn das braucht CI und Hosting (Entscheidung
    Nutzer/Koordinator).
    - Messwerte: `wineboot` 45 s plus 7 s bis der wineserver weg ist. Ein frisches Präfix hat 567 MB, davon 518 MB
      byte-gleiche Kopien der Engine-DLLs. Mit zstd -19 sind es 94 MB, das Entpacken dauert 2,7 s. Der erste Wine-Aufruf
      danach ist nicht langsamer, solange `.update-timestamp` der mtime von `wine.inf` der Engine entspricht (tar erhält sie).
      Sonst läuft `wineboot --update`, nicht schneller als heute, aber auch nicht langsamer.
    - Lizenz: nur Wines eigene Dateien (LGPL wie die Engine), keine Schriften, kein Mono/Gecko.
    - Beim Bauen entfernen: `dosdevices` außer c:/z: (Volumes des Build-Macs), die Benutzerordner-Links und
      „Desktop/My Mac Desktop“ (Home des Build-Macs).
    - Beim Entpacken `MachineGuid` in system.reg neu würfeln, sonst haben alle Nutzer dieselbe. Schlägt etwas fehl: `wineboot`.
    - Weg: CI baut pro winecx-Version ein Archiv als Komponente, geladen parallel zur Engine. Erwartet: −40…45 s. Dann
      bleibt weniger Zeit fürs Vorabladen; der 32-Bit-Schritt (~12 s) passt noch.
    - Eine lokale Vorlage pro Engine hilft nur bei einer zweiten Einrichtung: verworfen.

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

- **Steams erstes Update auf einem frischen winecx-Prefix** (früher „rund 11 Minuten“) – Ursache gefunden und behoben
  (29.10., Branch `claude/first-start-6-1-18d92f`, siehe Roadmap 6.1):
  - Nightforge selbst hat die Schleife ausgelöst. Beim Entpacken schreibt Steam Valves `steamwebhelper.exe` zurück. Die
    Einrichtung sah das alle 2 s, tauschte den Wrapper ein und startete Steam neu – mitten in der Installation. Der
    Bootstrapper begann dann wieder mit „installed version 0“, alle 13 s (124-mal in 30 Minuten). Nur wenn die Installation
    zufällig zwischen zwei Prüfungen fertig wurde, ging es weiter.
  - Jetzt liest `SteamBootstrap` Steams Update-Log (nur Marker, die Steam nicht übersetzt). Getauscht und neu gestartet
    wird erst, wenn der neue Client läuft; `stopSteam` und die Hänger-Erkennung warten eine Installation ab.
  - Dazu zwei kleinere Fehler: Der allererste Start mit `-noverifyfiles` prüfte keine Updates und stand 92 s, bis
    Nightforge Steam neu startete. Jetzt startet Steam ohne `-noverifyfiles`, bis der Client da ist, und ein solcher
    Stillstand wird nach 15 s beendet. Und das Quit-Skript beendete Steam ohne `-noverifyfiles`, worauf Steam Valves Helper
    über den Wrapper installierte.
  - Danach hing noch der Neustart nach dem Tausch (93 s): gestartet, während das alte Steam noch beendet wurde. Jetzt
    startet die Einrichtung Steam nur neu, wenn Valves Helper schon läuft, wartet vorher, bis alles von Steam weg ist,
    und startet einen Client, der nach 20 s nicht hochgekommen ist („Client version“ in `console_log.txt`), noch einmal.
  - Gemessen: mit dem Schleifen-Fix 4:39 bis zum Anmeldefenster, im zweiten Lauf (57cb377) 4:13, davon 93 s der hängende
    Neustart, im dritten (a40e22a) 3:09, davon 26 s der hängende Neustart bis zum 20-s-Netz.
  - Der erste Neustart nach dem Update hing in allen drei Läufen beim Einlesen des Browser-Profils (nach „This is Chrome
    version“). Verdacht: Valves Browser hatte seinen Cache (`htmlcache`) halb angelegt, als er beendet wurde (im ersten
    Lauf, 2 s nach dem Client-Start beendet, hing nichts). Seit dem 29.10. leert die Einrichtung den Cache vor dem Neustart
    (vor der Anmeldung steht nichts darin). Ziel um 2:40 – beim nächsten frischen Durchlauf prüfen.
  - Nicht gemacht: den Wrapper schon im ~1-s-Fenster zwischen „Shutdown“ und dem Browser-Start tauschen (schnelleres
    Abfragen). Der neue Client prüft in genau diesem Fenster seine Dateigrößen und lädt einen zu früh getauschten Helper
    neu herunter.

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
